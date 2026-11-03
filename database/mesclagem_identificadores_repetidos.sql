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
end $function$
