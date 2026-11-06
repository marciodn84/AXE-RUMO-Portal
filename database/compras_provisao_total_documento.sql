alter table public.tributos_registros
  add column total_documento numeric(18,2),
  add column subtotal_documento numeric(18,2),
  add constraint tributos_total_documento_compra check (
    (total_documento is null and subtotal_documento is null)
    or (origem='compra' and total_documento is not null and subtotal_documento is not null
        and total_documento>0 and subtotal_documento>0)
  );

CREATE OR REPLACE FUNCTION public.axe_imp_programar_parcelas(pid uuid, uid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare p public.imp_pedidos;x jsonb;pa public.imp_parcelas;total numeric;v numeric;ac numeric:=0;idx int:=0;base date;old jsonb;plano jsonb;total_documento numeric;subtotal_documento numeric;begin
 if not public.axe_compra_fin_autorizado(uid)then return;end if;
 perform pg_advisory_xact_lock(728102826);
 select * into p from public.imp_pedidos where id=pid for update;if not found then return;end if;
 if not exists(select 1 from public.fornecedores where id=p.fornecedor_id and upper(btrim(pais))='BR')then perform public.axe_imp_programar_parcelas_importacao(pid,uid);return;end if;
 if p.status in('Elaboração','Cancelado')or p.forma_pagamento is null then return;end if;
 if exists(select 1 from public.compras_nfe_entradas where pedido_id=pid and estado='Confirmada')then return;end if;
 select coalesce(sum(round(quantidade*valor_unitario,2)),0) into total from public.imp_pedido_itens where pedido_id=pid;if total<=0 then return;end if;
 -- O total já inclui os tributos do documento. Preserve o subtotal comercial nos itens.
 select r.total_documento,r.subtotal_documento into total_documento,subtotal_documento
 from public.tributos_registros r where r.origem='compra' and r.registro=pid::text;
 if total_documento is not null then
  if total is distinct from subtotal_documento then
   raise exception 'O subtotal dos itens diverge do documento usado na provisão. Revise o total documentado antes de salvar';
  end if;
  total:=total_documento;
 end if;
 -- Preserva parcelas manuais/pagas e provisiona apenas eventual acréscimo do pedido.
 if exists(select 1 from public.imp_parcelas where pedido_id=pid and status<>'Cancelada' and (valor_pago>0 or financeiro->>'automatico' is distinct from 'true'))then
 select total-coalesce(sum(pp.valor),0) into v from public.imp_parcelas pp where pp.pedido_id=pid and pp.status<>'Cancelada' and not(coalesce(pp.financeiro->>'complemento','false')='true'and pp.financeiro->>'automatico'='true'and pp.valor_pago=0);
 if v<0 then raise exception 'As parcelas manuais ou pagas ultrapassam o pedido. Resolva a programação antes de salvar';end if;
 select * into pa from public.imp_parcelas where pedido_id=pid and status<>'Cancelada'and financeiro->>'complemento'='true'and financeiro->>'automatico'='true'and valor_pago=0 order by criado_em limit 1 for update;old:=to_jsonb(pa);
 base:=case when p.forma_pagamento='ANTECIPADO'then p.data_pedido else p.previsao_entrega end;
 if v>0 and base is null then raise exception 'Informe a data-base para provisionar o saldo do pedido';end if;
 if v>0 and pa.id is null then insert into public.imp_parcelas(pedido_id,referencia,modo,valor,marco,data_base,dias,vencimento,status,valor_pago,atualizado_por,financeiro)values(pid,p.referencia||' / saldo previsto','Valor',v,'Manual',base,0,base,'Prevista',0,uid,jsonb_build_object('automatico',true,'complemento',true,'fase','Provisionado'))returning * into pa;
 elsif pa.id is not null then update public.imp_parcelas set valor=case when v>0 then v else valor end,status=case when v=0 then 'Cancelada'else 'Prevista'end,vencimento=base,versao=versao+1,atualizado_por=uid,atualizado_em=clock_timestamp()where id=pa.id and (valor is distinct from v or vencimento is distinct from base) returning * into pa;end if;
 if pa.id is not null and pa.meio_pagamento is distinct from p.meio_pagamento_previsto then update public.imp_parcelas set meio_pagamento=p.meio_pagamento_previsto,versao=versao+1,atualizado_por=uid,atualizado_em=clock_timestamp() where id=pa.id returning * into pa;end if;
 if pa.id is not null and old is distinct from to_jsonb(pa)then insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('parcelas',pa.id,uid,old,to_jsonb(pa));end if;return;
 end if;
 plano:=p.programacao_financeira;
 if p.forma_pagamento='ANTECIPADO' then plano:='[{"percentual":100,"dias":0,"base":"Pedido"}]';
 elsif p.forma_pagamento='NA_ENTREGA' then plano:='[{"percentual":100,"dias":0,"base":"Entrega"}]';end if;
 if jsonb_array_length(plano)=0 then return;end if;
 for x in select value from jsonb_array_elements(plano)loop
 idx:=idx+1;base:=case when x->>'base'='Pedido' then p.data_pedido else p.previsao_entrega end;
 if base is null then raise exception 'Informe a data do pedido e a previsão de entrega para programar o financeiro';end if;
 v:=case when idx=jsonb_array_length(plano)then total-ac else round(total*(x->>'percentual')::numeric/100,2)end;ac:=ac+v;
 select * into pa from public.imp_parcelas where pedido_id=pid and financeiro->>'automatico'='true' and (financeiro->>'indice')::int=idx order by criado_em limit 1 for update;old:=to_jsonb(pa);
 if pa.id is null then
 insert into public.imp_parcelas(pedido_id,referencia,modo,valor,marco,data_base,dias,vencimento,status,valor_pago,atualizado_por,financeiro)
 values(pid,p.referencia||' / parcela '||idx,'Valor',v,'Manual',base,(x->>'dias')::int,base+(x->>'dias')::int,'Prevista',0,uid,jsonb_build_object('automatico',true,'indice',idx,'base',x->>'base','dias',x->'dias','fase',case when x->>'base'='Pedido'then 'Adiantamento'else 'Provisionado'end))returning * into pa;
 else update public.imp_parcelas set valor=v,data_base=base,dias=(x->>'dias')::int,vencimento=base+(x->>'dias')::int,status='Prevista',financeiro=jsonb_build_object('automatico',true,'indice',idx,'base',x->>'base','dias',x->'dias','fase',case when x->>'base'='Pedido'then 'Adiantamento'else 'Provisionado'end),versao=versao+1,atualizado_por=uid,atualizado_em=clock_timestamp() where id=pa.id and (valor is distinct from v or vencimento is distinct from base+(x->>'dias')::int or status='Cancelada' or financeiro->>'base' is distinct from x->>'base') returning * into pa;
 end if;
 if pa.id is not null and pa.meio_pagamento is distinct from p.meio_pagamento_previsto then update public.imp_parcelas set meio_pagamento=p.meio_pagamento_previsto,versao=versao+1,atualizado_por=uid,atualizado_em=clock_timestamp() where id=pa.id returning * into pa;end if;
 if pa.id is not null and old is distinct from to_jsonb(pa)then insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('parcelas',pa.id,uid,old,to_jsonb(pa));end if;
 end loop;
 for pa in select * from public.imp_parcelas where pedido_id=pid and status<>'Cancelada' and financeiro->>'automatico'='true' and (financeiro->>'indice')::int>idx loop
 update public.imp_parcelas set status='Cancelada',versao=versao+1,atualizado_por=uid where id=pa.id;
 insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('parcelas',pa.id,uid,to_jsonb(pa),jsonb_build_object('evento','Substituição da programação automática','status','Cancelada'));
 end loop;
end $function$
;
