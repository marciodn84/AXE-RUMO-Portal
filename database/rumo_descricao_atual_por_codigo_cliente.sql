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
RETURN jsonb_build_object('descricoes_atualizadas',n);
END $fn$;
REVOKE ALL ON FUNCTION public.axe_sincronizar_descricoes_rumo(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.axe_sincronizar_descricoes_rumo(uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.axe_atualizar_cadastros(p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE r record;x record;j jsonb;prod bigint;cl bigint;localid bigint;cnt int;key text;tip text;dados jsonb;fase text;dt date;ref_cliente bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.axe_rumo_revisores WHERE usuario_id=p_usuario AND ativo) THEN RAISE EXCEPTION 'Revisor não autorizado';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('axe_cadastros_comerciais',0));
 FOR r IN
  SELECT DISTINCT ON (e.id) v.numero_pedido,e.*,o.observado_em,p.id AS pedido_oficial_id,p.data_pedido,(e.dados_extraidos || coalesce(k.dados,'{}'::jsonb)) AS dados_cadastro
  FROM public.axe_rumo_pdf_consultas o JOIN public.axe_rumo_coletas c ON c.id=o.coleta_id
  JOIN public.axe_rumo_pdf_extracoes e ON e.id=o.extracao_id AND e.estado='VALIDADA'
  JOIN public.axe_rumo_pdf_versoes v ON v.id=e.pdf_versao_id
  LEFT JOIN public.pedidos p ON p.numero_pedido=v.numero_pedido AND p.cliente_id=(SELECT id FROM public.clientes WHERE cnpj=e.dados_faturamento->>'cnpj' AND NOT legado_grupo)
  LEFT JOIN LATERAL(SELECT k2.dados FROM public.pdf_cadastros_complementos k2 WHERE k2.extracao_pdf_id=e.id ORDER BY k2.criado_em DESC LIMIT 1)k ON true
  WHERE o.estado='OK' AND c.estado='COLETADO' AND c.metadados->'escopo'->>'empresa'='AXE' AND c.metadados->'escopo'->>'portal'='RUMO'
  ORDER BY e.id,o.observado_em DESC,o.id DESC
 LOOP
  cl:=public.axe_cliente_faturamento(r.dados_faturamento->>'cnpj',r.dados_faturamento->>'nome');
  IF cl IS NULL THEN CONTINUE;END IF;
  FOREACH tip IN ARRAY ARRAY['FATURAMENTO','ENTREGA','COBRANCA'] LOOP
   dados:=CASE tip WHEN 'FATURAMENTO' THEN r.dados_faturamento WHEN 'ENTREGA' THEN r.dados_entrega ELSE r.dados_cadastro->'cobranca' END;
   localid:=public.axe_cadastro_local(cl,tip,dados);
   IF localid IS NOT NULL THEN
    INSERT INTO public.pedidos_locais_documentais(numero_pedido,local_id,extracao_pdf_id,fonte_chave,observado_em)
    VALUES(r.numero_pedido,localid,r.id,'PDF:'||r.id,r.observado_em) ON CONFLICT DO NOTHING;
   END IF;
  END LOOP;
  FOR x IN SELECT pi.*,i.id AS item_oficial_id FROM public.axe_rumo_pdf_itens pi
   LEFT JOIN public.pedido_itens i ON i.pedido_id=r.pedido_oficial_id AND public.axe_rumo_item_canonico(i.numero_item)=pi.numero_item
   WHERE pi.extracao_id=r.id LOOP
   -- O código do cliente pertence à referência, mesmo sem produto AXE vinculado.
   ref_cliente:=NULL;prod:=NULL;
   IF nullif(btrim(x.codigo_material),'') IS NOT NULL THEN
   INSERT INTO public.produtos_clientes_referencias(cliente_id,codigo_cliente,descricao_cliente,descricao_detalhada,unidade_cliente)
   VALUES(cl,x.codigo_material,public.axe_rumo_nome_produto(x.descricao_detalhada),public.axe_rumo_descricao_produto(x.descricao_detalhada),x.unidade)
   ON CONFLICT(cliente_id,codigo_cliente) DO NOTHING;
   SELECT id INTO ref_cliente FROM public.produtos_clientes_referencias WHERE cliente_id=cl AND codigo_cliente=x.codigo_material;
   SELECT rr.produto_axe_id INTO prod FROM public.produtos_clientes_referencias rr JOIN public.produtos_conciliacao pr ON pr.id=rr.produto_axe_id
   WHERE rr.id=ref_cliente AND pr.ativo AND pr.mesclado_em_id IS NULL AND pr.codigo_axe IS NOT NULL;
   END IF;
   fase:=CASE WHEN prod IS NULL THEN 'CANDIDATO_DOCUMENTAL' ELSE 'IDENTIFICADOR_VALIDADO' END;
   INSERT INTO public.produtos_observacoes(produto_id,referencia_cliente_id,cliente_id,item_id,contexto,codigo,descricao,unidade,ncm,dados,fonte_chave,extracao_pdf_id,situacao_vinculo,observado_em)
   VALUES(prod,ref_cliente,cl,x.item_oficial_id,'CLIENTE',x.codigo_material,x.descricao_detalhada,x.unidade,coalesce(x.dados_extraidos->>'ncm',public.axe_ncm_documental(x.descricao_detalhada)),x.dados_extraidos,'PDF:'||r.id||':'||x.numero_item,r.id,fase,r.observado_em) ON CONFLICT DO NOTHING;
   IF x.item_oficial_id IS NOT NULL AND prod IS NOT NULL THEN
    INSERT INTO public.pedido_itens_produtos(item_id,produto_id,fonte,status_validacao)
    VALUES(x.item_oficial_id,prod,'Cadastro PDF / vínculo documental',CASE WHEN fase='IDENTIFICADOR_VALIDADO' THEN 'VALIDADO' ELSE 'PENDENTE' END) ON CONFLICT DO NOTHING;
   END IF;
   SELECT coalesce(r.data_pedido,public.axe_cadastro_data(s.payload_original->>'data_pedido')) INTO dt
    FROM public.axe_rumo_status_fiori_snapshots s WHERE s.numero_pedido=r.numero_pedido ORDER BY s.observado_em DESC,s.id DESC LIMIT 1;
   INSERT INTO public.pedido_itens_condicoes(cliente_id,produto_id,referencia_cliente_id,item_id,numero_pedido,numero_item,origem,fonte_chave,extracao_pdf_id,data_negocio,observado_em,cnpj_faturamento,codigo_produto,descricao,unidade,moeda,quantidade,valor_unitario,valor_total,icms_aliquota,icms_valor,ipi_aliquota,ipi_valor,ncm,contexto_fiscal,situacao_vinculo)
   VALUES(cl,prod,ref_cliente,x.item_oficial_id,r.numero_pedido,x.numero_item,'PEDIDO_PDF','PDF:'||r.id||':'||x.numero_item,r.id,dt,r.observado_em,r.dados_faturamento->>'cnpj',x.codigo_material,x.descricao_detalhada,x.unidade,x.moeda,x.quantidade_total,x.valor_unitario,x.valor_total,x.icms_aliquota,x.icms_valor,x.ipi_aliquota,x.ipi_valor,coalesce(x.dados_extraidos->>'ncm',public.axe_ncm_documental(x.descricao_detalhada)),jsonb_strip_nulls(jsonb_build_object('uf_destino',r.dados_faturamento->>'uf')),fase) ON CONFLICT DO NOTHING;
  END LOOP;
 END LOOP;
 FOR r IN SELECT n.*,d.dados_extraidos,d.recebido_em,d.id AS docid,coalesce(k.dados,d.dados_extraidos) AS ext
  FROM public.axe_rumo_nf_itens_documentais n JOIN public.axe_rumo_documentos_externos d ON d.id=n.documento_id
  LEFT JOIN LATERAL(SELECT k2.dados FROM public.documentos_fiscais_complementos k2 WHERE k2.documento_id=d.id ORDER BY k2.criado_em DESC LIMIT 1)k ON true
  WHERE d.canal='EMAIL_NOMUS' AND d.dados_extraidos->>'estado'='AUTORIZADA_XML' LOOP
  cl:=public.axe_cliente_faturamento(r.ext->>'destinatario_cnpj',r.ext->'destinatario'->>'nome');
  IF cl IS NULL THEN CONTINUE;END IF;
  SELECT z.value INTO j FROM jsonb_array_elements(r.ext->'itens') z WHERE z.value->>'item_nf'=r.numero_item_nf;
  j:=coalesce(j,r.dados_originais);
  IF r.ext->'cobranca' IS NOT NULL THEN
   INSERT INTO public.clientes_cobrancas_documentais(documento_id,cliente_id,dados,observado_em)
   VALUES(r.docid,cl,r.ext->'cobranca',r.recebido_em) ON CONFLICT DO NOTHING;
  END IF;
  SELECT min(produto_id),count(DISTINCT produto_id) INTO prod,cnt FROM public.pedido_itens_produtos WHERE item_id=r.item_id AND status_validacao='VALIDADO';
  IF cnt<>1 THEN SELECT min(produto_id),count(DISTINCT produto_id) INTO prod,cnt FROM public.produtos_observacoes WHERE item_id=r.item_id AND contexto='CLIENTE';END IF;
  IF cnt<>1 THEN CONTINUE;END IF;
  -- XML aponta candidato pelo vínculo do item; não aprova equivalência automaticamente.
  INSERT INTO public.produtos_observacoes(produto_id,cliente_id,item_id,contexto,codigo,descricao,unidade,ncm,dados,fonte_chave,documento_id,situacao_vinculo,observado_em)
  VALUES(prod,cl,r.item_id,'AXE_NOMUS',j->>'codigo_produto',j->>'descricao',j->>'unidade',j->>'ncm',j,'XML:'||r.docid||':'||r.numero_item_nf,r.docid,'CANDIDATO_DOCUMENTAL',r.recebido_em)
  ON CONFLICT(fonte_chave) DO UPDATE SET ncm=EXCLUDED.ncm,dados=EXCLUDED.dados;
  IF nullif(j->>'codigo_produto','') IS NOT NULL THEN
   INSERT INTO public.produtos_identificadores(produto_id,contexto,entidade,codigo_produto,descricao_produto,unidade,fonte,status_validacao)
   VALUES(prod,'AXE_NOMUS','AXE',j->>'codigo_produto',j->>'descricao',j->>'unidade','XML Nomus / candidato por item do pedido','PENDENTE') ON CONFLICT DO NOTHING;
  END IF;
  INSERT INTO public.pedido_itens_condicoes(cliente_id,produto_id,item_id,numero_pedido,numero_item,origem,fonte_chave,documento_id,data_negocio,observado_em,cnpj_faturamento,codigo_produto,descricao,unidade,moeda,quantidade,valor_unitario,valor_total,icms_aliquota,icms_valor,ipi_aliquota,ipi_valor,ncm,cfop,contexto_fiscal,situacao_vinculo)
  VALUES(cl,prod,r.item_id,r.numero_pedido,r.numero_item_pedido,'NF_XML','XML:'||r.docid||':'||r.numero_item_nf,r.docid,public.axe_cadastro_data(r.ext->>'data_emissao'),r.recebido_em,r.ext->>'destinatario_cnpj',j->>'codigo_produto',j->>'descricao',j->>'unidade','BRL',r.quantidade,(j->>'valor_unitario')::numeric,r.valor_total,(j->>'icms_aliquota')::numeric,(j->>'icms_valor')::numeric,(j->>'ipi_aliquota')::numeric,(j->>'ipi_valor')::numeric,j->>'ncm',j->>'cfop',jsonb_strip_nulls(jsonb_build_object('uf_origem',r.ext->'emitente'->'endereco'->>'uf','uf_destino',r.ext->'destinatario'->'endereco'->>'uf','cfop',j->>'cfop','crt',r.ext->'emitente'->>'crt','cst_icms',j->>'icms_cst','csosn',j->>'icms_csosn')),'CANDIDATO_DOCUMENTAL')
  ON CONFLICT(fonte_chave) DO UPDATE SET ncm=EXCLUDED.ncm,cfop=EXCLUDED.cfop,contexto_fiscal=EXCLUDED.contexto_fiscal;
  FOREACH tip IN ARRAY ARRAY['FATURAMENTO','ENTREGA'] LOOP
   dados:=CASE tip WHEN 'FATURAMENTO' THEN r.ext->'destinatario' ELSE r.ext->'entrega' END;
   localid:=public.axe_cadastro_local(cl,tip,dados);
   IF localid IS NOT NULL AND r.numero_pedido IS NOT NULL THEN
    INSERT INTO public.pedidos_locais_documentais(numero_pedido,local_id,documento_id,fonte_chave,observado_em)
    VALUES(r.numero_pedido,localid,r.docid,'XML:'||r.docid,r.recebido_em) ON CONFLICT DO NOTHING;
   END IF;
  END LOOP;
 END LOOP;
 PERFORM public.axe_sincronizar_descricoes_rumo(p_usuario);
 PERFORM public.axe_validar_produtos_xml_exato(p_usuario);
 RETURN jsonb_build_object('ok',true,'clientes_locais',(SELECT count(*) FROM public.clientes_locais),'condicoes',(SELECT count(*) FROM public.pedido_itens_condicoes),'produtos',(SELECT count(*) FROM public.produtos_conciliacao));
END $function$;
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
  UPDATE public.comercial_pedidos SET estado='APROVADO',versao=versao+1,aprovado_em=now(),aprovado_por=p_usuario WHERE id=p.id RETURNING * INTO p;
  INSERT INTO public.comercial_eventos(tipo,registro_id,acao,usuario_id,evidencia,atual)VALUES('pedido',p.id,'APROVAR_INICIAR_FLUXO',p_usuario,'Demandas internas geradas sem baixa de estoque ou emissão fiscal',to_jsonb(p));
 END IF;
 f:=public.axe_venda_rumo_fonte(p.pedido_rumo_id);
 items:=(SELECT coalesce(jsonb_agg(to_jsonb(i)||jsonb_build_object('produto_axe',CASE WHEN pr.id IS NOT NULL THEN jsonb_build_object('id',pr.id,'codigo_axe',pr.codigo_axe,'descricao_referencia',pr.descricao_referencia,'unidade_referencia',pr.unidade_referencia,'forma_obtencao',pr.forma_obtencao) END,'execucao',(SELECT to_jsonb(e) FROM public.comercial_pedido_execucao e WHERE e.pedido_item_id=i.id)) ORDER BY i.numero_item),'[]') FROM public.comercial_pedido_itens i LEFT JOIN public.produtos_conciliacao pr ON pr.id=i.produto_id WHERE i.pedido_id=p.id);
 RETURN to_jsonb(p)||jsonb_build_object('itens',items,'fonte_alterada',public.axe_rumo_hash_json(f) IS DISTINCT FROM p.fonte_hash,'fonte_atual',f,
 'total',(SELECT sum(quantidade*preco_unitario) FROM public.comercial_pedido_itens WHERE pedido_id=p.id));
END $function$;