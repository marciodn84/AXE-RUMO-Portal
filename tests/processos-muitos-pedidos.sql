set constraints all deferred;
do $test$
declare uid uuid;f bigint;po1 uuid:=gen_random_uuid();po2 uuid:=gen_random_uuid();proc1 uuid;proc2 uuid;r jsonb;item1 uuid:=gen_random_uuid();item2 uuid:=gen_random_uuid();paid uuid;
begin
 select fornecedor_id,atualizado_por into f,uid from public.imp_pedidos limit 1;
 insert into public.imp_pedidos(id,fornecedor_id,referencia,moeda,status,atualizado_por)values(po1,f,'TESTE-M1-'||po1,'USD','Enviado',uid),(po2,f,'TESTE-M2-'||po2,'USD','Enviado',uid);
 insert into public.imp_pedido_itens(id,pedido_id,linha,descricao,unidade,quantidade,valor_unitario)values(item1,po1,'1','TESTE','UN',1,10),(item2,po2,'1','TESTE','UN',1,20);
 set constraints all immediate;
 select processo_id into proc1 from public.imp_importacao_pedidos where pedido_id=po1;
 select processo_id into proc2 from public.imp_importacao_pedidos where pedido_id=po2;
 perform public.axe_imp_fluxo(jsonb_build_object('acao','custo_fluxo_consolidar','processo_id',proc1,'origem_id',proc2),uid);
 r:=public.axe_imp_fluxo(jsonb_build_object('acao','custo_fluxo_detalhe','processo_id',proc1,'pedido_id',po1),uid);
 if jsonb_array_length(r->'pedidos')<>2 then raise exception 'Processo deve reunir dois POs';end if;
 if public.axe_imp_processo_raiz(proc2)<>proc1 then raise exception 'Origem consolidada deve preservar destino';end if;
 r:=public.axe_imp_estrutura(jsonb_build_object('acao','v2_salvar','tipo','parcelas','requisicao_id',gen_random_uuid(),'dados',jsonb_build_object('pedido_id',po1,'referencia','TESTE PIX','modo','Valor','valor',10,'marco','Manual','status','Prevista','valor_pago',10,'data_pagamento',current_date,'meio_pagamento','PIX')),uid);
 paid:=(r->>'id')::uuid;if not exists(select 1 from public.imp_parcelas where id=paid and valor_pago=10 and meio_pagamento='PIX' and contrato_cambio is null) then raise exception 'PIX manual deve dispensar SWIFT/contrato';end if;
end $test$;
