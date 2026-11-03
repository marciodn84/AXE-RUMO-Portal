-- Integração, sem persistir alterações de teste. Executar como administrador do banco.
BEGIN;
DO $test$
DECLARE a public.axe_email_arquivos; u uuid; r jsonb; n bigint; statuses jsonb;
BEGIN
SELECT af.* INTO a FROM public.axe_email_arquivos af JOIN public.axe_email_mensagens m ON m.id=af.mensagem_id WHERE lower(m.remetente)='erpindustrial@nomuserp.com.br' AND lower(af.nome) LIKE '%.xml' ORDER BY af.criado_em DESC LIMIT 1;
IF a.id IS NULL THEN RAISE EXCEPTION 'Teste requer um XML Nomus arquivado';END IF;
SELECT usuario_id INTO u FROM public.gestao_membros WHERE ativo AND papel='ADMIN' LIMIT 1;
SELECT jsonb_agg(jsonb_build_array(id,fase_status_sap,quantidade_pendente) ORDER BY id) INTO statuses FROM public.pedido_itens;
r:=public.axe_documentos_entrada(jsonb_build_object('acao','email_anexar','mensagem_id',a.mensagem_id,'anexo_id',a.anexo_id,'conteudo_base64',encode(a.conteudo,'base64')),u);
IF r->'processamento_fiscal'->>'estado'<>'PROCESSADO' THEN RAISE EXCEPTION 'XML não processado: %',r;END IF;
SELECT count(*) INTO n FROM public.axe_rumo_nf_itens_documentais;
PERFORM public.axe_email_processar_nfe(a.id,u);
IF (SELECT count(*) FROM public.axe_rumo_nf_itens_documentais)<>n THEN RAISE EXCEPTION 'Duplicação fiscal';END IF;
IF statuses IS DISTINCT FROM (SELECT jsonb_agg(jsonb_build_array(id,fase_status_sap,quantidade_pendente) ORDER BY id) FROM public.pedido_itens) THEN RAISE EXCEPTION 'Enriquecimento modificou a entrega';END IF;
END $test$;
ROLLBACK;
