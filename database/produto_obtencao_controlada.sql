begin;
create table public.produtos_obtencao_correcoes(id uuid primary key,produto_id bigint not null references public.produtos_conciliacao(id),usuario_id uuid not null references auth.users(id),anterior jsonb not null,atual jsonb,forma_nova text not null check(forma_nova in('IMP','TER','FAB')),justificativa text not null check(length(btrim(justificativa))between 10 and 2000),transacao bigint not null default txid_current(),estado text not null check(estado in('EXECUTANDO','CONCLUIDA')),criado_em timestamptz not null default clock_timestamp());
alter table public.produtos_obtencao_correcoes enable row level security;revoke all on public.produtos_obtencao_correcoes from public,anon,authenticated;grant select,insert,update on public.produtos_obtencao_correcoes to service_role;
CREATE OR REPLACE FUNCTION public.axe_produto_codigo_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare seq text;
begin
 if TG_OP='UPDATE' and exists(select 1 from public.produtos_obtencao_correcoes c where c.produto_id=OLD.id and c.transacao=txid_current() and c.estado='EXECUTANDO' and c.anterior->>'forma_obtencao' is not distinct from OLD.forma_obtencao and c.forma_nova=NEW.forma_obtencao) and NEW.codigo_axe is not distinct from OLD.codigo_axe and (to_jsonb(NEW)-array['forma_obtencao','atualizado_em','ncm_capitulo','ncm_posicao','ncm_subposicao'])=(to_jsonb(OLD)-array['forma_obtencao','atualizado_em','ncm_capitulo','ncm_posicao','ncm_subposicao']) then return NEW;end if;
 if current_user='service_role' and TG_OP='UPDATE' and exists(select 1 from public.cadastros_mesclagens m where m.tipo='produto' and m.transacao=txid_current() and m.estado='EXECUTANDO' and ((m.origem_id=OLD.id and NEW.codigo_axe is null and (to_jsonb(NEW)-array['codigo_axe','codigo_anterior','chave_cadastro','mesclado_em_id','ativo','atualizado_em','ncm_capitulo','ncm_posicao','ncm_subposicao'])=(to_jsonb(OLD)-array['codigo_axe','codigo_anterior','chave_cadastro','mesclado_em_id','ativo','atualizado_em','ncm_capitulo','ncm_posicao','ncm_subposicao']))or(m.destino_id=OLD.id and OLD.codigo_axe is null and NEW.codigo_axe=m.origem_anterior->>'codigo_axe' and NEW.forma_obtencao is not distinct from m.origem_anterior->>'forma_obtencao')))then return NEW;end if;

 if TG_OP='UPDATE' and OLD.codigo_axe is not null and
 (NEW.codigo_axe is distinct from OLD.codigo_axe or NEW.forma_obtencao is distinct from OLD.forma_obtencao) then
  raise exception 'Código e forma de obtenção são permanentes; cadastre outro produto para outra origem de fornecimento';
 end if;
 if NEW.codigo_axe is not null and (TG_OP='INSERT' or OLD.codigo_axe is null) then
  raise exception 'O código Axe deve ser gerado automaticamente';
 end if;
 if NEW.codigo_axe is null and NEW.forma_obtencao is not null then
  seq := nextval('public.axe_produto_codigo_seq')::text;
  NEW.codigo_axe := NEW.forma_obtencao || '-' || case when length(seq)<6 then lpad(seq,6,'0') else seq end;
 end if;
 return NEW;
end $function$;
create function public.axe_produto_obtencao_corrigir(p_dados jsonb,p_usuario uuid)returns jsonb language plpgsql set search_path=''as $$
declare pr public.produtos_conciliacao;old public.produtos_obtencao_correcoes;req uuid:=(p_dados->>'requisicao_id')::uuid;forma text:=p_dados->>'forma_obtencao';motivo text:=btrim(p_dados->>'justificativa');after_row jsonb;begin
 if not exists(select 1 from public.axe_rumo_revisores where usuario_id=p_usuario and ativo)or not exists(select 1 from public.gestao_membros where usuario_id=p_usuario and ativo and papel='ADMIN')then raise exception 'Somente administrador autorizado pode corrigir a forma de obtenção';end if;
 if req is null or forma is null or forma not in('IMP','TER','FAB')or length(coalesce(motivo,''))not between 10 and 2000 or p_dados->>'confirmado'is distinct from 'true'then raise exception 'Informe a classificação, justificativa e confirmação da correção';end if;
 perform set_config('lock_timeout','5s',true);perform pg_advisory_xact_lock(728102826);
 select * into old from public.produtos_obtencao_correcoes where id=req;
 if found then if old.usuario_id<>p_usuario or old.produto_id<>(p_dados->>'produto_id')::bigint or old.forma_nova<>forma or old.justificativa<>motivo then raise exception 'Identificador reutilizado com outros dados';end if;return jsonb_build_object('ok',true,'resultado',old.atual);end if;
 select * into pr from public.produtos_conciliacao where id=(p_dados->>'produto_id')::bigint for update;
 if pr.id is null or pr.mesclado_em_id is not null or pr.codigo_axe is null then raise exception 'Selecione um produto canônico com código AXE';end if;
 if pr.atualizado_em is distinct from (p_dados->>'atualizado_em')::timestamptz then raise exception 'Produto alterado. Reabra o cadastro e confira a correção';end if;
 if pr.forma_obtencao is not distinct from forma then raise exception 'O produto já possui esta forma de obtenção';end if;
 insert into public.produtos_obtencao_correcoes(id,produto_id,usuario_id,anterior,forma_nova,justificativa,estado)values(req,pr.id,p_usuario,to_jsonb(pr),forma,motivo,'EXECUTANDO');
 update public.produtos_conciliacao set forma_obtencao=forma,atualizado_em=clock_timestamp()where id=pr.id returning to_jsonb(produtos_conciliacao.*)into after_row;
 update public.produtos_obtencao_correcoes set atual=after_row,estado='CONCLUIDA'where id=req;
 insert into public.catalogo_alteracoes(tipo,registro_id,usuario_id,anterior,atual)values('produto',pr.id,p_usuario,to_jsonb(pr),after_row);
 return jsonb_build_object('ok',true,'resultado',after_row);
end $$;
revoke all on function public.axe_produto_obtencao_corrigir(jsonb,uuid)from public,anon,authenticated;grant execute on function public.axe_produto_obtencao_corrigir(jsonb,uuid)to service_role;
CREATE OR REPLACE FUNCTION public.axe_produto_ficha(p_id bigint, p_aba text, p_pagina integer, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
 UNION ALL SELECT c.criado_em,'Correção da forma de obtenção','CORRECAO_CLASSIFICACAO',c.anterior,c.atual||jsonb_build_object('justificativa',c.justificativa),c.usuario_id::text,c.id::text FROM public.produtos_obtencao_correcoes c WHERE c.produto_id=pid AND c.estado='CONCLUIDA'
 UNION ALL SELECT m.criado_em,'Mesclagem','CADASTROS_REUNIDOS',m.origem_anterior,m.destino_atual,m.usuario_id::text,m.id::text FROM public.cadastros_mesclagens m WHERE m.tipo='produto' AND m.estado='CONCLUIDA' AND(m.destino_id=pid OR m.origem_id=pid)
 UNION ALL SELECT e.criado_em,'Descrição do cliente',e.acao,e.anterior,e.atual,e.usuario_id::text,e.id::text FROM public.comercial_eventos e WHERE e.tipo='referencia_cliente' AND e.registro_id IN(SELECT id FROM public.produtos_clientes_referencias WHERE produto_axe_id=pid)
 UNION ALL SELECT d.criado_em,'Bloqueio comercial',d.acao,d.anterior,d.atual,d.usuario_id::text,d.id::text FROM public.cadastros_decisoes d WHERE d.entidade='PRODUTO_COMERCIAL' AND d.referencia=pid::text
 ) SELECT (SELECT count(*) FROM eventos),coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY criado_em DESC,chave DESC) FROM(SELECT * FROM eventos ORDER BY criado_em DESC,chave DESC LIMIT 50 OFFSET offn)t),'[]') INTO total,linhas;
ELSE RAISE EXCEPTION 'Aba inválida';END IF;
RETURN extra||jsonb_build_object('produto_id',pid,'linhas',linhas,'total',total);
END $function$;
commit;
