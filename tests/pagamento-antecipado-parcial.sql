begin;set constraints all deferred;
do $test$ declare f bigint;uid uuid;pid uuid;r record;cnt integer;
begin select fornecedor_id,atualizado_por into f,uid from public.imp_pedidos limit 1;
for r in select * from (values('50% antecipado',0),('USD 50 antecipado',0),('100% antecipado',1)) t(termos,esperado) loop
 pid:=gen_random_uuid();insert into public.imp_pedidos(id,fornecedor_id,referencia,moeda,status,forma_pagamento,condicao_pagamento,atualizado_por)values(pid,f,'TESTE-ANT-GUARD-'||pid,'USD','Elaboração','ANTECIPADO',r.termos,uid);
 insert into public.imp_pedido_itens(id,pedido_id,linha,descricao,unidade,quantidade,valor_unitario)values(gen_random_uuid(),pid,'1','TESTE','UN',1,100);
 set constraints all immediate;select count(*) into cnt from public.imp_parcelas where pedido_id=pid;if cnt<>r.esperado then raise exception 'Percentual/valor parcial não pode gerar cobrança integral: % / %',r.termos,cnt;end if;set constraints all deferred;
end loop;end $test$;rollback;