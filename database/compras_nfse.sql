create table public.compras_nfse_entradas (
  id uuid primary key default gen_random_uuid(),
  pedido_id uuid not null unique references public.imp_pedidos(id),
  parcela_id uuid not null unique references public.imp_parcelas(id),
  chave text not null unique,
  documento jsonb not null,
  xml_original text not null,
  parcela_anterior jsonb not null,
  divergencias jsonb not null,
  justificativa text,
  registrado_por uuid not null,
  registrado_em timestamptz not null default now()
);
alter table public.compras_nfse_entradas enable row level security;
revoke all on public.compras_nfse_entradas from public,anon,authenticated;
grant select,insert on public.compras_nfse_entradas to service_role;

create function public.axe_nfse_texto(doc xml, caminho text) returns text
language sql immutable set search_path='' as $$
  select nullif(btrim((xpath('string('||caminho||')',doc,array[array['n','http://www.sped.fazenda.gov.br/nfse']]))[1]::text),'')
$$;

create function public.axe_nfse_ler_xml(conteudo text) returns jsonb
language plpgsql set search_path='' as $$
declare
  doc xml;
  h constant text:='/n:NFSe/n:infNFSe';
  d constant text:=h||'/n:DPS/n:infDPS';
  v constant text:=h||'/n:valores/';
  fed constant text:=d||'/n:valores/n:trib/n:tribFed/';
  chave text;
  bruto numeric;
  descontos numeric;
  retencoes numeric;
  liquido numeric;
  custo numeric;
  total_nf numeric;
  impostos jsonb;
begin
  if coalesce(octet_length(conteudo),0) not between 1 and 350000 or conteudo ~* '<![[:space:]]*(DOCTYPE|ENTITY)' then
    raise exception 'Selecione um XML de NFS-e de até 350 KB, sem declaração de entidades';
  end if;
  doc:=xmlparse(document conteudo);
  chave:=public.axe_nfse_texto(doc,h||'/@Id');
  if coalesce(chave,'') !~ '^NFS[0-9]{50}$' or coalesce(public.axe_nfse_texto(doc,h||'/n:cStat'),'') not in ('100','101','102','103','107')
     or public.axe_nfse_texto(doc,d||'/n:tpAmb') is distinct from '1'
     or public.axe_nfse_texto(doc,h||'/n:nNFSe') is null then
    raise exception 'Use o XML de uma NFS-e emitida em produção no padrão nacional';
  end if;
  if public.axe_nfse_texto(doc,d||'/n:toma/n:CNPJ') is distinct from '39893713000167' then
    raise exception 'O tomador da NFS-e deve ser o CNPJ da AXE';
  end if;
  bruto:=public.axe_nfse_texto(doc,d||'/n:valores/n:vServPrest/n:vServ')::numeric;
  descontos:=coalesce(public.axe_nfse_texto(doc,d||'/n:valores/n:vDescCondIncond/n:vDescCond')::numeric,0)
           +coalesce(public.axe_nfse_texto(doc,d||'/n:valores/n:vDescCondIncond/n:vDescIncond')::numeric,0);
  retencoes:=coalesce(public.axe_nfse_texto(doc,v||'n:vTotalRet')::numeric,0);
  liquido:=public.axe_nfse_texto(doc,v||'n:vLiq')::numeric;
  total_nf:=coalesce(public.axe_nfse_texto(doc,h||'/n:IBSCBS/n:totCIBS/n:vTotNF')::numeric,liquido);
  if bruto is null or liquido is null or bruto<=0 or descontos<0 or retencoes<0 or liquido<0 or total_nf<liquido
     or total_nf>=1e12 or bruto-descontos-retencoes<>liquido
     or exists(select 1 from unnest(array[bruto,descontos,retencoes,liquido,total_nf]) x where x::text in ('NaN','Infinity','-Infinity') or scale(x)>2 or x>=1e15) then
    raise exception 'Os valores de serviço, descontos, retenções e líquido do XML não fecham';
  end if;
  custo:=total_nf+retencoes;
  select coalesce(jsonb_agg(jsonb_build_object('nota',public.axe_nfse_texto(doc,h||'/n:nNFSe'),'imposto',t.nome,
    'valor',public.axe_nfse_texto(doc,t.valor)::numeric,'base',public.axe_nfse_texto(doc,t.base)::numeric,
    'aliquota',public.axe_nfse_texto(doc,t.aliquota)::numeric,'estado','Documentado') order by t.nome),'[]')
  into impostos from (values
    ('ISS',v||'n:vISSQN',v||'n:vBC',v||'n:pAliqAplic'),
    ('INSS',fed||'n:vRetCP',null,null),
    ('IRRF',fed||'n:vRetIRRF',null,null),
    ('CSLL',fed||'n:vRetCSLL',null,null),
    ('PIS',fed||'n:piscofins/n:vPis',fed||'n:piscofins/n:vBCPisCofins',fed||'n:piscofins/n:pAliqPis'),
    ('COFINS',fed||'n:piscofins/n:vCofins',fed||'n:piscofins/n:vBCPisCofins',fed||'n:piscofins/n:pAliqCofins'),
    ('IBS',h||'/n:IBSCBS/n:totCIBS/n:gIBS/n:vIBSTot',h||'/n:IBSCBS/n:valores/n:vBC',null),
    ('CBS',h||'/n:IBSCBS/n:totCIBS/n:gCBS/n:vCBS',h||'/n:IBSCBS/n:valores/n:vBC',h||'/n:IBSCBS/n:valores/n:gCBS/n:pCBSEfet')
  ) t(nome,valor,base,aliquota) where public.axe_nfse_texto(doc,t.valor) is not null;
  if exists(select 1 from jsonb_array_elements(impostos) i cross join lateral
    unnest(array[i->>'valor',i->>'base',i->>'aliquota']) n
    where n in ('NaN','Infinity','-Infinity') or n::numeric<0 or n::numeric>=1e15) then
    raise exception 'O XML contém valores tributários inválidos';
  end if;
  return jsonb_build_object('chave',chave,'numero',public.axe_nfse_texto(doc,h||'/n:nNFSe'),
    'cnpj',public.axe_nfse_texto(doc,h||'/n:emit/n:CNPJ'),'emissao',public.axe_nfse_texto(doc,h||'/n:dhProc'),
    'bruto',bruto,'descontos',descontos,'retencoes',retencoes,'liquido',total_nf,'custo',custo,'tributos',impostos);
end
$$;

alter function public.axe_imp_programar_parcelas(uuid,uuid) rename to axe_imp_programar_parcelas_sem_nfse;
create function public.axe_imp_programar_parcelas(pid uuid,uid uuid) returns void
language plpgsql set search_path='' as $$
begin
  perform 1 from public.imp_pedidos where id=pid for update;
  if not exists(select 1 from public.compras_nfse_entradas where pedido_id=pid) then
    perform public.axe_imp_programar_parcelas_sem_nfse(pid,uid);
  end if;
end
$$;

alter function public.axe_imp_estrutura(jsonb,uuid) rename to axe_imp_estrutura_sem_nfse;
create function public.axe_imp_estrutura(p_dados jsonb,p_usuario uuid) returns jsonb
language plpgsql set search_path='' as $$
declare
  acao text:=p_dados->>'acao';
  pid uuid;
  pedido public.imp_pedidos;
  parcela public.imp_parcelas;
  nota public.compras_nfse_entradas;
  previsto jsonb;
  esperado numeric;
  doc_fiscal jsonb;
  divergencias jsonb;
  resposta jsonb;
  resumo jsonb;
  assinatura text;
  motivo text;
  fornecedor text;
begin
  if acao not in ('v2_nfse_listar','v2_nfse_conferir','v2_nfse_confirmar') then
    resposta:=public.axe_imp_estrutura_sem_nfse(p_dados,p_usuario);
    if acao='v2_tributos_ler' and p_dados->>'origem'='compra' then
      select documento into doc_fiscal from public.compras_nfse_entradas where pedido_id::text=p_dados->>'registro';
      if found then resposta:=jsonb_set(resposta,'{fiscais}',coalesce(resposta->'fiscais','[]')||(doc_fiscal->'tributos')); end if;
    end if;
    return resposta;
  end if;

  pid:=(p_dados->>'pedido_id')::uuid;
  perform public.axe_imp_estrutura_sem_nfse('{"acao":"v2_opcoes"}',p_usuario);
  if acao='v2_nfse_confirmar' then perform pg_advisory_xact_lock(728102826); end if;
  select * into pedido from public.imp_pedidos where id=pid for update;
  select regexp_replace(coalesce(f.cnpj,f.documento_fiscal,''),'\D','','g') into fornecedor
    from public.fornecedores f where f.id=pedido.fornecedor_id and upper(btrim(f.pais))='BR';
  if pedido.id is null or pedido.natureza_compra<>'SERVICO' or pedido.moeda<>'BRL' or fornecedor is null then
    raise exception 'Selecione um pedido de serviço nacional';
  end if;

  select * into nota from public.compras_nfse_entradas where pedido_id=pid;
  if acao='v2_nfse_listar' then
    return jsonb_build_object('editar',public.axe_compra_fin_autorizado(p_usuario),'nota',nota.documento,'registrado_em',nota.registrado_em);
  end if;
  if not public.axe_compra_fin_autorizado(p_usuario) then raise exception 'Acesso de edição necessário'; end if;
  if pedido.status='Cancelado' then raise exception 'Pedido cancelado'; end if;
  doc_fiscal:=public.axe_nfse_ler_xml(p_dados->>'xml');
  if doc_fiscal->>'cnpj' is distinct from fornecedor or fornecedor !~ '^[0-9]{14}$' then
    raise exception 'O CNPJ do prestador diverge do fornecedor do pedido';
  end if;
  if nota.id is not null then
    if nota.chave=doc_fiscal->>'chave' and nota.xml_original=p_dados->>'xml' then
      return jsonb_build_object('nota',nota.documento,'confirmada',true);
    end if;
    raise exception 'Já existe NFS-e registrada neste pedido';
  end if;
  if exists(select 1 from public.compras_nfse_entradas where chave=doc_fiscal->>'chave') then
    raise exception 'Esta NFS-e já está vinculada a outro pedido';
  end if;
  select * into parcela from public.imp_parcelas where pedido_id=pid and status<>'Cancelada' order by id limit 1 for update;
  if parcela.id is null or (select count(*) from public.imp_parcelas where pedido_id=pid and status<>'Cancelada')<>1 then
    raise exception 'A entrada exige uma única parcela ativa já cadastrada no pedido';
  end if;
  if (doc_fiscal->>'liquido')::numeric < parcela.valor_pago then
    raise exception 'O valor líquido da NFS-e é menor que o pagamento já registrado';
  end if;
  select r.linhas,r.total_documento into previsto,esperado from public.tributos_registros r where r.origem='compra' and r.registro=pid::text for update;
  esperado:=coalesce(esperado,parcela.valor);
  select coalesce(jsonb_agg(jsonb_build_object('imposto',coalesce(a.imposto,b.imposto),'pedido',a.valor,'nota',b.valor,
     'aliquota_pedido',a.aliquota,'aliquota_nota',b.aliquota) order by coalesce(a.imposto,b.imposto)),'[]') into divergencias
  from (select upper(i->>'imposto') imposto,sum(nullif(i->>'valor','')::numeric) valor,max(nullif(i->>'aliquota','')::numeric) aliquota
        from jsonb_array_elements(coalesce(previsto,'[]')) i group by 1) a
  full join (select i->>'imposto' imposto,(i->>'valor')::numeric valor,(i->>'aliquota')::numeric aliquota
        from jsonb_array_elements(doc_fiscal->'tributos') i) b using(imposto)
  where coalesce(a.valor,0)<>coalesce(b.valor,0) or a.aliquota is distinct from b.aliquota;

  resumo:=jsonb_build_object('nota',doc_fiscal,'divergencias',divergencias,'custo_previsto',esperado,
    'parcela',jsonb_build_object('valor',parcela.valor,'valor_pago',parcela.valor_pago,'vencimento',parcela.vencimento),
    'exige_confirmacao',divergencias<>'[]' or esperado<>(doc_fiscal->>'custo')::numeric or parcela.valor<>(doc_fiscal->>'liquido')::numeric);
  assinatura:=sha256(convert_to(jsonb_build_array(resumo,parcela.id,parcela.versao,sha256(convert_to(p_dados->>'xml','UTF8'))::text)::text,'UTF8'))::text;
  if acao='v2_nfse_conferir' then return resumo||jsonb_build_object('conferencia',assinatura); end if;
  if assinatura is distinct from p_dados->>'conferencia' then raise exception 'O pedido ou a parcela mudou. Leia o XML novamente'; end if;
  motivo:=nullif(btrim(p_dados->>'justificativa'),'');
  if (resumo->>'exige_confirmacao')::boolean and (p_dados->>'aceite' is distinct from 'true' or coalesce(length(motivo),0)<5) then
    raise exception 'Confirme a divergência e informe a justificativa antes de registrar';
  end if;
  insert into public.compras_nfse_entradas(pedido_id,parcela_id,chave,documento,xml_original,parcela_anterior,divergencias,justificativa,registrado_por)
  values(pid,parcela.id,doc_fiscal->>'chave',doc_fiscal,p_dados->>'xml',to_jsonb(parcela),divergencias,left(motivo,1000),p_usuario)
  returning * into nota;
  update public.imp_parcelas
    set valor=case when (doc_fiscal->>'liquido')::numeric>0 then (doc_fiscal->>'liquido')::numeric else parcela.valor end,
        modo='Valor',percentual=null,marco='Manual',data_base=parcela.vencimento,dias=0,
        status=case when (doc_fiscal->>'liquido')::numeric=0 then 'Cancelada' else parcela.status end,
        financeiro=financeiro||jsonb_build_object('automatico',false,'fase','Confirmado','nfse_id',nota.id,'nfse_numero',doc_fiscal->>'numero'),
        versao=versao+1,atualizado_por=p_usuario,atualizado_em=clock_timestamp()
    where id=parcela.id;
  insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)
  values('parcelas',parcela.id,p_usuario,to_jsonb(parcela),(select to_jsonb(p) from public.imp_parcelas p where p.id=parcela.id));
  return jsonb_build_object('nota',doc_fiscal,'confirmada',true);
end
$$;

revoke all on function public.axe_nfse_texto(xml,text),public.axe_nfse_ler_xml(text),public.axe_imp_programar_parcelas(uuid,uuid),public.axe_imp_estrutura(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_nfse_texto(xml,text),public.axe_nfse_ler_xml(text),public.axe_imp_programar_parcelas(uuid,uuid),public.axe_imp_estrutura(jsonb,uuid) to service_role;

create function public.axe_nfse_proteger_parcela() returns trigger
language plpgsql set search_path='' as $$
declare
  nota public.compras_nfse_entradas;
  liquido numeric;
begin
  select * into nota from public.compras_nfse_entradas where pedido_id=new.pedido_id;
  if not found then return new; end if;
  if tg_op='INSERT' then
    if new.status='Cancelada' then return new; end if;
    raise exception 'O pedido já tem parcela conciliada pela NFS-e';
  end if;
  if new.id<>nota.parcela_id then
    if new.status='Cancelada' then return new; end if;
    raise exception 'O pedido já tem parcela conciliada pela NFS-e';
  end if;
  liquido:=(nota.documento->>'liquido')::numeric;
  if new.vencimento is distinct from nullif(nota.parcela_anterior->>'vencimento','')::date
     or new.modo<>'Valor' or new.marco<>'Manual'
     or (liquido>0 and (new.valor<>liquido or new.status='Cancelada'))
     or (liquido=0 and new.status<>'Cancelada') then
    raise exception 'Preserve o valor e o vencimento da parcela conciliada pela NFS-e';
  end if;
  return new;
end
$$;
revoke all on function public.axe_nfse_proteger_parcela() from public,anon,authenticated;
grant execute on function public.axe_nfse_proteger_parcela() to service_role;
create trigger axe_nfse_proteger_parcela before insert or update on public.imp_parcelas
for each row execute function public.axe_nfse_proteger_parcela();

-- A baixa usa o limite fiscal da parcela vinculada, inclusive quando o serviço
-- documentado custa mais que o previsto no pedido.
do $$
declare
  definicao text:=pg_get_functiondef('public.axe_imp_estrutura_sem_financeiro_nacional(jsonb,uuid)'::regprocedure);
  original constant text:='if valor is null or valor<=0 or valor>=1e12 then raise exception ''Valor da parcela inválido'';end if;';
  ajuste constant text:='select greatest(total,coalesce((select (n.documento->>''liquido'')::numeric from public.compras_nfse_entradas n where n.pedido_id=pedido.id and n.parcela_id=i),0)) into total;';
begin
  if strpos(definicao,original)=0 then raise exception 'Validação de parcela incompatível com a migração de NFS-e'; end if;
  execute replace(definicao,original,original||E'\n  '||ajuste);
end
$$;
