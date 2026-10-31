begin;
create or replace function public.axe_imp_valor_processo_pedido(proc uuid,pid uuid) returns numeric language sql stable set search_path='' as $fn$
 select coalesce((select sum(round(ei.quantidade*pi.valor_unitario,2)) from public.imp_importacao_embarques pe join public.imp_embarques em on em.id=pe.embarque_id and em.status<>'Cancelado' join public.imp_embarque_itens ei on ei.embarque_id=em.id join public.imp_pedido_itens pi on pi.id=ei.pedido_item_id and pi.pedido_id=pid where public.axe_imp_processo_raiz(pe.processo_id)=public.axe_imp_processo_raiz(proc)),(select sum(round(it.quantidade*pi.valor_unitario,2)) from public.imp_importacao_itens it join public.imp_pedido_itens pi on pi.id=it.pedido_item_id and pi.pedido_id=pid where public.axe_imp_processo_raiz(it.processo_id)=public.axe_imp_processo_raiz(proc)),0);
$fn$;
create or replace function public.axe_imp_transferir_credito_processo(anterior uuid,seguinte uuid,uid uuid) returns void language plpgsql set search_path='' as $fn$
declare ap public.imp_remessa_processos;consumido numeric;credito numeric;
begin
 for ap in select * from public.imp_remessa_processos a where public.axe_imp_processo_raiz(a.processo_id)=anterior loop
  if not exists(select 1 from public.imp_importacao_pedidos pp where pp.pedido_id=ap.pedido_id and public.axe_imp_processo_raiz(pp.processo_id)=seguinte) then continue;end if;
  select coalesce(sum(cp.valor_me),0) into consumido from public.imp_custo_pagamentos cp join public.imp_pedido_itens pi on pi.id=cp.pedido_item_id and pi.pedido_id=ap.pedido_id join public.imp_importacao_embarques pe on pe.embarque_id=cp.embarque_id where cp.remessa_id=ap.remessa_id and public.axe_imp_processo_raiz(pe.processo_id)=anterior;
  if exists(select 1 from public.imp_custo_pagamentos cp join public.imp_remessas rm on rm.id=ap.remessa_id and rm.contrato_id=cp.contrato_id join public.imp_pedido_itens pi on pi.id=cp.pedido_item_id and pi.pedido_id=ap.pedido_id join public.imp_importacao_embarques pe on pe.embarque_id=cp.embarque_id where cp.remessa_id is null and public.axe_imp_processo_raiz(pe.processo_id)=anterior) then continue;end if;
  credito:=least(greatest(0,ap.valor-consumido),greatest(0,public.axe_imp_valor_processo_pedido(seguinte,ap.pedido_id)-coalesce((select sum(v.valor) from public.imp_remessa_processos v where v.pedido_id=ap.pedido_id and public.axe_imp_processo_raiz(v.processo_id)=seguinte),0)));if credito<=0 then continue;end if;
  if credito=ap.valor then delete from public.imp_remessa_processos where remessa_id=ap.remessa_id and processo_id=ap.processo_id and pedido_id=ap.pedido_id;
  else update public.imp_remessa_processos set valor=ap.valor-credito,usuario_id=uid,atualizado_em=clock_timestamp() where remessa_id=ap.remessa_id and processo_id=ap.processo_id and pedido_id=ap.pedido_id;end if;
  insert into public.imp_remessa_processos(remessa_id,processo_id,pedido_id,valor,usuario_id)values(ap.remessa_id,seguinte,ap.pedido_id,credito,uid)on conflict(remessa_id,processo_id,pedido_id)do update set valor=imp_remessa_processos.valor+excluded.valor,atualizado_em=clock_timestamp();
  insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('processos',seguinte,uid,null,jsonb_build_object('evento','Crédito não consumido transferido à próxima parcial','processo_anterior',anterior,'remessa_id',ap.remessa_id,'pedido_id',ap.pedido_id,'valor',credito));
 end loop;
end $fn$;
revoke all on function public.axe_imp_valor_processo_pedido(uuid,uuid),public.axe_imp_transferir_credito_processo(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.axe_imp_valor_processo_pedido(uuid,uuid),public.axe_imp_transferir_credito_processo(uuid,uuid,uuid) to service_role;

CREATE OR REPLACE FUNCTION public.axe_imp_processos_reconciliar(uid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare p record;emrow record;pr public.imp_importacao_processos;pid uuid;dest uuid;r record;pendentes uuid[];saldos numeric;seguinte uuid;
begin
 if not exists(select 1 from public.gestao_membros m join public.axe_rumo_revisores rv on rv.usuario_id=m.usuario_id and rv.ativo where m.usuario_id=uid and m.ativo and m.papel in('ADMIN','EDITOR')) then return;end if;
 perform pg_advisory_xact_lock(728102826);
 for p in select * from public.imp_pedidos where public.axe_imp_processo_iniciado(id) and status<>'Cancelado' loop
  select public.axe_imp_processo_raiz(pp.processo_id) into pid from public.imp_importacao_pedidos pp join public.imp_importacao_processos root on root.id=public.axe_imp_processo_raiz(pp.processo_id) and root.estado='Aberto' where pp.pedido_id=p.id order by pp.parcial desc limit 1;
  if pid is null then
   if not exists(select 1 from public.imp_pedido_itens pi where pi.pedido_id=p.id and pi.quantidade>coalesce((select sum(ei.recebida) from public.imp_embarque_itens ei join public.imp_embarques e on e.id=ei.embarque_id and e.status<>'Cancelado' where ei.pedido_item_id=pi.id),0)) then continue;end if;
   insert into public.imp_importacao_processos(fornecedor_id,moeda,criado_por)values(p.fornecedor_id,p.moeda,uid)returning id into pid;
   insert into public.imp_importacao_pedidos values(pid,p.id,(select coalesce(max(parcial),0)+1 from public.imp_importacao_pedidos where pedido_id=p.id));
   insert into public.imp_importacao_itens select pid,pi.id,pi.quantidade-coalesce((select sum(ei.recebida) from public.imp_embarque_itens ei join public.imp_embarques e on e.id=ei.embarque_id and e.status<>'Cancelado' where ei.pedido_item_id=pi.id),0) from public.imp_pedido_itens pi where pi.pedido_id=p.id and pi.quantidade>coalesce((select sum(ei.recebida) from public.imp_embarque_itens ei join public.imp_embarques e on e.id=ei.embarque_id and e.status<>'Cancelado' where ei.pedido_item_id=pi.id),0);
   insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('processos',pid,uid,null,jsonb_build_object('evento','Processo iniciado pelo envio do PO','pedido_id',p.id));
  end if;
 end loop;
 -- Um embarque consolidado pertence a um processo; os POs envolvidos são preservados.
 for emrow in select em.* from public.imp_embarques em where em.status<>'Cancelado' and not exists(select 1 from public.imp_importacao_embarques pe where pe.embarque_id=em.id) order by em.criado_em,em.id loop
  select array_agg(distinct public.axe_imp_processo_raiz(pp.processo_id)) into pendentes from public.imp_embarque_itens ei join public.imp_pedido_itens pi on pi.id=ei.pedido_item_id join public.imp_importacao_pedidos pp on pp.pedido_id=pi.pedido_id join public.imp_importacao_processos rp on rp.id=public.axe_imp_processo_raiz(pp.processo_id) and rp.estado='Aberto' where ei.embarque_id=emrow.id and rp.fornecedor_id=emrow.fornecedor_id and rp.moeda=emrow.moeda;
  if coalesce(array_length(pendentes,1),0)=0 then continue;end if;dest:=pendentes[1];
  foreach pid in array pendentes loop
   if pid<>dest then update public.imp_importacao_processos set estado='Consolidado',consolidado_em=dest where id=pid;insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('processos',pid,uid,jsonb_build_object('estado','Aberto'),jsonb_build_object('evento','Consolidação comprovada pelos itens do embarque','processo_destino',dest,'embarque_id',emrow.id));end if;
  end loop;
  insert into public.imp_importacao_embarques values(dest,emrow.id);
 end loop;
 for pr in select * from public.imp_importacao_processos where estado='Aberto' order by criado_em,id loop
  if not exists(select 1 from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=pr.id and po.status<>'Cancelado') then update public.imp_importacao_processos set estado='Cancelado' where id=pr.id;continue;end if;
  if exists(select 1 from public.imp_importacao_embarques pe join public.imp_embarques em on em.id=pe.embarque_id and em.status<>'Cancelado' where public.axe_imp_processo_raiz(pe.processo_id)=pr.id)
   and not exists(select 1 from public.imp_importacao_embarques pe join public.imp_embarques em on em.id=pe.embarque_id and em.status<>'Cancelado' where public.axe_imp_processo_raiz(pe.processo_id)=pr.id and (em.status<>'Recebido' or exists(select 1 from public.imp_embarque_itens ei where ei.embarque_id=em.id and ei.recebida<ei.quantidade) or not exists(select 1 from public.imp_fluxo_estoque_confirmacoes st where st.embarque_id=em.id) or not exists(select 1 from public.imp_custos c where c.embarque_id=em.id and c.estado='Final'))) then
   update public.imp_importacao_processos set estado='Encerrado',encerrado_em=clock_timestamp() where id=pr.id;
   insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('processos',pr.id,uid,jsonb_build_object('estado','Aberto'),jsonb_build_object('evento','Processo encerrado: estoque, custos e créditos concluídos','estado','Encerrado'));
   seguinte:=null;
   for p in select distinct po.* from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=pr.id and po.status<>'Cancelado' loop
    if exists(select 1 from public.imp_pedido_itens pi where pi.pedido_id=p.id and pi.quantidade>coalesce((select sum(ei.recebida) from public.imp_embarque_itens ei join public.imp_embarques em on em.id=ei.embarque_id and em.status<>'Cancelado' where ei.pedido_item_id=pi.id),0)) then
     if seguinte is null then insert into public.imp_importacao_processos(fornecedor_id,moeda,criado_por)values(pr.fornecedor_id,pr.moeda,uid)returning id into seguinte;end if;
     insert into public.imp_importacao_pedidos values(seguinte,p.id,(select coalesce(max(parcial),0)+1 from public.imp_importacao_pedidos where pedido_id=p.id));
     insert into public.imp_importacao_itens select seguinte,pi.id,pi.quantidade-coalesce((select sum(ei.recebida) from public.imp_embarque_itens ei join public.imp_embarques em on em.id=ei.embarque_id and em.status<>'Cancelado' where ei.pedido_item_id=pi.id),0) from public.imp_pedido_itens pi where pi.pedido_id=p.id and pi.quantidade>coalesce((select sum(ei.recebida) from public.imp_embarque_itens ei join public.imp_embarques em on em.id=ei.embarque_id and em.status<>'Cancelado' where ei.pedido_item_id=pi.id),0);
    end if;
   end loop;
   if seguinte is not null then perform public.axe_imp_transferir_credito_processo(pr.id,seguinte,uid);insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('processos',seguinte,uid,null,jsonb_build_object('evento','Próxima parcial criada com o saldo a entregar','processo_anterior',pr.id));end if;
  end if;
 end loop;
end $function$;
CREATE OR REPLACE FUNCTION public.axe_imp_fluxo(p_dados jsonb, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare a text:=p_dados->>'acao';papel text;pr public.imp_importacao_processos;src public.imp_importacao_processos;pid uuid;oid uuid;dest uuid;page integer:=coalesce((p_dados->>'pagina')::integer,0);term text:=left(coalesce(p_dados->>'busca',''),120);r jsonb;rr jsonb;x jsonb;ships jsonb:='[]';members jsonb;
begin
 select m.papel into papel from public.gestao_membros m join public.axe_rumo_revisores rv on rv.usuario_id=m.usuario_id and rv.ativo where m.usuario_id=p_usuario and m.ativo;if papel is null then raise exception 'Sem acesso às importações';end if;
 if a in('custo_fluxo_listar','custo_fluxo_processos_abertos') then
  if page<0 or page>100000 then raise exception 'Página inválida';end if;
  return jsonb_build_object('editar',papel in('ADMIN','EDITOR'),'total',(select count(*) from public.imp_importacao_processos q where q.estado<>'Consolidado' and (a<>'custo_fluxo_processos_abertos' or q.estado='Aberto' and q.fornecedor_id=(p_dados->>'fornecedor_id')::bigint and q.moeda=p_dados->>'moeda') and exists(select 1 from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=q.id and po.referencia ilike '%'||term||'%')),
  'linhas',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select q.id processo_id,(select pp.pedido_id from public.imp_importacao_pedidos pp where public.axe_imp_processo_raiz(pp.processo_id)=q.id order by pp.parcial,pp.pedido_id limit 1) id,
   (select string_agg(po.referencia,', ' order by po.referencia) from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=q.id) referencia,
   (select string_agg(case when (select count(*) from public.imp_importacao_pedidos p2 where public.axe_imp_processo_raiz(p2.processo_id)=q.id)>1 then po.referencia||': ' else '' end||lpad(pp.parcial::text,2,'0'),', ' order by po.referencia) from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=q.id) parcial,
   (select jsonb_agg(jsonb_build_object('id',po.id,'referencia',po.referencia,'parcial',pp.parcial)) from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=q.id) pedidos,
   public.axe_imp_status_parcial(q.id) status_processo,f.razao_social fornecedor,q.fornecedor_id,q.moeda,
   (select coalesce(sum(public.axe_imp_valor_processo_pedido(q.id,pp.pedido_id)),0) from public.imp_importacao_pedidos pp where public.axe_imp_processo_raiz(pp.processo_id)=q.id) total,
   (select coalesce(sum(ap.valor),0) from public.imp_remessa_processos ap where public.axe_imp_processo_raiz(ap.processo_id)=q.id) pago,(select count(*) from public.imp_importacao_embarques pe where public.axe_imp_processo_raiz(pe.processo_id)=q.id) embarques
   from public.imp_importacao_processos q join public.fornecedores f on f.id=q.fornecedor_id where q.estado<>'Consolidado' and (a<>'custo_fluxo_processos_abertos' or q.estado='Aberto' and q.fornecedor_id=(p_dados->>'fornecedor_id')::bigint and q.moeda=p_dados->>'moeda') and exists(select 1 from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=q.id and po.referencia ilike '%'||term||'%') order by q.criado_em desc,q.id limit 30 offset page*30)z));
 end if;
 if a='custo_fluxo_consolidar' then
  if papel not in('ADMIN','EDITOR') then raise exception 'Sem permissão para consolidar';end if;perform pg_advisory_xact_lock(728102826);
  select * into pr from public.imp_importacao_processos where id=public.axe_imp_processo_raiz((p_dados->>'processo_id')::uuid) and estado='Aberto';
  select * into src from public.imp_importacao_processos where id=public.axe_imp_processo_raiz((p_dados->>'origem_id')::uuid) and estado='Aberto';
  if pr.id is null or src.id is null or pr.id=src.id or pr.fornecedor_id<>src.fornecedor_id or pr.moeda<>src.moeda then raise exception 'Selecione dois processos abertos do mesmo fornecedor e moeda';end if;
  update public.imp_importacao_processos set estado='Consolidado',consolidado_em=pr.id where id=src.id;
  insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('processos',src.id,p_usuario,jsonb_build_object('estado','Aberto'),jsonb_build_object('evento','Processo consolidado por escolha do usuário','processo_destino',pr.id));
  return jsonb_build_object('processo_id',pr.id);
 end if;
 if a<>'custo_fluxo_detalhe' then return public.axe_imp_fluxo_base(p_dados,p_usuario);end if;
 oid:=(p_dados->>'pedido_id')::uuid;pid:=public.axe_imp_processo_raiz(nullif(p_dados->>'processo_id','')::uuid);
 if pid is null then select public.axe_imp_processo_raiz(pp.processo_id) into pid from public.imp_importacao_pedidos pp where pp.pedido_id=oid order by pp.parcial desc limit 1;end if;
 select * into pr from public.imp_importacao_processos where id=pid;if not found then raise exception 'O processo inicia ao enviar o PO ao fornecedor estrangeiro';end if;
 if oid is null then select pp.pedido_id into oid from public.imp_importacao_pedidos pp where public.axe_imp_processo_raiz(pp.processo_id)=pid limit 1;end if;
 if not exists(select 1 from public.imp_importacao_pedidos pp where pp.pedido_id=oid and public.axe_imp_processo_raiz(pp.processo_id)=pid) then raise exception 'Pedido não pertence a este processo';end if;
 r:=public.axe_imp_fluxo_base(jsonb_build_object('acao','custo_fluxo_detalhe','pedido_id',oid),p_usuario);
 select jsonb_agg(public.axe_imp_estrutura_detalhe('pedidos',pp.pedido_id)||jsonb_build_object('parcial',pp.parcial)) into members from public.imp_importacao_pedidos pp where public.axe_imp_processo_raiz(pp.processo_id)=pid;
 for x in select value from jsonb_array_elements(members) loop
  rr:=public.axe_imp_fluxo_base(jsonb_build_object('acao','custo_fluxo_detalhe','pedido_id',x->>'id'),p_usuario);
  for x in select value from jsonb_array_elements(rr->'embarques') loop
   if exists(select 1 from public.imp_importacao_embarques pe where pe.embarque_id=(x->'embarque'->>'id')::uuid and public.axe_imp_processo_raiz(pe.processo_id)=pid) and not exists(select 1 from jsonb_array_elements(ships) s where s->'embarque'->>'id'=x->'embarque'->>'id') then ships:=ships||jsonb_build_array(x);end if;
  end loop;
 end loop;
 return r||jsonb_build_object('editar',(r->>'editar')::boolean and pr.estado='Aberto','pedido',(r->'pedido')||jsonb_build_object('status_processo',public.axe_imp_status_parcial(pid)),'processo',to_jsonb(pr),'pedidos',members,'embarques',ships,'processo_itens',(select coalesce(jsonb_agg(to_jsonb(it)),'[]') from public.imp_importacao_itens it where public.axe_imp_processo_raiz(it.processo_id)=pid));
end $function$;
CREATE OR REPLACE FUNCTION public.axe_pagamento_processos(p_dados jsonb, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare papel text;d jsonb:=p_dados->'dados';proof jsonb:=p_dados->'swift';req uuid:=(p_dados->>'requisicao_id')::uuid;cid uuid;f public.imp_cambio_arquivos;c public.imp_fin_documentos;rm public.imp_remessas;pr public.imp_importacao_processos;po jsonb;old record;x jsonb;r jsonb;result jsonb;rows jsonb:='[]';selected numeric;usado numeric;valor numeric;disponivel numeric;registrar numeric;pid uuid;parid uuid;par public.imp_parcelas;candidate uuid[];meta jsonb;oldvalor numeric;
begin
 if jsonb_array_length(coalesce(d->'processos','[]'))=0 then return public.axe_pagamento_documental(p_dados,p_usuario);end if;
 select m.papel into papel from public.gestao_membros m join public.axe_rumo_revisores rv on rv.usuario_id=m.usuario_id and rv.ativo where m.usuario_id=p_usuario and m.ativo;
 if papel not in('ADMIN','EDITOR') or papel is null or p_dados->>'confirmado' is distinct from 'true' or p_dados->>'nao_duplicado' is distinct from 'true' then raise exception 'Confirme os valores a aplicar nos processos';end if;
 perform pg_advisory_xact_lock(728102826);
 if req is null then raise exception 'Identificação obrigatória';end if;
 select * into old from public.imp_requisicoes where usuario_id=p_usuario and requisicao_id=req;if found then if old.dados<>p_dados then raise exception 'Identificação reutilizada com outros dados';end if;return old.resultado;end if;
 if jsonb_typeof(d->'processos')<>'array' or jsonb_array_length(d->'processos')>50 then raise exception 'Selecione até 50 aplicações';end if;
 if exists(select 1 from jsonb_array_elements(d->'processos') ap0(value) group by ap0.value->>'processo_id',ap0.value->>'pedido_id' having count(*)>1) then raise exception 'Processo e PO repetidos na distribuição';end if;
 select sum((value->>'valor')::numeric) into selected from jsonb_array_elements(d->'processos');
 if selected is null or selected<=0 or selected>(proof->>'valor')::numeric then raise exception 'O total aplicado ultrapassa o comprovante';end if;
 cid:=nullif(p_dados->>'contrato_id','')::uuid;
 if cid is null then r:=public.axe_cambio_criar_com_arquivo(p_dados->'novo_contrato',p_usuario);cid:=(r->>'id')::uuid;end if;
 select * into c from public.imp_fin_documentos where id=cid and tipo='contratos' and status='Ativo';if not found or c.moeda is distinct from proof->>'moeda' then raise exception 'Confira contrato e moeda';end if;
 if p_dados->>'contrato_id' is not null and c.versao is distinct from (p_dados->>'versao_contrato')::integer then raise exception 'Contrato alterado. Reabra a conferência';end if;
 select * into f from public.imp_cambio_arquivos where id=nullif(p_dados->>'swift_arquivo_id','')::uuid and contrato_id=cid and categoria='SWIFT' and pronto;
 if not found then
  meta:=public.axe_cambio_arquivos(jsonb_build_object('acao','fxdoc_reservar','contrato_id',cid,'requisicao_id',req,'categoria','SWIFT','nome',p_dados->'arquivo'->>'nome','sha256',p_dados->'arquivo'->>'sha256','tamanho',p_dados->'arquivo'->'tamanho'),p_usuario);
  if meta->>'pronto'<>'true' then
   if p_dados->'arquivo'->>'caminho' is distinct from 'entrada/'||p_usuario||'/'||req||'/SWIFT.pdf' then raise exception 'Caminho documental inválido';end if;
   update public.imp_cambio_arquivos set caminho=p_dados->'arquivo'->>'caminho' where id=(meta->>'id')::uuid;
   perform public.axe_cambio_arquivos(jsonb_build_object('acao','fxdoc_confirmar','id',meta->>'id'),p_usuario);
  end if;
  select * into f from public.imp_cambio_arquivos where id=(meta->>'id')::uuid;
 end if;
 if f.sha256 is distinct from p_dados->'arquivo'->>'sha256' then raise exception 'Comprovante alterado';end if;
 select * into rm from public.imp_remessas where sha256=f.sha256 or (nullif(proof->>'uetr','') is not null and uetr=proof->>'uetr');
 if found and (rm.contrato_id<>cid or rm.moeda<>proof->>'moeda' or rm.valor<>(proof->>'valor')::numeric or rm.data_pagamento<>(proof->>'data')::date) then raise exception 'SWIFT já registrado com valores diferentes';end if;
 if rm.id is not null then select coalesce(sum(ap.valor),0) into usado from public.imp_remessa_processos ap where ap.remessa_id=rm.id;if usado+selected>rm.valor then raise exception 'Comprovante sem saldo para esta distribuição';end if;end if;
 for x in select value from jsonb_array_elements(d->'processos') loop
  pid:=(x->>'pedido_id')::uuid;valor:=(x->>'valor')::numeric;
  select * into pr from public.imp_importacao_processos where id=public.axe_imp_processo_raiz((x->>'processo_id')::uuid) and estado='Aberto';
  po:=public.axe_imp_estrutura_detalhe('pedidos',pid);
  if pr.id is null or po is null or po->>'status'='Cancelado' or pr.fornecedor_id<>c.fornecedor_id or pr.moeda<>c.moeda or (po->>'fornecedor_id')::bigint<>c.fornecedor_id or po->>'moeda'<>c.moeda or not exists(select 1 from public.imp_importacao_pedidos pp where pp.pedido_id=pid and public.axe_imp_processo_raiz(pp.processo_id)=pr.id) then raise exception 'Processo/PO deve pertencer ao mesmo fornecedor e moeda do comprovante';end if;
  if valor is null or valor<=0 or valor<>round(valor,2) then raise exception 'Informe valores positivos com até duas casas';end if;
  if (select coalesce(sum(a.valor),0) from public.imp_remessa_processos a where a.pedido_id=pid and public.axe_imp_processo_raiz(a.processo_id)=pr.id)+valor>public.axe_imp_valor_processo_pedido(pr.id,pid) then raise exception 'Aplicação ultrapassa o valor dos itens do PO neste processo';end if;
  disponivel:=0;
  if rm.id is not null then select greatest(0,coalesce((select sum(rp.valor) from public.imp_remessa_parcelas rp join public.imp_parcelas pa on pa.id=rp.parcela_id where rp.remessa_id=rm.id and pa.pedido_id=pid),0)-coalesce((select sum(ap.valor) from public.imp_remessa_processos ap where ap.remessa_id=rm.id and ap.pedido_id=pid),0)) into disponivel;end if;
  registrar:=greatest(0,valor-disponivel);
  if registrar>0 then
   parid:=nullif(x->>'parcela_id','')::uuid;
   if parid is null then select array_agg(pa.id) into candidate from public.imp_parcelas pa where pa.pedido_id=pid and pa.status<>'Cancelada' and pa.valor-pa.valor_pago>=registrar;
    if coalesce(array_length(candidate,1),0)=1 then parid:=candidate[1];elsif coalesce(array_length(candidate,1),0)>1 then raise exception 'Mais de uma parcela pode receber o pagamento no PO %. Selecione a parcela.',po->>'referencia';end if;
   end if;
   select * into par from public.imp_parcelas where id=parid;
   select * into c from public.imp_fin_documentos where id=cid;
   r:=public.axe_pagamento_documental(p_dados||jsonb_build_object('pedido_id',pid,'versao_pedido',po->'versao','contrato_id',cid,'versao_contrato',c.versao,'swift_arquivo_id',f.id,'requisicao_id',gen_random_uuid(),'dados',jsonb_build_object('valor',registrar,'referencia',(po->>'referencia')||' / pagamento','parcela_id',parid,'versao_parcela',par.versao,'invoice',d->>'invoice','motivo',d->>'motivo')),p_usuario);
   select * into rm from public.imp_remessas where id=(r->>'remessa_id')::uuid;
  end if;
  select ap.valor into oldvalor from public.imp_remessa_processos ap where ap.remessa_id=rm.id and ap.processo_id=pr.id and ap.pedido_id=pid;
  insert into public.imp_remessa_processos(remessa_id,processo_id,pedido_id,valor,usuario_id)values(rm.id,pr.id,pid,valor,p_usuario)on conflict(remessa_id,processo_id,pedido_id) do update set valor=imp_remessa_processos.valor+excluded.valor,usuario_id=p_usuario,atualizado_em=clock_timestamp();
  insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('processos',pr.id,p_usuario,jsonb_build_object('valor_aplicado',coalesce(oldvalor,0)),jsonb_build_object('evento','Pagamento aplicado ao processo','remessa_id',rm.id,'pedido_id',pid,'valor_aplicado',coalesce(oldvalor,0)+valor));
  rows:=rows||jsonb_build_array(jsonb_build_object('processo_id',pr.id,'pedido_id',pid,'valor',valor));
 end loop;
 result:=jsonb_build_object('id',coalesce(nullif(d->>'parcela_id',''),r->>'id',(select rp.parcela_id::text from public.imp_remessa_parcelas rp join public.imp_parcelas pa on pa.id=rp.parcela_id where rp.remessa_id=rm.id and pa.pedido_id=(p_dados->>'pedido_id')::uuid limit 1)),'pedido_id',p_dados->>'pedido_id','contrato_id',cid,'remessa_id',rm.id,'aplicacoes',rows,'valor_aplicado',selected,'saldo_comprovante',rm.valor-(select sum(ap.valor) from public.imp_remessa_processos ap where ap.remessa_id=rm.id));
 insert into public.imp_requisicoes(usuario_id,requisicao_id,dados,resultado)values(p_usuario,req,p_dados,result);return result;
end $function$;
commit;
