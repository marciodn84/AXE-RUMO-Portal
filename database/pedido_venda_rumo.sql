-- Pedido de venda AXE originado no SAP RUMO; sem emissão fiscal ou baixa automática de estoque.
ALTER TABLE public.produtos_clientes_referencias
 ADD COLUMN descricao_detalhada text,
 ADD COLUMN produto_axe_id bigint REFERENCES public.produtos_conciliacao(id),
 ADD COLUMN fator_conversao_axe numeric CHECK(fator_conversao_axe>0),
 ADD COLUMN vinculado_em timestamptz, ADD COLUMN vinculado_por uuid REFERENCES auth.users(id);
CREATE INDEX referencias_produto_axe_idx ON public.produtos_clientes_referencias(produto_axe_id);
ALTER TABLE public.comercial_pedidos ALTER COLUMN proposta_id DROP NOT NULL,ALTER COLUMN numero_proposta DROP NOT NULL;
ALTER TABLE public.comercial_pedidos
 ADD COLUMN origem text NOT NULL DEFAULT 'PROPOSTA' CHECK(origem IN ('PROPOSTA','RUMO')),
 ADD COLUMN pedido_rumo_id bigint UNIQUE REFERENCES public.pedidos(id),
 ADD COLUMN cliente_id bigint REFERENCES public.clientes(id),
 ADD COLUMN estado text NOT NULL DEFAULT 'APROVADO' CHECK(estado IN ('RASCUNHO','APROVADO','CANCELADO')),
 ADD COLUMN versao integer NOT NULL DEFAULT 1,
 ADD COLUMN fonte_hash text, ADD COLUMN aprovado_em timestamptz, ADD COLUMN aprovado_por uuid REFERENCES auth.users(id);
ALTER TABLE public.comercial_pedidos ADD CONSTRAINT comercial_origem_check CHECK(
 (origem='PROPOSTA' AND proposta_id IS NOT NULL AND numero_proposta IS NOT NULL AND pedido_rumo_id IS NULL)
 OR (origem='RUMO' AND pedido_rumo_id IS NOT NULL AND cliente_id IS NOT NULL AND proposta_id IS NULL AND numero_proposta IS NULL));
CREATE INDEX comercial_pedidos_cliente_rumo_idx ON public.comercial_pedidos(cliente_id);
CREATE TABLE public.comercial_pedido_itens(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 pedido_id bigint NOT NULL REFERENCES public.comercial_pedidos(id),
 item_rumo_id bigint NOT NULL UNIQUE REFERENCES public.pedido_itens(id),
 referencia_cliente_id bigint REFERENCES public.produtos_clientes_referencias(id),
 produto_id bigint REFERENCES public.produtos_conciliacao(id),
 fator_conversao numeric CHECK(fator_conversao>0),
 numero_item text NOT NULL,codigo_cliente text,nome_cliente text NOT NULL,descricao_detalhada text,unidade_cliente text,
 quantidade numeric CHECK(quantidade>0),preco_unitario numeric CHECK(preco_unitario>=0),moeda text,data_remessa date,
 dados_fonte jsonb NOT NULL,UNIQUE(pedido_id,numero_item));
CREATE INDEX comercial_pedido_itens_pedido_idx ON public.comercial_pedido_itens(pedido_id);
CREATE INDEX comercial_pedido_itens_produto_idx ON public.comercial_pedido_itens(produto_id);
CREATE INDEX comercial_pedido_itens_referencia_idx ON public.comercial_pedido_itens(referencia_cliente_id);
CREATE TABLE public.comercial_pedido_execucao(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 pedido_item_id bigint NOT NULL UNIQUE REFERENCES public.comercial_pedido_itens(id),
 produto_id bigint NOT NULL REFERENCES public.produtos_conciliacao(id),
 quantidade numeric NOT NULL CHECK(quantidade>0),
 etapa text NOT NULL DEFAULT 'PLANEJAMENTO' CHECK(etapa IN ('PLANEJAMENTO','ESTOQUE','COMPRAS','PRODUCAO','IMPORTACAO','CONCLUIDO')),
 criado_em timestamptz NOT NULL DEFAULT now());
CREATE INDEX comercial_execucao_produto_idx ON public.comercial_pedido_execucao(produto_id);
ALTER TABLE public.comercial_pedido_itens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comercial_pedido_execucao ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.comercial_pedido_itens,public.comercial_pedido_execucao FROM anon,authenticated;
GRANT ALL ON public.comercial_pedido_itens,public.comercial_pedido_execucao TO service_role;
GRANT USAGE,SELECT ON SEQUENCE public.comercial_pedido_itens_id_seq,public.comercial_pedido_execucao_id_seq TO service_role;

ALTER TABLE public.produtos_observacoes ALTER COLUMN produto_id DROP NOT NULL,ADD COLUMN referencia_cliente_id bigint REFERENCES public.produtos_clientes_referencias(id);
ALTER TABLE public.pedido_itens_condicoes ALTER COLUMN produto_id DROP NOT NULL,ADD COLUMN referencia_cliente_id bigint REFERENCES public.produtos_clientes_referencias(id);
CREATE INDEX produtos_observacoes_referencia_idx ON public.produtos_observacoes(referencia_cliente_id);
CREATE INDEX pedido_condicoes_referencia_idx ON public.pedido_itens_condicoes(referencia_cliente_id);
CREATE OR REPLACE FUNCTION public.axe_rumo_nome_produto(p_texto text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO '' AS $f$
 SELECT btrim(split_part(replace(coalesce(p_texto,''),chr(92)||'n',chr(10)),chr(10),1))
$f$;
CREATE OR REPLACE FUNCTION public.axe_rumo_descricao_produto(p_texto text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO '' AS $f$
 SELECT coalesce(string_agg(linha,chr(10) ORDER BY n),'') FROM
 unnest(string_to_array(replace(coalesce(p_texto,''),chr(92)||'n',chr(10)),chr(10))) WITH ORDINALITY t(linha,n)
 WHERE n>1 AND linha !~* '^\s*(Dt[.]?\s*Entrega|Data\s*(de\s*)?(remessa|entrega)|==>)'
$f$;
CREATE OR REPLACE FUNCTION public.axe_venda_rumo_fonte(p_pedido bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO '' AS $f$
 SELECT jsonb_build_object('pedido',p.numero_pedido,'pedido_id',p.id,'cliente_id',p.cliente_id,
 'cliente',jsonb_build_object('id',c.id,'nome',c.nome,'cnpj',c.cnpj),'data_pedido',p.data_pedido,'condicao_pagamento',p.condicao_pagamento,
 'itens',(SELECT coalesce(jsonb_agg(jsonb_build_object('item_rumo_id',i.id,'numero_item',i.numero_item,'codigo_cliente',i.codigo_material,
 'nome_cliente',public.axe_rumo_nome_produto(coalesce(k.descricao,i.descricao_material)),
 'descricao_detalhada',public.axe_rumo_descricao_produto(k.descricao),
 'quantidade',coalesce(k.quantidade,i.quantidade_original),'preco_unitario',k.valor_unitario,'unidade_cliente',k.unidade,'moeda',k.moeda,
 'data_remessa',i.data_remessa,'icms_aliquota',k.icms_aliquota,'ipi_aliquota',k.ipi_aliquota,'ncm',k.ncm) ORDER BY i.numero_item),'[]')
 FROM public.pedido_itens i LEFT JOIN LATERAL(SELECT * FROM public.pedido_itens_condicoes k WHERE k.item_id=i.id AND k.origem='PEDIDO_PDF' ORDER BY k.observado_em DESC,k.id DESC LIMIT 1)k ON true
 WHERE i.pedido_id=p.id))
 FROM public.pedidos p JOIN public.clientes c ON c.id=p.cliente_id WHERE p.id=p_pedido
$f$;

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
   UPDATE public.produtos_clientes_referencias SET descricao_cliente=it.nome_cliente,descricao_detalhada=it.descricao_detalhada,unidade_cliente=it.unidade_cliente,
    produto_axe_id=prod.id,fator_conversao_axe=it.fator_conversao,vinculado_em=now(),vinculado_por=p_usuario,atualizado_em=now() WHERE id=refid;
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
END $function$


GRANT UPDATE(documento,fonte_hash,versao,estado,aprovado_em,aprovado_por) ON public.comercial_pedidos TO service_role;



CREATE OR REPLACE VIEW public.portal_pedidos AS  SELECT i.id,
    p.numero_pedido,
    i.numero_item,
    p.cliente_id,
    c.nome AS cliente,
    i.codigo_material,
    i.descricao_material,
    i.fase_status_sap,
    i.status_texto,
    i.quantidade_original,
    i.quantidade_pendente,
    i.numero_nf,
    i.data_remessa,
    k.valor_unitario,
    k.moeda,
    k.icms_aliquota,
    k.ipi_aliquota,
    k.ncm,
    k.unidade,
    k.data_negocio,
    concat_ws(' '::text, p.numero_pedido, i.numero_item, c.nome, i.codigo_material, i.descricao_material, i.status_texto, i.fase_status_sap, i.numero_nf, c.cnpj) AS termos_busca,
    c.cnpj AS cnpj_faturamento,
    p.data_pedido,
    p.id AS pedido_rumo_id
   FROM pedido_itens i
     JOIN pedidos p ON p.id = i.pedido_id
     JOIN clientes c ON c.id = p.cliente_id
     LEFT JOIN LATERAL ( SELECT x.id,
            x.cliente_id,
            x.produto_id,
            x.item_id,
            x.numero_pedido,
            x.numero_item,
            x.origem,
            x.fonte_chave,
            x.extracao_pdf_id,
            x.documento_id,
            x.data_negocio,
            x.observado_em,
            x.cnpj_faturamento,
            x.codigo_produto,
            x.descricao,
            x.unidade,
            x.moeda,
            x.quantidade,
            x.valor_unitario,
            x.valor_total,
            x.icms_aliquota,
            x.icms_valor,
            x.ipi_aliquota,
            x.ipi_valor,
            x.ncm,
            x.cfop,
            x.contexto_fiscal,
            x.situacao_vinculo
           FROM pedido_itens_condicoes x
          WHERE x.item_id = i.id AND x.origem = 'PEDIDO_PDF'::text
          ORDER BY x.observado_em DESC, x.id DESC
         LIMIT 1) k ON true;
NOTIFY pgrst,'reload schema';
