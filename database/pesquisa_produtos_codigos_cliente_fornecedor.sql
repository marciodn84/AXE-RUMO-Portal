CREATE OR REPLACE VIEW public.cadastro_produtos_busca AS
SELECT p.id,p.descricao_referencia,p.unidade_referencia,p.ncm_referencia,p.status_validacao,
(SELECT coalesce(jsonb_agg(jsonb_build_object('contexto',z.contexto,'entidade',z.entidade,'empresa',z.empresa,'codigo',z.codigo,'descricao',z.descricao,'validacao',z.validacao) ORDER BY z.contexto,z.entidade,z.codigo),'[]'::jsonb)
 FROM (SELECT DISTINCT ON(contexto,entidade,codigo) * FROM(
 SELECT 'CLIENTE'::text contexto,c.cnpj entidade,c.nome empresa,r.codigo_cliente codigo,r.descricao_cliente descricao,
 CASE WHEN o.situacao='APROVADO' THEN 'VALIDADO' WHEN o.situacao='BLOQUEADO' THEN 'DIVERGENTE' ELSE 'PENDENTE' END validacao,0 prioridade
 FROM public.produtos_clientes_referencias r JOIN public.clientes c ON c.id=r.cliente_id
 LEFT JOIN public.produtos_clientes_opcoes o ON o.referencia_cliente_id=r.id AND o.produto_id=p.id
 WHERE r.ativo AND(r.produto_axe_id=p.id OR(o.produto_id=p.id AND o.situacao<>'INATIVO'))
 UNION ALL
 SELECT 'FORNECEDOR',coalesce(nullif(f.cnpj,''),nullif(f.documento_fiscal,''),f.id::text),f.razao_social,r.codigo_fornecedor,r.descricao_fornecedor,
 CASE WHEN r.situacao='APROVADO' THEN 'VALIDADO' WHEN r.situacao='BLOQUEADO' THEN 'DIVERGENTE' ELSE 'PENDENTE' END,0
 FROM public.produtos_fornecedores r JOIN public.fornecedores f ON f.id=r.fornecedor_id WHERE r.produto_id=p.id AND r.situacao<>'INATIVO'
 UNION ALL
 SELECT i.contexto,i.entidade,NULL::text,i.codigo_produto,i.descricao_produto,i.status_validacao,1
 FROM public.produtos_identificadores i WHERE i.produto_id=p.id
 )u ORDER BY contexto,entidade,codigo,prioridade)z) AS identificadores,
(SELECT string_agg(DISTINCT concat_ws(' ',o.codigo,o.descricao,o.unidade,o.ncm),' ') FROM public.produtos_observacoes o WHERE o.produto_id=p.id) AS termos_documentais
FROM public.produtos_conciliacao p;