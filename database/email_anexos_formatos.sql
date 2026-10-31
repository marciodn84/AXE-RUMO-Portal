CREATE OR REPLACE FUNCTION public.axe_email_documentos(p_dados jsonb, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare a text:=p_dados->>'acao';papel text;m public.axe_email_mensagens;f public.axe_email_arquivos;pedido public.imp_pedidos;
 ack public.imp_acks; b bytea;h text;z jsonb;r jsonb;rev jsonb;v jsonb;i uuid;n int;
begin
 select gm.papel into papel from public.gestao_membros gm join public.axe_rumo_revisores rv on rv.usuario_id=gm.usuario_id and rv.ativo where gm.usuario_id=p_usuario and gm.ativo;
 if papel is null or a<>'ack_arquivo' and papel<>'ADMIN' then raise exception 'Entrada compartilhada de e-mails restrita à administração AXE';end if;
 if a='ack_arquivo' then
  select af.* into f from public.imp_acks ak join public.axe_email_arquivos af on af.mensagem_id=ak.email_id and af.anexo_id=ak.anexo_id and af.sha256=ak.sha256 where ak.id=(p_dados->>'id')::uuid and ak.pronto;
  if not found then return null;end if;
  return jsonb_build_object('nome',f.nome,'caminho','email/'||f.id::text||'.pdf','sha256',f.sha256,'conteudo_base64',encode(f.conteudo,'base64'),'tipo_mime',f.tipo_mime);
 elsif a='email_arquivo' then
  select * into f from public.axe_email_arquivos where id=(p_dados->>'arquivo_id')::uuid;
  if not found then raise exception 'Anexo compartilhado não encontrado';end if;
  return jsonb_build_object('nome',f.nome,'caminho','email/'||f.id::text||'/'||f.sha256,'sha256',f.sha256,'conteudo_base64',encode(f.conteudo,'base64'),'tipo_mime',f.tipo_mime);
 elsif a='email_anexar' then
  if length(p_dados->>'conteudo_base64')>11300000 then raise exception 'Anexo excede 8 MB';end if;
  b:=decode(p_dados->>'conteudo_base64','base64');if b is null or octet_length(b) not between 1 and 8388608 then raise exception 'Anexo vazio ou acima de 8 MB';end if;h:=encode(sha256(b),'hex');
  select * into m from public.axe_email_mensagens where id=(p_dados->>'mensagem_id')::uuid;if not found then raise exception 'Registre a mensagem completa antes dos anexos';end if;
  select value into z from jsonb_array_elements(m.anexos) where value->>'anexo_id'=p_dados->>'anexo_id';
  if z is null or z->>'sha256' is distinct from h or nullif(z->>'nome','') is null or nullif(z->>'tipo_mime','') is null then raise exception 'Identificação ou hash do anexo diverge da mensagem';end if;
  if z->>'tipo_mime' not in ('application/pdf','application/xml','text/xml','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/octet-stream','text/plain','message/rfc822','image/jpeg','image/png','image/jpg','application/vnd.ms-excel','text/csv','application/csv','application/zip','application/x-zip-compressed','application/vnd.ms-outlook','image/gif','application/vnd.openxmlformats-officedocument.wordprocessingml.document') then raise exception 'Formato de anexo ainda não suportado';end if;
  perform pg_advisory_xact_lock(728102826);
  select * into f from public.axe_email_arquivos where mensagem_id=m.id and anexo_id=p_dados->>'anexo_id';
  if found then if f.sha256<>h then raise exception 'Anexo já armazenado com outro conteúdo';end if;return jsonb_build_object('arquivo_id',f.id,'sha256',h,'duplicado',true);end if;
  insert into public.axe_email_arquivos(mensagem_id,anexo_id,nome,tipo_mime,sha256,tamanho,conteudo,criado_por) values(m.id,p_dados->>'anexo_id',left(z->>'nome',240),z->>'tipo_mime',h,octet_length(b),b,p_usuario) returning id into i;
  return jsonb_build_object('arquivo_id',i,'sha256',h,'duplicado',false);
 elsif a='email_ack_propor' then
  perform pg_advisory_xact_lock(728102826);
  select * into f from public.axe_email_arquivos where id=(p_dados->>'arquivo_id')::uuid;
  if not found or f.tipo_mime<>'application/pdf' or substring(f.conteudo from 1 for 5)<>decode('255044462d','hex') then raise exception 'ACK exige o PDF original arquivado';end if;
  v:=p_dados->'extraido';rev:=jsonb_build_object('pedido',v->>'pedido','ack_numero',v->>'ack_numero','ack_data',v->>'ack_data','metodo','Pré-cadastro por análise de e-mail; aguarda aceite humano');
  if jsonb_typeof(v) is distinct from 'object' or nullif(btrim(v->>'pedido'),'') is null or nullif(btrim(v->>'ack_numero'),'') is null or length(v->>'ack_numero')>200 or coalesce(v->>'ack_data','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Número do pedido, ACK ou data ausentes; mantenha a pendência documental';end if;
  perform (v->>'ack_data')::date;
  select count(*) into n from public.imp_pedidos where referencia=v->>'pedido' and status<>'Cancelado';if n<>1 then raise exception 'Pedido ausente ou ambíguo; revisão necessária';end if;
  select * into pedido from public.imp_pedidos where referencia=v->>'pedido' and status<>'Cancelado';
  r:=public.axe_documentos_entrada_base(jsonb_build_object('acao','ack_reservar','requisicao_id',f.id,'pedido_id',pedido.id,'nome',f.nome,'tamanho',f.tamanho,'sha256',f.sha256,'paginas',coalesce(v->'paginas','[]'),'extraido',v,'revisado',rev,'email_id',f.mensagem_id,'anexo_id',f.anexo_id),p_usuario);
  i:=(r->>'id')::uuid;
  perform public.axe_documentos_entrada_base(jsonb_build_object('acao','ack_confirmar_arquivo','id',i),p_usuario);
  if exists(select 1 from public.axe_email_propostas where id=i) then return (select jsonb_build_object('id',id,'estado',estado,'duplicado',true) from public.axe_email_propostas where id=i);end if;
  return public.axe_documentos_entrada(jsonb_build_object('acao','email_propor','requisicao_id',i,'mensagem_id',f.mensagem_id,'agente','importacoes.ack','chave_processo','ack:'||i::text,'tipo','ACK','resumo','Confirmar ACK '||(v->>'ack_numero')||' do pedido '||pedido.referencia,'pendencias',coalesce(p_dados->'pendencias','[]'),'aplicacao',jsonb_build_object('acao','ack_aplicar','id',i,'versao',pedido.versao)),p_usuario);
 end if;
 raise exception 'Ação documental inválida';
end;$function$

