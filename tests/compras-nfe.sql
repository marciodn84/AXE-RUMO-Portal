-- Rodar em BEGIN/ROLLBACK com axe.test_xml definido para um XML de teste autorizado.
-- O arquivo real permanece fora do repositório.
do $test$
declare uid uuid;pid uuid;xml text:=current_setting('axe.test_xml');d jsonb;r jsonb;payload jsonb;item uuid;count_before bigint;failed boolean;begin
 select g.usuario_id into uid from public.gestao_membros g join public.axe_rumo_revisores ar on ar.usuario_id=g.usuario_id and ar.ativo where g.ativo and g.papel='ADMIN'limit 1;
 select p.id,i.id into pid,item from public.imp_pedidos p join public.imp_pedido_itens i on i.pedido_id=p.id where p.referencia='PO002225';
 if uid is null or pid is null then raise exception 'Contexto de teste ausente';end if;
 select count(*)into count_before from public.estoque_movimentos;
 d:=public.axe_compra_nfe_ler(xml);
 assert d->>'numero'='417542';assert (d->'totais'->>'vNF')::numeric=16236.86;
 assert d->'itens'->0->>'unidade'='PC';assert (d->'itens'->0->>'valor_unitario')::numeric=1176.5841666667;
 r:=public.axe_compra_nfe(jsonb_build_object('acao','compra_nf_ler','pedido_id',pid,'xml',xml),uid);
 assert (select count(*)from public.estoque_movimentos)=count_before;
 payload:=jsonb_build_object('acao','compra_nf_confirmar','pedido_id',pid,'pedido_versao',r->'pedido_versao','requisicao_id',gen_random_uuid(),'xml',xml,'nome','teste.xml','data_entrada',current_date,'confirmado',true,'custos_conferidos',true,'justificativa','Conferência de teste PC para UN e diferença de centavos','vinculos',jsonb_build_array(jsonb_build_object('linha',1,'pedido_item_id',item,'fator','1','custo_total','16236.86','salvar_fornecedor',true)));
 failed:=false;begin perform public.axe_compra_nfe(payload-'custos_conferidos',uid);exception when raise_exception then failed:=true;end;assert failed,'Exige conferência dos custos';
 failed:=false;begin perform public.axe_compra_nfe(jsonb_set(payload,'{vinculos,0,fator}','"2"'),uid);exception when raise_exception then failed:=true;end;assert failed,'Bloqueia recebimento acima do saldo';
 r:=public.axe_compra_nfe(payload,uid);
 assert (select status from public.imp_pedidos where id=pid)='Recebido';
 assert public.axe_compra_nfe_recebida(item)=12;
 assert (select count(*)from public.estoque_movimentos)=count_before+1;
 assert public.axe_compra_nfe(payload,uid)=r,'Repetição idempotente';
 assert exists(select 1 from public.produtos_fornecedores where produto_id=1160 and codigo_fornecedor='1066714'and unidade_compra='PC'and fator_conversao=1);
 failed:=false;begin perform public.axe_compra_nfe(payload||jsonb_build_object('requisicao_id',gen_random_uuid()),uid);exception when raise_exception then failed:=true;end;assert failed,'Bloqueia chave duplicada';
 failed:=false;begin perform public.axe_compra_nfe_ler(replace(xml,'39893713000167','39893713000168'));exception when raise_exception then failed:=true;end;assert failed,'Bloqueia destinatário diferente';
 failed:=false;begin perform public.axe_compra_nfe_ler('<!DOCTYPE root [<!ENTITY a "x">]><root/>');exception when raise_exception then failed:=true;end;assert failed,'Bloqueia DTD';
 failed:=false;begin perform public.axe_compra_nfe(payload,null);exception when raise_exception then failed:=true;end;assert failed,'Bloqueia usuário ausente';
 perform public.axe_compra_nfe(jsonb_build_object('acao','compra_nf_estornar','pedido_id',pid,'id',r->>'id','requisicao_id',gen_random_uuid(),'confirmado',true,'justificativa','Estorno no teste de integração'),uid);
 assert public.axe_compra_nfe_recebida(item)=0;
 assert (select sum(case when tipo='ENTRADA'then quantidade else -quantidade end)from public.estoque_movimentos where pedido_item_id=item or estorno_de in(select movimento_id from public.compras_nfe_itens where pedido_item_id=item))=0;
 -- Após estorno, a mesma nota pode ser conferida e registrada novamente, preservando o histórico.
 r:=public.axe_compra_nfe(jsonb_build_object('acao','compra_nf_ler','pedido_id',pid,'xml',xml),uid);
 payload:=payload||jsonb_build_object('requisicao_id',gen_random_uuid(),'pedido_versao',r->'pedido_versao');
 payload:=jsonb_set(payload,'{vinculos,0,fator}','"0.5"');
 r:=public.axe_compra_nfe(payload,uid);
 assert public.axe_compra_nfe_recebida(item)=6;
 assert (select status from public.imp_pedidos where id=pid)='Recebimento Parcial';
 failed:=false;begin update public.imp_pedido_itens set quantidade=30 where id=item;exception when raise_exception then failed:=true;end;assert failed,'Protege o item recebido contra alterações';
 failed:=false;begin perform public.axe_estoque(jsonb_build_object('acao','stock_estornar','requisicao_id',gen_random_uuid(),'movimento_id',(select movimento_id from public.compras_nfe_itens where entrada_id=(r->>'id')::uuid),'referencia','Estorno individual indevido'),uid);exception when raise_exception then failed:=true;end;assert failed,'Impede estorno avulso da nota';
 set constraints all immediate;
end $test$;
