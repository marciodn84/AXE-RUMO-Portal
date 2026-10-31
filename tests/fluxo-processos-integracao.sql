set constraints all deferred;
do $test$
declare f bigint;u uuid;pid uuid:=gen_random_uuid();p2 uuid:=gen_random_uuid();i1 uuid:=gen_random_uuid();i2 uuid:=gen_random_uuid();eid uuid:=gen_random_uuid();nid uuid:=gen_random_uuid();root uuid;r jsonb;cnt int;total numeric;
begin
 select fornecedor_id,atualizado_por into f,u from public.imp_pedidos limit 1;
 insert into public.imp_pedidos(id,fornecedor_id,referencia,moeda,status,forma_pagamento,condicao_pagamento,atualizado_por)values(pid,f,'TESTE-ANT-'||pid,'USD','Enviado','ANTECIPADO','100% antecipado',u);
 insert into public.imp_pedido_itens(id,pedido_id,linha,descricao,unidade,quantidade,valor_unitario)values(i1,pid,'1','TESTE','UN',5,100),(i2,pid,'2','TESTE','UN',10,100);
 set constraints all immediate;
 select count(*),sum(valor) into cnt,total from public.imp_parcelas where pedido_id=pid;if cnt<>1 or total<>1500 then raise exception 'Antecipado deve gerar 1500 uma vez: % / %',cnt,total;end if;
 perform public.axe_imp_processos_reconciliar(u);perform public.axe_imp_processos_reconciliar(u);
 select count(*) into cnt from public.imp_importacao_pedidos where pedido_id=pid;if cnt<>1 then raise exception 'Processo duplicado';end if;
 insert into public.imp_embarques(id,referencia,fornecedor_id,moeda,status,atualizado_por)values(eid,'TESTE-EMB-'||eid,f,'USD','Em trânsito',u);
 insert into public.imp_embarque_itens(embarque_id,pedido_item_id,quantidade)values(eid,i1,2);
 -- Fatos de recebimento e fechamento são isolados e revertidos neste teste.
 update public.imp_embarque_itens set recebida=2,data_recebimento=current_date where embarque_id=eid;
 update public.imp_embarques set status='Recebido' where id=eid;
 insert into public.imp_notas(id,chave,xml,xml_sha256,embarque_id,estado,atualizado_por)values(nid,lpad(floor(random()*1e15)::text,44,'9'),'{}'::jsonb,repeat('a',64),eid,'Conciliada',u);
 insert into public.imp_fluxo_estoque_confirmacoes(embarque_id,nota_id,data_entrada,referencia,usuario_id)values(eid,nid,current_date,'TESTE',u);
 select count(*) into cnt from public.imp_importacao_processos q join public.imp_importacao_pedidos pp on pp.processo_id=q.id where pp.pedido_id=pid and q.estado='Encerrado';if cnt<>0 then raise exception 'Estoque sozinho não encerra';end if;
 insert into public.imp_custos(embarque_id,estado,dados,resultado,atualizado_por)values(eid,'Final','{}','{}',u);
 select count(*) into cnt from public.imp_importacao_pedidos where pedido_id=pid;if cnt<>2 then raise exception 'Saldo deve abrir parcial 02: %',cnt;end if;
 select q.id into root from public.imp_importacao_pedidos pp join public.imp_importacao_processos q on q.id=pp.processo_id where pp.pedido_id=pid and pp.parcial=2;
 select sum(quantidade) into total from public.imp_importacao_itens where processo_id=root;if total<>13 then raise exception 'Saldo deve ser 3 + 10, obtido %',total;end if;
 perform public.axe_imp_processos_reconciliar(u);select count(*) into cnt from public.imp_importacao_pedidos where pedido_id=pid;if cnt<>2 then raise exception 'Revisão não deve abrir parcial repetida';end if;
 -- Parcelado com percentuais documentados e pagamento manual sem SWIFT.
 insert into public.imp_pedidos(id,fornecedor_id,referencia,moeda,status,forma_pagamento,condicao_pagamento,atualizado_por)values(p2,f,'TESTE-PARC-'||p2,'USD','Enviado','PARCELADO','30% antecipado e 70% no embarque',u);
 insert into public.imp_pedido_itens(id,pedido_id,linha,descricao,unidade,quantidade,valor_unitario)values(gen_random_uuid(),p2,'1','TESTE','UN',1,100);
 select count(*),sum(valor) into cnt,total from public.imp_parcelas where pedido_id=p2;if cnt<>2 or total<>100 then raise exception 'Parcelado deve gerar 30 + 70: % / %',cnt,total;end if;
end $test$;
