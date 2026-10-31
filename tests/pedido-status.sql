-- Executar em uma transação de teste e encerrar com ROLLBACK.
do $test$
declare pid uuid:=gen_random_uuid();i1 uuid:=gen_random_uuid();i2 uuid:=gen_random_uuid();eid uuid:=gen_random_uuid();f bigint;u uuid;s text;
begin
 select fornecedor_id,atualizado_por into f,u from public.imp_pedidos limit 1;
 insert into public.imp_pedidos(id,fornecedor_id,referencia,moeda,status,atualizado_por)values(pid,f,'TESTE-STATUS-'||pid,'USD','Elaboração',u);
 insert into public.imp_pedido_itens(id,pedido_id,linha,descricao,unidade,quantidade,valor_unitario)values(i1,pid,'1','Teste','UN',1,1),(i2,pid,'2','Teste','UN',1,1);
 set constraints all immediate;
 select status into s from public.imp_pedidos where id=pid;if s<>'Elaboração' then raise exception 'Esperado Elaboração, obtido %',s;end if;
 update public.imp_pedidos set status='Enviado' where id=pid;
 update public.imp_pedidos set status='Aceito -ACK',ack_numero='TESTE',ack_data=current_date where id=pid;
 insert into public.imp_embarques(id,referencia,fornecedor_id,moeda,status,atualizado_por)values(eid,'TESTE-'||eid,f,'USD','Em trânsito',u);
 insert into public.imp_embarque_itens(embarque_id,pedido_item_id,quantidade)values(eid,i1,1);
 select status into s from public.imp_pedidos where id=pid;if s<>'Aguardando Recebimento' then raise exception 'Esperado aguardando, obtido %',s;end if;
 update public.imp_embarque_itens set recebida=1,data_recebimento=current_date where embarque_id=eid;
 select status into s from public.imp_pedidos where id=pid;if s<>'Recebimento Parcial' then raise exception 'Embarque completo não completa pedido: %',s;end if;
 insert into public.imp_embarque_itens(embarque_id,pedido_item_id,quantidade,recebida,data_recebimento)values(eid,i2,1,1,current_date);
 select status into s from public.imp_pedidos where id=pid;if s<>'Recebido' then raise exception 'Esperado recebido, obtido %',s;end if;
 update public.imp_embarque_itens set recebida=0,data_recebimento=null where embarque_id=eid and pedido_item_id=i2;
 select status into s from public.imp_pedidos where id=pid;if s<>'Recebimento Parcial' then raise exception 'Estorno deve reabrir parcial: %',s;end if;
end $test$;
