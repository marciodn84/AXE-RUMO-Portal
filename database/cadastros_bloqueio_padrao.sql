begin;
do $$ declare t text;begin foreach t in array array['produtos_conciliacao','fornecedores'] loop
 execute format('alter table public.%I add column bloqueado_comercial boolean not null default false, add column motivo_bloqueio text, add column bloqueio_alterado_em timestamptz, add column bloqueio_alterado_por uuid references auth.users(id)',t);
 execute format('alter table public.%I add constraint %I check(not bloqueado_comercial or length(btrim(coalesce(motivo_bloqueio,''''))) between 3 and 1000)',t,t||'_bloqueio_motivo');end loop;end $$;
do $$ declare def text;begin def:=rtrim(pg_get_viewdef('public.portal_produtos'::regclass,true),';');execute 'create or replace view public.portal_produtos with (security_invoker=true) as select v.*,p.bloqueado_comercial,p.motivo_bloqueio,p.bloqueio_alterado_em,p.bloqueio_alterado_por from ('||def||') v join public.produtos_conciliacao p on p.id=v.id';end $$;
create or replace function public.axe_cadastro_bloqueio(p_tipo text,p_id bigint,p_bloquear boolean,p_motivo text,p_usuario uuid,p_versao timestamptz) returns jsonb language plpgsql set search_path='' as $$
declare t text;antes jsonb;depois jsonb;
begin
 if not exists(select 1 from public.axe_rumo_revisores where usuario_id=p_usuario and ativo) then raise exception 'Usuário não autorizado';end if;
 t:=case p_tipo when 'produto' then 'produtos_conciliacao' when 'fornecedor' then 'fornecedores' end;if t is null or p_bloquear is null then raise exception 'Cadastro ou ação inválida';end if;
 if p_bloquear and length(btrim(coalesce(p_motivo,''))) not between 3 and 1000 then raise exception 'Informe o motivo do bloqueio (3 a 1000 caracteres)';end if;
 execute format('select to_jsonb(x) from public.%I x where id=$1 for update',t) into antes using p_id;
 if antes is null then raise exception 'Cadastro não encontrado';end if;
 if (antes->>'bloqueado_comercial')::boolean=p_bloquear then return jsonb_build_object('id',p_id,'bloqueado',p_bloquear,'sem_alteracao',true);end if;
 if (antes->>'atualizado_em')::timestamptz is distinct from p_versao then raise exception 'Cadastro alterado. Atualize a pesquisa antes de continuar';end if;
 execute format('update public.%I set bloqueado_comercial=$1,motivo_bloqueio=$2,bloqueio_alterado_em=clock_timestamp(),bloqueio_alterado_por=$3,atualizado_em=clock_timestamp() where id=$4 returning to_jsonb(%I.*)',t,t) into depois using p_bloquear,case when p_bloquear then btrim(p_motivo) end,p_usuario,p_id;
 insert into public.cadastros_decisoes(entidade,referencia,acao,anterior,atual,usuario_id)values(upper(p_tipo)||'_COMERCIAL',p_id::text,case when p_bloquear then 'BLOQUEAR' else 'DESBLOQUEAR' end,antes,depois,p_usuario);
 return jsonb_build_object('id',p_id,'bloqueado',p_bloquear);
end $$;
revoke all on function public.axe_cadastro_bloqueio(text,bigint,boolean,text,uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.axe_cadastro_bloqueio(text,bigint,boolean,text,uuid,timestamptz) to service_role;
create or replace function public.axe_exigir_cadastro_liberado(p_tipo text,p_id bigint) returns void language plpgsql set search_path='' as $$
declare t text;b boolean;m text;
begin
 if p_id is null then return;end if;t:=case p_tipo when 'produto' then 'produtos_conciliacao' when 'fornecedor' then 'fornecedores' end;if t is null then raise exception 'Tipo inválido';end if;
 execute format('select bloqueado_comercial,motivo_bloqueio from public.%I where id=$1 for share',t) into b,m using p_id;
 if b then raise exception '% bloqueado: %. Desbloqueie o cadastro antes de iniciar esta operação.',initcap(p_tipo),m;end if;
end $$;
revoke all on function public.axe_exigir_cadastro_liberado(text,bigint) from public,anon,authenticated;
grant execute on function public.axe_exigir_cadastro_liberado(text,bigint) to service_role;
create or replace function public.axe_guardar_cadastros_bloqueados() returns trigger language plpgsql set search_path='' as $$
declare itens jsonb;it jsonb;fid bigint;checar boolean:=false;
begin
 if tg_table_name in ('imp_pedidos','imp_processos') then
  if tg_op='INSERT' then checar:=true;else checar:=new.fornecedor_id is distinct from old.fornecedor_id;end if;
  if checar then perform public.axe_exigir_cadastro_liberado('fornecedor',new.fornecedor_id);end if;
 elsif tg_table_name='imp_pedido_itens' then
  if tg_op='INSERT' then checar:=true;else checar:=new.produto_id is distinct from old.produto_id or new.pedido_id is distinct from old.pedido_id or new.quantidade>old.quantidade;end if;
  if checar then select fornecedor_id into fid from public.imp_pedidos where id=new.pedido_id;perform public.axe_exigir_cadastro_liberado('fornecedor',fid);perform public.axe_exigir_cadastro_liberado('produto',new.produto_id);end if;
 elsif tg_table_name='comercial_propostas' then
  if tg_op='INSERT' then checar:=true;else checar:=new.documento is distinct from old.documento or (new.estado is distinct from old.estado and new.estado in ('EM_REVISAO','APROVADA','ENVIADA','ACEITA'));end if;
  if checar then itens:=new.documento->'itens';end if;
 elsif tg_table_name='comercial_pedidos' then
  select documento->'itens' into itens from public.comercial_propostas where id=new.proposta_id;
 end if;
 if jsonb_typeof(itens)='array' then for it in select value from jsonb_array_elements(itens) loop perform public.axe_exigir_cadastro_liberado('produto',nullif(it->>'produto_id','')::bigint);end loop;end if;
 return new;
end $$;
revoke all on function public.axe_guardar_cadastros_bloqueados() from public,anon,authenticated;
create trigger cadastros_bloqueio_compra before insert or update of fornecedor_id on public.imp_pedidos for each row execute function public.axe_guardar_cadastros_bloqueados();
create trigger cadastros_bloqueio_processo before insert or update of fornecedor_id on public.imp_processos for each row execute function public.axe_guardar_cadastros_bloqueados();
create trigger cadastros_bloqueio_item before insert or update of produto_id,pedido_id,quantidade on public.imp_pedido_itens for each row execute function public.axe_guardar_cadastros_bloqueados();
create trigger cadastros_bloqueio_proposta before insert or update of documento,estado on public.comercial_propostas for each row execute function public.axe_guardar_cadastros_bloqueados();
create trigger cadastros_bloqueio_venda before insert or update of proposta_id on public.comercial_pedidos for each row execute function public.axe_guardar_cadastros_bloqueados();
commit;
