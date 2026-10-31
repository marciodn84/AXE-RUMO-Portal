begin;
do $test$
declare u uuid;v timestamptz;p uuid:=gen_random_uuid();r jsonb;
begin
select usuario_id into u from public.axe_rumo_revisores where ativo limit 1;
select atualizado_em into v from public.produtos_conciliacao where id=1;
begin perform public.axe_cadastro_bloqueio('produto',1,true,'',u,v);raise exception 'TEST motivo não rejeitado';exception when others then if sqlerrm not like 'Informe o motivo%' then raise;end if;end;
perform public.axe_cadastro_bloqueio('produto',1,true,'Teste transacional',u,v);
begin perform public.axe_exigir_cadastro_liberado('produto',1);raise exception 'TEST produto liberado';exception when others then if sqlerrm not like 'Produto bloqueado:%' then raise;end if;end;
begin insert into public.comercial_propostas(cliente_id,titulo,entrada,documento,total,pendencias,criado_por)values(12184,'Teste bloqueio','{}','{"itens":[{"produto_id":1}]}',1,'[]',u);raise exception 'TEST proposta aceita';exception when others then if sqlerrm not like 'Produto bloqueado:%' then raise;end if;end;
insert into public.imp_pedidos(id,fornecedor_id,referencia,moeda,status,atualizado_por)values(p,7,'TEST-BLOCK-'||p,'USD','Rascunho',u);
begin insert into public.imp_pedido_itens(id,pedido_id,linha,descricao,unidade,quantidade,valor_unitario,produto_id)values(gen_random_uuid(),p,'1','Teste','UN',1,1,1);raise exception 'TEST item aceito';exception when others then if sqlerrm not like 'Produto bloqueado:%' then raise;end if;end;
select atualizado_em into v from public.produtos_conciliacao where id=1;perform public.axe_cadastro_bloqueio('produto',1,false,null,u,v);
perform public.axe_exigir_cadastro_liberado('produto',1);
insert into public.imp_pedido_itens(id,pedido_id,linha,descricao,unidade,quantidade,valor_unitario,produto_id)values(gen_random_uuid(),p,'1','Teste','UN',1,1,1);
select atualizado_em into v from public.fornecedores where id=7;perform public.axe_cadastro_bloqueio('fornecedor',7,true,'Teste transacional',u,v);
begin insert into public.imp_pedidos(fornecedor_id,referencia,moeda,status,atualizado_por)values(7,'TEST-BLOCK-NEW','USD','Rascunho',u);raise exception 'TEST fornecedor aceito';exception when others then if sqlerrm not like 'Fornecedor bloqueado:%' then raise;end if;end;
begin insert into public.imp_pedido_itens(id,pedido_id,linha,descricao,unidade,quantidade,valor_unitario,produto_id)values(gen_random_uuid(),p,'2','Teste','UN',1,1,1);raise exception 'TEST fornecedor item aceito';exception when others then if sqlerrm not like 'Fornecedor bloqueado:%' then raise;end if;end;
select atualizado_em into v from public.fornecedores where id=7;perform public.axe_cadastro_bloqueio('fornecedor',7,false,null,u,v);
perform public.axe_exigir_cadastro_liberado('fornecedor',7);
if (select count(*) from public.cadastros_decisoes where entidade in ('PRODUTO_COMERCIAL','FORNECEDOR_COMERCIAL') and criado_em>=transaction_timestamp())<>4 then raise exception 'TEST histórico incompleto';end if;
end $test$;
rollback;
select 'Bloqueio, desbloqueio, motivo, histórico e proteção de operações: OK; testes revertidos' as resultado;
