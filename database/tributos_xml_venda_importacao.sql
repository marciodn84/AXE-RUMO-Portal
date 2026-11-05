create table public.vendas_nfe_tributos (
  chave text primary key check (chave ~ '^[0-9]{44}$'),
  pedido_id bigint not null references public.comercial_pedidos(id),
  numero text not null,
  serie text not null,
  xml_original text not null check (octet_length(xml_original) <= 2097152),
  tributos jsonb not null,
  usuario_id uuid not null references auth.users(id),
  criado_em timestamptz not null default now()
);
create index vendas_nfe_tributos_pedido on public.vendas_nfe_tributos(pedido_id);
alter table public.vendas_nfe_tributos enable row level security;
revoke all on public.vendas_nfe_tributos from public,anon,authenticated;
grant select,insert on public.vendas_nfe_tributos to service_role;

create function public.axe_venda_nfe_tributos(pid bigint, conteudo text, uid uuid)
returns jsonb language plpgsql set search_path='' as $$
declare
  pedido public.comercial_pedidos;
  existente public.vendas_nfe_tributos;
  doc xml;
  caminho text := '/n:nfeProc/n:NFe/n:infNFe/';
  chave_nfe text;
  numero_nf text;
  serie_nf text;
  emitente text;
  destinatario text;
  cnpj_pedido text;
  linhas jsonb;
begin
  if not public.axe_compra_fin_autorizado(uid) then raise exception 'Sem permissão para vincular NF-e de venda'; end if;
  select * into pedido from public.comercial_pedidos where id=pid for update;
  if not found then raise exception 'Pedido de venda não encontrado'; end if;
  if conteudo is null or octet_length(conteudo)>2097152 or conteudo ~* '<![[:space:]]*(DOCTYPE|ENTITY)' then
    raise exception 'XML inválido ou acima de 2 MB';
  end if;
  doc:=xmlparse(document conteudo);
  chave_nfe:=substring(public.axe_nfe_texto(doc,caminho||'@Id') from '^NFe([0-9]{44})$');
  numero_nf:=public.axe_nfe_texto(doc,caminho||'n:ide/n:nNF/text()');
  serie_nf:=public.axe_nfe_texto(doc,caminho||'n:ide/n:serie/text()');
  emitente:=public.axe_nfe_texto(doc,caminho||'n:emit/n:CNPJ/text()');
  destinatario:=public.axe_nfe_texto(doc,caminho||'n:dest/n:CNPJ/text()');
  if chave_nfe is null or numero_nf is null or serie_nf is null
    or public.axe_nfe_texto(doc,caminho||'n:ide/n:mod/text()') is distinct from '55'
    or public.axe_nfe_texto(doc,caminho||'n:ide/n:tpNF/text()') is distinct from '1'
    or public.axe_nfe_texto(doc,caminho||'n:ide/n:finNFe/text()') is distinct from '1'
    or public.axe_nfe_texto(doc,caminho||'n:ide/n:tpAmb/text()') is distinct from '1'
    or public.axe_nfe_texto(doc,'/n:nfeProc/n:protNFe/n:infProt/n:chNFe/text()') is distinct from chave_nfe
    or coalesce(public.axe_nfe_texto(doc,'/n:nfeProc/n:protNFe/n:infProt/n:cStat/text()'),'') not in ('100','150') then
    raise exception 'Selecione uma NF-e normal de saída com protocolo de produção';
  end if;
  if not exists (select 1 from public.fiscal_estabelecimento f where regexp_replace(f.cnpj,'[^0-9]','','g')=emitente) then
    raise exception 'O emitente do XML não corresponde ao estabelecimento da AXE';
  end if;
  select regexp_replace(coalesce(pedido.documento#>>'{cliente,cnpj}',pedido.documento#>>'{documento,cliente,cnpj}',c.cnpj),'[^0-9]','','g')
    into cnpj_pedido from (select 1) x left join public.clientes c on c.id=pedido.cliente_id;
  if destinatario is null or destinatario is distinct from cnpj_pedido then
    raise exception 'O destinatário do XML diverge do cliente deste pedido';
  end if;
  if exists (select 1 from xmltable(xmlnamespaces('http://www.portalfiscal.inf.br/nfe' as n),
    '/n:nfeProc/n:NFe/n:infNFe/n:det/n:prod/n:xPed' passing doc columns referencia text path '.') x
    where nullif(btrim(x.referencia),'') is not null
      and upper(btrim(x.referencia)) is distinct from upper(btrim(pedido.pedido_cliente))
      and upper(btrim(x.referencia)) <> 'PC-'||lpad(pid::text,6,'0')) then
    raise exception 'O XML referencia outro pedido ou reúne mais de um pedido';
  end if;

  linhas:=public.axe_nfe_tributos(conteudo);
  insert into public.vendas_nfe_tributos(chave,pedido_id,numero,serie,xml_original,tributos,usuario_id)
    values(chave_nfe,pid,numero_nf,serie_nf,conteudo,linhas,uid)
    on conflict(chave) do nothing;
  if not found then
    select * into existente from public.vendas_nfe_tributos where chave=chave_nfe;
    if existente.pedido_id<>pid or existente.xml_original<>conteudo then
      raise exception 'A chave já está vinculada a outro pedido ou a outro conteúdo';
    end if;
  end if;
  return jsonb_build_object('numero',numero_nf,'serie',serie_nf);
end $$;

alter function public.axe_imp_estrutura(jsonb,uuid) rename to axe_imp_estrutura_tributos_base;
create function public.axe_imp_estrutura(p_dados jsonb,p_usuario uuid) returns jsonb
language plpgsql set search_path='' as $$
declare
  resposta jsonb;
  fiscais jsonb;
begin
  resposta:=public.axe_imp_estrutura_tributos_base(p_dados,p_usuario);
  if p_dados->>'acao'='v2_tributos_ler' and p_dados->>'origem'='venda' then
    select coalesce(jsonb_agg(t || jsonb_build_object('nota',n.numero||' / '||n.serie,'estado','Vinculada')
      order by n.criado_em,(t->>'item')::int,t->>'imposto'),'[]')
      into fiscais from public.vendas_nfe_tributos n cross join lateral jsonb_array_elements(n.tributos) t
      where n.pedido_id=(p_dados->>'registro')::bigint;
    return resposta || jsonb_build_object('fiscais',fiscais);
  elsif p_dados->>'acao'='v2_tributos_ler' and p_dados->>'origem'='entrada_importacao' then
    select coalesce(jsonb_agg(t || jsonb_build_object('nota',n.xml->>'numero','estado',n.estado)
      order by (t->>'item')::int,t->>'imposto'),'[]')
      into fiscais from public.imp_notas n cross join lateral jsonb_array_elements(coalesce(n.xml->'tributos','[]')) t
      where n.id=(p_dados->>'registro')::uuid;
    return resposta || jsonb_build_object('fiscais',fiscais);
  end if;
  return resposta;
end $$;
revoke all on function public.axe_venda_nfe_tributos(bigint,text,uuid),public.axe_imp_estrutura(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_venda_nfe_tributos(bigint,text,uuid),public.axe_imp_estrutura(jsonb,uuid) to service_role;
