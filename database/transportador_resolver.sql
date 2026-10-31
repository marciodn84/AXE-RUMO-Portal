create or replace function public.axe_transportador_nome(p_nome text)returns text language sql immutable set search_path='' as $$select btrim(regexp_replace(translate(upper(coalesce(p_nome,'')),'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ','AAAAAEEEEIIIIOOOOOUUUUC'),'[^A-Z0-9]+',' ','g'))$$;
create or replace function public.axe_imp_transportador_resolver(p_nome text,p_documento text default null)returns jsonb language plpgsql set search_path='' as $$
declare nome text:=public.axe_transportador_nome(p_nome);doc text:=regexp_replace(coalesce(p_documento,''),'\D','','g');lista jsonb;ativos jsonb;criterio text;begin
 if nome='' and doc='' then return jsonb_build_object('estado','Não identificado','candidatos','[]'::jsonb);end if;
 if doc<>'' then
 select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'nome',f.razao_social,'ativo',f.ativo,'bloqueado',f.bloqueado_comercial) order by f.id),'[]') into lista from public.fornecedores f where regexp_replace(coalesce(f.cnpj,f.documento_fiscal,''),'\D','','g')=doc;
 criterio:='CNPJ do transportador no documento';
 else
 select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'nome',f.razao_social,'ativo',f.ativo,'bloqueado',f.bloqueado_comercial) order by f.id),'[]') into lista from public.fornecedores f where public.axe_transportador_nome(f.razao_social)=nome or public.axe_transportador_nome(f.nome_fantasia)=nome;
 criterio:='Nome exato do cadastro';
 if nome in('DHL','FEDEX','UPS')then
 select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'nome',f.razao_social,'ativo',f.ativo,'bloqueado',f.bloqueado_comercial) order by f.id),'[]') into lista from public.fornecedores f where public.axe_transportador_nome(f.razao_social)=nome or public.axe_transportador_nome(f.nome_fantasia)=nome or public.axe_transportador_nome(f.razao_social) like nome||' %' or public.axe_transportador_nome(f.nome_fantasia) like nome||' %';
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
