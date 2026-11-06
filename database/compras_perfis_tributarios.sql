alter table public.imp_pedidos add column natureza_compra text not null default 'PRODUTO'
  check (natureza_compra in ('PRODUTO','SERVICO'));

create table public.compras_perfis_tributarios (
  perfil text primary key check (perfil in ('PRODUTO_NACIONAL','PRODUTO_IMPORTADO','SERVICO_NACIONAL','SERVICO_IMPORTADO')),
  impostos jsonb not null check (jsonb_typeof(impostos)='array'),
  versao integer not null default 1,
  atualizado_por uuid not null references auth.users(id),
  atualizado_em timestamptz not null default now()
);
alter table public.compras_perfis_tributarios enable row level security;
revoke all on public.compras_perfis_tributarios from public,anon,authenticated;
grant select,insert,update on public.compras_perfis_tributarios to service_role;

create function public.axe_compra_catalogo_tributos() returns text[]
language sql immutable set search_path='' as $$
 select array['ICMS','ICMS ST','ICMS destino','ICMS remetente','FCP','FCP ST','FCP destino','IPI',
 'PIS','PIS ST','COFINS','COFINS ST','II','ISS','IBS estadual','IBS municipal','IBS monofásico','CBS','CBS monofásica','IS','IRRF','INSS','CSLL','CIDE','IOF']::text[];
$$;
CREATE OR REPLACE FUNCTION public.axe_imp_pedido_catalogo(d jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare x jsonb;itens jsonb:='[]';p public.produtos_conciliacao;rid bigint;n int;
begin
 if d->>'natureza_compra'='SERVICO' then
  if exists(select 1 from jsonb_array_elements(d->'itens') i where nullif(i->>'produto_id','') is not null) then raise exception 'Desvincule produtos do estoque das linhas de serviço'; end if;
  return d;
 end if;
 for x in select value from jsonb_array_elements(d->'itens') loop
  rid:=nullif(x->>'produto_id','')::bigint;
  if rid is null then
   select count(*),min(pr.id) into n,rid from public.portal_produtos pr where pr.ativo and (pr.codigo_axe=nullif(x->>'codigo_axe','') or pr.codigo_anterior=nullif(x->>'codigo_axe','') or (nullif(x->>'codigo_fornecedor','') is not null and exists(select 1 from public.produtos_fornecedores pf where pf.produto_id=pr.id and pf.fornecedor_id=(d->>'fornecedor_id')::bigint and regexp_replace(upper(pf.codigo_fornecedor),'[^A-Z0-9]','','g')=regexp_replace(upper(x->>'codigo_fornecedor'),'[^A-Z0-9]','','g'))));
   if n<>1 then raise exception 'Linha %: selecione o produto do cadastro ou cadastre o produto identificado no documento',x->>'linha';end if;
  end if;
  select * into p from public.produtos_conciliacao where id=rid and ativo;if not found then raise exception 'Produto ativo não encontrado';end if;
  itens:=itens||jsonb_build_array(x||jsonb_build_object('produto_id',rid));
 end loop;
 return jsonb_set(d,'{itens}',itens);
end $function$
;

CREATE OR REPLACE FUNCTION public.axe_imp_processo_iniciado(pid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
select exists(select 1 from public.imp_pedidos p join public.fornecedores f on f.id=p.fornecedor_id where p.id=pid and p.natureza_compra='PRODUTO' and nullif(upper(btrim(f.pais)),'') is not null and upper(btrim(f.pais))<>'BR' and (p.status not in ('Elaboração','Cancelado') or exists(select 1 from public.imp_estrutura_eventos ev where ev.tipo='pedidos' and ev.registro_id=p.id and (ev.anterior->>'status' in ('Enviado','Emitido','Aceito -ACK','ACK recebido','Aguardando Entrega','Aguardando Recebimento','Recebimento Parcial','Recebido') or ev.atual->>'status' in ('Enviado','Emitido','Aceito -ACK','ACK recebido','Aguardando Entrega','Aguardando Recebimento','Recebimento Parcial','Recebido')))));
$function$
;

CREATE OR REPLACE FUNCTION public.axe_imp_estrutura_tributos_base(p_dados jsonb, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
    if not (coalesce(linha->>'imposto','') = any(public.axe_compra_catalogo_tributos()))
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
end $function$
;

alter function public.axe_imp_estrutura(jsonb,uuid) rename to axe_imp_estrutura_sem_perfis_compra;
create function public.axe_imp_estrutura(p_dados jsonb,p_usuario uuid) returns jsonb
language plpgsql set search_path='' as $$
<<tributos_config>>
declare
  acao text:=p_dados->>'acao';
  dados jsonb:=p_dados->'dados';
  resposta jsonb;
  pedido public.imp_pedidos;
  configuracao public.compras_perfis_tributarios;
  perfil_compra text;
  natureza text;
  impostos jsonb;
  administrador boolean;
begin
  if acao in ('v2_perfis_tributarios_ler','v2_perfis_tributarios_salvar') then
    perform public.axe_imp_estrutura_sem_perfis_compra('{"acao":"v2_opcoes"}'::jsonb,p_usuario);
    select exists(select 1 from public.gestao_membros where usuario_id=p_usuario and ativo and papel='ADMIN') into administrador;
    if acao='v2_perfis_tributarios_ler' then
      return jsonb_build_object('editar',administrador,'catalogo',public.axe_compra_catalogo_tributos(),
        'perfis',(select coalesce(jsonb_object_agg(p.perfil,jsonb_build_object('impostos',p.impostos,'versao',p.versao)),'{}') from public.compras_perfis_tributarios p));
    end if;
    if not administrador then raise exception 'A configuração de tributos exige acesso de administrador'; end if;
    perfil_compra:=p_dados->>'perfil';
    impostos:=p_dados->'impostos';
    if coalesce(perfil_compra,'') not in ('PRODUTO_NACIONAL','PRODUTO_IMPORTADO','SERVICO_NACIONAL','SERVICO_IMPORTADO')
      or jsonb_typeof(impostos) is distinct from 'array' then raise exception 'Perfil tributário inválido'; end if;
    if jsonb_array_length(impostos)>cardinality(public.axe_compra_catalogo_tributos())
      or exists(select 1 from jsonb_array_elements_text(impostos) i where i is null or not(i=any(public.axe_compra_catalogo_tributos())))
      or (select count(distinct i) from jsonb_array_elements_text(impostos) i)<>jsonb_array_length(impostos) then
      raise exception 'Selecione tributos válidos e sem repetição';
    end if;
    if p_dados->>'versao'='0' then
      insert into public.compras_perfis_tributarios(perfil,impostos,atualizado_por)
      values(perfil_compra,impostos,p_usuario) on conflict do nothing returning * into configuracao;
    else
      update public.compras_perfis_tributarios p
      set impostos=tributos_config.impostos,versao=p.versao+1,atualizado_por=p_usuario,atualizado_em=clock_timestamp()
      where p.perfil=perfil_compra and p.versao=(p_dados->>'versao')::int returning * into configuracao;
    end if;
    if not found then raise exception 'O perfil mudou. Reabra a configuração antes de salvar';end if;
    return jsonb_build_object('versao',configuracao.versao);
  end if;

  if acao='v2_salvar' and p_dados->>'tipo'='pedidos' then
    if not public.axe_compra_fin_autorizado(p_usuario) then raise exception 'Sem permissão para salvar pedido';end if;
    perform pg_advisory_xact_lock(728102826);
    if nullif(p_dados->>'id','') is not null then
      select * into pedido from public.imp_pedidos where id=(p_dados->>'id')::uuid for update;
    end if;
    natureza:=coalesce(dados->>'natureza_compra',pedido.natureza_compra,'PRODUTO');
    if natureza not in ('PRODUTO','SERVICO') then raise exception 'Selecione produto ou serviço';end if;
    if pedido.id is not null and natureza<>pedido.natureza_compra and pedido.status<>'Elaboração' then
      raise exception 'A natureza de um pedido enviado não pode ser alterada';
    end if;
    if natureza='SERVICO' and not (dados ? 'natureza_compra') then
      p_dados:=jsonb_set(p_dados,'{dados,natureza_compra}',to_jsonb(natureza));
    end if;
    resposta:=public.axe_imp_estrutura_sem_perfis_compra(p_dados,p_usuario);
    update public.imp_pedidos set natureza_compra=natureza where id=(resposta->>'id')::uuid and natureza_compra is distinct from natureza;
    return resposta;
  end if;

  resposta:=public.axe_imp_estrutura_sem_perfis_compra(p_dados,p_usuario);
  if acao='v2_tributos_ler' and p_dados->>'origem'='compra' then
    select p.natureza_compra||case when upper(btrim(f.pais))='BR' then '_NACIONAL'
      when nullif(btrim(f.pais),'') is not null then '_IMPORTADO' end into perfil_compra
    from public.imp_pedidos p join public.fornecedores f on f.id=p.fornecedor_id
    where p.id=(p_dados->>'registro')::uuid;
    select * into configuracao from public.compras_perfis_tributarios where perfil=perfil_compra;
    resposta:=resposta||jsonb_build_object('perfil',perfil_compra,'impostos_perfil',configuracao.impostos);
  end if;
  return resposta;
end $$;

alter function public.axe_compra_nfe(jsonb,uuid) rename to axe_compra_nfe_produtos;
create function public.axe_compra_nfe(p_dados jsonb,p_usuario uuid) returns jsonb
language plpgsql set search_path='' as $$
begin
  if p_dados->>'acao' in ('compra_nf_ler','compra_nf_confirmar') then
    if not public.axe_compra_fin_autorizado(p_usuario) then raise exception 'Sem permissão para registrar entrada';end if;
    perform pg_advisory_xact_lock(728102826);
    if exists(select 1 from public.imp_pedidos where id=(p_dados->>'pedido_id')::uuid and natureza_compra='SERVICO') then
      raise exception 'Pedido de serviço utiliza documento de serviço. A entrada de produtos não se aplica';
    end if;
  end if;
  return public.axe_compra_nfe_produtos(p_dados,p_usuario);
end $$;
revoke all on function public.axe_compra_catalogo_tributos(),public.axe_imp_estrutura(jsonb,uuid),public.axe_compra_nfe(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_compra_catalogo_tributos(),public.axe_imp_estrutura(jsonb,uuid),public.axe_compra_nfe(jsonb,uuid) to service_role;

create function public.axe_compra_impedir_embarque_servico() returns trigger
language plpgsql set search_path='' as $$
begin
  if exists (
    select 1 from public.imp_pedido_itens i join public.imp_pedidos p on p.id=i.pedido_id
    where i.id=new.pedido_item_id and p.natureza_compra='SERVICO'
  ) then
    raise exception 'Itens de serviço não podem ser vinculados a um embarque de mercadorias';
  end if;
  return new;
end $$;
revoke all on function public.axe_compra_impedir_embarque_servico() from public,anon,authenticated;
grant execute on function public.axe_compra_impedir_embarque_servico() to service_role;
create trigger imp_embarque_itens_sem_servicos
before insert or update of pedido_item_id on public.imp_embarque_itens
for each row execute function public.axe_compra_impedir_embarque_servico();
