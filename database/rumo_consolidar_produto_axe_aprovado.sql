CREATE OR REPLACE FUNCTION public.axe_cadastro_mesclar(p_dados jsonb, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare tipo text:=p_dados->>'tipo';acao text:=p_dados->>'acao';t text;origem bigint:=(p_dados->>'origem_id')::bigint;destino bigint:=(p_dados->>'destino_id')::bigint;
 a jsonb;b jsonb;merged jsonb;fields jsonb:='[]';links jsonb:='[]';linksall jsonb:='[]';blockers jsonb:='[]';choices jsonb:=coalesce(p_dados->'escolhas','{}');k text;v jsonb;av jsonb;bv jsonb;selected text;ignore text[];c record;dup record;ref record;dedupe jsonb:='[]';n bigint;rowsj jsonb;finger text;mid uuid;sets text:='';clearcols text:='';err text;result jsonb;aplicar boolean:=acao='cadastro_mesclar_salvar';
begin
 if not exists(select 1 from public.axe_rumo_revisores where usuario_id=p_usuario and ativo) or not exists(select 1 from public.gestao_membros where usuario_id=p_usuario and ativo and papel in('ADMIN','EDITOR'))then raise exception 'Sem permissão para combinar cadastros';end if;
 t:=case tipo when 'cliente' then 'clientes' when 'produto' then 'produtos_conciliacao' when 'fornecedor'then 'fornecedores'end;
 if acao='cadastro_mesclar_historico' and t is not null then return jsonb_build_object('linhas',(select coalesce(jsonb_agg(to_jsonb(x)order by x.criado_em desc),'[]')from(select id,tipo,origem_id,destino_id,usuario_id,criado_em,origem_anterior,destino_anterior,destino_atual,escolhas,vinculos from public.cadastros_mesclagens where cadastros_mesclagens.tipo=p_dados->>'tipo' and public.axe_cadastro_canonico(cadastros_mesclagens.tipo,origem_id)=public.axe_cadastro_canonico(cadastros_mesclagens.tipo,destino)and estado='CONCLUIDA' order by criado_em desc limit 50)x));end if;
 if t is null or origem is null or destino is null or origem=destino or origem<1 or destino<1 or acao not in('cadastro_mesclar_previa','cadastro_mesclar_salvar')then raise exception 'Selecione dois cadastros distintos do mesmo tipo';end if;
 perform set_config('lock_timeout','5s',true);
 perform pg_advisory_xact_lock(728102826);
 execute format('select to_jsonb(x) from public.%I x where id=$1 for update',t) into a using least(origem,destino);
 execute format('select to_jsonb(x) from public.%I x where id=$1 for update',t) into b using greatest(origem,destino);
 if a is null or b is null then raise exception 'Cadastro não encontrado';end if;
 if (a->>'id')::bigint<>origem then v:=a;a:=b;b:=v;end if;
 if a->>'mesclado_em_id' is not null or b->>'mesclado_em_id' is not null then raise exception 'Um cadastro já foi combinado. Utilize o ID mantido';end if;
 if tipo in('cliente','fornecedor') and nullif(a->>'cnpj','') is not null and nullif(b->>'cnpj','') is not null and regexp_replace(a->>'cnpj','[^0-9]','','g')<>regexp_replace(b->>'cnpj','[^0-9]','','g')then blockers:=blockers||jsonb_build_array('CNPJs diferentes identificam empresas de faturamento distintas. Corrija o cadastro antes de combinar.');end if;
 if tipo='fornecedor' and nullif(a->>'documento_fiscal','') is not null and nullif(b->>'documento_fiscal','')is not null and lower(btrim(a->>'documento_fiscal'))<>lower(btrim(b->>'documento_fiscal')) then blockers:=blockers||jsonb_build_array('Documentos fiscais de fornecedores diferentes. Corrija a identificação antes de combinar.');end if;
 if tipo='produto' and nullif(a->>'unidade_referencia','') is not null and nullif(b->>'unidade_referencia','') is not null and upper(btrim(a->>'unidade_referencia'))<>upper(btrim(b->>'unidade_referencia'))then blockers:=blockers||jsonb_build_array('Unidades diferentes. Corrija a unidade ou sua conversão antes de reunir produtos e quantidades.');end if;
 ignore:=array['id','criado_em','atualizado_em','mesclado_em_id','chave_cadastro','ncm_capitulo','ncm_posicao','ncm_subposicao','bloqueio_alterado_em','bloqueio_alterado_por','bloqueado_comercial','motivo_bloqueio','legado_grupo'];if tipo='produto' and nullif(b->>'codigo_axe','')is not null then ignore:=ignore||array['codigo_axe','forma_obtencao'];end if;merged:=b;
 for k,bv in select * from jsonb_each(b) where not(key=any(ignore)) order by key loop
 av:=a->k;v:=bv;
 if (bv='null'::jsonb or bv='""'::jsonb) and av is not null and av<>'null'::jsonb and av<>'""'::jsonb then v:=av;
 elsif av is not null and av<>'null'::jsonb and av<>'""'::jsonb and bv is distinct from av then
 selected:=choices->>k;
 fields:=fields||jsonb_build_array(jsonb_build_object('campo',k,'origem',av,'destino',bv,'conflito',true));
 if aplicar and selected not in('origem','destino')or aplicar and selected is null then raise exception 'Escolha o valor do campo % antes de combinar',k;end if;
 if selected='origem'then v:=av;end if;
 end if;
 if v is distinct from bv then fields:=fields||jsonb_build_array(jsonb_build_object('campo',k,'origem',av,'destino',bv,'valor',v,'conflito',false));end if;
 merged:=jsonb_set(merged,array[k],v);
 end loop;
 if tipo='cliente' and nullif(merged->>'cnpj','')is not null then merged:=merged||jsonb_build_object('legado_grupo',false);end if;
 -- Nenhuma mesclagem pode remover um bloqueio comercial.
 if coalesce((a->>'bloqueado_comercial')::boolean,false)or coalesce((b->>'bloqueado_comercial')::boolean,false)then merged:=merged||jsonb_build_object('bloqueado_comercial',true,'motivo_bloqueio',concat_ws(' | ',nullif(b->>'motivo_bloqueio',''),nullif(a->>'motivo_bloqueio','')),'bloqueio_alterado_em',clock_timestamp(),'bloqueio_alterado_por',p_usuario);end if;
 -- Bloqueia inserções concorrentes enquanto a prévia e a aplicação conferem os vínculos.
 for c in select distinct k.conrelid::regclass as rel from pg_constraint k where k.contype='f' and k.confrelid=to_regclass('public.'||t) and k.conrelid<>to_regclass('public.'||t) order by 1 loop execute format('lock table %s in share row exclusive mode',c.rel);end loop;
 for c in select k.conrelid::regclass as rel,at.attname col from pg_constraint k join pg_attribute at on at.attrelid=k.conrelid and at.attnum=any(k.conkey) where k.contype='f' and k.confrelid=to_regclass('public.'||t) and k.conrelid<>to_regclass('public.'||t) order by 1,2 loop
 execute format($q$select count(*),coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]') from %s x where %I=$1$q$,c.rel,c.col)into n,rowsj using origem;
 if n>0 then links:=links||jsonb_build_array(jsonb_build_object('tabela',c.rel::text,'campo',c.col,'quantidade',n,'hash',md5(rowsj::text)));linksall:=linksall||jsonb_build_array(jsonb_build_object('tabela',c.rel::text,'campo',c.col,'registros_anteriores',rowsj));end if;
 end loop;
 if tipo='produto'then
 lock table public.comercial_propostas in share row exclusive mode;
 select count(*),coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')into n,rowsj from public.comercial_propostas x where documento is distinct from public.axe_mesclagem_json(documento,origem,destino);
 if n>0 then links:=links||jsonb_build_array(jsonb_build_object('tabela','comercial_propostas','campo','documento','quantidade',n,'hash',md5(rowsj::text)));linksall:=linksall||jsonb_build_array(jsonb_build_object('tabela','comercial_propostas','campo','documento','registros_anteriores',rowsj));end if;end if;
 if tipo='produto' then
  -- A prévia inclui os identificadores de destino e todos os vínculos afetados.
  for dup in select s.id origem_alias,d.id destino_alias,to_jsonb(s) origem_anterior,to_jsonb(d) destino_anterior
   from public.produtos_identificadores s join public.produtos_identificadores d on d.produto_id=destino and d.contexto=s.contexto and d.entidade=s.entidade and d.codigo_produto=s.codigo_produto
   where s.produto_id=origem order by s.id
  loop
   dedupe:=dedupe||jsonb_build_array(jsonb_build_object('origem',dup.origem_anterior,'destino',dup.destino_anterior));
   for ref in select k.conrelid::regclass rel,at.attname col from pg_constraint k join pg_attribute at on at.attrelid=k.conrelid and at.attnum=any(k.conkey)
    where k.contype='f' and k.confrelid='public.produtos_identificadores'::regclass order by 1,2
   loop
    execute format('lock table %s in share row exclusive mode',ref.rel);
    execute format('select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),''[]''::jsonb) from %s x where %I=$1 or %I=$2',ref.rel,ref.col,ref.col) into rowsj using dup.origem_alias,dup.destino_alias;
    dedupe:=dedupe||jsonb_build_array(jsonb_build_object('tabela',ref.rel::text,'campo',ref.col,'registros_anteriores',rowsj));
   end loop;
  end loop;
 end if;
 finger:=md5(jsonb_build_array(a,b,links,dedupe,case when tipo='produto'then public.axe_estoque_mesclagem_previa(origem,destino)end)::text);
 if aplicar and p_dados->>'versao' is distinct from finger then raise exception 'Os cadastros ou vínculos mudaram. Gere uma nova prévia';end if;
 if jsonb_array_length(blockers)>0 then if aplicar then raise exception '%',blockers->>0;end if;return jsonb_build_object('origem',a,'destino',b,'campos',fields,'vinculos',links,'impedimentos',blockers,'versao',finger,'estoque',case when tipo='produto'then public.axe_estoque_mesclagem_previa(origem,destino)end);end if;
 begin
 insert into public.cadastros_mesclagens(tipo,origem_id,destino_id,usuario_id,estado,origem_anterior,destino_anterior,escolhas)values(tipo,origem,destino,p_usuario,'EXECUTANDO',a,b,choices)returning id into mid;
 if tipo='produto' then for k in select unnest(array['codigo_axe','codigo_anterior'])loop if nullif(a->>k,'')is not null and a->>k is distinct from merged->>k then insert into public.produtos_identificadores(produto_id,contexto,entidade,codigo_produto,descricao_produto,unidade,fonte,status_validacao)values(destino,'AXE_NOMUS','AXE',a->>k,a->>'descricao_referencia',a->>'unidade_referencia','Mesclagem do cadastro #'||origem,case when k='codigo_axe'then 'VALIDADO'else 'PENDENTE'end)on conflict(produto_id,contexto,entidade,codigo_produto)do nothing;end if;end loop;end if;
 if tipo='produto' then
  for dup in select s.*,d.id destino_alias,to_jsonb(d) destino_anterior from public.produtos_identificadores s
   join public.produtos_identificadores d on d.produto_id=destino and d.contexto=s.contexto and d.entidade=s.entidade and d.codigo_produto=s.codigo_produto
   where s.produto_id=origem order by s.id
  loop
   -- Os dois registros e seus vínculos anteriores permanecem no histórico da mesclagem.
   linksall:=linksall||jsonb_build_array(jsonb_build_object('tabela','produtos_identificadores','campo','identificador_reunido','registros_anteriores',jsonb_build_array(to_jsonb(dup)-'destino_alias'-'destino_anterior',dup.destino_anterior),'origem_identificador_id',dup.id,'destino_identificador_id',dup.destino_alias));
   for ref in select k.conrelid::regclass rel,at.attname col from pg_constraint k join pg_attribute at on at.attrelid=k.conrelid and at.attnum=any(k.conkey)
    where k.contype='f' and k.confrelid='public.produtos_identificadores'::regclass order by 1,2
   loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from %s x where %I=$1',ref.rel,ref.col)into rowsj using dup.id;
    linksall:=linksall||jsonb_build_array(jsonb_build_object('tabela',ref.rel::text,'campo',ref.col,'registros_anteriores',rowsj));
    execute format('update %s set %I=$1 where %I=$2',ref.rel,ref.col,ref.col)using dup.destino_alias,dup.id;
   end loop;
   update public.produtos_identificadores d set
    descricao_produto=coalesce(nullif(d.descricao_produto,''),dup.descricao_produto),
    unidade=coalesce(nullif(d.unidade,''),dup.unidade),
    fabricante=coalesce(nullif(d.fabricante,''),dup.fabricante),
    codigo_fabricante=coalesce(nullif(d.codigo_fabricante,''),dup.codigo_fabricante),
    fonte=concat_ws(' | ',nullif(d.fonte,''),nullif(dup.fonte,'')),
    status_validacao=case when d.status_validacao='DIVERGENTE' or dup.status_validacao='DIVERGENTE' then 'DIVERGENTE'
     when d.status_validacao='VALIDADO' and dup.status_validacao='VALIDADO' then 'VALIDADO'
     when d.status_validacao='INATIVO' and dup.status_validacao='INATIVO' then 'INATIVO' else 'PENDENTE' end,
    atualizado_em=clock_timestamp() where d.id=dup.destino_alias;
   update public.produtos_identificadores set status_validacao='INATIVO',atualizado_em=clock_timestamp() where id=dup.id;
  end loop;
 end if;
 -- Libera chaves exclusivas, preservadas integralmente nos snapshots da mesclagem.
 for k in select unnest(case tipo when 'cliente'then array['cnpj','codigo_externo']when 'fornecedor'then array['cnpj','documento_fiscal']else array['codigo_axe','codigo_anterior','chave_cadastro']end)loop clearcols:=clearcols||case when clearcols=''then ''else ','end||format('%I=null',k);end loop;
 execute format('update public.%I set %s,mesclado_em_id=$2,ativo=false,atualizado_em=clock_timestamp() where id=$1',t,clearcols)using origem,destino;
 for k,v in select * from jsonb_each(merged)where key not in('id','criado_em','atualizado_em','mesclado_em_id','ncm_capitulo','ncm_posicao','ncm_subposicao')loop sets:=sets||case when sets=''then ''else ','end||format('%I=r.%I',k,k);end loop;
 execute format('update public.%I x set %s,atualizado_em=clock_timestamp() from jsonb_populate_record(null::public.%I,$1)r where x.id=$2',t,sets,t)using merged,destino;

 -- Reunir relações duplicadas, preservando ambos os registros no histórico da mesclagem.
 if tipo='produto' then
  select coalesce(jsonb_agg(to_jsonb(d)),'[]') into rowsj from public.pedido_itens_produtos d
  where d.produto_id=destino and exists(select 1 from public.pedido_itens_produtos s where s.produto_id=origem and s.item_id=d.item_id);
  linksall:=linksall||jsonb_build_array(jsonb_build_object('tabela','pedido_itens_produtos','campo','destinos_duplicados_anteriores','registros_anteriores',rowsj));
  update public.pedido_itens_produtos d set fonte=concat_ws(' | ',d.fonte,s.fonte),atualizado_em=clock_timestamp(),
   status_validacao=case when d.status_validacao='VALIDADO' then 'VALIDADO' when d.status_validacao='DIVERGENTE' or s.status_validacao='DIVERGENTE' then 'DIVERGENTE' else s.status_validacao end
  from public.pedido_itens_produtos s where d.produto_id=destino and s.produto_id=origem and d.item_id=s.item_id;
  delete from public.pedido_itens_produtos s where s.produto_id=origem and exists(select 1 from public.pedido_itens_produtos d where d.produto_id=destino and d.item_id=s.item_id);
  -- Duplicidade de opção só pode ser resolvida automaticamente quando o destino já foi aprovado
  -- e a origem ainda era candidata; condições comerciais diferentes seguem bloqueando.
  select coalesce(jsonb_agg(to_jsonb(d)),'[]') into rowsj from public.produtos_clientes_opcoes d
  where d.produto_id=destino and exists(select 1 from public.produtos_clientes_opcoes s where s.produto_id=origem and s.referencia_cliente_id=d.referencia_cliente_id);
  linksall:=linksall||jsonb_build_array(jsonb_build_object('tabela','produtos_clientes_opcoes','campo','destinos_duplicados_anteriores','registros_anteriores',rowsj));
  delete from public.produtos_clientes_opcoes s using public.produtos_clientes_opcoes d
   where s.produto_id=origem and d.produto_id=destino and s.referencia_cliente_id=d.referencia_cliente_id
   and s.situacao='EM_AVALIACAO' and d.situacao='APROVADO'
   and s.fator_conversao is null and s.quantidade_minima is null and s.multiplo_venda is null
   and s.prazo_dias is null and s.restricoes is null and s.valido_desde is null and s.valido_ate is null;
 end if;
 for c in select k.conrelid::regclass as rel,at.attname col from pg_constraint k join pg_attribute at on at.attrelid=k.conrelid and at.attnum=any(k.conkey) where k.contype='f' and k.confrelid=to_regclass('public.'||t) and k.conrelid<>to_regclass('public.'||t) order by 1,2 loop
 if tipo='produto' and c.rel='public.produtos_identificadores'::regclass and c.col='produto_id' then
  update public.produtos_identificadores x set produto_id=destino where x.produto_id=origem
  and not exists(select 1 from public.produtos_identificadores d where d.produto_id=destino and d.contexto=x.contexto and d.entidade=x.entidade and d.codigo_produto=x.codigo_produto);
 else
  execute format('update %s set %I=$1 where %I=$2',c.rel,c.col,c.col)using destino,origem;
 end if;
 end loop;
 if tipo='produto'then update public.comercial_propostas set documento=public.axe_mesclagem_json(documento,origem,destino)where documento is distinct from public.axe_mesclagem_json(documento,origem,destino);end if;

 execute format('select to_jsonb(x) from public.%I x where id=$1',t)into merged using destino;
 update public.cadastros_mesclagens set estado='CONCLUIDA',destino_atual=merged,vinculos=linksall where id=mid;
 set constraints all immediate;
 result:=jsonb_build_object('id',mid,'destino_id',destino,'origem_id',origem,'campos',fields,'vinculos',links,'destino_atual',merged);
 if not aplicar then raise exception using errcode='Z0001',message='PREVIA';end if;
 exception when sqlstate 'Z0001'then null;
 when others then get stacked diagnostics err=message_text;
 if aplicar then raise exception 'Mesclagem não aplicada. Nenhum dado foi alterado: %',err;end if;
 blockers:=blockers||jsonb_build_array('Vínculo necessita de ajuste antes da mesclagem: '||err);
 end;
 if aplicar then return result;end if;
 return jsonb_build_object('origem',a,'destino',b,'campos',fields,'vinculos',links,'impedimentos',blockers,'versao',finger,'estoque',case when tipo='produto'then public.axe_estoque_mesclagem_previa(origem,destino)end);
end $function$;
CREATE OR REPLACE FUNCTION public.axe_consolidar_produtos_rumo(p_cliente bigint,p_codigo text,p_destino bigint,p_usuario uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $fn$
DECLARE x record;prev jsonb;choices jsonb;results jsonb:='[]';refid bigint;
BEGIN
IF NOT EXISTS(SELECT 1 FROM public.axe_rumo_revisores WHERE usuario_id=p_usuario AND ativo) OR NOT EXISTS(SELECT 1 FROM public.gestao_membros WHERE usuario_id=p_usuario AND ativo AND papel IN('ADMIN','EDITOR')) THEN RAISE EXCEPTION 'Sem permissão';END IF;
SELECT id INTO refid FROM public.produtos_clientes_referencias WHERE cliente_id=p_cliente AND codigo_cliente=p_codigo AND produto_axe_id=p_destino AND fator_conversao_axe=1;
IF refid IS NULL THEN RETURN jsonb_build_object('mesclagens',results);END IF;
FOR x IN SELECT DISTINCT pr.id FROM public.produtos_conciliacao pr
WHERE pr.ativo AND pr.mesclado_em_id IS NULL AND pr.codigo_axe IS NULL AND pr.codigo_anterior IS NULL AND pr.id<>p_destino
AND (EXISTS(SELECT 1 FROM public.produtos_clientes_opcoes op WHERE op.produto_id=pr.id AND op.referencia_cliente_id=refid)
 OR EXISTS(SELECT 1 FROM public.produtos_identificadores i JOIN public.clientes c ON c.cnpj=i.entidade WHERE c.id=p_cliente AND i.produto_id=pr.id AND i.contexto='CLIENTE' AND i.codigo_produto=p_codigo AND i.status_validacao<>'INATIVO'))
AND NOT EXISTS(SELECT 1 FROM public.produtos_identificadores i WHERE i.produto_id=pr.id AND i.contexto<>'CLIENTE' AND i.status_validacao<>'INATIVO')
AND NOT EXISTS(SELECT 1 FROM public.produtos_identificadores i WHERE i.produto_id=pr.id AND i.contexto='CLIENTE' AND i.status_validacao<>'INATIVO' AND NOT EXISTS(
 SELECT 1 FROM public.produtos_clientes_referencias r JOIN public.clientes c ON c.id=r.cliente_id WHERE c.cnpj=i.entidade AND r.codigo_cliente=i.codigo_produto AND r.produto_axe_id=p_destino AND r.fator_conversao_axe=1))
LOOP
prev:=public.axe_cadastro_mesclar(jsonb_build_object('acao','cadastro_mesclar_previa','tipo','produto','origem_id',x.id,'destino_id',p_destino),p_usuario);
IF jsonb_array_length(prev->'impedimentos')>0 THEN RAISE EXCEPTION 'Não foi possível consolidar o produto RUMO %: %',x.id,prev->'impedimentos'->>0;END IF;
SELECT coalesce(jsonb_object_agg(value->>'campo','destino'),'{}') INTO choices FROM jsonb_array_elements(prev->'campos') WHERE (value->>'conflito')::boolean;
results:=results||jsonb_build_array(public.axe_cadastro_mesclar(jsonb_build_object('acao','cadastro_mesclar_salvar','tipo','produto','origem_id',x.id,'destino_id',p_destino,'versao',prev->>'versao','escolhas',choices),p_usuario));
END LOOP;
RETURN jsonb_build_object('mesclagens',results);
END $fn$;
REVOKE ALL ON FUNCTION public.axe_consolidar_produtos_rumo(bigint,text,bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.axe_consolidar_produtos_rumo(bigint,text,bigint,uuid) TO service_role;
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