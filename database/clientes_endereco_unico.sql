begin;
lock table public.clientes_locais in share row exclusive mode;
alter table public.clientes_locais add column if not exists vigente boolean not null default true;
alter table public.clientes_locais add column if not exists excluido_em timestamptz;
with ranked as (select id,row_number() over(partition by cliente_id order by id desc) n from public.clientes_locais where finalidade='FATURAMENTO' and excluido_em is null)
update public.clientes_locais l set vigente=false from ranked r where r.id=l.id and r.n>1;
create unique index if not exists clientes_faturamento_unico_vigente on public.clientes_locais(cliente_id) where finalidade='FATURAMENTO' and vigente and excluido_em is null;
create or replace function public.axe_cadastro_local(p_cliente bigint,p_tipo text,p_dados jsonb) returns bigint language plpgsql set search_path='' as $
declare h text;i bigint;atual public.clientes_locais;cep text;numero text;anterior bigint;
begin
 if p_dados is null or p_dados='{}'::jsonb or jsonb_typeof(p_dados)<>'object' then return null;end if;
 perform 1 from public.clientes where id=p_cliente for update;
 anterior:=nullif(p_dados->>'local_anterior_id','')::bigint;
 cep:=regexp_replace(coalesce(p_dados#>>'{endereco,cep}',''),'[^0-9]','','g');
 numero:=upper(regexp_replace(trim(coalesce(p_dados#>>'{endereco,numero}','')),'\s+','','g'));
 if p_tipo='FATURAMENTO' and p_dados->>'origem'='MANUTENCAO_PORTAL' then
  if anterior is null then raise exception 'Cadastre o faturamento pela consulta Buscar CNPJ';end if;
  if exists(select 1 from public.clientes_locais l cross join unnest(array['cep','logradouro','numero','complemento','bairro','municipio','uf']) k where l.id=anterior and l.cliente_id=p_cliente and upper(trim(coalesce(l.dados->'endereco'->>k,''))) is distinct from upper(trim(coalesce(p_dados->'endereco'->>k,'')))) then raise exception 'Atualize o endereço de faturamento pela consulta Buscar CNPJ';end if;
 end if;
 if anterior is not null then
  select * into atual from public.clientes_locais where id=anterior and cliente_id=p_cliente and vigente and excluido_em is null;
  if not found then raise exception 'Endereço alterado ou excluído; atualize a lista antes de editar';end if;
  if atual.finalidade<>p_tipo then raise exception 'A finalidade do endereço não pode ser alterada nesta edição';end if;
  if not exists(select 1 from unnest(array['cep','logradouro','numero','complemento','bairro','municipio','uf']) k where upper(trim(coalesce(atual.dados->'endereco'->>k,''))) is distinct from upper(trim(coalesce(p_dados->'endereco'->>k,''))))
   and not exists(select 1 from unnest(array['nome','cnpj','inscricao_estadual','contato','email','telefone','observacoes']) k where trim(coalesce(atual.dados->>k,'')) is distinct from trim(coalesce(p_dados->>k,''))) then return atual.id;end if;
 else
  if length(cep)=8 and numero<>'' then
   select * into atual from public.clientes_locais l where cliente_id=p_cliente and finalidade=p_tipo and vigente and excluido_em is null and regexp_replace(coalesce(l.dados#>>'{endereco,cep}',''),'[^0-9]','','g')=cep and upper(regexp_replace(trim(coalesce(l.dados#>>'{endereco,numero}','')),'\s+','','g'))=numero order by id desc limit 1;
   if found then
    if p_dados->>'origem'='MANUTENCAO_PORTAL' then raise exception 'Endereço já cadastrado com este CEP e número. Use Editar no endereço existente';end if;
    if atual.dados->'endereco'=p_dados->'endereco' and atual.cnpj is not distinct from p_dados->>'cnpj' and atual.inscricao_estadual is not distinct from p_dados->>'inscricao_estadual' then return atual.id;end if;
   end if;
  end if;
  if p_tipo='FATURAMENTO' and p_dados->>'origem'='MANUTENCAO_PORTAL' and exists(select 1 from public.clientes_locais where cliente_id=p_cliente and finalidade=p_tipo and vigente and excluido_em is null) then raise exception 'Já existe endereço de faturamento. Use Editar no endereço vigente';end if;
 end if;
 h:=public.axe_rumo_hash_json(p_dados);
 select id into i from public.clientes_locais where cliente_id=p_cliente and finalidade=p_tipo and hash_dados=h;
 if p_tipo='FATURAMENTO' then update public.clientes_locais set vigente=false where cliente_id=p_cliente and finalidade=p_tipo and vigente;end if;
 if anterior is not null then update public.clientes_locais set vigente=false where id=anterior;end if;
 if i is not null then update public.clientes_locais set vigente=true,excluido_em=null where id=i;return i;end if;
 insert into public.clientes_locais(cliente_id,finalidade,cnpj,nome,inscricao_estadual,dados,hash_dados) values(p_cliente,p_tipo,p_dados->>'cnpj',p_dados->>'nome',p_dados->>'inscricao_estadual',p_dados,h) returning id into i;
 return i;
end $;
create or replace function public.axe_portal_excluir_local(p_id bigint,p_cliente bigint,p_usuario uuid) returns jsonb language plpgsql set search_path='' as $$
declare antigo public.clientes_locais;
begin
 if not exists(select 1 from public.axe_rumo_revisores where usuario_id=p_usuario and ativo) then raise exception 'Usuário não autorizado';end if;
 perform 1 from public.clientes where id=p_cliente for update;
 select * into antigo from public.clientes_locais where id=p_id and cliente_id=p_cliente for update;
 if not found then raise exception 'Endereço não encontrado neste cliente';end if;
 if antigo.excluido_em is not null then return jsonb_build_object('ok',true,'id',p_id);end if;
 update public.clientes_locais set vigente=false,excluido_em=now() where id=p_id;
 insert into public.cadastros_decisoes(entidade,referencia,acao,anterior,atual,usuario_id) values('PORTAL_LOCAL',p_id::text,'EXCLUIR',to_jsonb(antigo),(select to_jsonb(l) from public.clientes_locais l where id=p_id),p_usuario);
 return jsonb_build_object('ok',true,'id',p_id);
end $$;
revoke all on function public.axe_portal_excluir_local(bigint,bigint,uuid) from public,anon,authenticated;
grant execute on function public.axe_portal_excluir_local(bigint,bigint,uuid) to service_role;
commit;

create unique index if not exists clientes_local_cep_numero_vigente on public.clientes_locais(cliente_id,finalidade,(regexp_replace(dados#>>'{endereco,cep}','[^0-9]','','g')),(upper(regexp_replace(trim(dados#>>'{endereco,numero}'),'\s+','','g')))) where vigente and excluido_em is null and length(regexp_replace(dados#>>'{endereco,cep}','[^0-9]','','g'))=8 and trim(coalesce(dados#>>'{endereco,numero}',''))<>'';