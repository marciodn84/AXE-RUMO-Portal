create or replace function public.axe_email_arquivar_original(p_dados jsonb,p_usuario uuid) returns jsonb language plpgsql security invoker set search_path='' as $$
declare m public.axe_email_mensagens;b bytea;h text;z jsonb;n integer;aid text;
begin
 if not exists(select 1 from public.gestao_membros gm join public.axe_rumo_revisores rv on rv.usuario_id=gm.usuario_id and rv.ativo where gm.usuario_id=p_usuario and gm.ativo and gm.papel='ADMIN') then raise exception 'Arquivamento restrito ao administrador';end if;
 if length(p_dados->>'conteudo_base64')>11300000 then raise exception 'Anexo excede 8 MB';end if;
 b:=decode(p_dados->>'conteudo_base64','base64');if b is null or octet_length(b) not between 1 and 8388608 then raise exception 'Anexo vazio ou acima de 8 MB';end if;h:=encode(sha256(b),'hex');
 select * into m from public.axe_email_mensagens where id=(p_dados->>'mensagem_id')::uuid for update;if not found then raise exception 'Mensagem não cadastrada';end if;
 select value into z from jsonb_array_elements(m.anexos) where value->>'anexo_id'=p_dados->>'anexo_id';
 if z is null then
  select count(*),min(value->>'anexo_id') into n,aid from jsonb_array_elements(m.anexos) where value->>'sha256'=h and value->>'nome'=p_dados->>'nome';
  if n<>1 then raise exception 'Identidade do anexo não coincide com inventário; atualize os IDs pelo conector';end if;
 else aid:=z->>'anexo_id';end if;
 return public.axe_documentos_entrada(jsonb_build_object('acao','email_anexar','mensagem_id',m.id,'anexo_id',aid,'conteudo_base64',p_dados->>'conteudo_base64'),p_usuario);
end $$;
revoke all on function public.axe_email_arquivar_original(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_email_arquivar_original(jsonb,uuid) to service_role;
