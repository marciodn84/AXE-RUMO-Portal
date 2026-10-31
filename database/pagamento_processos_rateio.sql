begin;
create table public.imp_remessa_processos(
 remessa_id uuid not null references public.imp_remessas(id),processo_id uuid not null references public.imp_importacao_processos(id),pedido_id uuid not null references public.imp_pedidos(id),
 valor numeric not null check(valor>0 and valor=round(valor,2)),usuario_id uuid not null references auth.users(id),atualizado_em timestamptz not null default now(),primary key(remessa_id,processo_id,pedido_id)
);
alter table public.imp_remessa_processos enable row level security;
revoke all on public.imp_remessa_processos from public,anon,authenticated;
grant all on public.imp_remessa_processos to service_role;
create index imp_remessa_processos_processo on public.imp_remessa_processos(processo_id,pedido_id);
create or replace function public.axe_imp_processos_opcoes(forn bigint,moeda_busca text) returns jsonb language sql stable set search_path='' as $fn$
 select coalesce(jsonb_agg(jsonb_build_object('processo_id',p.id,'pedidos',(select jsonb_agg(public.axe_imp_estrutura_detalhe('pedidos',pp.pedido_id)||jsonb_build_object('parcial',pp.parcial)) from public.imp_importacao_pedidos pp where public.axe_imp_processo_raiz(pp.processo_id)=p.id),'aplicado',(select coalesce(sum(v.valor),0) from public.imp_remessa_processos v where public.axe_imp_processo_raiz(v.processo_id)=p.id)) order by p.criado_em,p.id),'[]') from public.imp_importacao_processos p where p.estado='Aberto' and p.fornecedor_id=forn and p.moeda=moeda_busca;
$fn$;
create or replace function public.axe_pagamento_processos(p_dados jsonb,p_usuario uuid) returns jsonb language plpgsql set search_path='' as $fn$
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
  if (select coalesce(sum(a.valor),0) from public.imp_remessa_processos a where a.pedido_id=pid and public.axe_imp_processo_raiz(a.processo_id)=pr.id)+valor>(select coalesce(sum(round(it.quantidade*pi.valor_unitario,2)),0) from public.imp_importacao_itens it join public.imp_pedido_itens pi on pi.id=it.pedido_item_id and pi.pedido_id=pid where public.axe_imp_processo_raiz(it.processo_id)=pr.id) then raise exception 'Aplicação ultrapassa o valor dos itens do PO neste processo';end if;
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
end $fn$;
revoke all on function public.axe_imp_processos_opcoes(bigint,text),public.axe_pagamento_processos(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_imp_processos_opcoes(bigint,text),public.axe_pagamento_processos(jsonb,uuid) to service_role;

CREATE OR REPLACE FUNCTION public.axe_pagamento_documental(p_dados jsonb, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare a text:=p_dados->>'acao'; papel text; p jsonb; c public.imp_fin_documentos; par public.imp_parcelas; rem public.imp_remessas; f public.imp_cambio_arquivos; x record; req uuid; d jsonb:=p_dados->'dados'; proof jsonb:=p_dados->'swift'; cid uuid; pid uuid; nr jsonb; result jsonb; amount numeric; used numeric; totalpaid numeric; allocation numeric; oldmap numeric; outros numeric; rate numeric; antes jsonb; cantes jsonb; path text; lib public.imp_liberacoes; linkvalue numeric; libused numeric; parused numeric; lold numeric;
begin
 select m.papel into papel from public.gestao_membros m join public.axe_rumo_revisores rv on rv.usuario_id=m.usuario_id and rv.ativo where m.usuario_id=p_usuario and m.ativo;
 if papel is null then raise exception 'Usuário sem acesso às importações';end if;
 if a not in ('pagdoc_contexto','pagdoc_arquivo','pagdoc_aprovar') or a is null then raise exception 'Ação inválida';end if;
 if a='pagdoc_arquivo' then
  select * into f from public.imp_cambio_arquivos where id=(p_dados->>'id')::uuid and pronto and categoria in ('CONTRATO','SWIFT');if not found then raise exception 'Anexo não encontrado';end if;return public.axe_cambio_arquivos(jsonb_build_object('acao','fxdoc_arquivo','id',f.id),p_usuario);
 end if;
 perform pg_advisory_xact_lock(728102826);
 p:=public.axe_imp_estrutura_detalhe('pedidos',(p_dados->>'pedido_id')::uuid);if p is null or p->>'status'='Cancelado' then raise exception 'Pedido inexistente ou cancelado';end if;
 if a='pagdoc_contexto' then return jsonb_build_object('pedido',p,'processos',public.axe_imp_processos_opcoes((p->>'fornecedor_id')::bigint,p->>'moeda'),'editar',papel in ('ADMIN','EDITOR'),'contratos',(select coalesce(jsonb_agg(to_jsonb(cd)||jsonb_build_object('arquivos',(select coalesce(jsonb_agg(jsonb_build_object('id',fa.id,'nome',fa.nome,'categoria',fa.categoria)),'[]') from public.imp_cambio_arquivos fa where fa.contrato_id=cd.id and fa.pronto),'registrado',(select coalesce(sum(rp.valor),0) from public.imp_remessa_parcelas rp join public.imp_remessas rm on rm.id=rp.remessa_id where rm.contrato_id=cd.id))), '[]') from public.imp_fin_documentos cd where cd.tipo='contratos' and cd.status='Ativo' and cd.fornecedor_id=(p->>'fornecedor_id')::bigint and cd.moeda=p->>'moeda'),'pago',(select coalesce(sum(pa.valor_pago),0) from public.imp_parcelas pa where pa.pedido_id=(p->>'id')::uuid),'remessas',(select coalesce(jsonb_agg(to_jsonb(rm)||jsonb_build_object('utilizado',(select coalesce(sum(rp.valor),0) from public.imp_remessa_parcelas rp where rp.remessa_id=rm.id))),'[]') from public.imp_remessas rm join public.imp_fin_documentos cd on cd.id=rm.contrato_id where cd.fornecedor_id=(p->>'fornecedor_id')::bigint and cd.moeda=p->>'moeda'),'liberacoes',(select coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object('utilizado',(select coalesce(sum(lp.valor),0) from public.imp_liberacao_parcelas lp where lp.liberacao_id=l.id))),'[]') from public.imp_liberacoes l where l.pedido_id=(p->>'id')::uuid));end if;
 if papel not in ('ADMIN','EDITOR') or p_dados->>'confirmado' is distinct from 'true' or p_dados->>'nao_duplicado' is distinct from 'true' then raise exception 'Confirme o pagamento e a ausência de duplicidade';end if;
 req:=(p_dados->>'requisicao_id')::uuid;if req is null then raise exception 'Identificador obrigatório';end if;
 select * into x from public.imp_requisicoes where usuario_id=p_usuario and requisicao_id=req;if found then if x.dados is distinct from p_dados then raise exception 'Identificador reutilizado com outros dados';end if;return x.resultado;end if;
 if (p->>'versao')::int is distinct from (p_dados->>'versao_pedido')::int then raise exception 'Pedido alterado. Reabra a conferência';end if;
 cid:=nullif(p_dados->>'contrato_id','')::uuid;
 if cid is null then
  nr:=public.axe_cambio_criar_com_arquivo(p_dados->'novo_contrato',p_usuario);cid:=(nr->>'id')::uuid;
 end if;
 select * into c from public.imp_fin_documentos where id=cid and tipo='contratos' and status='Ativo';
 if not found or c.fornecedor_id is distinct from (p->>'fornecedor_id')::bigint or c.moeda is distinct from p->>'moeda' then raise exception 'Contrato deve ter mesmo fornecedor e moeda do pedido';end if;
 if nr is null and c.versao is distinct from (p_dados->>'versao_contrato')::int then raise exception 'Contrato alterado. Reabra a conferência';end if;
 if proof->>'moeda' is distinct from c.moeda or proof->>'moeda' is distinct from p->>'moeda' then raise exception 'Moeda do SWIFT diverge do contrato ou do pedido';end if;
 amount:=(d->>'valor')::numeric;
 if amount is null or amount<=0 or amount<>round(amount,2) or amount::text in ('NaN','Infinity','-Infinity') or amount>(proof->>'valor')::numeric then raise exception 'Informe valor positivo dentro do comprovante';end if;
 if nullif(proof->>'data','') is null or nullif(proof->>'valor','') is null or (proof->>'valor')::numeric<=0 then raise exception 'Data e valor do SWIFT obrigatórios';end if;
 if nullif(proof->>'referencia','') is not null and proof->>'referencia'<>c.referencia and nullif(btrim(d->>'motivo'),'') is null then raise exception 'Referência do SWIFT difere do contrato. Justifique a vinculação';end if;
 select coalesce(sum(pa.valor_pago),0) into totalpaid from public.imp_parcelas pa where pa.pedido_id=(p->>'id')::uuid;
 if totalpaid+amount>(p->>'total')::numeric then raise exception 'Pagamento ultrapassa o saldo devedor do pedido';end if;
 select * into f from public.imp_cambio_arquivos where id=nullif(p_dados->>'swift_arquivo_id','')::uuid and contrato_id=cid and categoria='SWIFT' and pronto;
 if not found then
  nr:=public.axe_cambio_arquivos(jsonb_build_object('acao','fxdoc_reservar','contrato_id',cid,'requisicao_id',req,'categoria','SWIFT','nome',p_dados->'arquivo'->>'nome','sha256',p_dados->'arquivo'->>'sha256','tamanho',p_dados->'arquivo'->'tamanho'),p_usuario);
  if not (nr->>'pronto')::boolean then
   path:='entrada/'||p_usuario||'/'||req||'/SWIFT.pdf';if p_dados->'arquivo'->>'caminho' is distinct from path then raise exception 'Caminho do anexo inválido';end if;
   update public.imp_cambio_arquivos set caminho=path where id=(nr->>'id')::uuid;perform public.axe_cambio_arquivos(jsonb_build_object('acao','fxdoc_confirmar','id',nr->>'id'),p_usuario);
  end if;
  select * into f from public.imp_cambio_arquivos where id=(nr->>'id')::uuid;
 end if;
 if f.sha256 is distinct from p_dados->'arquivo'->>'sha256' then raise exception 'O comprovante não corresponde ao arquivo';end if;
 select * into rem from public.imp_remessas where sha256=f.sha256 or (uetr is not null and uetr=proof->>'uetr');
 if found then
  if rem.contrato_id<>cid or rem.moeda<>proof->>'moeda' or rem.valor is distinct from (proof->>'valor')::numeric or rem.data_pagamento is distinct from (proof->>'data')::date then raise exception 'Comprovante já registrado com outros dados';end if;
 else
  select coalesce(sum(rm.valor),0) into used from public.imp_remessas rm where rm.contrato_id=cid;
  if used+(proof->>'valor')::numeric>c.valor then raise exception 'Remessas ultrapassam o valor do contrato';end if;
  insert into public.imp_remessas(contrato_id,arquivo_id,sha256,uetr,referencia,moeda,valor,data_pagamento,extraido,criado_por) values(cid,f.id,f.sha256,nullif(proof->>'uetr',''),proof->>'referencia',proof->>'moeda',(proof->>'valor')::numeric,(proof->>'data')::date,p_dados->'extraido',p_usuario) returning * into rem;
 end if;
 select coalesce(sum(rp.valor),0) into used from public.imp_remessa_parcelas rp where rp.remessa_id=rem.id;
 if used+amount>rem.valor then raise exception 'Este comprovante já foi utilizado ou não tem saldo suficiente';end if;
 pid:=nullif(d->>'parcela_id','')::uuid;rate:=nullif(c.dados->>'taxa','')::numeric;
 if pid is null then
  nr:=public.axe_imp_estrutura(jsonb_build_object('acao','v2_salvar','tipo','parcelas','requisicao_id',gen_random_uuid(),'dados',jsonb_build_object('pedido_id',p->>'id','referencia',d->>'referencia','modo','Valor','valor',amount,'marco','Manual','status','Prevista','valor_pago',amount,'data_pagamento',proof->>'data','contrato_cambio',c.referencia,'cambio',rate,'proforma',d->>'invoice','observacoes','Pagamento por comprovante SWIFT; remessa '||rem.id)),p_usuario);pid:=(nr->>'id')::uuid;
 else
  select * into par from public.imp_parcelas where id=pid and pedido_id=(p->>'id')::uuid and status<>'Cancelada';if not found then raise exception 'Parcela inválida';end if;
  if par.versao is distinct from (d->>'versao_parcela')::int or par.valor_pago+amount>par.valor then raise exception 'Parcela alterada ou pagamento maior que o saldo. Reabra a conferência';end if;
  antes:=public.axe_imp_estrutura_detalhe('parcelas',pid);
  update public.imp_parcelas set valor_pago=par.valor_pago+amount,data_pagamento=greatest(par.data_pagamento,(proof->>'data')::date),contrato_cambio=case when coalesce(par.contrato_cambio,'')='' then c.referencia when par.contrato_cambio=c.referencia then par.contrato_cambio else par.contrato_cambio||'; '||c.referencia end,cambio=case when par.valor_pago=0 then rate when par.cambio is not null and rate is not null then (par.valor_pago*par.cambio+amount*rate)/(par.valor_pago+amount) else null end,atualizado_por=p_usuario,atualizado_em=clock_timestamp(),versao=versao+1 where id=pid;
  insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual) values('parcelas',pid,p_usuario,antes,public.axe_imp_estrutura_detalhe('parcelas',pid));
 end if;
 insert into public.imp_remessa_parcelas(requisicao_id,remessa_id,parcela_id,valor,dados,usuario_id) values(req,rem.id,pid,amount,p_dados,p_usuario);
 -- The user explicitly confirms the relation between this payment, the contract and this order.
 cantes:=public.axe_imp_fin_detalhe('contratos',cid);
 select coalesce(sum(rp.valor),0) into allocation from public.imp_remessa_parcelas rp join public.imp_remessas rm on rm.id=rp.remessa_id join public.imp_parcelas pa on pa.id=rp.parcela_id where rm.contrato_id=cid and pa.pedido_id=(p->>'id')::uuid;
 select valor into oldmap from public.imp_fin_pedidos where documento_id=cid and pedido_id=(p->>'id')::uuid;
 allocation:=greatest(coalesce(oldmap,0),allocation);
 select coalesce(sum(m.valor),0) into outros from public.imp_fin_pedidos m where m.documento_id=cid and m.pedido_id<>(p->>'id')::uuid;
 if allocation+outros>c.valor then raise exception 'Vínculo do contrato aos pedidos ultrapassa seu valor';end if;
 if oldmap is distinct from allocation then
  insert into public.imp_fin_pedidos(documento_id,pedido_id,valor) values(cid,(p->>'id')::uuid,allocation) on conflict(documento_id,pedido_id) do update set valor=excluded.valor;
  update public.imp_fin_documentos set versao=versao+1,atualizado_por=p_usuario,atualizado_em=clock_timestamp() where id=cid;
  insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual) values('fx_contratos',cid,p_usuario,cantes,public.axe_imp_fin_detalhe('contratos',cid));
 end if;
 if nullif(d->>'liberacao_id','') is not null then
  select * into lib from public.imp_liberacoes where id=(d->>'liberacao_id')::uuid and pedido_id=(p->>'id')::uuid;if not found then raise exception 'Invoice logística não pertence ao pedido';end if;
  linkvalue:=(d->>'valor_vincular')::numeric;
  select coalesce(sum(lp.valor),0) into libused from public.imp_liberacao_parcelas lp where lp.liberacao_id=lib.id;
  select coalesce(sum(lp.valor),0) into parused from public.imp_liberacao_parcelas lp where lp.parcela_id=pid;
  select valor into allocation from public.imp_parcelas where id=pid;
  if linkvalue is null or linkvalue<=0 or linkvalue<>round(linkvalue,2) or linkvalue>amount or libused+linkvalue>(lib.dados->>'valor')::numeric or parused+linkvalue>allocation then raise exception 'Vínculo logístico ultrapassa o saldo da invoice, da parcela ou deste pagamento';end if;
  insert into public.imp_liberacao_parcelas(liberacao_id,parcela_id,valor) values(lib.id,pid,linkvalue) on conflict(liberacao_id,parcela_id) do update set valor=imp_liberacao_parcelas.valor+excluded.valor;
  insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual) values('embarques',lib.embarque_id,p_usuario,null,jsonb_build_object('evento','Parcela vinculada aos documentos da carga','parcela_id',pid,'valor',linkvalue,'invoice',lib.invoice));
 end if;
 result:=jsonb_build_object('id',pid,'contrato_id',cid,'remessa_id',rem.id,'valor_registrado',amount,'saldo_pedido',(p->>'total')::numeric-totalpaid-amount,'saldo_comprovante',rem.valor-used-amount);
 result:=result||jsonb_build_object('pagamento_automatico',public.axe_imp_swift_invoice_automatico((p->>'id')::uuid,p_usuario));insert into public.imp_requisicoes values(p_usuario,req,p_dados,result,now());return result;
end $function$;

insert into public.imp_remessa_processos(remessa_id,processo_id,pedido_id,valor,usuario_id)
select rp.remessa_id,public.axe_imp_processo_raiz(pp.processo_id),pa.pedido_id,sum(rp.valor),min(rp.usuario_id::text)::uuid
from public.imp_remessa_parcelas rp join public.imp_parcelas pa on pa.id=rp.parcela_id join public.imp_importacao_pedidos pp on pp.pedido_id=pa.pedido_id
where (select count(*) from public.imp_importacao_pedidos p2 where p2.pedido_id=pa.pedido_id)=1
group by rp.remessa_id,public.axe_imp_processo_raiz(pp.processo_id),pa.pedido_id;
create or replace function public.axe_imp_pagamento_saldo_processos(arquivo_sha text,p_usuario uuid) returns jsonb language plpgsql set search_path='' as $fn$
declare r jsonb;
begin
 if not exists(select 1 from public.gestao_membros m join public.axe_rumo_revisores rv on rv.usuario_id=m.usuario_id and rv.ativo where m.usuario_id=p_usuario and m.ativo) then raise exception 'Sem acesso';end if;
 select jsonb_build_object('saldo',rm.valor-coalesce((select sum(ap.valor) from public.imp_remessa_processos ap where ap.remessa_id=rm.id),0)) into r from public.imp_remessas rm where rm.sha256=arquivo_sha;return coalesce(r,'{}'::jsonb);
end $fn$;
revoke all on function public.axe_imp_pagamento_saldo_processos(text,uuid) from public,anon,authenticated;
grant execute on function public.axe_imp_pagamento_saldo_processos(text,uuid) to service_role;

create or replace function public.axe_imp_fluxo(p_dados jsonb,p_usuario uuid) returns jsonb language plpgsql set search_path='' as $fn$
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
   (select coalesce(sum(round(it.quantidade*pi.valor_unitario,2)),0) from public.imp_importacao_itens it join public.imp_pedido_itens pi on pi.id=it.pedido_item_id where public.axe_imp_processo_raiz(it.processo_id)=q.id) total,
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
end $fn$;
create or replace function public.axe_imp_pedido_da_invoice(p_referencia text,p_usuario uuid) returns jsonb language plpgsql set search_path='' as $fn$
declare ids uuid[];
begin
 if not exists(select 1 from public.gestao_membros m join public.axe_rumo_revisores rv on rv.usuario_id=m.usuario_id and rv.ativo where m.usuario_id=p_usuario and m.ativo) then raise exception 'Sem acesso';end if;
 select array_agg(p.id) into ids from public.imp_pedidos p where upper(regexp_replace(p.referencia,'[[:space:]]','','g'))=upper(regexp_replace(p_referencia,'[[:space:]]','','g')) and p.status<>'Cancelado';
 if coalesce(array_length(ids,1),0)<>1 then raise exception 'O PO da invoice não foi localizado de forma única. Confira o cadastro do pedido';end if;
 if not public.axe_imp_processo_iniciado(ids[1]) then raise exception 'Envie o PO ao fornecedor estrangeiro antes de importar os documentos';end if;return public.axe_imp_estrutura_detalhe('pedidos',ids[1]);
end $fn$;
revoke all on function public.axe_imp_pedido_da_invoice(text,uuid) from public,anon,authenticated;
grant execute on function public.axe_imp_pedido_da_invoice(text,uuid) to service_role;

commit;
