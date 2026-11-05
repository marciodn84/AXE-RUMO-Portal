create table public.tributos_registros (
  origem text not null check (origem in ('compra','venda','estoque','entrada_importacao')),
  registro text not null,
  versao integer not null default 1,
  linhas jsonb not null,
  usuario_id uuid not null references auth.users(id),
  atualizado_em timestamptz not null default now(),
  primary key (origem, registro)
);
alter table public.tributos_registros enable row level security;
revoke all on public.tributos_registros from public, anon, authenticated;
grant select, insert, update on public.tributos_registros to service_role;

create function public.axe_nfe_tributos(conteudo text) returns jsonb
language sql immutable set search_path='' as $$
  select coalesce(jsonb_agg(
    jsonb_strip_nulls(jsonb_build_object(
      'item', item.linha, 'imposto', spec.imposto, 'valor', campos.valor::numeric,
      'base', campos.base::numeric, 'aliquota', campos.aliquota::numeric,
      'aliquota_efetiva', campos.efetiva::numeric, 'cst', campos.cst,
      'classificacao', campos.classificacao, 'aliquota_especifica', campos.especifica::numeric,
      'base_quantidade', campos.quantidade::numeric, 'fonte', 'XML'
    )) order by item.linha, spec.imposto
  ), '[]')
  from xmltable(xmlnamespaces('http://www.portalfiscal.inf.br/nfe' as n),
    '/n:nfeProc/n:NFe/n:infNFe/n:det' passing xmlparse(document conteudo)
    columns linha int path '@nItem', imposto xml path 'n:imposto') item
  cross join (values
    ('ICMS','n:ICMS/*','vICMS','vBC','pICMS'),
    ('ICMS ST','n:ICMS/*','vICMSST','vBCST','pICMSST'),
    ('ICMS destino','n:ICMSUFDest','vICMSUFDest','vBCUFDest','pICMSUFDest'),
    ('ICMS remetente','n:ICMSUFDest','vICMSUFRemet','vBCUFDest',''),
    ('FCP','n:ICMS/*','vFCP','vBCFCP','pFCP'),
    ('FCP ST','n:ICMS/*','vFCPST','vBCFCPST','pFCPST'),
    ('FCP destino','n:ICMSUFDest','vFCPUFDest','vBCFCPUFDest','pFCPUFDest'),
    ('IPI','n:IPI/*','vIPI','vBC','pIPI'),
    ('PIS','n:PIS/*','vPIS','vBC','pPIS'),
    ('PIS ST','n:PISST','vPIS','vBC','pPIS'),
    ('COFINS','n:COFINS/*','vCOFINS','vBC','pCOFINS'),
    ('COFINS ST','n:COFINSST','vCOFINS','vBC','pCOFINS'),
    ('II','n:II','vII','vBC',''),
    ('IBS estadual','n:IBSCBS/n:gIBSCBS/n:gIBSUF','vIBSUF','../n:vBC','pIBSUF'),
    ('IBS municipal','n:IBSCBS/n:gIBSCBS/n:gIBSMun','vIBSMun','../n:vBC','pIBSMun'),
    ('IBS monofásico','n:IBSCBS/n:gIBSCBSMono','vTotIBSMonoItem','',''),
    ('CBS','n:IBSCBS/n:gIBSCBS/n:gCBS','vCBS','../n:vBC','pCBS'),
    ('CBS monofásica','n:IBSCBS/n:gIBSCBSMono','vTotCBSMonoItem','',''),
    ('IS','n:IS','vIS','vBCIS','pIS')
  ) spec(imposto, caminho, valor, base, aliquota)
  cross join lateral (
    select public.axe_nfe_texto(item.imposto,'/n:imposto/'||spec.caminho||'/n:'||spec.valor||'/text()') valor,
      case when spec.base<>'' then public.axe_nfe_texto(item.imposto,'/n:imposto/'||spec.caminho||'/'||case when spec.base like '../%' then spec.base else 'n:'||spec.base end||'/text()') end base,
      case when spec.aliquota<>'' then public.axe_nfe_texto(item.imposto,'/n:imposto/'||spec.caminho||'/n:'||spec.aliquota||'/text()') end aliquota,
      public.axe_nfe_texto(item.imposto,'/n:imposto/'||spec.caminho||'/n:gRed/n:pAliqEfet/text()') efetiva,
      case when spec.caminho like 'n:IBSCBS/%' then public.axe_nfe_texto(item.imposto,'/n:imposto/n:IBSCBS/n:CST/text()')
           when spec.imposto='IS' then public.axe_nfe_texto(item.imposto,'/n:imposto/n:IS/n:CSTIS/text()')
           else public.axe_nfe_texto(item.imposto,'/n:imposto/'||spec.caminho||'/n:CST/text()') end cst,
      case when spec.caminho like 'n:IBSCBS/%' then public.axe_nfe_texto(item.imposto,'/n:imposto/n:IBSCBS/n:cClassTrib/text()')
           when spec.imposto='IS' then public.axe_nfe_texto(item.imposto,'/n:imposto/n:IS/n:cClassTribIS/text()') end classificacao,
      case when spec.imposto='IS' then public.axe_nfe_texto(item.imposto,'/n:imposto/n:IS/n:pISEspec/text()')
           when spec.imposto='IPI' then public.axe_nfe_texto(item.imposto,'/n:imposto/'||spec.caminho||'/n:vUnid/text()')
           when spec.imposto in ('PIS','PIS ST','COFINS','COFINS ST') then public.axe_nfe_texto(item.imposto,'/n:imposto/'||spec.caminho||'/n:vAliqProd/text()') end especifica,
      case when spec.imposto='IS' then public.axe_nfe_texto(item.imposto,'/n:imposto/n:IS/n:qTrib/text()')
           when spec.imposto='IPI' then public.axe_nfe_texto(item.imposto,'/n:imposto/'||spec.caminho||'/n:qUnid/text()')
           when spec.imposto in ('PIS','PIS ST','COFINS','COFINS ST') then public.axe_nfe_texto(item.imposto,'/n:imposto/'||spec.caminho||'/n:qBCProd/text()') end quantidade
  ) campos
  where campos.valor is not null or campos.aliquota is not null or campos.especifica is not null;
$$;

create function public.axe_nfe_gravar_tributos() returns trigger
language plpgsql set search_path='' as $$
begin
  new.documento := new.documento || jsonb_build_object('tributos', public.axe_nfe_tributos(new.xml_original));
  return new;
end $$;
create trigger compras_nfe_tributos before insert on public.compras_nfe_entradas
for each row execute function public.axe_nfe_gravar_tributos();

alter function public.axe_imp_estrutura(jsonb,uuid) rename to axe_imp_estrutura_sem_tributos;
create function public.axe_imp_estrutura(p_dados jsonb,p_usuario uuid) returns jsonb
language plpgsql set search_path='' as $$
<<tributos>>
declare
  acao text:=p_dados->>'acao';
  origem text:=p_dados->>'origem';
  registro text:=p_dados->>'registro';
  permissao jsonb;
  atual public.tributos_registros;
  linhas jsonb:=p_dados->'linhas';
  linha jsonb;
  fiscais jsonb:='[]';
  movimento_original uuid;
begin
  if acao not in ('v2_tributos_ler','v2_tributos_salvar') then
    return public.axe_imp_estrutura_sem_tributos(p_dados,p_usuario);
  end if;
  permissao:=public.axe_imp_estrutura_sem_tributos(jsonb_build_object('acao','v2_opcoes'),p_usuario);
  if origem='compra' then
    perform 1 from public.imp_pedidos where id=registro::uuid;
  elsif origem='venda' then
    perform 1 from public.comercial_pedidos where id=registro::bigint;
  elsif origem='estoque' then
    select coalesce(estorno_de,id) into movimento_original from public.estoque_movimentos where id=registro::uuid;
  elsif origem='entrada_importacao' then
    perform 1 from public.imp_notas where id=registro::uuid;
  elsif origem='entrada' then
    perform 1 from public.compras_nfe_entradas where id=registro::uuid;
  else
    raise exception 'Origem tributária inválida';
  end if;
  if not found then raise exception 'Registro fiscal não encontrado'; end if;

  if origem in ('compra','entrada','estoque') then
    select coalesce(jsonb_agg(t || jsonb_build_object('nota',n.documento->>'numero','estado',n.estado)
      order by n.criado_em, (t->>'item')::int, t->>'imposto'),'[]') into fiscais
    from (
      select e.* from public.compras_nfe_entradas e
      where (origem='compra' and e.pedido_id=registro::uuid and e.estado='Confirmada')
         or (origem='entrada' and e.id=registro::uuid)
         or (origem='estoque' and exists (
           select 1 from public.compras_nfe_itens i where i.entrada_id=e.id and i.movimento_id=movimento_original))
    ) n
    cross join lateral jsonb_array_elements(coalesce(n.documento->'tributos',public.axe_nfe_tributos(n.xml_original))) t
    where origem<>'estoque' or exists (
      select 1 from public.compras_nfe_itens i
      where i.entrada_id=n.id and i.linha=(t->>'item')::int and i.movimento_id=movimento_original);
  end if;
  select * into atual from public.tributos_registros r where r.origem=tributos.origem and r.registro=tributos.registro;
  if acao='v2_tributos_ler' then
    return jsonb_build_object('linhas',coalesce(atual.linhas,'[]'),'fiscais',fiscais,'versao',coalesce(atual.versao,0),
      'editar',permissao->>'editar'='true' and origem<>'entrada' and (origem<>'estoque' or not exists(select 1 from public.compras_nfe_itens where movimento_id=movimento_original)));
  end if;
  if permissao->>'editar' is distinct from 'true' or origem='entrada'
    or (origem='estoque' and exists(select 1 from public.compras_nfe_itens where movimento_id=movimento_original)) then
    raise exception 'Registro tributário somente para consulta';
  end if;
  if jsonb_typeof(linhas) is distinct from 'array' or jsonb_array_length(linhas)>500 then
    raise exception 'Informe até 500 registros tributários';
  end if;
  for linha in select value from jsonb_array_elements(linhas) loop
    if coalesce(linha->>'imposto','') not in ('ICMS','ICMS ST','ICMS destino','ICMS remetente','FCP','FCP ST','FCP destino','IPI','PIS','PIS ST','COFINS','COFINS ST','II','ISS','IBS estadual','IBS municipal','IBS monofásico','CBS','CBS monofásica','IS')
      or coalesce(linha->>'natureza','') not in ('Previsto','Documentado','Recolhido')
      or length(coalesce(linha->>'item',''))>80
      or length(btrim(coalesce(linha->>'referencia','')))<3 or length(linha->>'referencia')>240
      or coalesce(linha->>'valor','') !~ '^[0-9]{1,12}(\.[0-9]{1,2})?$'
      or (nullif(linha->>'base','') is not null and linha->>'base' !~ '^[0-9]{1,12}(\.[0-9]{1,6})?$')
      or (nullif(linha->>'aliquota','') is not null and linha->>'aliquota' !~ '^[0-9]{1,5}(\.[0-9]{1,8})?$')
      or length(coalesce(linha->>'cst',''))>4 or length(coalesce(linha->>'classificacao',''))>12 then
      raise exception 'Confira imposto, valor, alíquota e referência de cada linha';
    end if;
  end loop;
  if exists (select 1 from jsonb_array_elements(linhas) x group by coalesce(x->>'item',''),x->>'imposto',x->>'natureza' having count(*)>1) then
    raise exception 'Informe cada tributo uma vez por item e natureza';
  end if;
  if coalesce(atual.versao,0) is distinct from (p_dados->>'versao')::int then raise exception 'Os tributos foram alterados. Reabra a consulta'; end if;
  if atual.versao is null then
    insert into public.tributos_registros(origem,registro,linhas,usuario_id)
    values(origem,registro,linhas,p_usuario) on conflict do nothing;
  else
    update public.tributos_registros r set linhas=tributos.linhas,versao=r.versao+1,
      usuario_id=p_usuario,atualizado_em=clock_timestamp()
    where r.origem=tributos.origem and r.registro=tributos.registro and r.versao=atual.versao;
  end if;
  if not found then raise exception 'Os tributos foram alterados. Reabra a consulta'; end if;
  return jsonb_build_object('versao',coalesce(atual.versao,0)+1);
end $$;
revoke all on function public.axe_nfe_tributos(text), public.axe_nfe_gravar_tributos(), public.axe_imp_estrutura(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_nfe_tributos(text), public.axe_nfe_gravar_tributos(), public.axe_imp_estrutura(jsonb,uuid) to service_role;

alter function public.axe_compra_nfe(jsonb,uuid) rename to axe_compra_nfe_sem_tributos;
create function public.axe_compra_nfe(p_dados jsonb,p_usuario uuid) returns jsonb
language plpgsql set search_path='' as $$
declare resposta jsonb;
begin
  resposta:=public.axe_compra_nfe_sem_tributos(p_dados,p_usuario);
  if p_dados->>'acao'='compra_nf_ler' then
    resposta:=jsonb_set(resposta,'{documento,tributos}',public.axe_nfe_tributos(p_dados->>'xml'));
  end if;
  return resposta;
end $$;
revoke all on function public.axe_compra_nfe(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_compra_nfe(jsonb,uuid) to service_role;
