do $$
declare definicao text:=pg_get_functiondef('public.axe_imp_fluxo_base(jsonb,uuid)'::regprocedure);
begin
 if strpos(definicao,'select p.id,p.referencia,p.status,public.axe_imp_status_processo(p.id)')=0 then raise exception 'Consulta de importações incompatível';end if;
 execute replace(definicao,'select p.id,p.referencia,p.status,public.axe_imp_status_processo(p.id)',
 'select p.id,p.referencia,p.status,greatest(p.atualizado_em,(select max(e.atualizado_em) from public.imp_embarque_itens ei join public.imp_pedido_itens pi on pi.id=ei.pedido_item_id join public.imp_embarques e on e.id=ei.embarque_id where pi.pedido_id=p.id)) atualizado_em,public.axe_imp_status_processo(p.id)');
end $$;

alter function public.axe_imp_estrutura(jsonb,uuid) rename to axe_imp_estrutura_sem_data_pesquisa;
create function public.axe_imp_estrutura(p_dados jsonb,p_usuario uuid) returns jsonb
language plpgsql set search_path='' as $$
declare r jsonb; linhas jsonb; tipo text:=p_dados->>'tipo';
begin
 r:=public.axe_imp_estrutura_sem_data_pesquisa(p_dados,p_usuario);
 if p_dados->>'acao'='v2_listar' and tipo in ('pedidos','parcelas','embarques') and jsonb_typeof(r->'linhas')='array' then
  select coalesce(jsonb_agg(l||jsonb_build_object('atualizado_em',coalesce(p.atualizado_em,a.atualizado_em,e.atualizado_em)) order by ord),'[]') into linhas
  from jsonb_array_elements(r->'linhas') with ordinality t(l,ord)
  left join public.imp_pedidos p on tipo='pedidos' and p.id=(l->>'id')::uuid
  left join public.imp_parcelas a on tipo='parcelas' and a.id=(l->>'id')::uuid
  left join public.imp_embarques e on tipo='embarques' and e.id=(l->>'id')::uuid;
  r:=jsonb_set(r,'{linhas}',linhas);
 end if;
 return r;
end $$;
revoke all on function public.axe_imp_estrutura(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_imp_estrutura(jsonb,uuid) to service_role;

alter table public.comercial_pedidos add column atualizado_em timestamptz;
update public.comercial_pedidos p set atualizado_em=greatest(p.criado_em,
 (select max(e.criado_em) from public.comercial_eventos e where e.tipo='pedido' and e.registro_id=p.id));
alter table public.comercial_pedidos alter column atualizado_em set default now();
create function public.axe_comercial_pedido_atualizado() returns trigger
language plpgsql set search_path='' as $$
begin
 new.atualizado_em:=clock_timestamp();
 return new;
end $$;
revoke all on function public.axe_comercial_pedido_atualizado() from public,anon,authenticated;
create trigger axe_comercial_pedido_atualizado before update on public.comercial_pedidos
for each row when (old is distinct from new) execute function public.axe_comercial_pedido_atualizado();
