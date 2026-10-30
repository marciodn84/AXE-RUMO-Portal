begin;
alter table public.clientes add column if not exists bloqueado_comercial boolean not null default false;
alter table public.clientes add column if not exists motivo_bloqueio text;
alter table public.clientes add column if not exists bloqueio_alterado_em timestamptz;
alter table public.clientes add column if not exists bloqueio_alterado_por uuid references auth.users(id);
alter table public.clientes add constraint clientes_bloqueio_motivo check(not bloqueado_comercial or length(btrim(coalesce(motivo_bloqueio,''))) between 3 and 1000);
create or replace view public.portal_clientes with (security_invoker=true) as
select id,nome,codigo_externo,cnpj,criado_em,atualizado_em,concat_ws(' ',id::text,nome,codigo_externo,cnpj,(select string_agg(concat_ws(' ',l.cnpj,l.nome,l.dados::text),' ') from public.clientes_locais l where l.cliente_id=c.id)) as termos_busca,grupo_comercial,ativo,bloqueado_comercial,motivo_bloqueio,bloqueio_alterado_em,bloqueio_alterado_por from public.clientes c where not legado_grupo;
create or replace function public.axe_cliente_bloqueio(p_cliente bigint,p_bloquear boolean,p_motivo text,p_usuario uuid,p_versao timestamptz) returns jsonb language plpgsql set search_path='' as $$
declare antes public.clientes;depois public.clientes;
begin
 if not exists(select 1 from public.axe_rumo_revisores where usuario_id=p_usuario and ativo) then raise exception 'Usuário não autorizado';end if;
 if p_bloquear is null then raise exception 'Informe bloquear ou desbloquear';end if;
 if p_bloquear and length(btrim(coalesce(p_motivo,''))) not between 3 and 1000 then raise exception 'Informe o motivo do bloqueio (3 a 1000 caracteres)';end if;
 select * into antes from public.clientes where id=p_cliente and not legado_grupo for update;
 if not found then raise exception 'Cliente não encontrado';end if;
 if antes.bloqueado_comercial=p_bloquear then return jsonb_build_object('id',p_cliente,'bloqueado',p_bloquear,'sem_alteracao',true);end if;
 if antes.atualizado_em is distinct from p_versao then raise exception 'Cadastro alterado. Atualize a pesquisa antes de continuar';end if;
 update public.clientes set bloqueado_comercial=p_bloquear,motivo_bloqueio=case when p_bloquear then btrim(p_motivo) else null end,bloqueio_alterado_em=clock_timestamp(),bloqueio_alterado_por=p_usuario,atualizado_em=clock_timestamp() where id=p_cliente returning * into depois;
 insert into public.cadastros_decisoes(entidade,referencia,acao,anterior,atual,usuario_id) values('CLIENTE_COMERCIAL',p_cliente::text,case when p_bloquear then 'BLOQUEAR' else 'DESBLOQUEAR' end,to_jsonb(antes),to_jsonb(depois),p_usuario);
 return jsonb_build_object('id',p_cliente,'bloqueado',p_bloquear);
end $$;
revoke all on function public.axe_cliente_bloqueio(bigint,boolean,text,uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.axe_cliente_bloqueio(bigint,boolean,text,uuid,timestamptz) to service_role;
create or replace function public.axe_exigir_cliente_liberado(p_cliente bigint) returns void language plpgsql set search_path='' as $$
declare b boolean;m text;
begin
 if p_cliente is null then return;end if;
 select bloqueado_comercial,motivo_bloqueio into b,m from public.clientes where id=p_cliente for share;
 if b then raise exception 'Cliente bloqueado comercialmente: %. Desbloqueie o cadastro antes de iniciar esta operação.',m;end if;
end $$;
create or replace function public.axe_guardar_bloqueio_comercial() returns trigger language plpgsql set search_path='' as $$
declare cid bigint;
begin
 if tg_table_name='comercial_pedidos' then
  select cliente_id into cid from public.comercial_propostas where id=new.proposta_id;
  if tg_op='INSERT' or new.proposta_id is distinct from old.proposta_id then perform public.axe_exigir_cliente_liberado(cid);end if;
 else
  cid:=new.cliente_id;
  if tg_op='INSERT' then perform public.axe_exigir_cliente_liberado(cid);
  elsif new.cliente_id is distinct from old.cliente_id then perform public.axe_exigir_cliente_liberado(cid);
  elsif tg_table_name='comercial_propostas' then
   if new.estado is distinct from old.estado and new.estado in ('EM_REVISAO','APROVADA','ENVIADA','ACEITA') then perform public.axe_exigir_cliente_liberado(cid);end if;
  elsif tg_table_name='comercial_oportunidades' then
   if new.etapa is distinct from old.etapa and new.etapa<>'PERDIDA' then perform public.axe_exigir_cliente_liberado(cid);end if;
  end if;
 end if;
 return new;
end $$;
create trigger clientes_bloqueio_pedidos before insert or update of cliente_id on public.pedidos for each row execute function public.axe_guardar_bloqueio_comercial();
create trigger clientes_bloqueio_oportunidades before insert or update of cliente_id,etapa on public.comercial_oportunidades for each row execute function public.axe_guardar_bloqueio_comercial();
create trigger clientes_bloqueio_propostas before insert or update of cliente_id,estado on public.comercial_propostas for each row execute function public.axe_guardar_bloqueio_comercial();
create trigger clientes_bloqueio_vendas before insert or update of proposta_id on public.comercial_pedidos for each row execute function public.axe_guardar_bloqueio_comercial();
revoke all on function public.axe_guardar_bloqueio_comercial() from public,anon,authenticated;
commit;
revoke all on function public.axe_exigir_cliente_liberado(bigint) from public,anon,authenticated;
grant execute on function public.axe_exigir_cliente_liberado(bigint) to service_role;
