begin;
CREATE OR REPLACE FUNCTION public.axe_imp_nf_proteger_origem()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare bloqueado boolean:=false;
begin
 perform pg_advisory_xact_lock(728102826);
 if tg_table_name='imp_fin_documentos' then
  select exists(select 1 from public.imp_nota_vinculos v join public.imp_notas n on n.id=v.nota_id where v.declaracao_id=old.id and n.estado='Conciliada') into bloqueado;
  if tg_op='UPDATE' and (to_jsonb(new)-array['versao','atualizado_em','atualizado_por'])=(to_jsonb(old)-array['versao','atualizado_em','atualizado_por']) then bloqueado:=false;end if;
 elsif tg_table_name='imp_fin_pedidos' then
  select exists(select 1 from public.imp_nota_vinculos v join public.imp_notas n on n.id=v.nota_id join public.imp_pedido_itens pi on pi.id=v.pedido_item_id where v.declaracao_id=old.documento_id and pi.pedido_id=old.pedido_id and n.estado='Conciliada') into bloqueado;
 elsif tg_table_name='imp_pedido_itens' then
  select exists(select 1 from public.imp_nota_vinculos v join public.imp_notas n on n.id=v.nota_id where v.pedido_item_id=old.id and n.estado='Conciliada') into bloqueado;
  if tg_op='UPDATE' and (to_jsonb(new)-array['disponibilizada','data_disponibilidade'])=(to_jsonb(old)-array['disponibilizada','data_disponibilidade']) then bloqueado:=false;end if;
 elsif tg_table_name='imp_pedidos' then
  select exists(select 1 from public.imp_nota_vinculos v join public.imp_notas n on n.id=v.nota_id join public.imp_pedido_itens pi on pi.id=v.pedido_item_id where pi.pedido_id=old.id and n.estado='Conciliada') into bloqueado;
  if tg_op='UPDATE' and new.referencia=old.referencia and new.fornecedor_id=old.fornecedor_id and new.moeda=old.moeda and (new.status=old.status or (new.status in ('Elaboração','Enviado','Aceito -ACK','Aguardando Recebimento','Aguardando Entrega','Recebimento Parcial','Recebido') and old.status in ('Rascunho','Emitido','ACK recebido','Elaboração','Enviado','Aceito -ACK','Aguardando Recebimento','Aguardando Entrega','Recebimento Parcial','Recebido'))) then bloqueado:=false;end if;
 end if;
 if bloqueado then raise exception 'Origem possui nota conciliada. Reabra a conciliação antes de alterar o vínculo';end if;
 return case when tg_op='DELETE' then old else new end;
end $function$;
alter table public.imp_pedidos drop constraint imp_pedidos_status_check;
create or replace function public.axe_imp_processo_iniciado(pid uuid) returns boolean language sql stable set search_path='' as $fn$
select exists(select 1 from public.imp_pedidos p join public.fornecedores f on f.id=p.fornecedor_id where p.id=pid and nullif(upper(btrim(f.pais)),'') is not null and upper(btrim(f.pais))<>'BR' and (p.status not in ('Elaboração','Cancelado') or exists(select 1 from public.imp_estrutura_eventos ev where ev.tipo='pedidos' and ev.registro_id=p.id and (ev.anterior->>'status' in ('Enviado','Emitido','Aceito -ACK','ACK recebido','Aguardando Entrega','Aguardando Recebimento','Recebimento Parcial','Recebido') or ev.atual->>'status' in ('Enviado','Emitido','Aceito -ACK','ACK recebido','Aguardando Entrega','Aguardando Recebimento','Recebimento Parcial','Recebido')))));
$fn$;
revoke all on function public.axe_imp_processo_iniciado(uuid) from public,anon,authenticated;
grant execute on function public.axe_imp_processo_iniciado(uuid) to service_role;
create or replace function public.axe_imp_status_processo(pid uuid) returns text language sql stable set search_path='' as $fn$
select case when p.status in ('Cancelado','Recebido','Recebimento Parcial') then p.status when p.status='Aceito -ACK' or exists(select 1 from public.imp_acks a where a.pedido_id=p.id and a.aplicado_em is not null) or exists(select 1 from public.imp_estrutura_eventos ev where ev.tipo='pedidos' and ev.registro_id=p.id and (ev.atual->>'status'='Aceito -ACK' or ev.anterior->>'status'='Aceito -ACK')) or (p.ack_numero is not null and p.ack_data is not null) then 'Aguardando Entrega' else 'Aguardando aceite' end from public.imp_pedidos p where p.id=pid;
$fn$;
revoke all on function public.axe_imp_status_processo(uuid) from public,anon,authenticated;
grant execute on function public.axe_imp_status_processo(uuid) to service_role;
CREATE OR REPLACE FUNCTION public.axe_imp_recalcular_status_pedido(pid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare p public.imp_pedidos; novo text; itens int; completos int; recebidos numeric; embarcado boolean;
begin
 select * into p from public.imp_pedidos where id=pid for update;
 if not found or p.status='Cancelado' then return;end if;
 select count(*),count(*) filter(where recebida>=quantidade),coalesce(sum(recebida),0) into itens,completos,recebidos
 from (select pi.quantidade,coalesce((select sum(ei.recebida) from public.imp_embarque_itens ei join public.imp_embarques e on e.id=ei.embarque_id where ei.pedido_item_id=pi.id and e.status<>'Cancelado'),0) recebida from public.imp_pedido_itens pi where pi.pedido_id=pid) s;
 select exists(select 1 from public.imp_embarque_itens ei join public.imp_pedido_itens pi on pi.id=ei.pedido_item_id join public.imp_embarques e on e.id=ei.embarque_id where pi.pedido_id=pid and e.status<>'Cancelado') into embarcado;
 novo:=case when itens>0 and completos=itens then 'Recebido' when recebidos>0 then 'Recebimento Parcial' when p.status='Aceito -ACK' or (embarcado and (p.ack_numero is not null and p.ack_data is not null or exists(select 1 from public.imp_estrutura_eventos ev where ev.registro_id=p.id and ev.tipo='pedidos' and (ev.atual->>'status'='Aceito -ACK' or ev.anterior->>'status'='Aceito -ACK')))) then 'Aguardando Entrega' when p.status in ('Recebido','Recebimento Parcial') then case when p.ack_numero is not null and p.ack_data is not null then 'Aceito -ACK' else 'Enviado' end else p.status end;
 if novo is distinct from p.status then
  update public.imp_pedidos set status=novo,versao=versao+1,atualizado_em=clock_timestamp() where id=pid;
  insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('pedidos',pid,p.atualizado_por,jsonb_build_object('status',p.status),jsonb_build_object('status',novo,'origem','Quantidades dos itens e embarques ativos'));
 end if;
end $function$;
CREATE OR REPLACE FUNCTION public.axe_imp_fluxo(p_dados jsonb, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare a text:=p_dados->>'acao';pid uuid;eid uuid;papel text;p jsonb;shipids uuid[];r jsonb;page int;term text;before jsonb;
begin
 select m.papel into papel from public.gestao_membros m join public.axe_rumo_revisores rv on rv.usuario_id=m.usuario_id and rv.ativo where m.usuario_id=p_usuario and m.ativo;
 if papel is null then raise exception 'Sem acesso às importações';end if;
 if a='custo_fluxo_declaracao_vincular' then
   if papel not in ('ADMIN','EDITOR') then raise exception 'Sem permissão para vincular declaração';end if;
   eid:=(p_dados->>'embarque_id')::uuid;perform pg_advisory_xact_lock(728102826);
   if not exists(select 1 from public.imp_embarques e join public.imp_fin_documentos di on di.id=(p_dados->>'declaracao_id')::uuid and di.tipo='declaracoes' and di.status='Ativo' and di.fornecedor_id=e.fornecedor_id and di.moeda=e.moeda where e.id=eid and e.status<>'Cancelado') then raise exception 'Selecione uma declaração ativa deste fornecedor e moeda';end if;
   insert into public.imp_embarque_declaracoes values(eid,(p_dados->>'declaracao_id')::uuid) on conflict do nothing;
   insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('embarques',eid,p_usuario,null,jsonb_build_object('evento','DI/DUIMP vinculada ao embarque','declaracao_id',p_dados->>'declaracao_id'));
   return jsonb_build_object('embarque_id',eid);
  end if;
 if a='custo_fluxo_estoque_confirmar' then
  if papel not in ('ADMIN','EDITOR') or p_dados->>'confirmado' is distinct from 'true' then raise exception 'Confirme a entrada já realizada no estoque';end if;
  eid:=(p_dados->>'embarque_id')::uuid;perform pg_advisory_xact_lock(728102826);
  if not exists(select 1 from public.imp_embarques where id=eid and status='Recebido') then raise exception 'Confirme antes o recebimento integral do embarque';end if;
  if not exists(select 1 from public.imp_notas where id=(p_dados->>'nota_id')::uuid and embarque_id=eid and estado='Conciliada') then raise exception 'Vincule uma nota conciliada deste embarque';end if;
  if nullif(p_dados->>'data_entrada','') is null then raise exception 'Informe a data da entrada realizada';end if;
  select to_jsonb(c) into before from public.imp_fluxo_estoque_confirmacoes c where embarque_id=eid;
  if before is not null then raise exception 'Entrada já confirmada; consulte o histórico';end if;
  insert into public.imp_fluxo_estoque_confirmacoes(embarque_id,nota_id,data_entrada,referencia,usuario_id)values(eid,(p_dados->>'nota_id')::uuid,(p_dados->>'data_entrada')::date,(select 'NF-e '||chave from public.imp_notas where id=(p_dados->>'nota_id')::uuid),p_usuario);
  insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('embarques',eid,p_usuario,before,jsonb_build_object('evento','Entrada de estoque realizada no Nomus confirmada','dados',p_dados));return jsonb_build_object('embarque_id',eid);
 end if;
 if a='custo_fluxo_listar' then
  page:=coalesce((p_dados->>'pagina')::int,0);term:=left(coalesce(p_dados->>'busca',''),120);if page<0 or page>100000 then raise exception 'Página inválida';end if;
  return jsonb_build_object('total',(select count(*) from public.imp_pedidos p where public.axe_imp_processo_iniciado(p.id) and p.referencia ilike '%'||term||'%'), 'linhas',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select p.id,p.referencia,p.status,public.axe_imp_status_processo(p.id) status_processo,f.razao_social fornecedor,p.moeda,(select sum(round(pi.quantidade*pi.valor_unitario,2)) from public.imp_pedido_itens pi where pi.pedido_id=p.id) total,(select coalesce(sum(pa.valor_pago),0) from public.imp_parcelas pa where pa.pedido_id=p.id and pa.status<>'Cancelada') pago,(select count(distinct ei.embarque_id) from public.imp_embarque_itens ei join public.imp_pedido_itens pi on pi.id=ei.pedido_item_id join public.imp_embarques em on em.id=ei.embarque_id where pi.pedido_id=p.id and em.status<>'Cancelado') embarques from public.imp_pedidos p join public.fornecedores f on f.id=p.fornecedor_id where public.axe_imp_processo_iniciado(p.id) and p.referencia ilike '%'||term||'%' order by p.atualizado_em desc,p.id limit 30 offset page*30)z));
 end if;
 if a<>'custo_fluxo_detalhe' then raise exception 'Ação inválida';end if;
 pid:=(p_dados->>'pedido_id')::uuid;p:=public.axe_imp_estrutura_detalhe('pedidos',pid);if p is null then raise exception 'Pedido não encontrado';end if;if not public.axe_imp_processo_iniciado(pid) then raise exception 'O processo de importação inicia no envio do pedido a um fornecedor estrangeiro';end if;p:=p||jsonb_build_object('status_processo',public.axe_imp_status_processo(pid));
 select jsonb_set(p,'{itens}',coalesce(jsonb_agg(x.value||jsonb_build_object('produto_codigo',pr.codigo_axe,'produto_nome',pr.descricao_referencia)),'[]')) into p from jsonb_array_elements(p->'itens')x(value) left join public.produtos_conciliacao pr on pr.id=nullif(x.value->>'produto_id','')::bigint;
 select coalesce(array_agg(distinct ei.embarque_id),'{}') into shipids from public.imp_embarque_itens ei join public.imp_pedido_itens pi on pi.id=ei.pedido_item_id join public.imp_embarques em on em.id=ei.embarque_id where pi.pedido_id=pid and em.status<>'Cancelado';
 return jsonb_build_object('pedido',p,'editar',papel in ('ADMIN','EDITOR'),
 'declaracoes_pedido',(select coalesce(jsonb_agg(public.axe_imp_fin_detalhe('declaracoes',di.id)),'[]') from public.imp_fin_documentos di where di.tipo='declaracoes' and di.status='Ativo' and di.fornecedor_id=(p->>'fornecedor_id')::bigint and di.moeda=p->>'moeda'),
 'acks',(select coalesce(jsonb_agg(to_jsonb(x)-'paginas'-'extraido'),'[]') from public.imp_acks x where x.pedido_id=pid),
 'parcelas',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.imp_parcelas x where x.pedido_id=pid),
 'remessas',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select rm.id,rm.contrato_id,cd.referencia contrato,rm.referencia,rm.moeda,rm.valor,rm.data_pagamento,rm.arquivo_id,rp.parcela_id,sum(rp.valor) valor_no_pedido from public.imp_remessas rm join public.imp_remessa_parcelas rp on rp.remessa_id=rm.id join public.imp_parcelas pa on pa.id=rp.parcela_id join public.imp_fin_documentos cd on cd.id=rm.contrato_id where pa.pedido_id=pid group by rm.id,cd.referencia,rp.parcela_id)z),
 'contratos',(select coalesce(jsonb_agg(public.axe_imp_fin_detalhe('contratos',cd.id)),'[]') from public.imp_fin_documentos cd join public.imp_fin_pedidos fp on fp.documento_id=cd.id where fp.pedido_id=pid and cd.tipo='contratos'),
 'arquivos_banco',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from public.imp_cambio_arquivos x join public.imp_fin_pedidos fp on fp.documento_id=x.contrato_id where fp.pedido_id=pid),
 'embarques',(select coalesce(jsonb_agg(jsonb_build_object('embarque',public.axe_imp_estrutura_detalhe('embarques',sid),'financeiro',public.axe_imp_financeiro_embarque(sid),
 'liberacoes',(select coalesce(jsonb_agg(to_jsonb(l)-'extraido'),'[]') from public.imp_liberacoes l where l.embarque_id=sid),
 'arquivos_carga',(select coalesce(jsonb_agg(to_jsonb(fa)),'[]') from public.imp_liberacao_arquivos fa join public.imp_liberacoes l on l.id=fa.liberacao_id where l.embarque_id=sid),
 'transporte',(select to_jsonb(tr) from public.imp_transporte_revisoes tr where tr.embarque_id=sid order by versao desc limit 1),
 'arquivos_transporte',(select coalesce(jsonb_agg(to_jsonb(fa)),'[]') from public.imp_transporte_arquivos fa where fa.embarque_id=sid),
 'declaracoes',(select coalesce(jsonb_agg(public.axe_imp_fin_detalhe('declaracoes',cd.id)||jsonb_build_object('documento_importado',exists(select 1 from public.imp_di_leituras dl where dl.declaracao_id=cd.id and dl.pronto))),'[]') from public.imp_fin_documentos cd where cd.tipo='declaracoes' and cd.id in (select ed.declaracao_id from public.imp_embarque_declaracoes ed where ed.embarque_id=sid union select nv.declaracao_id from public.imp_nota_vinculos nv join public.imp_notas nt on nt.id=nv.nota_id where nt.embarque_id=sid union select fe.declaracao_id from public.imp_fechamentos fe where fe.embarque_id=sid union select nullif(tr.dados->>'duimp_id','')::uuid from public.imp_transporte_revisoes tr where tr.embarque_id=sid)),
 'notas',(select coalesce(jsonb_agg(to_jsonb(nt)-'xml'),'[]') from public.imp_notas nt where nt.embarque_id=sid),
 'fechamentos',(select coalesce(jsonb_agg(to_jsonb(fe)-'extraido'-'paginas'||jsonb_build_object('importado',exists(select 1 from public.imp_fech_importacoes fi where fi.fechamento_id=fe.id))),'[]') from public.imp_fechamentos fe where fe.embarque_id=sid),
 'custo',(select to_jsonb(cu) from public.imp_custos cu where cu.embarque_id=sid),
 'estoque',(select to_jsonb(st) from public.imp_fluxo_estoque_confirmacoes st where st.embarque_id=sid)
 )),'[]') from unnest(shipids) sid),
 'historico',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select ev.id,ev.tipo,ev.registro_id,ev.criado_em,ev.atual->>'evento' evento from public.imp_estrutura_eventos ev where ev.registro_id in(select nt.id from public.imp_notas nt where nt.embarque_id=any(shipids)) or ev.registro_id in(select fe.id from public.imp_fechamentos fe where fe.embarque_id=any(shipids)) or ev.registro_id in(select ed.declaracao_id from public.imp_embarque_declaracoes ed where ed.embarque_id=any(shipids)) or ev.registro_id=pid or ev.registro_id=any(shipids) or ev.registro_id in(select pa.id from public.imp_parcelas pa where pa.pedido_id=pid) or ev.registro_id in(select fp.documento_id from public.imp_fin_pedidos fp where fp.pedido_id=pid) order by ev.id desc limit 100)z));
end $function$;
with changes as(update public.imp_pedidos set status='Aguardando Entrega',versao=versao+1,atualizado_em=clock_timestamp() where status='Aguardando Recebimento' returning id,atualizado_por)
insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)select 'pedidos',id,atualizado_por,jsonb_build_object('status','Aguardando Recebimento'),jsonb_build_object('status','Aguardando Entrega','origem','Fluxo de envio e aceite do PO') from changes;

set constraints all immediate;
alter table public.imp_pedidos add constraint imp_pedidos_status_check check(status in ('Elaboração','Enviado','Aceito -ACK','Aguardando Entrega','Recebimento Parcial','Recebido','Cancelado'));

do $run$declare p record;begin for p in select id from public.imp_pedidos loop perform public.axe_imp_recalcular_status_pedido(p.id);end loop;end $run$;
commit;
