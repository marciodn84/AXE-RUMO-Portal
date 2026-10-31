create table public.axe_email_upload_partes(
 mensagem_id uuid not null references public.axe_email_mensagens(id),anexo_id text not null,sha256 text not null check(sha256~'^[a-f0-9]{64}$'),
 numero integer not null,quantidade integer not null check(quantidade between 1 and 256),nome text not null,conteudo bytea not null check(octet_length(conteudo) between 1 and 32768),
 usuario_id uuid not null references auth.users(id),criado_em timestamptz not null default clock_timestamp(),
 primary key(mensagem_id,anexo_id,sha256,numero),check(numero between 0 and quantidade-1));
alter table public.axe_email_upload_partes enable row level security;
revoke all on public.axe_email_upload_partes from public,anon,authenticated;grant all on public.axe_email_upload_partes to service_role;
create function public.axe_email_arquivar_parte(p_dados jsonb,p_usuario uuid)returns jsonb language plpgsql security invoker set search_path='' as $$
declare mid uuid:=(p_dados->>'mensagem_id')::uuid;aid text:=p_dados->>'anexo_id';h text:=p_dados->>'sha256';n integer:=(p_dados->>'parte')::integer;q integer:=(p_dados->>'partes')::integer;b bytea;all_bytes bytea;prev public.axe_email_upload_partes;cont integer;r jsonb;
begin
 if not exists(select 1 from public.gestao_membros m join public.axe_rumo_revisores rv on rv.usuario_id=m.usuario_id and rv.ativo where m.usuario_id=p_usuario and m.ativo and m.papel='ADMIN') then raise exception 'Arquivamento restrito ao administrador';end if;
 if length(p_dados->>'conteudo_base64')>44000 or q not between 1 and 256 or n not between 0 and q-1 or h!~'^[a-f0-9]{64}$' then raise exception 'Parte inválida';end if;
 if not exists(select 1 from public.axe_email_mensagens m,jsonb_array_elements(m.anexos)a where m.id=mid and a->>'sha256'=h and a->>'nome'=p_dados->>'nome') then raise exception 'Parte não corresponde ao inventário original';end if;
 b:=decode(p_dados->>'conteudo_base64','base64');perform pg_advisory_xact_lock(hashtextextended(mid::text||aid,0));
 delete from public.axe_email_upload_partes where criado_em<clock_timestamp()-interval '24 hours';
 select * into prev from public.axe_email_upload_partes where mensagem_id=mid and anexo_id=aid and sha256=h and numero=n;
 if found then if prev.conteudo<>b or prev.quantidade<>q or prev.nome is distinct from p_dados->>'nome' then raise exception 'Parte já recebida com outro conteúdo';end if;
 else insert into public.axe_email_upload_partes(mensagem_id,anexo_id,sha256,numero,quantidade,nome,conteudo,usuario_id)values(mid,aid,h,n,q,p_dados->>'nome',b,p_usuario);end if;
 select count(*),string_agg(conteudo,''::bytea order by numero) into cont,all_bytes from public.axe_email_upload_partes where mensagem_id=mid and anexo_id=aid and sha256=h;
 if cont<q then return jsonb_build_object('recebidas',cont,'partes',q,'completo',false);end if;
 if cont<>q or encode(sha256(all_bytes),'hex')<>h then raise exception 'Integridade do original não confirmada';end if;
 r:=public.axe_email_arquivar_original(jsonb_build_object('mensagem_id',mid,'anexo_id',aid,'nome',p_dados->>'nome','conteudo_base64',encode(all_bytes,'base64')),p_usuario);
 delete from public.axe_email_upload_partes where mensagem_id=mid and anexo_id=aid and sha256=h;return r||jsonb_build_object('completo',true);
end $$;
revoke all on function public.axe_email_arquivar_parte(jsonb,uuid) from public,anon,authenticated;grant execute on function public.axe_email_arquivar_parte(jsonb,uuid) to service_role;
