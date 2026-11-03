CREATE OR REPLACE FUNCTION public.axe_produto_ficha(p_id bigint,p_aba text,p_pagina integer,p_usuario uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path='' AS $fn$
DECLARE pid bigint;linhas jsonb;total bigint;extra jsonb:='{}';offn int;
BEGIN
IF NOT EXISTS(SELECT 1 FROM public.axe_rumo_revisores WHERE usuario_id=p_usuario AND ativo) THEN RAISE EXCEPTION 'Sem permissão';END IF;
IF p_pagina IS NULL OR p_pagina<0 OR p_pagina>10000 THEN RAISE EXCEPTION 'Página inválida';END IF;offn:=p_pagina*50;
pid:=public.axe_cadastro_canonico('produto',p_id);
IF NOT EXISTS(SELECT 1 FROM public.produtos_conciliacao WHERE id=pid) THEN RAISE EXCEPTION 'Produto não encontrado';END IF;
IF p_aba='clientes' THEN
 SELECT count(*) INTO total FROM public.produtos_clientes_referencias r WHERE r.produto_axe_id=pid OR EXISTS(SELECT 1 FROM public.produtos_clientes_opcoes o WHERE o.referencia_cliente_id=r.id AND o.produto_id=pid);
 SELECT coalesce(jsonb_agg(t.doc ORDER BY t.id),'[]') INTO linhas FROM(
 SELECT r.id,to_jsonb(r)||jsonb_build_object('cliente_nome',c.nome,'cnpj',c.cnpj,'opcao',(SELECT to_jsonb(o) FROM public.produtos_clientes_opcoes o WHERE o.referencia_cliente_id=r.id AND o.produto_id=pid)) AS doc
 FROM public.produtos_clientes_referencias r JOIN public.clientes c ON c.id=r.cliente_id WHERE r.produto_axe_id=pid OR EXISTS(SELECT 1 FROM public.produtos_clientes_opcoes o WHERE o.referencia_cliente_id=r.id AND o.produto_id=pid)
 ORDER BY r.id LIMIT 50 OFFSET offn)t;
ELSIF p_aba='fornecedores' THEN
 SELECT count(*) INTO total FROM public.produtos_fornecedores WHERE produto_id=pid;
 SELECT coalesce(jsonb_agg(t.doc ORDER BY t.id),'[]') INTO linhas FROM(
 SELECT r.id,to_jsonb(r)||jsonb_build_object('fornecedor_nome',f.razao_social,'documento',coalesce(f.cnpj,f.documento_fiscal)) AS doc
 FROM public.produtos_fornecedores r JOIN public.fornecedores f ON f.id=r.fornecedor_id WHERE r.produto_id=pid ORDER BY r.id LIMIT 50 OFFSET offn)t;
ELSIF p_aba='codigos' THEN
 SELECT count(*) INTO total FROM public.produtos_identificadores WHERE produto_id=pid AND status_validacao<>'INATIVO';
 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]') INTO linhas FROM(SELECT * FROM public.produtos_identificadores WHERE produto_id=pid AND status_validacao<>'INATIVO' ORDER BY id LIMIT 50 OFFSET offn)t;
ELSIF p_aba='estoque' THEN
 extra:=jsonb_build_object('saldo',(SELECT to_jsonb(s) FROM public.estoque_saldos s WHERE produto_id=pid));
 SELECT count(*) INTO total FROM public.estoque_movimentos WHERE produto_id=pid;
 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.ordem DESC),'[]') INTO linhas FROM(SELECT m.*,EXISTS(SELECT 1 FROM public.estoque_movimentos e WHERE e.estorno_de=m.id) AS estornado FROM public.estoque_movimentos m WHERE produto_id=pid ORDER BY ordem DESC LIMIT 50 OFFSET offn)t;
ELSIF p_aba='historico' THEN
 WITH eventos AS(
 SELECT a.criado_em,'Cadastro' AS origem,a.operacao AS acao,a.anterior,a.atual,coalesce(a.usuario_id,(SELECT l.usuario_id FROM public.catalogo_alteracoes l WHERE l.atual=a.atual AND l.registro_id::text=a.registro_id ORDER BY l.id DESC LIMIT 1))::text AS responsavel,a.id::text AS chave
 FROM public.produtos_catalogo_auditoria a WHERE
 (a.tabela='produtos_conciliacao' AND a.registro_id IN(SELECT id::text FROM public.produtos_conciliacao WHERE id=pid OR mesclado_em_id=pid))
 OR (a.anterior->>'produto_id'=pid::text OR a.atual->>'produto_id'=pid::text)
 OR (a.tabela='produtos_clientes_referencias' AND a.registro_id IN(SELECT id::text FROM public.produtos_clientes_referencias r WHERE produto_axe_id=pid OR EXISTS(SELECT 1 FROM public.produtos_clientes_opcoes o WHERE o.referencia_cliente_id=r.id AND produto_id=pid)))
 UNION ALL SELECT m.criado_em,'Mesclagem','CADASTROS_REUNIDOS',m.origem_anterior,m.destino_atual,m.usuario_id::text,m.id::text FROM public.cadastros_mesclagens m WHERE m.tipo='produto' AND m.estado='CONCLUIDA' AND(m.destino_id=pid OR m.origem_id=pid)
 UNION ALL SELECT e.criado_em,'Descrição do cliente',e.acao,e.anterior,e.atual,e.usuario_id::text,e.id::text FROM public.comercial_eventos e WHERE e.tipo='referencia_cliente' AND e.registro_id IN(SELECT id FROM public.produtos_clientes_referencias WHERE produto_axe_id=pid)
 UNION ALL SELECT d.criado_em,'Bloqueio comercial',d.acao,d.anterior,d.atual,d.usuario_id::text,d.id::text FROM public.cadastros_decisoes d WHERE d.entidade='PRODUTO_COMERCIAL' AND d.referencia=pid::text
 ) SELECT (SELECT count(*) FROM eventos),coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY criado_em DESC,chave DESC) FROM(SELECT * FROM eventos ORDER BY criado_em DESC,chave DESC LIMIT 50 OFFSET offn)t),'[]') INTO total,linhas;
ELSE RAISE EXCEPTION 'Aba inválida';END IF;
RETURN extra||jsonb_build_object('produto_id',pid,'linhas',linhas,'total',total);
END $fn$;
REVOKE ALL ON FUNCTION public.axe_produto_ficha(bigint,text,integer,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.axe_produto_ficha(bigint,text,integer,uuid) TO service_role;
CREATE OR REPLACE FUNCTION public.axe_catalogo_salvar(p_tipo text, p_dados jsonb, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
 t text; allowed text[]; d jsonb; before_row jsonb; after_row jsonb; k text;
 cols text; vals text; sets text; i bigint; req uuid; h text; prev record;
 spec jsonb := '{
 "produto":{"t":"produtos_conciliacao","f":"descricao_referencia,unidade_referencia,ncm_referencia,codigo_anterior,forma_obtencao,tipo_item,descricao_tecnica,marca,fabricante,part_number,modelo,composicao,aplicacao,origem_fiscal_padrao,pais_origem,controla_estoque,estoque_minimo,controle_lote,controle_serie,peso_liquido_kg,peso_bruto_kg,comprimento_mm,largura_mm,altura_mm,ativo,observacoes,gtin,ex_tipi,cest"},
 "cliente":{"t":"clientes","f":"nome,codigo_externo,cnpj,nome_fantasia,inscricao_estadual,grupo_comercial,contato,email,telefone,observacoes,ativo"},
 "fornecedor":{"t":"fornecedores","f":"razao_social,nome_fantasia,pais,documento_fiscal,cnpj,ativo,observacoes,inscricao_estadual,contato,email,telefone,endereco"},
 "referencia_cliente":{"t":"produtos_clientes_referencias","f":"cliente_id,codigo_cliente,descricao_cliente,descricao_detalhada,unidade_cliente,referencia_tecnica,desenho,revisao,embalagem_exigida,identificacao_exigida,certificados_exigidos,observacoes,ativo"},
 "opcao_cliente":{"t":"produtos_clientes_opcoes","f":"referencia_cliente_id,produto_id,tipo_vinculo,situacao,fator_conversao,quantidade_minima,multiplo_venda,prazo_dias,aprovado_por,evidencia_aceite,restricoes,valido_desde,valido_ate"},
 "produto_fornecedor":{"t":"produtos_fornecedores","f":"produto_id,fornecedor_id,codigo_fornecedor,descricao_fornecedor,fabricante,part_number,unidade_compra,fator_conversao,quantidade_minima,multiplo_compra,prazo_dias,ncm_informado,origem_fiscal,pais_origem,moeda,preferencial,situacao,valido_desde,valido_ate,observacoes"},
 "similar":{"t":"produtos_similares","f":"produto_id,similar_id,justificativa"},
 "documento":{"t":"produtos_documentos","f":"produto_id,tipo,titulo,referencia_arquivo,revisao,valido_desde,valido_ate"}
 }'::jsonb;
begin
 if not exists(select 1 from public.axe_rumo_revisores where usuario_id=p_usuario and ativo) then raise exception 'Usuário não autorizado';end if;
 if p_tipo is null or not spec ? p_tipo then raise exception 'Cadastro não permitido';end if;
 if p_dados is null or jsonb_typeof(p_dados)<>'object' or octet_length(p_dados::text)>50000 then raise exception 'Dados inválidos';end if;
 req:=(p_dados->>'requisicao_id')::uuid;if req is null then raise exception 'Requisição obrigatória';end if;
 h:=public.axe_rumo_hash_json(jsonb_build_object('catalogo',p_tipo,'dados',p_dados));
 perform pg_advisory_xact_lock(hashtextextended('axe_catalogo_salvar',0));
 select * into prev from public.portal_cadastros_requisicoes where requisicao_id=req and usuario_id=p_usuario;
 if found then if prev.hash_dados<>h then raise exception 'Requisição já utilizada com outros dados';end if;return prev.resultado;end if;
 t:=spec->p_tipo->>'t';allowed:=string_to_array(spec->p_tipo->>'f',',');d:='{}';
 for k in select jsonb_object_keys(p_dados) loop
  if not k=any(allowed||array['id','atualizado_em','requisicao_id']) then raise exception 'Campo não permitido: %',k;end if;
  if k=any(allowed) then
   if jsonb_typeof(p_dados->k) not in ('string','number','boolean','null') then raise exception 'Valor inválido para %',k;end if;
   d:=d||jsonb_build_object(k,case when jsonb_typeof(p_dados->k)='string' then to_jsonb(nullif(btrim(p_dados->>k),'')) else p_dados->k end);
  end if;
 end loop;
 i:=(p_dados->>'id')::bigint;
 if i is not null then
  execute format('select to_jsonb(x) from public.%I x where id=$1 for update',t) into before_row using i;
  if before_row is null then raise exception 'Registro não encontrado';end if;
  if (before_row->>'atualizado_em')::timestamptz is distinct from (p_dados->>'atualizado_em')::timestamptz then raise exception 'Cadastro alterado por outra operação. Atualize a consulta';end if;
 end if;
 if p_tipo='produto' then
  if i is null then d:=jsonb_build_object('chave_cadastro','PORTAL_CATALOGO:'||req,'status_validacao','PENDENTE')||d;end if;
  if i is not null and before_row->>'codigo_axe' is not null and d ? 'forma_obtencao' and d->>'forma_obtencao' is distinct from before_row->>'forma_obtencao' then raise exception 'A forma de obtenção é permanente. Outra origem exige outro produto';end if;
  if coalesce(d,before_row)->>'descricao_referencia'='' then raise exception 'Informe a descrição';end if;
  if d->>'ncm_referencia' is not null and d->>'ncm_referencia' !~ '^[0-9]{8}$' then raise exception 'NCM deve ter 8 números';end if;
  if d->>'origem_fiscal_padrao' is not null and d->>'origem_fiscal_padrao' !~ '^[0-8]$' then raise exception 'Origem fiscal inválida';end if;
  if before_row is not null and exists(select 1 from jsonb_object_keys(d) key where key in ('descricao_referencia','unidade_referencia','ncm_referencia') and d->key is distinct from before_row->key) then d:=d||jsonb_build_object('status_validacao','PENDENTE');end if;
 end if;
 if p_tipo='cliente' then
  if i is not null and (before_row->>'legado_grupo')::boolean then raise exception 'Grupo legado não é um cliente de faturamento';end if;
  if i is not null and d ? 'cnpj' and d->>'cnpj' is distinct from before_row->>'cnpj' then raise exception 'Para outro CNPJ, cadastre outro cliente';end if;
  if i is null and nullif(d->>'codigo_externo','') is null then d:=d||jsonb_build_object('codigo_externo','CNPJ_'||(d->>'cnpj'));end if;
 end if;
 if p_tipo in ('cliente','fornecedor') then
  if d->>'cnpj' is not null then d:=d||jsonb_build_object('cnpj',regexp_replace(d->>'cnpj','[^0-9]','','g'));end if;
  if d->>'email' is not null and d->>'email' !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'E-mail inválido';end if;
 end if;
 if p_tipo='cliente' and coalesce(d->>'cnpj',before_row->>'cnpj','') !~ '^[0-9]{14}$' then raise exception 'Informe o CNPJ com 14 números';end if;
 if p_tipo='fornecedor' then
  d:=d||jsonb_build_object('pais',upper(coalesce(d->>'pais',before_row->>'pais','BR')));
  if d->>'pais' !~ '^[A-Z]{2}$' then raise exception 'País deve ter duas letras (BR, US, CN)';end if;
  if d->>'pais'='BR' and (coalesce(before_row,'{}')||d)->>'cnpj' is null then raise exception 'Informe o CNPJ do fornecedor nacional';end if;
  if d->>'pais'<>'BR' and (coalesce(before_row,'{}')||d)->>'documento_fiscal' is null then raise exception 'Informe a identificação fiscal do fornecedor estrangeiro';end if;
 end if;
 if p_tipo='referencia_cliente' and exists(select 1 from public.clientes where id=coalesce(d->>'cliente_id',before_row->>'cliente_id')::bigint and legado_grupo) then raise exception 'Selecione um cliente por CNPJ';end if;
 if p_tipo='opcao_cliente' then
  if coalesce(d->>'situacao',before_row->>'situacao')='APROVADO' then
   if nullif(coalesce(d->>'aprovado_por',before_row->>'aprovado_por'),'') is null or nullif(coalesce(d->>'evidencia_aceite',before_row->>'evidencia_aceite'),'') is null then raise exception 'Aprovação exige responsável e evidência de aceite do cliente';end if;
   d:=d||jsonb_build_object('aprovado_em',now());
  else d:=d||jsonb_build_object('aprovado_em',null);end if;
 end if;
 if p_tipo='similar' and (d->>'produto_id')::bigint>(d->>'similar_id')::bigint then d:=d||jsonb_build_object('produto_id',d->'similar_id','similar_id',d->'produto_id');end if;
 if i is not null then
  d:=d||jsonb_build_object('atualizado_em',clock_timestamp());
  select string_agg(format('%I=r.%I',key,key),',') into sets from jsonb_object_keys(d) key;
  execute format('update public.%I x set %s from jsonb_populate_record(null::public.%I,$1) r where x.id=$2 returning to_jsonb(x)',t,sets,t) into after_row using d,i;
 else
  select string_agg(format('%I',key),','),string_agg(format('r.%I',key),',') into cols,vals from jsonb_object_keys(d) key;
  execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I,$1) r returning to_jsonb(%I)',t,cols,vals,t,t) into after_row using d;
  i:=(after_row->>'id')::bigint;
 end if;
 if p_tipo='referencia_cliente' and before_row is not null and
  (before_row->>'codigo_cliente' is distinct from after_row->>'codigo_cliente' or before_row->>'descricao_cliente' is distinct from after_row->>'descricao_cliente' or before_row->>'cliente_id' is distinct from after_row->>'cliente_id') then
  update public.produtos_clientes_opcoes set situacao='EM_AVALIACAO',aprovado_em=null,atualizado_em=clock_timestamp() where referencia_cliente_id=i and situacao='APROVADO';
 end if;
 insert into public.catalogo_alteracoes(tipo,registro_id,usuario_id,anterior,atual) values(p_tipo,i,p_usuario,before_row,after_row);
 insert into public.portal_cadastros_requisicoes(requisicao_id,usuario_id,hash_dados,resultado) values(req,p_usuario,h,jsonb_build_object('id',i,'ok',true));
 return jsonb_build_object('id',i,'ok',true);
end $function$;
