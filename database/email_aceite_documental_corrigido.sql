begin;
alter table public.imp_cambio_arquivos add column email_arquivo_id uuid references public.axe_email_arquivos(id);
alter table public.axe_email_propostas add column substituida_por uuid references public.axe_email_propostas(id);
CREATE OR REPLACE FUNCTION public.axe_documentos_entrada(p_dados jsonb, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare a text:=p_dados->>'acao'; papel text; p public.axe_email_propostas; d jsonb; r jsonb; i uuid; valido boolean; n int; fid bigint; fornecedor jsonb; ar jsonb; af public.axe_email_arquivos; arquivo uuid;
begin
 if a like 'email_%' and not exists(select 1 from public.gestao_membros gm2 where gm2.usuario_id=p_usuario and gm2.ativo and gm2.papel='ADMIN') then raise exception 'Entrada compartilhada restrita à administração AXE';end if;
 if a in ('email_anexar','email_ack_propor','email_arquivo') then return public.axe_email_documentos(p_dados,p_usuario);end if;
 if a='ack_arquivo' then r:=public.axe_email_documentos(p_dados,p_usuario);if r is not null then return r;end if;end if;
 if a='email_detalhe' then return public.axe_documentos_entrada_base(p_dados,p_usuario)||jsonb_build_object('arquivos',(select coalesce(jsonb_agg(jsonb_build_object('arquivo_id',id,'anexo_id',anexo_id,'nome',nome,'tipo_mime',tipo_mime,'sha256',sha256)),'[]') from public.axe_email_arquivos where mensagem_id=(p_dados->>'id')::uuid));end if;
 if a not in ('ack_localizar','email_propor','email_propostas_listar','email_proposta_detalhe','email_decidir') then return public.axe_documentos_entrada_base(p_dados,p_usuario);end if;
 select gm.papel into papel from public.gestao_membros gm join public.axe_rumo_revisores rv on rv.usuario_id=gm.usuario_id and rv.ativo where gm.usuario_id=p_usuario and gm.ativo;
 if papel is null then raise exception 'Usuário sem acesso aos pré-cadastros';end if;
 if a='ack_localizar' then
  select count(*) into n from public.imp_pedidos where upper(referencia)=upper(p_dados->>'referencia') and status<>'Cancelado';
  if n<>1 then raise exception 'Pedido do ACK ausente ou ambíguo. Encaminhe para revisão';end if;
  return (select jsonb_build_object('id',id,'versao',versao,'referencia',referencia,'status',status,'ack_numero',ack_numero,'ack_data',ack_data,'proposta',(select to_jsonb(q) from public.axe_email_propostas q where q.id=nullif(p_dados->>'requisicao_id','')::uuid)) from public.imp_pedidos where upper(referencia)=upper(p_dados->>'referencia') and status<>'Cancelado');
 end if;
 if a='email_propostas_listar' then
  return jsonb_build_object('linhas',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select pr.id,pr.tipo,pr.resumo,pr.estado,pr.pendencias,pr.criado_em,pr.decidido_em,m.remetente,m.assunto from public.axe_email_propostas pr join public.axe_email_mensagens m on m.id=pr.mensagem_id where pr.substituida_por is null and (coalesce(p_dados->>'estado','Pendente')='Todos' or pr.estado=coalesce(p_dados->>'estado','Pendente')) order by pr.criado_em desc limit 100 offset greatest(0,least(100000,coalesce((p_dados->>'pagina')::int,0)))*100)z));
 elsif a='email_proposta_detalhe' then
  select * into p from public.axe_email_propostas where id=(p_dados->>'id')::uuid;if not found then raise exception 'Pré-cadastro não encontrado';end if;
  if p.tipo='ACK' then
   select p.aplicacao||jsonb_build_object('alteracoes',jsonb_build_object('pedido',o.referencia,'situacao',jsonb_build_object('anterior',o.status,'novo','ACK recebido'),'numero_ack',jsonb_build_object('anterior',o.ack_numero,'novo',f.revisado->>'ack_numero'),'data_ack',jsonb_build_object('anterior',o.ack_data,'novo',f.revisado->>'ack_data')),'itens_documento',f.extraido->'itens','avisos',f.extraido->'avisos','condicoes',f.extraido->'condicoes') into d from public.imp_acks f join public.imp_pedidos o on o.id=f.pedido_id where f.id=(p.aplicacao->>'id')::uuid;
  else d:=p.aplicacao;end if;
  return to_jsonb(p)||jsonb_build_object('aplicacao',d,'arquivos',(select coalesce(jsonb_agg(jsonb_build_object('arquivo_id',id,'nome',nome,'tipo_mime',tipo_mime)),'[]') from public.axe_email_arquivos where mensagem_id=p.mensagem_id or id in (select (value->>'arquivo_id')::uuid from jsonb_array_elements(coalesce(p.aplicacao->'arquivos_documentais','[]')))),'mensagem',(select to_jsonb(m) from public.axe_email_mensagens m where m.id=p.mensagem_id));
 end if;
 if papel not in ('ADMIN','EDITOR') then raise exception 'Sem permissão para aprovar';end if;
 if octet_length(p_dados::text)>500000 then raise exception 'Pré-cadastro excede o limite';end if;
 perform pg_advisory_xact_lock(728102826);
 if a='email_propor' then
  d:=p_dados->'aplicacao';
  valido:=case p_dados->>'tipo'
   when 'GESTAO_TAREFA' then d->>'acao'='gestao_salvar' and d->'dados'->>'tipo'='tarefas'
   when 'COMERCIAL_OPORTUNIDADE' then d->>'acao'='comercial_salvar' and d->>'operacao'='oportunidade'
   when 'COMERCIAL_PROPOSTA' then d->>'acao'='comercial_salvar' and d->>'operacao'='proposta'
   when 'COMERCIAL_PEDIDO' then d->>'acao'='comercial_salvar' and d->>'operacao'='pedido'
   when 'ACK' then d->>'acao'='ack_aplicar'
   when 'PEDIDO_IMPORTACAO' then d->>'acao'='v2_salvar' and d->>'tipo'='pedidos'
   when 'PARCELA_IMPORTACAO' then d->>'acao'='v2_salvar' and d->>'tipo'='parcelas'
   when 'EMBARQUE' then d->>'acao'='v2_salvar' and d->>'tipo'='embarques'
   when 'CONTRATO_CAMBIO' then d->>'acao'='fx_salvar' and d->>'tipo'='contratos'
   when 'SWIFT' then d->>'acao'='fx_salvar' and d->>'tipo'='contratos'
   when 'DI_DUIMP' then d->>'acao'='fx_salvar' and d->>'tipo'='declaracoes'
   when 'NOTA_FISCAL' then d->>'acao'='nf_salvar'
   when 'FECHAMENTO' then d->>'acao'='fech_aplicar'
   when 'CUSTO_IMPORTACAO' then d->>'acao'='custo_salvar' and coalesce(d->>'finalizar','false')='false'
   else false end;
  if valido is distinct from true or jsonb_typeof(d) is distinct from 'object' then raise exception 'Tipo de pré-cadastro ou operação ainda sem processador habilitado';end if;
  if p_dados->>'tipo'='ACK' and not exists(select 1 from public.imp_acks f where f.id=(d->>'id')::uuid and f.pronto and f.email_id=(p_dados->>'mensagem_id')::uuid) then raise exception 'ACK precisa estar anexado à mensagem compartilhada';end if;
  select * into p from public.axe_email_propostas where mensagem_id=(p_dados->>'mensagem_id')::uuid and agente=p_dados->>'agente' and chave_processo=p_dados->>'chave_processo';
  if found then if p.aplicacao is distinct from d or p.tipo is distinct from p_dados->>'tipo' or p.resumo is distinct from p_dados->>'resumo' or p.pendencias is distinct from coalesce(p_dados->'pendencias','[]') then raise exception 'Pré-cadastro já registrado com outros dados. Crie nova etapa de revisão';end if;return jsonb_build_object('id',p.id,'duplicado',true);end if;
  i:=(p_dados->>'requisicao_id')::uuid;
  insert into public.axe_email_propostas(id,mensagem_id,agente,chave_processo,tipo,resumo,aplicacao,pendencias,criado_por) values(i,(p_dados->>'mensagem_id')::uuid,p_dados->>'agente',p_dados->>'chave_processo',p_dados->>'tipo',p_dados->>'resumo',d,coalesce(p_dados->'pendencias','[]'),p_usuario);
  if nullif(d->>'substitui_proposta_id','') is not null then
   update public.axe_email_propostas set substituida_por=i where id=(d->>'substitui_proposta_id')::uuid and mensagem_id=(p_dados->>'mensagem_id')::uuid and tipo=p_dados->>'tipo' and estado='Pendente' and substituida_por is null;
   if not found then raise exception 'Versão anterior não corresponde a este documento pendente';end if;
  end if;
  return jsonb_build_object('id',i,'duplicado',false);
 end if;
 select * into p from public.axe_email_propostas where id=(p_dados->>'id')::uuid for update;
 if not found then raise exception 'Pré-cadastro não encontrado';end if;
 if coalesce(p_dados->>'decisao','') not in ('Aprovar','Rejeitar') or p_dados->>'confirmado' is distinct from 'true' then raise exception 'Confirme o aceite ou a rejeição';end if;
 if p.estado<>'Pendente' then
  if (p.estado='Aprovado' and p_dados->>'decisao'='Aprovar') or (p.estado='Rejeitado' and p_dados->>'decisao'='Rejeitar') then return jsonb_build_object('id',p.id,'estado',p.estado,'resultado',p.resultado,'duplicado',true);end if;
  raise exception 'Pré-cadastro já decidido. Preserve o histórico';
 end if;
 if p_dados->>'decisao'='Rejeitar' then
  if nullif(btrim(p_dados->>'motivo'),'') is null then raise exception 'Informe o motivo da rejeição';end if;
  update public.axe_email_propostas set estado='Rejeitado',motivo=left(p_dados->>'motivo',2000),decidido_por=p_usuario,decidido_em=clock_timestamp() where id=p.id;
  return jsonb_build_object('id',p.id,'estado','Rejeitado');
 end if;
 if p.substituida_por is not null then raise exception 'Existe uma versão mais recente deste pré-cadastro';end if;
 if jsonb_array_length(p.pendencias)>0 then raise exception 'Resolva as pendências e gere nova versão antes de aprovar';end if;
  if p.tipo='CONTRATO_CAMBIO' and p.aplicacao ? 'arquivos_documentais' then
  if jsonb_array_length(p.aplicacao->'arquivos_documentais')=0 then raise exception 'Anexe os documentos originais antes do aceite';end if;
  for ar in select value from jsonb_array_elements(p.aplicacao->'arquivos_documentais') loop
   select * into af from public.axe_email_arquivos where id=(ar->>'arquivo_id')::uuid;
   if not found or af.sha256 is distinct from ar->>'sha256' or encode(sha256(af.conteudo),'hex')<>af.sha256 or ar->>'categoria' not in ('CONTRATO','SWIFT') then raise exception 'Documento original ausente ou divergente';end if;
  end loop;
  fornecedor:=p.aplicacao->'fornecedor_proposto';
  if nullif(p.aplicacao->'dados'->>'fornecedor_id','') is null and fornecedor is not null then
   if nullif(btrim(fornecedor->>'razao_social'),'') is null or coalesce(fornecedor->>'pais','') !~ '^[A-Z]{2}$' then raise exception 'Dados oficiais do fornecedor incompletos';end if;
   select count(*),min(id) into n,fid from public.fornecedores where upper(btrim(razao_social))=upper(btrim(fornecedor->>'razao_social')) and pais=fornecedor->>'pais';
   if n>1 then raise exception 'Fornecedor ambíguo; escolha o cadastro existente';end if;
   if n=0 then
    if fornecedor->>'pais'<>'BR' and nullif(fornecedor->>'documento_fiscal','') is null then
     -- Documentary basic registration: keep an absent foreign tax ID null; never invent one.
     perform pg_advisory_xact_lock(hashtextextended('axe_catalogo_salvar',0));
     insert into public.fornecedores(razao_social,pais,endereco,ativo) values(btrim(fornecedor->>'razao_social'),fornecedor->>'pais',nullif(btrim(fornecedor->>'endereco'),''),true) returning id into fid;
     insert into public.catalogo_alteracoes(tipo,registro_id,usuario_id,anterior,atual) values('fornecedor',fid,p_usuario,null,(select to_jsonb(x) from public.fornecedores x where id=fid)||jsonb_build_object('proposta_origem',p.id));
    else
     r:=public.axe_catalogo_salvar('fornecedor',fornecedor||jsonb_build_object('requisicao_id',p.id,'ativo',true),p_usuario);
     fid:=(r->>'id')::bigint;
    end if;
   end if;
   if fid is null then raise exception 'Fornecedor não cadastrado';end if;
   perform public.axe_exigir_cadastro_liberado('fornecedor',fid);
   p.aplicacao:=jsonb_set(p.aplicacao,'{dados,fornecedor_id}',to_jsonb(fid));
   update public.axe_email_propostas set aplicacao=p.aplicacao where id=p.id;
  end if;
 end if;
 d:=p.aplicacao||jsonb_build_object('requisicao_id',p.id,'confirmado',true);
 if p.tipo='GESTAO_TAREFA' and d->'dados'->'propriedades'->>'Status'='Concluída' then
  if nullif(btrim(d->'conclusao'->>'feito'),'') is null or coalesce(d->'conclusao'->>'data','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Conclusão exige o que foi feito e a data informada';end if;perform (d->'conclusao'->>'data')::date;
 end if;
 if p.tipo='GESTAO_TAREFA' then r:=public.axe_gestao_salvar((d->'dados')||jsonb_build_object('requisicao_id',p.id),p_usuario);
 elsif p.tipo in ('COMERCIAL_OPORTUNIDADE','COMERCIAL_PROPOSTA','COMERCIAL_PEDIDO') then r:=public.axe_comercial_salvar(d->>'operacao',(d->'dados')||jsonb_build_object('requisicao_id',p.id),p_usuario);
 elsif p.tipo='ACK' then r:=public.axe_documentos_entrada_base(d,p_usuario);
 elsif p.tipo in ('PEDIDO_IMPORTACAO','PARCELA_IMPORTACAO','EMBARQUE') then r:=public.axe_imp_estrutura(d,p_usuario);
 elsif p.tipo in ('CONTRATO_CAMBIO','SWIFT','DI_DUIMP') then r:=public.axe_imp_financeiro(d,p_usuario);
 elsif p.tipo='NOTA_FISCAL' then r:=public.axe_imp_notas(d,p_usuario);
 elsif p.tipo='FECHAMENTO' then r:=public.axe_imp_fechamentos(d,p_usuario);
 elsif p.tipo='CUSTO_IMPORTACAO' then r:=public.axe_imp_custos(d,p_usuario);
 else raise exception 'Processador não habilitado';end if;
  if p.tipo='CONTRATO_CAMBIO' and p.aplicacao ? 'arquivos_documentais' then
  for ar in select value from jsonb_array_elements(p.aplicacao->'arquivos_documentais') loop
   select * into af from public.axe_email_arquivos where id=(ar->>'arquivo_id')::uuid;
   select id into arquivo from public.imp_cambio_arquivos where contrato_id=(r->>'id')::uuid and categoria=ar->>'categoria' and sha256=af.sha256;
   if arquivo is null then
    arquivo:=gen_random_uuid();
    insert into public.imp_cambio_arquivos(id,contrato_id,categoria,nome,sha256,tamanho,caminho,pronto,criado_por,email_arquivo_id)
    values(arquivo,(r->>'id')::uuid,ar->>'categoria',af.nome,af.sha256,af.tamanho,'email/'||af.id::text||'/'||af.sha256,true,p_usuario,af.id);
    insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual) values('fx_contratos',(r->>'id')::uuid,p_usuario,null,jsonb_build_object('evento','Original de e-mail vinculado após aceite','arquivo_id',arquivo,'origem_arquivo_id',af.id,'sha256',af.sha256,'proposta_id',p.id));
   end if;
  end loop;
 end if;
 update public.axe_email_propostas set estado='Aprovado',resultado=r,decidido_por=p_usuario,decidido_em=clock_timestamp() where id=p.id;
 return jsonb_build_object('id',p.id,'estado','Aprovado','resultado',r);
end;$function$;


CREATE OR REPLACE FUNCTION public.axe_cambio_arquivos(p_dados jsonb, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare a text:=p_dados->>'acao'; papel text; c public.imp_fin_documentos; f public.imp_cambio_arquivos; cid uuid; i uuid; linhas jsonb; original public.axe_email_arquivos;
begin
 select m.papel into papel from public.gestao_membros m join public.axe_rumo_revisores r on r.usuario_id=m.usuario_id and r.ativo where m.usuario_id=p_usuario and m.ativo;
 if papel is null then raise exception 'Usuário sem acesso ao financeiro cambial';end if;
 if a not in ('fxdoc_listar','fxdoc_reservar','fxdoc_confirmar','fxdoc_arquivo') or a is null then raise exception 'Ação inválida';end if;
 if a in ('fxdoc_reservar','fxdoc_confirmar') and papel not in ('ADMIN','EDITOR') then raise exception 'Sem permissão para anexar';end if;
 perform pg_advisory_xact_lock(728102826);
 if a in ('fxdoc_confirmar','fxdoc_arquivo') then
  select * into f from public.imp_cambio_arquivos where id=(p_dados->>'id')::uuid;
  if not found then raise exception 'Anexo não encontrado';end if;cid:=f.contrato_id;
 else cid:=(p_dados->>'contrato_id')::uuid;end if;
 select * into c from public.imp_fin_documentos where id=cid and tipo='contratos';
 if not found then raise exception 'Contrato não encontrado';end if;
 if a='fxdoc_listar' then
  select coalesce(jsonb_agg(jsonb_build_object('id',z.id,'categoria',z.categoria,'nome',z.nome,'tamanho',z.tamanho,'criado_em',z.criado_em) order by z.criado_em),'[]') into linhas from public.imp_cambio_arquivos z where z.contrato_id=cid and z.pronto;
  return jsonb_build_object('linhas',linhas);
 elsif a='fxdoc_reservar' then
  if c.status<>'Ativo' then raise exception 'Contrato cancelado não admite novos anexos';end if;
  i:=(p_dados->>'requisicao_id')::uuid;if i is null then raise exception 'Identificador obrigatório';end if;
  select * into f from public.imp_cambio_arquivos where id=i;
  if found then
   if f.contrato_id<>cid or f.categoria is distinct from p_dados->>'categoria' or f.sha256 is distinct from p_dados->>'sha256' or f.nome is distinct from p_dados->>'nome' or f.tamanho is distinct from (p_dados->>'tamanho')::int then raise exception 'Identificador reutilizado com outros dados';end if;
  else
   select * into f from public.imp_cambio_arquivos where contrato_id=cid and categoria=p_dados->>'categoria' and sha256=p_dados->>'sha256';
   if not found then
    insert into public.imp_cambio_arquivos(id,contrato_id,categoria,nome,sha256,tamanho,caminho,criado_por)
    values(i,cid,p_dados->>'categoria',p_dados->>'nome',p_dados->>'sha256',(p_dados->>'tamanho')::int,cid::text||'/'||i::text||'.pdf',p_usuario) returning * into f;
   end if;
  end if;
 elsif a='fxdoc_confirmar' then
  if not f.pronto then
   update public.imp_cambio_arquivos set pronto=true where id=f.id;
   insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual) values('fx_contratos',cid,p_usuario,null,jsonb_build_object('evento','Anexo adicionado','arquivo_id',f.id,'categoria',f.categoria,'nome',f.nome,'sha256',f.sha256));
  end if;
 elsif not f.pronto then raise exception 'Envio do arquivo incompleto';end if;
 if a='fxdoc_arquivo' and f.email_arquivo_id is not null then
 select * into original from public.axe_email_arquivos where id=f.email_arquivo_id and sha256=f.sha256;
 if not found or encode(sha256(original.conteudo),'hex')<>f.sha256 then raise exception 'Integridade do original não confirmada';end if;
 return to_jsonb(f)||jsonb_build_object('conteudo_base64',encode(original.conteudo,'base64'),'tipo_mime',original.tipo_mime);
 end if;
 return to_jsonb(f);
end $function$;


commit;