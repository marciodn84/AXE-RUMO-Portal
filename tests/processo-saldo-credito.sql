begin;
do $test$ declare ap public.imp_remessa_processos;src public.imp_importacao_processos;target uuid;cp record;antes numeric;depois numeric;rpantes numeric;
begin
 select * into ap from public.imp_remessa_processos limit 1;select * into src from public.imp_importacao_processos where id=ap.processo_id;
 insert into public.imp_importacao_processos(fornecedor_id,moeda,criado_por)values(src.fornecedor_id,src.moeda,src.criado_por)returning id into target;
 insert into public.imp_importacao_pedidos values(target,ap.pedido_id,(select max(parcial)+1 from public.imp_importacao_pedidos where pedido_id=ap.pedido_id));
 insert into public.imp_importacao_itens select target,pi.id,pi.quantidade from public.imp_pedido_itens pi where pi.pedido_id=ap.pedido_id;
 select * into cp from public.imp_custo_pagamentos where remessa_id=ap.remessa_id order by valor_me limit 1;
 if cp is null then raise exception 'Fixture de pagamento por item ausente';end if;
 select sum(valor) into antes from public.imp_remessa_processos where remessa_id=ap.remessa_id;
 select sum(valor) into rpantes from public.imp_remessa_parcelas where remessa_id=ap.remessa_id;
 delete from public.imp_custo_pagamentos where id=cp.id;
 perform public.axe_imp_transferir_credito_processo(src.id,target,src.criado_por);
 select sum(valor) into depois from public.imp_remessa_processos where remessa_id=ap.remessa_id;if antes<>depois then raise exception 'Crédito transferido não pode criar saldo';end if;
 if (select valor from public.imp_remessa_processos where processo_id=target and pedido_id=ap.pedido_id and remessa_id=ap.remessa_id)<>cp.valor_me then raise exception 'Transferir somente saldo não consumido';end if;
 if rpantes<>(select sum(valor) from public.imp_remessa_parcelas where remessa_id=ap.remessa_id) then raise exception 'Transferência não pode duplicar pagamento';end if;
end $test$;
rollback;
