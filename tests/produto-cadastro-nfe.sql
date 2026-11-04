do $test$
declare uid uuid;pr public.produtos_conciliacao;p public.imp_pedidos;n public.compras_nfe_entradas;r jsonb;payload jsonb;req uuid:=gen_random_uuid();decisao jsonb;c jsonb;x jsonb;vinculos jsonb:='[]';failed boolean;movs bigint;links bigint;begin
 select g.usuario_id into uid from public.gestao_membros g join public.axe_rumo_revisores ar on ar.usuario_id=g.usuario_id and ar.ativo where g.ativo and g.papel='ADMIN'limit 1;
 select * into pr from public.produtos_conciliacao where codigo_axe='IMP-000259';select count(*)into movs from public.estoque_movimentos;select count(*)into links from public.imp_pedido_itens where produto_id=pr.id;
 if pr.forma_obtencao='TER'then perform public.axe_produto_obtencao_corrigir(jsonb_build_object('produto_id',pr.id,'forma_obtencao','IMP','atualizado_em',pr.atualizado_em,'justificativa','Preparação isolada da fixture de teste de obtenção','requisicao_id',gen_random_uuid(),'confirmado',true),uid);select * into pr from public.produtos_conciliacao where id=pr.id;end if;
 payload:=jsonb_build_object('produto_id',pr.id,'forma_obtencao','TER','atualizado_em',pr.atualizado_em,'justificativa','Teste de correção de compra nacional, preservando vínculos','requisicao_id',req,'confirmado',true);
 failed:=false;begin perform public.axe_produto_obtencao_corrigir(payload,null);exception when raise_exception then failed:=true;end;assert failed;
 failed:=false;begin update public.produtos_conciliacao set forma_obtencao='TER'where id=pr.id;exception when raise_exception then failed:=true;end;assert failed,'Trava direta mantida';
 r:=public.axe_produto_obtencao_corrigir(payload,uid);assert r->'resultado'->>'codigo_axe'='IMP-000259';assert r->'resultado'->>'forma_obtencao'='TER';assert public.axe_produto_obtencao_corrigir(payload,uid)=r;
 assert (select count(*)from public.imp_pedido_itens where produto_id=pr.id)=links;
 select * into p from public.imp_pedidos where referencia='PO002225';select * into n from public.compras_nfe_entradas where pedido_id=p.id and estado='Confirmada'limit 1;
 update public.produtos_fornecedores set descricao_fornecedor='Descrição divergente de teste',atualizado_em=clock_timestamp()where produto_id=pr.id and fornecedor_id=p.fornecedor_id;
 r:=public.axe_compra_nfe(jsonb_build_object('acao','compra_nf_cadastro_previa','pedido_id',p.id,'id',n.id),uid);
 for c in select z from jsonb_array_elements(r->'cadastros')z loop
 decisao:=jsonb_build_object('conferido',true,'produto_versao',c->'cadastro'->'produto_versao','fornecedor_versao',c->'cadastro'->'fornecedor_versao','decisoes','{}'::jsonb);
 for x in select z from jsonb_array_elements(c->'cadastro'->'campos')z loop
 if (x->>'exige_decisao')::boolean then decisao:=jsonb_set(decisao,array['decisoes',x->>'campo'],jsonb_build_object('acao','XML'));end if;
 end loop;
 vinculos:=vinculos||jsonb_build_array(jsonb_build_object('linha',c->'linha','pedido_item_id',c->'pedido_item_id','cadastro',decisao));
 end loop;
 payload:=jsonb_build_object('acao','compra_nf_cadastro_salvar','id',n.id,'pedido_id',p.id,'requisicao_id',gen_random_uuid(),'confirmado',true,'vinculos',vinculos);
 failed:=false;begin perform public.axe_compra_nfe(jsonb_set(payload,'{vinculos,0,cadastro,conferido}','false'),uid);exception when raise_exception then failed:=true;end;assert failed,'Sem conferência não salva';
 failed:=false;begin perform public.axe_compra_nfe(jsonb_set(payload,'{vinculos,0,cadastro,produto_versao}','"2000-01-01"'),uid);exception when raise_exception then failed:=true;end;assert failed,'Versão desatualizada bloqueia';
 failed:=false;begin perform public.axe_compra_nfe(payload#-array['vinculos','0','cadastro','decisoes','fornecedor.descricao_fornecedor'],uid);exception when raise_exception then failed:=true;end;assert failed,'Divergência sem decisão bloqueia';
 r:=public.axe_compra_nfe(payload,uid);assert public.axe_compra_nfe(payload,uid)=r;
 select * into pr from public.produtos_conciliacao where id=pr.id;
 assert pr.ncm_referencia='85044030'and pr.cest='1200100'and pr.gtin='4055626734453';assert pr.origem_fiscal_padrao='2';assert pr.status_validacao='VALIDADO';
 assert exists(select 1 from public.produtos_fornecedores where produto_id=pr.id and fornecedor_id=p.fornecedor_id and ncm_informado='85044030'and origem_fiscal='1'and part_number='1066714'and situacao='APROVADO');
 assert (select count(*)from public.estoque_movimentos)=movs,'Completar cadastro não movimenta estoque';
 assert exists(select 1 from public.produtos_obtencao_correcoes where id=req and estado='CONCLUIDA');
end $test$;

do $test$
declare uid uuid;p public.imp_pedidos;n public.compras_nfe_entradas;r jsonb;payload jsonb;item jsonb;c jsonb;x jsonb;decisao jsonb;vinculos jsonb:='[]';movs bigint;begin
 select g.usuario_id into uid from public.gestao_membros g join public.axe_rumo_revisores ar on ar.usuario_id=g.usuario_id and ar.ativo where g.ativo and g.papel='ADMIN'limit 1;
 select * into p from public.imp_pedidos where referencia='PO002225';select * into n from public.compras_nfe_entradas where pedido_id=p.id and estado='Confirmada'limit 1;
 -- Fixture isolada: desativa a nota anterior apenas dentro da transação revertida.
 update public.compras_nfe_entradas set estado='Estornada'where id=n.id;
 select count(*)into movs from public.estoque_movimentos;
 r:=public.axe_compra_nfe(jsonb_build_object('acao','compra_nf_ler','pedido_id',p.id,'xml',n.xml_original),uid);
 for item in select z from jsonb_array_elements(r->'documento'->'itens')z loop
 select z->'cadastro'into c from jsonb_array_elements(r->'cadastros')cc cross join lateral jsonb_array_elements(cc->'opcoes')z where cc->>'linha'=item->>'linha'and z->>'pedido_item_id'=(select pedido_item_id::text from public.compras_nfe_itens where entrada_id=n.id and linha=(item->>'linha')::int);
 decisao:=jsonb_build_object('conferido',true,'produto_versao',c->'produto_versao','fornecedor_versao',c->'fornecedor_versao','decisoes','{}'::jsonb);
 for x in select z from jsonb_array_elements(c->'campos')z loop if(x->>'exige_decisao')::boolean then decisao:=jsonb_set(decisao,array['decisoes',x->>'campo'],jsonb_build_object('acao','XML'));end if;end loop;
 vinculos:=vinculos||jsonb_build_array(jsonb_build_object('linha',item->'linha','pedido_item_id',(select pedido_item_id from public.compras_nfe_itens where entrada_id=n.id and linha=(item->>'linha')::int),'fator','1','custo_total',item->>'valor_bruto','salvar_fornecedor',true,'cadastro',decisao));
 end loop;
 payload:=jsonb_build_object('acao','compra_nf_confirmar','pedido_id',p.id,'pedido_versao',r->'pedido_versao','requisicao_id',gen_random_uuid(),'xml',n.xml_original,'nome','teste.xml','data_entrada',n.data_entrada,'confirmado',true,'custos_conferidos',true,'justificativa','Teste de nova entrada com cadastro resolvido','vinculos',vinculos);
 r:=public.axe_compra_nfe(payload,uid);assert public.axe_compra_nfe(payload,uid)=r;assert(select count(*)from public.estoque_movimentos)=movs+1;
 assert exists(select 1 from public.compras_nfe_cadastro_eventos where nota_id=(r->>'id')::uuid);
 set constraints all immediate;
end $test$;
