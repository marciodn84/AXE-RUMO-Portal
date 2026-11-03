CREATE OR REPLACE FUNCTION public.axe_rumo_compartilhar_vinculos(p_usuario uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $fn$
DECLARE x record;s public.produtos_clientes_referencias;ant jsonb;fac numeric;n int:=0;
BEGIN
IF NOT EXISTS(SELECT 1 FROM public.axe_rumo_revisores WHERE usuario_id=p_usuario AND ativo) THEN RAISE EXCEPTION 'Sem permissão';END IF;
PERFORM pg_advisory_xact_lock(hashtextextended('axe_cadastros_comerciais',0));
FOR x IN
WITH mapas AS(SELECT r.codigo_cliente,min(r.produto_axe_id) AS produto_id FROM public.produtos_clientes_referencias r JOIN public.clientes c ON c.id=r.cliente_id JOIN public.produtos_conciliacao p ON p.id=r.produto_axe_id WHERE c.grupo_comercial='RUMO' AND NOT c.legado_grupo AND r.ativo AND p.ativo AND p.mesclado_em_id IS NULL AND p.codigo_axe IS NOT NULL GROUP BY r.codigo_cliente HAVING count(DISTINCT r.produto_axe_id)=1)
SELECT r.id,m.produto_id FROM public.produtos_clientes_referencias r JOIN public.clientes c ON c.id=r.cliente_id JOIN mapas m ON m.codigo_cliente=r.codigo_cliente
WHERE c.grupo_comercial='RUMO' AND NOT c.legado_grupo AND r.ativo AND r.produto_axe_id IS NULL
AND EXISTS(SELECT 1 FROM public.pedidos p JOIN public.pedido_itens i ON i.pedido_id=p.id WHERE p.cliente_id=r.cliente_id AND i.codigo_material=r.codigo_cliente)
AND NOT EXISTS(SELECT 1 FROM public.produtos_clientes_opcoes o WHERE o.referencia_cliente_id=r.id AND o.produto_id=m.produto_id AND o.situacao IN('BLOQUEADO','INATIVO'))
LOOP
SELECT * INTO s FROM public.produtos_clientes_referencias WHERE id=x.id FOR UPDATE;ant:=to_jsonb(s);
SELECT min(r.fator_conversao_axe) INTO fac FROM public.produtos_clientes_referencias r JOIN public.clientes c ON c.id=r.cliente_id
WHERE c.grupo_comercial='RUMO' AND r.codigo_cliente=s.codigo_cliente AND r.produto_axe_id=x.produto_id AND r.ativo AND upper(btrim(r.unidade_cliente))=upper(btrim(s.unidade_cliente))
HAVING count(DISTINCT r.fator_conversao_axe)=1;
UPDATE public.produtos_clientes_referencias SET produto_axe_id=x.produto_id,fator_conversao_axe=fac,vinculado_em=now(),vinculado_por=p_usuario,atualizado_em=now() WHERE id=s.id;
IF fac IS NOT NULL THEN
INSERT INTO public.produtos_clientes_opcoes(referencia_cliente_id,produto_id,tipo_vinculo,situacao,fator_conversao,aprovado_em,aprovado_por,evidencia_aceite)
VALUES(s.id,x.produto_id,'REFERENCIA','APROVADO',fac,now(),p_usuario::text,'Código SAP compartilhado no grupo RUMO; regra confirmada pelo usuário')
ON CONFLICT(referencia_cliente_id,produto_id) DO UPDATE SET situacao='APROVADO',fator_conversao=EXCLUDED.fator_conversao,aprovado_em=EXCLUDED.aprovado_em,aprovado_por=EXCLUDED.aprovado_por,evidencia_aceite=EXCLUDED.evidencia_aceite,atualizado_em=now()
WHERE public.produtos_clientes_opcoes.situacao='EM_AVALIACAO';
END IF;
INSERT INTO public.comercial_eventos(tipo,registro_id,acao,usuario_id,evidencia,anterior,atual)
VALUES('referencia_cliente',s.id,'RECONHECER_CODIGO_GRUPO_RUMO',p_usuario,'Mesmo código SAP; referência específica do CNPJ que enviou o pedido',ant,(SELECT to_jsonb(r) FROM public.produtos_clientes_referencias r WHERE id=s.id));
n:=n+1;
END LOOP;
RETURN jsonb_build_object('referencias_vinculadas',n);
END $fn$;
REVOKE ALL ON FUNCTION public.axe_rumo_compartilhar_vinculos(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.axe_rumo_compartilhar_vinculos(uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.axe_sincronizar_descricoes_rumo(p_usuario uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $fn$
DECLARE x record;r public.produtos_clientes_referencias;novo_nome text;novo_detalhe text;n int:=0;
BEGIN
IF NOT EXISTS(SELECT 1 FROM public.axe_rumo_revisores WHERE usuario_id=p_usuario AND ativo) THEN RAISE EXCEPTION 'Revisor não autorizado';END IF;
PERFORM pg_advisory_xact_lock(hashtextextended('axe_cadastros_comerciais',0));
FOR x IN
SELECT DISTINCT ON(c.id,pi.codigo_material) c.id AS cliente_id,pi.codigo_material,pi.descricao_detalhada,pi.unidade,v.numero_pedido,v.id AS pdf_versao_id,e.id AS extracao_id,v.criado_em AS recebido_em
FROM public.axe_rumo_pdf_itens pi JOIN public.axe_rumo_pdf_extracoes e ON e.id=pi.extracao_id AND e.estado='VALIDADA'
JOIN public.axe_rumo_pdf_versoes v ON v.id=e.pdf_versao_id
JOIN public.clientes c ON c.cnpj=e.dados_faturamento->>'cnpj' AND NOT c.legado_grupo
WHERE nullif(btrim(pi.codigo_material),'') IS NOT NULL AND nullif(btrim(pi.descricao_detalhada),'') IS NOT NULL
AND EXISTS(SELECT 1 FROM public.axe_rumo_pdf_consultas o JOIN public.axe_rumo_coletas co ON co.id=o.coleta_id WHERE o.extracao_id=e.id AND o.estado='OK' AND co.estado='COLETADO' AND co.metadados->'escopo'->>'empresa'='AXE' AND co.metadados->'escopo'->>'portal'='RUMO')
ORDER BY c.id,pi.codigo_material,v.criado_em DESC,v.id DESC,e.criado_em DESC,e.id DESC,pi.numero_item DESC
LOOP
novo_nome:=public.axe_rumo_nome_produto(x.descricao_detalhada);novo_detalhe:=public.axe_rumo_descricao_produto(x.descricao_detalhada);
INSERT INTO public.produtos_clientes_referencias(cliente_id,codigo_cliente,descricao_cliente,descricao_detalhada,unidade_cliente)
VALUES(x.cliente_id,x.codigo_material,novo_nome,novo_detalhe,x.unidade) ON CONFLICT(cliente_id,codigo_cliente) DO NOTHING;
SELECT * INTO r FROM public.produtos_clientes_referencias WHERE cliente_id=x.cliente_id AND codigo_cliente=x.codigo_material FOR UPDATE;
IF r.descricao_cliente IS DISTINCT FROM novo_nome OR r.descricao_detalhada IS DISTINCT FROM novo_detalhe THEN
UPDATE public.produtos_clientes_referencias SET descricao_cliente=novo_nome,descricao_detalhada=novo_detalhe,atualizado_em=now() WHERE id=r.id;
INSERT INTO public.comercial_eventos(tipo,registro_id,acao,usuario_id,evidencia,anterior,atual)
VALUES('referencia_cliente',r.id,'ATUALIZAR_DESCRICAO_RUMO',p_usuario,'Último documento recebido: pedido '||x.numero_pedido,
jsonb_build_object('nome',r.descricao_cliente,'descricao',r.descricao_detalhada),
jsonb_build_object('nome',novo_nome,'descricao',novo_detalhe,'pdf_versao_id',x.pdf_versao_id,'extracao_id',x.extracao_id,'recebido_em',x.recebido_em));
n:=n+1;END IF;
END LOOP;
PERFORM public.axe_rumo_compartilhar_vinculos(p_usuario);
RETURN jsonb_build_object('descricoes_atualizadas',n);
END $fn$;
REVOKE ALL ON FUNCTION public.axe_sincronizar_descricoes_rumo(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.axe_sincronizar_descricoes_rumo(uuid) TO service_role;;
CREATE OR REPLACE FUNCTION public.axe_venda_rumo(p_dados jsonb, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE a text:=p_dados->>'acao';p public.comercial_pedidos;s public.pedidos;
 f jsonb;j jsonb;v jsonb;antes jsonb;items jsonb;refid bigint;prod public.produtos_conciliacao;it record;
 pid bigint;fac numeric;pending numeric;n int;count_open int:=0;source_hash text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.axe_rumo_revisores WHERE usuario_id=p_usuario AND ativo)
 OR NOT EXISTS(SELECT 1 FROM public.gestao_membros WHERE usuario_id=p_usuario AND ativo AND papel IN ('ADMIN','EDITOR')) THEN RAISE EXCEPTION 'Usuário sem permissão para pedido de venda';END IF;
 IF a NOT IN ('rumo_criar','rumo_detalhe','rumo_salvar','rumo_aprovar','rumo_recarregar') THEN RAISE EXCEPTION 'Ação inválida';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('axe_venda_rumo',0));
 IF a='rumo_criar' THEN
  SELECT * INTO s FROM public.pedidos WHERE id=(p_dados->>'pedido_rumo_id')::bigint FOR SHARE;
  IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.clientes WHERE id=s.cliente_id AND grupo_comercial='RUMO' AND ativo AND NOT legado_grupo) THEN RAISE EXCEPTION 'Pedido RUMO não encontrado';END IF;
  SELECT * INTO p FROM public.comercial_pedidos WHERE pedido_rumo_id=s.id;
  IF FOUND THEN RETURN jsonb_build_object('id',p.id,'existente',true);END IF;
  PERFORM public.axe_exigir_cliente_liberado(s.cliente_id);
  f:=public.axe_venda_rumo_fonte(s.id);
  IF jsonb_array_length(f->'itens')=0 THEN RAISE EXCEPTION 'Pedido sem itens para importar';END IF;
  INSERT INTO public.comercial_pedidos(origem,pedido_rumo_id,cliente_id,estado,pedido_cliente,documento,fonte_hash,criado_por)
  VALUES('RUMO',s.id,s.cliente_id,'RASCUNHO',s.numero_pedido,f,public.axe_rumo_hash_json(f),p_usuario) RETURNING * INTO p;
 ELSIF a<>'rumo_criar' THEN
  SELECT * INTO p FROM public.comercial_pedidos WHERE id=(p_dados->>'id')::bigint AND origem='RUMO' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Pedido de venda não encontrado';END IF;
  IF a IN ('rumo_salvar','rumo_aprovar','rumo_recarregar') AND p.versao IS DISTINCT FROM (p_dados->>'versao')::int THEN RAISE EXCEPTION 'Pedido alterado. Atualize antes de continuar';END IF;
  IF a IN ('rumo_salvar','rumo_aprovar','rumo_recarregar') AND p.estado<>'RASCUNHO' THEN RAISE EXCEPTION 'Somente rascunhos podem ser alterados ou aprovados';END IF;
 END IF;
 IF a IN ('rumo_criar','rumo_recarregar') THEN
  PERFORM public.axe_sincronizar_descricoes_rumo(p_usuario);
  f:=public.axe_venda_rumo_fonte(p.pedido_rumo_id);
  FOR j IN SELECT value FROM jsonb_array_elements(f->'itens') LOOP
   SELECT id INTO refid FROM public.produtos_clientes_referencias WHERE cliente_id=p.cliente_id AND codigo_cliente=j->>'codigo_cliente';
   INSERT INTO public.comercial_pedido_itens(pedido_id,item_rumo_id,referencia_cliente_id,produto_id,fator_conversao,numero_item,codigo_cliente,nome_cliente,descricao_detalhada,unidade_cliente,quantidade,preco_unitario,moeda,data_remessa,dados_fonte)
   SELECT p.id,(j->>'item_rumo_id')::bigint,refid,r.produto_axe_id,r.fator_conversao_axe,j->>'numero_item',j->>'codigo_cliente',j->>'nome_cliente',j->>'descricao_detalhada',j->>'unidade_cliente',
    (j->>'quantidade')::numeric,(j->>'preco_unitario')::numeric,j->>'moeda',(j->>'data_remessa')::date,j
   FROM (SELECT 1)x LEFT JOIN public.produtos_clientes_referencias r ON r.id=refid
   ON CONFLICT(item_rumo_id) DO UPDATE SET produto_id=CASE WHEN public.comercial_pedido_itens.codigo_cliente IS NOT DISTINCT FROM EXCLUDED.codigo_cliente AND public.comercial_pedido_itens.unidade_cliente IS NOT DISTINCT FROM EXCLUDED.unidade_cliente THEN public.comercial_pedido_itens.produto_id ELSE EXCLUDED.produto_id END,fator_conversao=CASE WHEN public.comercial_pedido_itens.codigo_cliente IS NOT DISTINCT FROM EXCLUDED.codigo_cliente AND public.comercial_pedido_itens.unidade_cliente IS NOT DISTINCT FROM EXCLUDED.unidade_cliente THEN public.comercial_pedido_itens.fator_conversao ELSE EXCLUDED.fator_conversao END,referencia_cliente_id=EXCLUDED.referencia_cliente_id,codigo_cliente=EXCLUDED.codigo_cliente,nome_cliente=EXCLUDED.nome_cliente,descricao_detalhada=EXCLUDED.descricao_detalhada,
    unidade_cliente=EXCLUDED.unidade_cliente,quantidade=EXCLUDED.quantidade,preco_unitario=EXCLUDED.preco_unitario,moeda=EXCLUDED.moeda,data_remessa=EXCLUDED.data_remessa,dados_fonte=EXCLUDED.dados_fonte;
  END LOOP;
  -- Itens retirados/cancelados no SAP permanecem no histórico e impedem aprovação sem nova conferência.
  UPDATE public.comercial_pedidos SET documento=f,fonte_hash=public.axe_rumo_hash_json(f),versao=versao+CASE WHEN a='rumo_recarregar' THEN 1 ELSE 0 END WHERE id=p.id RETURNING * INTO p;
  INSERT INTO public.comercial_eventos(tipo,registro_id,acao,usuario_id,evidencia,atual)VALUES('pedido',p.id,a,p_usuario,'Pedido de origem RUMO '||p.pedido_cliente,to_jsonb(p));
 END IF;
 IF a='rumo_salvar' THEN
  IF jsonb_typeof(p_dados->'itens') IS DISTINCT FROM 'array' OR jsonb_array_length(p_dados->'itens')<>(SELECT count(*) FROM public.comercial_pedido_itens WHERE pedido_id=p.id) THEN RAISE EXCEPTION 'Confira todos os itens do pedido';END IF;
  IF (SELECT count(DISTINCT value->>'id') FROM jsonb_array_elements(p_dados->'itens'))<>jsonb_array_length(p_dados->'itens') THEN RAISE EXCEPTION 'Itens repetidos';END IF;
  FOR j IN SELECT value FROM jsonb_array_elements(p_dados->'itens') LOOP
   IF NOT EXISTS(SELECT 1 FROM public.comercial_pedido_itens WHERE id=(j->>'id')::bigint AND pedido_id=p.id) THEN RAISE EXCEPTION 'Item não pertence ao pedido';END IF;
   pid:=nullif(j->>'produto_id','')::bigint;fac:=nullif(j->>'fator_conversao','')::numeric;
   IF pid IS NOT NULL THEN
    SELECT * INTO prod FROM public.produtos_conciliacao WHERE id=pid AND ativo AND mesclado_em_id IS NULL AND codigo_axe IS NOT NULL FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Selecione um produto AXE ativo com código próprio';END IF;
    PERFORM public.axe_exigir_cadastro_liberado('produto',pid);
    IF fac IS NULL THEN
     SELECT CASE WHEN upper(btrim(unidade_cliente))=upper(btrim(prod.unidade_referencia)) THEN 1 END INTO fac FROM public.comercial_pedido_itens WHERE id=(j->>'id')::bigint;
    END IF;
   END IF;
   IF fac IS NOT NULL AND fac<=0 THEN RAISE EXCEPTION 'Fator de conversão deve ser positivo';END IF;
   UPDATE public.comercial_pedido_itens SET produto_id=pid,fator_conversao=fac WHERE id=(j->>'id')::bigint;
  END LOOP;
  UPDATE public.comercial_pedidos SET versao=versao+1 WHERE id=p.id RETURNING * INTO p;
  INSERT INTO public.comercial_eventos(tipo,registro_id,acao,usuario_id,evidencia,atual)VALUES('pedido',p.id,a,p_usuario,'Vínculos de produtos conferidos no rascunho',to_jsonb(p));
 END IF;
 IF a='rumo_aprovar' THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('axe_rumo_cadastro_oficial',0));
  PERFORM pg_advisory_xact_lock(hashtextextended('axe_cadastros_comerciais',0));
  PERFORM public.axe_sincronizar_descricoes_rumo(p_usuario);
  PERFORM public.axe_exigir_cliente_liberado(p.cliente_id);
  f:=public.axe_venda_rumo_fonte(p.pedido_rumo_id);
  IF public.axe_rumo_hash_json(f) IS DISTINCT FROM p.fonte_hash THEN RAISE EXCEPTION 'O pedido RUMO mudou. Recarregue os dados de origem e confira antes de aprovar';END IF;
  IF (SELECT count(*) FROM public.comercial_pedido_itens WHERE pedido_id=p.id)<>jsonb_array_length(f->'itens') THEN RAISE EXCEPTION 'A composição do pedido RUMO mudou';END IF;
  FOR it IN SELECT v.*,i.fase_status_sap,i.quantidade_pendente FROM public.comercial_pedido_itens v JOIN public.pedido_itens i ON i.id=v.item_rumo_id WHERE v.pedido_id=p.id ORDER BY v.id FOR UPDATE OF v,i LOOP
   IF it.produto_id IS NULL OR it.fator_conversao IS NULL THEN RAISE EXCEPTION 'Item %: vincule o produto AXE e confira a conversão de unidade',it.numero_item;END IF;
   SELECT * INTO prod FROM public.produtos_conciliacao WHERE id=it.produto_id AND ativo AND codigo_axe IS NOT NULL AND mesclado_em_id IS NULL FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Produto AXE inválido no item %',it.numero_item;END IF;
   PERFORM public.axe_exigir_cadastro_liberado('produto',prod.id);
   IF it.nome_cliente='' OR it.quantidade IS NULL OR it.preco_unitario IS NULL OR it.moeda IS NULL OR it.unidade_cliente IS NULL THEN RAISE EXCEPTION 'Item %: faltam dados no documento de origem',it.numero_item;END IF;
   IF it.fase_status_sap IN ('CANCELADO','RECUSADO','CANCELADO_PDF_SEM_PRODUTOS','ITEM_EXCLUIDO_PDF') THEN RAISE EXCEPTION 'Item % cancelado ou recusado no SAP',it.numero_item;END IF;
   IF EXISTS(SELECT 1 FROM public.produtos_clientes_referencias rr JOIN public.clientes cc ON cc.id=rr.cliente_id WHERE cc.grupo_comercial='RUMO' AND rr.ativo AND rr.codigo_cliente=it.codigo_cliente AND rr.produto_axe_id<>prod.id) THEN RAISE EXCEPTION 'Código SAP % já vinculado a outro produto AXE no grupo RUMO. Confira a identidade do produto',it.codigo_cliente;END IF;
   refid:=NULL;
   IF nullif(btrim(it.codigo_cliente),'') IS NOT NULL THEN
   INSERT INTO public.produtos_clientes_referencias(cliente_id,codigo_cliente,descricao_cliente,descricao_detalhada,unidade_cliente)
   VALUES(p.cliente_id,it.codigo_cliente,it.nome_cliente,it.descricao_detalhada,it.unidade_cliente) ON CONFLICT(cliente_id,codigo_cliente) DO NOTHING;
   SELECT id,produto_axe_id INTO refid,pid FROM public.produtos_clientes_referencias WHERE cliente_id=p.cliente_id AND codigo_cliente=it.codigo_cliente FOR UPDATE;
   IF pid IS NOT NULL AND pid<>prod.id THEN RAISE EXCEPTION 'Código % já vinculado a outro produto AXE. Revise o vínculo no cadastro do cliente',it.codigo_cliente;END IF;
   antes:=(SELECT to_jsonb(r) FROM public.produtos_clientes_referencias r WHERE id=refid);
   UPDATE public.produtos_clientes_referencias SET produto_axe_id=prod.id,fator_conversao_axe=it.fator_conversao,vinculado_em=now(),vinculado_por=p_usuario,atualizado_em=now() WHERE id=refid;
   INSERT INTO public.produtos_clientes_opcoes(referencia_cliente_id,produto_id,tipo_vinculo,situacao,fator_conversao,aprovado_em,aprovado_por,evidencia_aceite)
   VALUES(refid,prod.id,'REFERENCIA','APROVADO',it.fator_conversao,now(),p_usuario::text,'Vínculo aprovado no pedido AXE PC-'||lpad(p.id::text,6,'0'))
   ON CONFLICT(referencia_cliente_id,produto_id) DO UPDATE SET tipo_vinculo='REFERENCIA',situacao='APROVADO',fator_conversao=EXCLUDED.fator_conversao,aprovado_em=EXCLUDED.aprovado_em,aprovado_por=EXCLUDED.aprovado_por,evidencia_aceite=EXCLUDED.evidencia_aceite,atualizado_em=now();
   UPDATE public.comercial_pedido_itens SET referencia_cliente_id=refid WHERE id=it.id;
   END IF;
   -- Completar somente dados AXE ausentes; descrições do cliente ficam nos campos próprios.
   IF nullif(prod.unidade_referencia,'') IS NULL AND it.fator_conversao=1 THEN UPDATE public.produtos_conciliacao SET unidade_referencia=it.unidade_cliente WHERE id=prod.id;END IF;
   UPDATE public.pedido_itens_produtos SET status_validacao='PENDENTE' WHERE item_id=it.item_rumo_id AND produto_id<>prod.id AND status_validacao='VALIDADO';
   INSERT INTO public.pedido_itens_produtos(item_id,produto_id,fonte,status_validacao)VALUES(it.item_rumo_id,prod.id,'Vínculo aprovado em pedido de venda AXE','VALIDADO')
   ON CONFLICT(item_id,produto_id) DO UPDATE SET status_validacao='VALIDADO',fonte=EXCLUDED.fonte,atualizado_em=now();
   UPDATE public.produtos_observacoes ob SET produto_id=prod.id,referencia_cliente_id=refid,situacao_vinculo='IDENTIFICADOR_VALIDADO'
    WHERE ob.cliente_id=p.cliente_id AND ob.contexto='CLIENTE' AND (ob.codigo=it.codigo_cliente OR (it.codigo_cliente IS NULL AND ob.item_id=it.item_rumo_id))
    AND (ob.produto_id IS NULL OR ob.produto_id=prod.id OR EXISTS(SELECT 1 FROM public.produtos_conciliacao op WHERE op.id=ob.produto_id AND op.codigo_axe IS NULL));
   UPDATE public.pedido_itens_condicoes co SET produto_id=prod.id,referencia_cliente_id=refid,situacao_vinculo='IDENTIFICADOR_VALIDADO'
    WHERE co.cliente_id=p.cliente_id AND co.origem='PEDIDO_PDF' AND (co.codigo_produto=it.codigo_cliente OR (it.codigo_cliente IS NULL AND co.item_id=it.item_rumo_id))
    AND (co.produto_id IS NULL OR co.produto_id=prod.id OR EXISTS(SELECT 1 FROM public.produtos_conciliacao op WHERE op.id=co.produto_id AND op.codigo_axe IS NULL));
   INSERT INTO public.comercial_eventos(tipo,registro_id,acao,usuario_id,evidencia,anterior,atual)
   VALUES('pedido',p.id,'VINCULAR_PRODUTO_CLIENTE',p_usuario,'Cliente e código SAP; nome separado da descrição detalhada',antes,(SELECT to_jsonb(r) FROM public.produtos_clientes_referencias r WHERE id=refid));
   pending:=CASE WHEN it.fase_status_sap='ENTREGUE' THEN 0 ELSE it.quantidade_pendente END;
   IF pending IS NULL OR pending>it.quantidade THEN RAISE EXCEPTION 'Saldo do item % não confiável. Confira o SAP antes de liberar',it.numero_item;END IF;
   IF pending>0 THEN
    INSERT INTO public.comercial_pedido_execucao(pedido_item_id,produto_id,quantidade)VALUES(it.id,prod.id,pending*it.fator_conversao);
    count_open:=count_open+1;
   END IF;
  END LOOP;
  IF count_open=0 THEN RAISE EXCEPTION 'Pedido já entregue ou sem saldo para iniciar execução interna';END IF;
  PERFORM public.axe_rumo_compartilhar_vinculos(p_usuario);
  FOR it IN SELECT DISTINCT codigo_cliente,produto_id FROM public.comercial_pedido_itens WHERE pedido_id=p.id LOOP
   PERFORM public.axe_consolidar_produtos_rumo(p.cliente_id,it.codigo_cliente,it.produto_id,p_usuario);
  END LOOP;
  UPDATE public.comercial_pedidos SET estado='APROVADO',versao=versao+1,aprovado_em=now(),aprovado_por=p_usuario WHERE id=p.id RETURNING * INTO p;
  INSERT INTO public.comercial_eventos(tipo,registro_id,acao,usuario_id,evidencia,atual)VALUES('pedido',p.id,'APROVAR_INICIAR_FLUXO',p_usuario,'Demandas internas geradas sem baixa de estoque ou emissão fiscal',to_jsonb(p));
 END IF;
 f:=public.axe_venda_rumo_fonte(p.pedido_rumo_id);
 items:=(SELECT coalesce(jsonb_agg(to_jsonb(i)||jsonb_build_object('produto_axe',CASE WHEN pr.id IS NOT NULL THEN jsonb_build_object('id',pr.id,'codigo_axe',pr.codigo_axe,'descricao_referencia',pr.descricao_referencia,'unidade_referencia',pr.unidade_referencia,'forma_obtencao',pr.forma_obtencao) END,'execucao',(SELECT to_jsonb(e) FROM public.comercial_pedido_execucao e WHERE e.pedido_item_id=i.id)) ORDER BY i.numero_item),'[]') FROM public.comercial_pedido_itens i LEFT JOIN public.produtos_conciliacao pr ON pr.id=i.produto_id WHERE i.pedido_id=p.id);
 RETURN to_jsonb(p)||jsonb_build_object('itens',items,'fonte_alterada',public.axe_rumo_hash_json(f) IS DISTINCT FROM p.fonte_hash,'fonte_atual',f,
 'total',(SELECT sum(quantidade*preco_unitario) FROM public.comercial_pedido_itens WHERE pedido_id=p.id));
END $function$;