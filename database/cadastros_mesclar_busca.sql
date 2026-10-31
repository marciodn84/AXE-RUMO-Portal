begin;
create function public.axe_cadastro_canonico(p_tipo text,p_id bigint)returns bigint language plpgsql stable set search_path='' as $$
declare t text;i bigint:=p_id;j bigint;n int:=0;begin
t:=case p_tipo when 'cliente'then 'clientes'when 'produto'then 'produtos_conciliacao'when 'fornecedor'then 'fornecedores'end;if t is null then raise exception 'Tipo inválido';end if;
while i is not null loop execute format('select mesclado_em_id from public.%I where id=$1',t)into j using i;exit when j is null;i:=j;n:=n+1;if n>20 then raise exception 'Cadeia inválida';end if;end loop;return i;end $$;
create function public.axe_cadastro_aliases(p_tipo text,p_id bigint)returns text language sql stable set search_path='' as $$
 with recursive origens as(select m.* from public.cadastros_mesclagens m where m.tipo=p_tipo and m.destino_id=p_id and m.estado='CONCLUIDA' union all select m.* from public.cadastros_mesclagens m join origens o on m.destino_id=o.origem_id where m.tipo=p_tipo and m.estado='CONCLUIDA')
 select string_agg(origem_id::text||' '||origem_anterior::text,' ')from origens $$;
do $$declare v text;t text;d text;cols text;begin
 foreach v in array array['portal_clientes','portal_produtos']loop
 t:=case v when 'portal_clientes'then 'cliente'else 'produto'end;
 d:=rtrim(pg_get_viewdef(to_regclass('public.'||v),true),';');
 select string_agg(case when attname='termos_busca'then format($q$concat_ws(' ',v.termos_busca,public.axe_cadastro_aliases(%L,v.id)) as termos_busca$q$,t)else format('v.%I',attname)end,','order by attnum)into cols from pg_attribute where attrelid=to_regclass('public.'||v)and attnum>0 and not attisdropped;
 execute format('create or replace view public.%I with(security_invoker=true)as select %s from (%s)v',v,cols,d);
 end loop;end $$;
create view public.portal_fornecedores with(security_invoker=true)as select f.*,concat_ws(' ',f.id::text,f.razao_social,f.nome_fantasia,f.cnpj,f.documento_fiscal,public.axe_cadastro_aliases('fornecedor',f.id))as termos_busca from public.fornecedores f where f.mesclado_em_id is null;
revoke all on public.portal_fornecedores from public,anon,authenticated;
grant select on public.portal_fornecedores to service_role;
revoke all on function public.axe_cadastro_canonico(text,bigint),public.axe_cadastro_aliases(text,bigint)from public,anon,authenticated;
grant execute on function public.axe_cadastro_canonico(text,bigint),public.axe_cadastro_aliases(text,bigint)to service_role;
commit;
