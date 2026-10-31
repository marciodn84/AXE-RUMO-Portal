do $test$
declare pid uuid:=gen_random_uuid();nid uuid:=gen_random_uuid();f bigint;br bigint;u uuid;s text;
begin
 select p.fornecedor_id,p.atualizado_por into f,u from public.imp_pedidos p join public.fornecedores f on f.id=p.fornecedor_id where f.pais<>'BR' limit 1;
 insert into public.imp_pedidos(id,fornecedor_id,referencia,moeda,status,atualizado_por)values(pid,f,'TESTE-PROCESSO-'||pid,'USD','Elaboração',u);
 if public.axe_imp_processo_iniciado(pid) then raise exception 'Rascunho não inicia importação';end if;
 update public.imp_pedidos set status='Enviado' where id=pid;
 if not public.axe_imp_processo_iniciado(pid) or public.axe_imp_status_processo(pid)<>'Aguardando aceite' then raise exception 'Envio deve iniciar processo aguardando aceite';end if;
 update public.imp_pedidos set status='Aceito -ACK' where id=pid;
 set constraints all immediate;
 select status into s from public.imp_pedidos where id=pid;
 if s<>'Aguardando Entrega' or public.axe_imp_status_processo(pid)<>'Aguardando Entrega' then raise exception 'Aceite manual sem PDF deve avançar pedido e processo: %',s;end if;
 select id into br from public.fornecedores where pais='BR' limit 1;
 if br is null then raise exception 'Fixture nacional ausente';end if;
 insert into public.imp_pedidos(id,fornecedor_id,referencia,moeda,status,atualizado_por)values(nid,br,'TESTE-NACIONAL-'||nid,'BRL','Enviado',u);
 if public.axe_imp_processo_iniciado(nid) then raise exception 'Compra nacional não inicia importação';end if;
 if public.axe_imp_forma_pagamento_sugerida('50% antecipado e 50% no embarque')<>'PARCELADO' or public.axe_imp_forma_pagamento_sugerida('Cash on Delivery from invoice date')<>'NA_ENTREGA' or public.axe_imp_forma_pagamento_sugerida('NET 30')<>'A_PRAZO' or public.axe_imp_forma_pagamento_sugerida('100% antecipado')<>'ANTECIPADO' or public.axe_imp_forma_pagamento_sugerida('A combinar') is not null then raise exception 'Classificação de pagamento incorreta';end if;
end $test$;
