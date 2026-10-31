begin;
create view public.fornecedores_identidades with(security_invoker=true)as
select id as fornecedor_id,razao_social,nome_fantasia,cnpj,documento_fiscal from public.fornecedores where mesclado_em_id is null
union all select public.axe_cadastro_canonico('fornecedor',destino_id),origem_anterior->>'razao_social',origem_anterior->>'nome_fantasia',origem_anterior->>'cnpj',origem_anterior->>'documento_fiscal' from public.cadastros_mesclagens where tipo='fornecedor' and estado='CONCLUIDA';
revoke all on public.fornecedores_identidades from public,anon,authenticated;
grant select on public.fornecedores_identidades to service_role;
create or replace function public.axe_imp_transportador_resolver(p_nome text,p_documento text default null)returns jsonb language plpgsql set search_path='' as $$
declare nome text:=public.axe_transportador_nome(p_nome);doc text:=regexp_replace(coalesce(p_documento,''),'\D','','g');lista jsonb;ativos jsonb;criterio text;begin
 if nome='' and doc='' then return jsonb_build_object('estado','Não identificado','candidatos','[]'::jsonb);end if;
 if doc<>'' then
 select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'nome',f.razao_social,'ativo',f.ativo,'bloqueado',f.bloqueado_comercial) order by f.id),'[]') into lista from public.fornecedores f where exists(select 1 from public.fornecedores_identidades i where i.fornecedor_id=f.id and (regexp_replace(coalesce(i.cnpj,i.documento_fiscal,''),'\D','','g')=doc));
 criterio:='CNPJ do transportador no documento';
 else
 select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'nome',f.razao_social,'ativo',f.ativo,'bloqueado',f.bloqueado_comercial) order by f.id),'[]') into lista from public.fornecedores f where exists(select 1 from public.fornecedores_identidades i where i.fornecedor_id=f.id and (public.axe_transportador_nome(i.razao_social)=nome or public.axe_transportador_nome(i.nome_fantasia)=nome));
 criterio:='Nome exato do cadastro';
 if nome in('DHL','FEDEX','UPS')then
 select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'nome',f.razao_social,'ativo',f.ativo,'bloqueado',f.bloqueado_comercial) order by f.id),'[]') into lista from public.fornecedores f where exists(select 1 from public.fornecedores_identidades i where i.fornecedor_id=f.id and (public.axe_transportador_nome(i.razao_social)=nome or public.axe_transportador_nome(i.nome_fantasia)=nome or public.axe_transportador_nome(i.razao_social) like nome||' %' or public.axe_transportador_nome(i.nome_fantasia) like nome||' %'));
 criterio:='Marca do documento no nome do cadastro';end if;
 end if;
 select coalesce(jsonb_agg(x),'[]') into ativos from jsonb_array_elements(lista)x where(x->>'ativo')::boolean;
 if jsonb_array_length(ativos)>1 then return jsonb_build_object('estado','Ambíguo','criterio',criterio,'candidatos',ativos);end if;
 if jsonb_array_length(ativos)=1 then
 if (ativos->0->>'bloqueado')::boolean then return jsonb_build_object('estado','Bloqueado','criterio',criterio,'candidatos',ativos);end if;
 return jsonb_build_object('estado','Automático','id',ativos->0->'id','nome',ativos->0->'nome','criterio',criterio,'candidatos',ativos);end if;
 return jsonb_build_object('estado',case when jsonb_array_length(lista)>0 then 'Inativo' else 'Não encontrado' end,'criterio',criterio,'candidatos',lista);
end $$;
revoke all on function public.axe_transportador_nome(text),public.axe_imp_transportador_resolver(text,text)from public,anon,authenticated;
grant execute on function public.axe_transportador_nome(text),public.axe_imp_transportador_resolver(text,text)to service_role;
commit;
