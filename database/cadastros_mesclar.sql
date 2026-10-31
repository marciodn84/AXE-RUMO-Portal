begin;
alter table public.clientes add column if not exists mesclado_em_id bigint references public.clientes(id);
alter table public.fornecedores add column if not exists mesclado_em_id bigint references public.fornecedores(id);
alter table public.produtos_conciliacao add column if not exists mesclado_em_id bigint references public.produtos_conciliacao(id);
alter table public.clientes drop constraint clientes_cnpj_obrigatorio;
alter table public.clientes add constraint clientes_cnpj_obrigatorio check(mesclado_em_id is not null or legado_grupo or coalesce(cnpj,'')~'^[0-9]{14}$');
create table if not exists public.cadastros_mesclagens(
 id uuid primary key default gen_random_uuid(),tipo text not null check(tipo in ('cliente','produto','fornecedor')),
 origem_id bigint not null,destino_id bigint not null,usuario_id uuid not null references auth.users(id),criado_em timestamptz not null default clock_timestamp(),
 transacao bigint not null default txid_current(),estado text not null check(estado in ('EXECUTANDO','CONCLUIDA')),
 origem_anterior jsonb not null,destino_anterior jsonb not null,destino_atual jsonb,escolhas jsonb not null default '{}',vinculos jsonb not null default '[]',
 check(origem_id<>destino_id),unique(tipo,origem_id));
alter table public.cadastros_mesclagens enable row level security;
revoke all on public.cadastros_mesclagens from public,anon,authenticated;
grant select,insert,update on public.cadastros_mesclagens to service_role;
create function public.axe_mesclagem_json(p jsonb,origem bigint,destino bigint)returns jsonb language plpgsql immutable set search_path='' as $$
declare r jsonb;k text;v jsonb;begin
 if jsonb_typeof(p)='array' then select coalesce(jsonb_agg(public.axe_mesclagem_json(value,origem,destino)),'[]')into r from jsonb_array_elements(p);return r;
 elsif jsonb_typeof(p)='object' then r:='{}';for k,v in select * from jsonb_each(p)loop r:=r||jsonb_build_object(k,case when k='produto_id' and v in(to_jsonb(origem),to_jsonb(origem::text)) then to_jsonb(destino)else public.axe_mesclagem_json(v,origem,destino)end);end loop;return r;end if;return p;end $$;
create function public.axe_mesclagem_vinculo_permitido(tabela text,antes jsonb,depois jsonb)returns boolean language plpgsql set search_path='' as $$
declare m record;esperado jsonb;c record;begin
 for m in select * from public.cadastros_mesclagens where transacao=txid_current() and estado='EXECUTANDO' loop
 esperado:=antes;
 for c in select a.attname from pg_constraint k join pg_attribute a on a.attrelid=k.conrelid and a.attnum=any(k.conkey) where k.contype='f' and k.conrelid=to_regclass('public.'||tabela) and k.confrelid=to_regclass('public.'||case m.tipo when 'cliente'then 'clientes' when 'produto'then 'produtos_conciliacao'else 'fornecedores'end)loop
 if antes->>c.attname=m.origem_id::text then esperado:=jsonb_set(esperado,array[c.attname],to_jsonb(m.destino_id));end if;end loop;
 if m.tipo='produto' and tabela='comercial_propostas' then esperado:=jsonb_set(esperado,'{documento}',public.axe_mesclagem_json(antes->'documento',m.origem_id,m.destino_id));end if;
 if esperado<>antes and esperado=depois then return true;end if;
 end loop;return false;end $$;
-- A exceção é limitada à troca de identidade auditada nesta transação. Valores,
-- quantidades, documentos originais e estados continuam protegidos pelos guards.
do $$declare f record;d text;begin
 for f in select oid,proname from pg_proc where pronamespace='public'::regnamespace and proname in('axe_imp_custo_guard','axe_imp_nf_proteger_origem','axe_imp_nf_proteger_embarque','axe_proteger_regra_ativa','axe_fiscal_parametros_guard','axe_fiscal_regra_guard','axe_guardar_cadastros_bloqueados','axe_guardar_bloqueio_comercial','axe_imp_fin_guard_pedido')loop
 d:=pg_get_functiondef(f.oid);
 d:=regexp_replace(d,'\m[Bb][Ee][Gg][Ii][Nn]\M',E'begin\n if TG_OP=\'UPDATE\' and public.axe_mesclagem_vinculo_permitido(TG_TABLE_NAME,to_jsonb(OLD),to_jsonb(NEW)) then return NEW;end if;');execute d;
 end loop;end $$;
create function public.axe_cadastro_mesclar(p_dados jsonb,p_usuario uuid)returns jsonb language plpgsql set search_path='' as $$
declare tipo text:=p_dados->>'tipo';acao text:=p_dados->>'acao';t text;origem bigint:=(p_dados->>'origem_id')::bigint;destino bigint:=(p_dados->>'destino_id')::bigint;
 a jsonb;b jsonb;merged jsonb;fields jsonb:='[]';links jsonb:='[]';linksall jsonb:='[]';blockers jsonb:='[]';choices jsonb:=coalesce(p_dados->'escolhas','{}');k text;v jsonb;av jsonb;bv jsonb;selected text;ignore text[];c record;n bigint;rowsj jsonb;finger text;mid uuid;sets text:='';clearcols text:='';err text;result jsonb;aplicar boolean:=acao='cadastro_mesclar_salvar';
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
 finger:=md5(jsonb_build_array(a,b,links)::text);
 if aplicar and p_dados->>'versao' is distinct from finger then raise exception 'Os cadastros ou vínculos mudaram. Gere uma nova prévia';end if;
 if jsonb_array_length(blockers)>0 then if aplicar then raise exception '%',blockers->>0;end if;return jsonb_build_object('origem',a,'destino',b,'campos',fields,'vinculos',links,'impedimentos',blockers,'versao',finger,'estoque',case when tipo='produto'then 'Não há saldo ou livro de entradas e saídas cadastrado neste ERP. As confirmações de entrada da importação e seus custos serão preservados pelos vínculos dos itens.'end);end if;
 begin
 insert into public.cadastros_mesclagens(tipo,origem_id,destino_id,usuario_id,estado,origem_anterior,destino_anterior,escolhas)values(tipo,origem,destino,p_usuario,'EXECUTANDO',a,b,choices)returning id into mid;
 if tipo='produto' then for k in select unnest(array['codigo_axe','codigo_anterior'])loop if nullif(a->>k,'')is not null and a->>k is distinct from merged->>k then insert into public.produtos_identificadores(produto_id,contexto,entidade,codigo_produto,descricao_produto,unidade,fonte,status_validacao)values(destino,'AXE_NOMUS','AXE',a->>k,a->>'descricao_referencia',a->>'unidade_referencia','Mesclagem do cadastro #'||origem,case when k='codigo_axe'then 'VALIDADO'else 'PENDENTE'end)on conflict(produto_id,contexto,entidade,codigo_produto)do nothing;end if;end loop;end if;
 -- Libera chaves exclusivas, preservadas integralmente nos snapshots da mesclagem.
 for k in select unnest(case tipo when 'cliente'then array['cnpj','codigo_externo']when 'fornecedor'then array['cnpj','documento_fiscal']else array['codigo_axe','codigo_anterior','chave_cadastro']end)loop clearcols:=clearcols||case when clearcols=''then ''else ','end||format('%I=null',k);end loop;
 execute format('update public.%I set %s,mesclado_em_id=$2,ativo=false,atualizado_em=clock_timestamp() where id=$1',t,clearcols)using origem,destino;
 for k,v in select * from jsonb_each(merged)where key not in('id','criado_em','atualizado_em','mesclado_em_id','ncm_capitulo','ncm_posicao','ncm_subposicao')loop sets:=sets||case when sets=''then ''else ','end||format('%I=r.%I',k,k);end loop;
 execute format('update public.%I x set %s,atualizado_em=clock_timestamp() from jsonb_populate_record(null::public.%I,$1)r where x.id=$2',t,sets,t)using merged,destino;
 for c in select k.conrelid::regclass as rel,at.attname col from pg_constraint k join pg_attribute at on at.attrelid=k.conrelid and at.attnum=any(k.conkey) where k.contype='f' and k.confrelid=to_regclass('public.'||t) and k.conrelid<>to_regclass('public.'||t) order by 1,2 loop
 execute format('update %s set %I=$1 where %I=$2',c.rel,c.col,c.col)using destino,origem;
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
 return jsonb_build_object('origem',a,'destino',b,'campos',fields,'vinculos',links,'impedimentos',blockers,'versao',finger,'estoque',case when tipo='produto'then 'Não há saldo ou livro de entradas e saídas cadastrado neste ERP. As confirmações de entrada da importação e seus custos serão preservados pelos vínculos dos itens.'end);
end $$;
create function public.axe_mesclagem_referencias_guard()returns trigger language plpgsql set search_path='' as $$
declare c record;r jsonb:=to_jsonb(new);i bigint;j bigint;n int;begin
 for c in select at.attname col,cl.relname tabela from pg_constraint k join pg_attribute at on at.attrelid=k.conrelid and at.attnum=any(k.conkey) join pg_class cl on cl.oid=k.confrelid where k.contype='f' and k.conrelid=tg_relid and cl.relname in('clientes','produtos_conciliacao','fornecedores')and k.conrelid<>k.confrelid loop
 i:=nullif(r->>c.col,'')::bigint;n:=0;
 while i is not null loop execute format('select mesclado_em_id from public.%I where id=$1 for share',c.tabela)into j using i;exit when j is null;n:=n+1;if n>20 then raise exception 'Cadeia de mesclagem inválida';end if;i:=j;end loop;
 if i is not null then r:=jsonb_set(r,array[c.col],to_jsonb(i));end if;
 end loop;new:=jsonb_populate_record(new,r);return new;end $$;
do $$declare c record;begin for c in select distinct k.conrelid::regclass rel from pg_constraint k where k.contype='f' and k.confrelid in('public.clientes'::regclass,'public.produtos_conciliacao'::regclass,'public.fornecedores'::regclass)and k.conrelid<>k.confrelid loop execute format('create trigger aaa_mesclagem_referencias before insert or update on %s for each row execute function public.axe_mesclagem_referencias_guard()',c.rel);end loop;end $$;
-- Um cadastro absorvido não pode voltar a ser usado ou editado isoladamente.
create function public.axe_cadastro_mesclado_guard()returns trigger language plpgsql set search_path='' as $$
begin
 if TG_OP='UPDATE' and old.mesclado_em_id is not null then raise exception 'Cadastro combinado no ID %. Utilize o cadastro mantido',old.mesclado_em_id;end if;
 return new;end $$;
do $$declare t text;d text;v text;begin foreach t in array array['clientes','produtos_conciliacao','fornecedores']loop execute format('create trigger cadastro_mesclado_guard before update on public.%I for each row execute function public.axe_cadastro_mesclado_guard()',t);end loop;
 foreach v in array array['portal_clientes','portal_produtos']loop t:=case v when 'portal_clientes'then 'clientes'else 'produtos_conciliacao'end;d:=rtrim(pg_get_viewdef(to_regclass('public.'||v),true),';');execute format('create or replace view public.%I with(security_invoker=true)as select v.* from (%s)v join public.%I m on m.id=v.id where m.mesclado_em_id is null',v,d,t);end loop;end $$;
revoke all on function public.axe_cadastro_mesclar(jsonb,uuid),public.axe_mesclagem_json(jsonb,bigint,bigint),public.axe_mesclagem_vinculo_permitido(text,jsonb,jsonb),public.axe_cadastro_mesclado_guard(),public.axe_mesclagem_referencias_guard()from public,anon,authenticated;
grant execute on function public.axe_cadastro_mesclar(jsonb,uuid),public.axe_mesclagem_json(jsonb,bigint,bigint),public.axe_mesclagem_vinculo_permitido(text,jsonb,jsonb),public.axe_cadastro_mesclado_guard(),public.axe_mesclagem_referencias_guard()to service_role;
commit;
