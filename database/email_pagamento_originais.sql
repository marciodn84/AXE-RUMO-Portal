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
 if a='pagdoc_contexto' then return jsonb_build_object('pedido',p,'editar',papel in ('ADMIN','EDITOR'),'contratos',(select coalesce(jsonb_agg(to_jsonb(cd)||jsonb_build_object('arquivos',(select coalesce(jsonb_agg(jsonb_build_object('id',fa.id,'nome',fa.nome,'categoria',fa.categoria)),'[]') from public.imp_cambio_arquivos fa where fa.contrato_id=cd.id and fa.pronto),'registrado',(select coalesce(sum(rp.valor),0) from public.imp_remessa_parcelas rp join public.imp_remessas rm on rm.id=rp.remessa_id where rm.contrato_id=cd.id))), '[]') from public.imp_fin_documentos cd where cd.tipo='contratos' and cd.status='Ativo' and cd.fornecedor_id=(p->>'fornecedor_id')::bigint and cd.moeda=p->>'moeda'),'pago',(select coalesce(sum(pa.valor_pago),0) from public.imp_parcelas pa where pa.pedido_id=(p->>'id')::uuid),'remessas',(select coalesce(jsonb_agg(to_jsonb(rm)||jsonb_build_object('utilizado',(select coalesce(sum(rp.valor),0) from public.imp_remessa_parcelas rp where rp.remessa_id=rm.id))),'[]') from public.imp_remessas rm join public.imp_fin_documentos cd on cd.id=rm.contrato_id where cd.fornecedor_id=(p->>'fornecedor_id')::bigint and cd.moeda=p->>'moeda'),'liberacoes',(select coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object('utilizado',(select coalesce(sum(lp.valor),0) from public.imp_liberacao_parcelas lp where lp.liberacao_id=l.id))),'[]') from public.imp_liberacoes l where l.pedido_id=(p->>'id')::uuid));end if;
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
end $function$

