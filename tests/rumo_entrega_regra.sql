-- Executar em transação; nunca confirmar dados de teste.
BEGIN;
DO $test$
DECLARE c bigint; u uuid; r jsonb; original text;
BEGIN
SELECT id,(metadados->>'usuario_id')::uuid INTO c,u FROM public.axe_rumo_coletas WHERE estado='COLETADO' ORDER BY finalizada_em DESC,id DESC LIMIT 1;
IF c IS NULL THEN RAISE EXCEPTION 'Sem coleta para testar';END IF;
SELECT md5(string_agg(concat_ws('|',id,status_texto,status_codigo),',' ORDER BY id)) INTO original FROM public.pedido_itens;
UPDATE public.axe_rumo_consultas_rastreio SET completa=false WHERE coleta_id=c AND fonte='ULTIMO_STATUS';
r:=public.axe_rumo_aplicar_entregas(c,u);
IF r->>'motivo'<>'RELATORIO_INCOMPLETO' OR (r->>'entregues')::int<>0 THEN RAISE EXCEPTION 'Coleta incompleta alterou entrega';END IF;
UPDATE public.axe_rumo_consultas_rastreio SET completa=true WHERE coleta_id=c AND fonte='ULTIMO_STATUS';
PERFORM public.axe_rumo_aplicar_entregas(c,u);
r:=public.axe_rumo_aplicar_entregas(c,u);
IF (r->>'entregues')::int<>0 THEN RAISE EXCEPTION 'Regra não idempotente';END IF;
IF original IS DISTINCT FROM (SELECT md5(string_agg(concat_ws('|',id,status_texto,status_codigo),',' ORDER BY id)) FROM public.pedido_itens) THEN RAISE EXCEPTION 'Status original SAP alterado';END IF;
END $test$;
ROLLBACK;
