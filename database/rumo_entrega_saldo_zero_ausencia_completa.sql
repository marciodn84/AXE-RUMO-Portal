CREATE OR REPLACE FUNCTION public.axe_rumo_aplicar_entregas(p_coleta bigint,p_usuario uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO '' AS $fn$
DECLARE c public.axe_rumo_coletas%rowtype; r record; before_data jsonb; after_data jsonb; n integer:=0; pedidos_alterados bigint[]:=ARRAY[]::bigint[];
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.axe_rumo_revisores WHERE usuario_id=p_usuario AND ativo) THEN RAISE EXCEPTION 'Revisor não autorizado';END IF;
 SELECT * INTO c FROM public.axe_rumo_coletas WHERE id=p_coleta;
 IF NOT FOUND OR c.estado<>'COLETADO' OR c.versao_rastreio<>'rastreio_v1'
 OR c.metadados->>'usuario_id' IS DISTINCT FROM p_usuario::text
 OR c.metadados->'escopo'->>'empresa' IS DISTINCT FROM 'AXE'
 OR c.metadados->'escopo'->>'portal' IS DISTINCT FROM 'RUMO'
 THEN RETURN jsonb_build_object('entregues',0,'motivo','COLETA_NAO_ELEGIVEL');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('axe_rumo_cadastro_oficial',0));
 IF EXISTS(SELECT 1 FROM public.axe_rumo_coletas WHERE escopo_chave=c.escopo_chave AND estado='COLETADO' AND (finalizada_em,id)>(c.finalizada_em,c.id)) THEN RETURN jsonb_build_object('entregues',0,'motivo','COLETA_SUPERADA');END IF;
 IF (SELECT count(DISTINCT fonte) FROM public.axe_rumo_consultas_rastreio
 WHERE coleta_id=p_coleta AND fonte IN ('PENDENTES','HISTORICO','ULTIMO_STATUS')
 AND completa AND http=200 AND estrutura_validada AND NOT paginacao_detectada
 AND NOT (filtros ? '$top' OR filtros ? '$skip'))<>3
 THEN RETURN jsonb_build_object('entregues',0,'motivo','RELATORIO_INCOMPLETO');END IF;
 FOR r IN
 SELECT i.*,p.numero_pedido,o.escopo_chave,o.presente_ultimo_status,o.quantidade_pendente AS saldo_observado,o.observado_em,
 CASE WHEN o.presente_ultimo_status AND o.quantidade_pendente=0 THEN 'SALDO_ZERO' ELSE 'PEDIDO_AUSENTE_RELATORIO_COMPLETO' END AS motivo
 FROM public.pedido_itens i JOIN public.pedidos p ON p.id=i.pedido_id
 JOIN public.axe_rumo_itens_observados o ON o.coleta_id=p_coleta AND o.escopo_chave=c.escopo_chave AND o.numero_pedido=p.numero_pedido AND o.numero_item=public.axe_rumo_item_canonico(i.numero_item)
 WHERE coalesce(i.fase_status_sap,public.axe_rumo_fase_sap(i.status_texto),'') NOT IN ('CANCELADO','RECUSADO')
 AND coalesce(o.fase_status,'') NOT IN ('CANCELADO','RECUSADO','CANCELADO_PDF_SEM_PRODUTOS','ITEM_EXCLUIDO_PDF')
 AND o.situacao_pdf NOT IN ('PEDIDO_SEM_PRODUTOS','ITEM_AUSENTE_NO_PDF')
 AND coalesce(i.status_sap_observado_em,i.ultima_captura_em,'-infinity'::timestamptz)<=c.finalizada_em
 AND ((o.presente_ultimo_status AND o.quantidade_pendente=0) OR
 NOT EXISTS(SELECT 1 FROM public.axe_rumo_status_fiori_snapshots s WHERE s.coleta_id=p_coleta AND s.numero_pedido=p.numero_pedido))
 AND (i.fase_status_sap IS DISTINCT FROM 'ENTREGUE' OR i.situacao_entrega_sap IS DISTINCT FROM 'ENTREGUE' OR i.quantidade_pendente IS DISTINCT FROM 0::numeric)
 ORDER BY i.id FOR UPDATE OF i
 LOOP
  before_data:=jsonb_build_object('fase_status_sap',r.fase_status_sap,'situacao_entrega_sap',r.situacao_entrega_sap,'quantidade_pendente',r.quantidade_pendente,'status_texto_original',r.status_texto,'status_codigo_original',r.status_codigo);
  UPDATE public.pedido_itens SET fase_status_sap='ENTREGUE',situacao_entrega_sap='ENTREGUE',quantidade_pendente=0,atualizado_em=now() WHERE id=r.id;
  after_data:=before_data||jsonb_build_object('fase_status_sap','ENTREGUE','situacao_entrega_sap','ENTREGUE','quantidade_pendente',0);
  INSERT INTO public.axe_rumo_eventos_rastreio(coleta_id,escopo_chave,numero_pedido,numero_item,nivel,tipo,chave_evento,evidencia_tipo,dados,observado_em,versao_regra)
  VALUES(p_coleta,c.escopo_chave,r.numero_pedido,public.axe_rumo_item_canonico(r.numero_item),'ITEM','ENTREGA_REGRA_AXE',
   public.axe_rumo_hash_json(jsonb_build_object('regra','entrega_axe_v1','coleta',p_coleta,'item',r.id,'anterior',before_data,'atual',after_data)),
   'INFERIDO',jsonb_build_object('item_id',r.id,'anterior',before_data,'atual',after_data,'motivo',r.motivo,'usuario_id',p_usuario,'registrado_em',now(),'resposta_origem','Saldo zero ou ausência no relatório completo do SAP significa recebido/Entregue, mesmo antes do aceite.','data_entrega_fisica_nao_inferida',true),c.finalizada_em,'entrega_axe_v1')
  ON CONFLICT(chave_evento) DO NOTHING;
  pedidos_alterados:=array_append(pedidos_alterados,r.pedido_id);n:=n+1;
 END LOOP;
 UPDATE public.pedidos p SET status_cabecalho=x.status,atualizado_em=now()
 FROM (SELECT pedido_id,CASE WHEN bool_and(fase_status_sap='ENTREGUE') THEN 'ENTREGUE'
 WHEN count(DISTINCT coalesce(fase_status_sap,'NAO_VERIFICADO'))=1 THEN min(fase_status_sap) ELSE 'STATUS_POR_ITEM' END AS status
 FROM public.pedido_itens WHERE pedido_id=ANY(pedidos_alterados) GROUP BY pedido_id)x
 WHERE p.id=x.pedido_id AND p.status_cabecalho IS DISTINCT FROM x.status;
 RETURN jsonb_build_object('entregues',n,'pedidos',cardinality(ARRAY(SELECT DISTINCT unnest(pedidos_alterados))));
END $fn$;
REVOKE ALL ON FUNCTION public.axe_rumo_aplicar_entregas(bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.axe_rumo_aplicar_entregas(bigint,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.axe_rumo_sincronizar_cadastro(p_coleta bigint, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE c public.axe_rumo_coletas%rowtype; r record; old public.pedido_itens%rowtype;
 v_cliente bigint; v_pedido bigint; v_item bigint; v_fase text; v_status text; v_codigo text;
 v_saldo numeric; v_before jsonb; v_after jsonb; v_created boolean;
 n_new int:=0; n_update int:=0; n_skip int:=0; v_count int;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.axe_rumo_revisores WHERE usuario_id=p_usuario AND ativo) THEN RAISE EXCEPTION 'Revisor não autorizado';END IF;
 SELECT * INTO c FROM public.axe_rumo_coletas WHERE id=p_coleta;
 IF NOT FOUND OR c.estado<>'COLETADO' OR c.versao_rastreio<>'rastreio_v1' OR c.metadados->>'usuario_id' IS DISTINCT FROM p_usuario::text
  OR c.metadados->'escopo'->>'empresa' IS DISTINCT FROM 'AXE' OR c.metadados->'escopo'->>'portal' IS DISTINCT FROM 'RUMO' THEN
  RETURN jsonb_build_object('cadastros',0,'atualizacoes',0,'motivo','COLETA_NAO_ELEGIVEL');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('axe_rumo_cadastro_oficial',0));
 IF EXISTS(SELECT 1 FROM public.axe_rumo_coletas WHERE escopo_chave=c.escopo_chave AND estado='COLETADO' AND (finalizada_em,id)>(c.finalizada_em,c.id)) THEN
  RETURN jsonb_build_object('cadastros',0,'atualizacoes',0,'motivo','COLETA_SUPERADA');END IF;
 FOR r IN SELECT o.*,s.payload_original,pi.codigo_material,pi.descricao_detalhada,pi.quantidade_total,
   pi.unidade,pi.data_remessa,pi.dados_extraidos AS dados_item_pdf,e.dados_faturamento,e.dados_entrega,
   e.estado AS pdf_estado,e.sem_itens_confirmado
  FROM public.axe_rumo_itens_observados o
  LEFT JOIN public.axe_rumo_status_fiori_snapshots s ON s.id=o.snapshot_status_id AND s.coleta_id=o.coleta_id
  LEFT JOIN public.axe_rumo_pdf_extracoes e ON e.id=o.extracao_pdf_id
  LEFT JOIN public.axe_rumo_pdf_itens pi ON pi.extracao_id=e.id AND pi.numero_item=o.numero_item
  WHERE o.coleta_id=p_coleta ORDER BY o.numero_pedido,o.numero_item
 LOOP
  v_cliente:=public.axe_cliente_faturamento(r.dados_faturamento->>'cnpj',r.dados_faturamento->>'nome');
  IF v_cliente IS NULL THEN
   SELECT min(p.cliente_id),count(*) INTO v_cliente,v_count FROM public.pedidos p JOIN public.clientes c2 ON c2.id=p.cliente_id
   WHERE p.numero_pedido=r.numero_pedido AND c2.grupo_comercial='RUMO' AND NOT c2.legado_grupo;
   IF v_count<>1 THEN n_skip:=n_skip+1;CONTINUE;END IF;
  END IF;
  SELECT id INTO v_pedido FROM public.pedidos WHERE cliente_id=v_cliente AND numero_pedido=r.numero_pedido;
  SELECT * INTO old FROM public.pedido_itens WHERE pedido_id=v_pedido AND public.axe_rumo_item_canonico(numero_item)=r.numero_item FOR UPDATE;
  v_created:=old.id IS NULL;v_fase:=CASE WHEN r.presente_ultimo_status THEN public.axe_rumo_fase_sap(r.status_texto) END;
  IF v_created THEN
   IF NOT r.presente_ultimo_status OR v_fase NOT IN ('AGUARDANDO_ACEITE','ACEITO','CORRECAO_SOLICITADA','ENTREGUE')
    OR r.situacao_pdf<>'ITEM_PRESENTE_NO_PDF' OR r.pdf_estado IS DISTINCT FROM 'VALIDADA'
    OR r.sem_itens_confirmado OR r.quantidade_total IS NULL OR r.quantidade_total<=0
    OR nullif(trim(r.descricao_detalhada),'') IS NULL OR nullif(trim(r.unidade),'') IS NULL
    OR coalesce(r.dados_faturamento->>'cnpj','') !~ '^[0-9]{14}$'
    OR r.quantidade_pendente IS NULL OR r.quantidade_pendente<0 OR r.quantidade_pendente>r.quantidade_total
    OR trim(coalesce(r.payload_original->>'cod_fornecedor',''))<>'553530'
    OR EXISTS(SELECT 1 FROM public.pedidos WHERE numero_pedido=r.numero_pedido AND cliente_id<>v_cliente)
   THEN n_skip:=n_skip+1;CONTINUE;END IF;
   IF v_pedido IS NULL THEN
    INSERT INTO public.pedidos(cliente_id,numero_pedido,codigo_fornecedor,status_cabecalho,dados_sap,ultima_captura_em)
    VALUES(v_cliente,r.numero_pedido,trim(r.payload_original->>'cod_fornecedor'),r.status_texto,
     jsonb_build_object('origem','CADASTRO_AUTOMATICO_PDF_HISTORICO','coleta_id',p_coleta,'faturamento_pdf',r.dados_faturamento,'entrega_pdf',r.dados_entrega),r.observado_em)
    ON CONFLICT(cliente_id,numero_pedido) DO NOTHING;
    SELECT id INTO v_pedido FROM public.pedidos WHERE cliente_id=v_cliente AND numero_pedido=r.numero_pedido;
   END IF;
   INSERT INTO public.pedido_itens(pedido_id,numero_item,codigo_material,descricao_material,quantidade_pendente,quantidade_original,data_remessa,
    status_codigo,status_texto,fase_status_sap,situacao_entrega_sap,status_sap_observado_em,dados_sap,ultima_captura_em)
   VALUES(v_pedido,r.numero_item,r.codigo_material,coalesce(nullif(trim(r.payload_original->>'texto_material'),''),r.descricao_detalhada),r.quantidade_pendente,r.quantidade_total,r.data_remessa,
    r.status_codigo,r.status_texto,v_fase,r.situacao_entrega,r.observado_em,
    r.payload_original||jsonb_build_object('_cadastro_pdf',jsonb_build_object('coleta_id',p_coleta,'extracao_id',r.extracao_pdf_id,'descricao_detalhada',r.descricao_detalhada,'unidade',r.unidade,'dados',r.dados_item_pdf)),r.observado_em)
   ON CONFLICT(pedido_id,numero_item) DO NOTHING RETURNING id INTO v_item;
   IF v_item IS NULL THEN CONTINUE;END IF;
   v_before:='{}';n_new:=n_new+1;
  ELSE
   IF coalesce(old.status_sap_observado_em,old.ultima_captura_em,'-infinity'::timestamptz)>=r.observado_em THEN CONTINUE;END IF;
   v_item:=old.id;v_before:=jsonb_build_object('status_texto',old.status_texto,'status_codigo',old.status_codigo,'fase_status_sap',old.fase_status_sap,'situacao_entrega_sap',old.situacao_entrega_sap,'quantidade_pendente',old.quantidade_pendente);
   v_status:=old.status_texto;v_codigo:=old.status_codigo;
   IF r.presente_ultimo_status AND v_fase<>'STATUS_NAO_MAPEADO' THEN v_status:=r.status_texto;v_codigo:=r.status_codigo;
   ELSE v_fase:=old.fase_status_sap;END IF;
   IF r.situacao_pdf IN ('ITEM_AUSENTE_NO_PDF','PEDIDO_SEM_PRODUTOS') THEN v_fase:='CANCELADO';END IF;
   v_saldo:=old.quantidade_pendente;
   IF r.presente_ultimo_status AND r.situacao_pdf='ITEM_PRESENTE_NO_PDF' AND r.pdf_estado='VALIDADA'
    AND r.quantidade_pendente>=0 AND r.quantidade_pendente<=r.quantidade_total THEN v_saldo:=r.quantidade_pendente;END IF;
   UPDATE public.pedido_itens SET status_texto=v_status,status_codigo=v_codigo,fase_status_sap=v_fase,
    situacao_entrega_sap=r.situacao_entrega,quantidade_pendente=v_saldo,status_sap_observado_em=r.observado_em,
    ultima_captura_em=r.observado_em,atualizado_em=now() WHERE id=v_item;
  END IF;
  SELECT jsonb_build_object('status_texto',status_texto,'status_codigo',status_codigo,'fase_status_sap',fase_status_sap,'situacao_entrega_sap',situacao_entrega_sap,'quantidade_pendente',quantidade_pendente)
   INTO v_after FROM public.pedido_itens WHERE id=v_item;
  IF v_before IS DISTINCT FROM v_after THEN
   INSERT INTO public.axe_rumo_cadastros_auditoria(coleta_id,item_id,operacao,anterior,atual,usuario_id)
   VALUES(p_coleta,v_item,CASE WHEN v_created THEN 'CADASTRO' ELSE 'ATUALIZACAO_OPERACIONAL' END,v_before,v_after,p_usuario) ON CONFLICT DO NOTHING;
   IF NOT v_created THEN n_update:=n_update+1;END IF;
  END IF;
 END LOOP;
 UPDATE public.pedidos p SET status_cabecalho=x.status,atualizado_em=now()
 FROM (SELECT i.pedido_id,CASE WHEN count(DISTINCT coalesce(i.fase_status_sap,'NAO_VERIFICADO'))=1
   THEN min(i.fase_status_sap) ELSE 'STATUS_POR_ITEM' END AS status
  FROM public.pedido_itens i WHERE i.pedido_id IN
   (SELECT ii.pedido_id FROM public.axe_rumo_cadastros_auditoria a JOIN public.pedido_itens ii ON ii.id=a.item_id WHERE a.coleta_id=p_coleta)
  GROUP BY i.pedido_id) x WHERE p.id=x.pedido_id AND p.status_cabecalho IS DISTINCT FROM x.status;
 PERFORM public.axe_rumo_aplicar_entregas(p_coleta,p_usuario);
 RETURN jsonb_build_object('cadastros',n_new,'atualizacoes',n_update,'pendentes_validacao',n_skip);
END $function$
