-- Etapas comerciais e recebimento do pedido de compra.
begin;
CREATE OR REPLACE FUNCTION public.axe_imp_nf_proteger_origem()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare bloqueado boolean:=false;
begin
 perform pg_advisory_xact_lock(728102826);
 if tg_table_name='imp_fin_documentos' then
  select exists(select 1 from public.imp_nota_vinculos v join public.imp_notas n on n.id=v.nota_id where v.declaracao_id=old.id and n.estado='Conciliada') into bloqueado;
  if tg_op='UPDATE' and (to_jsonb(new)-array['versao','atualizado_em','atualizado_por'])=(to_jsonb(old)-array['versao','atualizado_em','atualizado_por']) then bloqueado:=false;end if;
 elsif tg_table_name='imp_fin_pedidos' then
  select exists(select 1 from public.imp_nota_vinculos v join public.imp_notas n on n.id=v.nota_id join public.imp_pedido_itens pi on pi.id=v.pedido_item_id where v.declaracao_id=old.documento_id and pi.pedido_id=old.pedido_id and n.estado='Conciliada') into bloqueado;
 elsif tg_table_name='imp_pedido_itens' then
  select exists(select 1 from public.imp_nota_vinculos v join public.imp_notas n on n.id=v.nota_id where v.pedido_item_id=old.id and n.estado='Conciliada') into bloqueado;
  if tg_op='UPDATE' and (to_jsonb(new)-array['disponibilizada','data_disponibilidade'])=(to_jsonb(old)-array['disponibilizada','data_disponibilidade']) then bloqueado:=false;end if;
 elsif tg_table_name='imp_pedidos' then
  select exists(select 1 from public.imp_nota_vinculos v join public.imp_notas n on n.id=v.nota_id join public.imp_pedido_itens pi on pi.id=v.pedido_item_id where pi.pedido_id=old.id and n.estado='Conciliada') into bloqueado;
  if tg_op='UPDATE' and new.referencia=old.referencia and new.fornecedor_id=old.fornecedor_id and new.moeda=old.moeda and (new.status=old.status or (new.status in ('Elaboração','Enviado','Aceito -ACK','Aguardando Recebimento','Recebimento Parcial','Recebido') and old.status in ('Rascunho','Emitido','ACK recebido','Elaboração','Enviado','Aceito -ACK','Aguardando Recebimento','Recebimento Parcial','Recebido'))) then bloqueado:=false;end if;
 end if;
 if bloqueado then raise exception 'Origem possui nota conciliada. Reabra a conciliação antes de alterar o vínculo';end if;
 return case when tg_op='DELETE' then old else new end;
end $function$;

alter table public.imp_pedidos drop constraint imp_pedidos_status_check;
alter table public.imp_pedidos alter column status set default 'Elaboração';
-- A atualização de nomes preserva as demais informações do pedido.
with alterados as (
 update public.imp_pedidos set status=case status when 'Rascunho' then 'Elaboração' when 'Emitido' then 'Enviado' when 'ACK recebido' then 'Aceito -ACK' else status end,
 versao=versao+1,atualizado_em=clock_timestamp()
 where status in ('Rascunho','Emitido','ACK recebido')
 returning id,status,atualizado_por
)
insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)
select 'pedidos',id,atualizado_por,jsonb_build_object('status',case status when 'Elaboração' then 'Rascunho' when 'Enviado' then 'Emitido' else 'ACK recebido' end),jsonb_build_object('status',status,'origem','Padronização das etapas do pedido') from alterados;
alter table public.imp_pedidos add constraint imp_pedidos_status_check check(status in ('Elaboração','Enviado','Aceito -ACK','Aguardando Recebimento','Recebimento Parcial','Recebido','Cancelado'));

create or replace function public.axe_imp_recalcular_status_pedido(pid uuid) returns void
language plpgsql set search_path='' as $fn$
declare p public.imp_pedidos; novo text; itens int; completos int; recebidos numeric; embarcado boolean;
begin
 select * into p from public.imp_pedidos where id=pid for update;
 if not found or p.status='Cancelado' then return;end if;
 select count(*),count(*) filter(where recebida>=quantidade),coalesce(sum(recebida),0) into itens,completos,recebidos
 from (select pi.quantidade,coalesce((select sum(ei.recebida) from public.imp_embarque_itens ei join public.imp_embarques e on e.id=ei.embarque_id where ei.pedido_item_id=pi.id and e.status<>'Cancelado'),0) recebida from public.imp_pedido_itens pi where pi.pedido_id=pid) s;
 select exists(select 1 from public.imp_embarque_itens ei join public.imp_pedido_itens pi on pi.id=ei.pedido_item_id join public.imp_embarques e on e.id=ei.embarque_id where pi.pedido_id=pid and e.status<>'Cancelado') into embarcado;
 novo:=case when itens>0 and completos=itens then 'Recebido' when recebidos>0 then 'Recebimento Parcial' when embarcado then 'Aguardando Recebimento' when p.status in ('Recebido','Recebimento Parcial') then case when p.ack_numero is not null and p.ack_data is not null then 'Aceito -ACK' else 'Enviado' end else p.status end;
 if novo is distinct from p.status then
  update public.imp_pedidos set status=novo,versao=versao+1,atualizado_em=clock_timestamp() where id=pid;
  insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('pedidos',pid,p.atualizado_por,jsonb_build_object('status',p.status),jsonb_build_object('status',novo,'origem','Quantidades dos itens e embarques ativos'));
 end if;
end $fn$;
revoke all on function public.axe_imp_recalcular_status_pedido(uuid) from public,anon,authenticated;
grant execute on function public.axe_imp_recalcular_status_pedido(uuid) to service_role;

create or replace function public.axe_imp_status_pedido_evento() returns trigger
language plpgsql set search_path='' as $fn$
declare pid uuid;r record;
begin
 if tg_table_name='imp_pedidos' then
  pid:=case when tg_op='DELETE' then old.id else new.id end;perform public.axe_imp_recalcular_status_pedido(pid);
 elsif tg_table_name='imp_embarques' then
  for r in select distinct pi.pedido_id from public.imp_pedido_itens pi join public.imp_embarque_itens ei on ei.pedido_item_id=pi.id where ei.embarque_id=case when tg_op='DELETE' then old.id else new.id end loop perform public.axe_imp_recalcular_status_pedido(r.pedido_id);end loop;
 elsif tg_table_name='imp_pedido_itens' then
  if tg_op<>'INSERT' then perform public.axe_imp_recalcular_status_pedido(old.pedido_id);end if;
  if tg_op<>'DELETE' then perform public.axe_imp_recalcular_status_pedido(new.pedido_id);end if;
 else
  if tg_op<>'INSERT' then select pedido_id into pid from public.imp_pedido_itens where id=old.pedido_item_id;perform public.axe_imp_recalcular_status_pedido(pid);end if;
  if tg_op<>'DELETE' then select pedido_id into pid from public.imp_pedido_itens where id=new.pedido_item_id;perform public.axe_imp_recalcular_status_pedido(pid);end if;
 end if;return null;
end $fn$;
revoke all on function public.axe_imp_status_pedido_evento() from public,anon,authenticated;
create constraint trigger imp_pedido_status_recalcular after insert or update on public.imp_pedidos deferrable initially deferred for each row execute function public.axe_imp_status_pedido_evento();
create constraint trigger imp_embarque_status_pedido after insert or update or delete on public.imp_embarques deferrable initially deferred for each row execute function public.axe_imp_status_pedido_evento();
create constraint trigger imp_embarque_itens_status_pedido after insert or update or delete on public.imp_embarque_itens deferrable initially deferred for each row execute function public.axe_imp_status_pedido_evento();
create constraint trigger imp_pedido_itens_status_pedido after insert or update or delete on public.imp_pedido_itens deferrable initially deferred for each row execute function public.axe_imp_status_pedido_evento();

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
   select p.aplicacao||jsonb_build_object('alteracoes',jsonb_build_object('pedido',o.referencia,'situacao',jsonb_build_object('anterior',o.status,'novo','Aceito -ACK'),'numero_ack',jsonb_build_object('anterior',o.ack_numero,'novo',f.revisado->>'ack_numero'),'data_ack',jsonb_build_object('anterior',o.ack_data,'novo',f.revisado->>'ack_data')),'itens_documento',f.extraido->'itens','avisos',f.extraido->'avisos','condicoes',f.extraido->'condicoes') into d from public.imp_acks f join public.imp_pedidos o on o.id=f.pedido_id where f.id=(p.aplicacao->>'id')::uuid;
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

CREATE OR REPLACE FUNCTION public.axe_imp_estrutura(p_dados jsonb, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
 acao text:=p_dados->>'acao'; t text:=p_dados->>'tipo'; d jsonb:=p_dados->'dados';
 papel text; i uuid; req uuid; r record; antes jsonb; atual jsonb; resultado jsonb;
 x jsonb; k text; itemid uuid; item public.imp_pedido_itens; pedido public.imp_pedidos;
 total numeric; valor numeric; pago numeric; pct numeric; qtd numeric; usada numeric;
 receb numeric; pronta numeric; parcela_id uuid; vers int; fornecedor bigint; moeda text; st text;
 pagina int; busca text; linhas jsonb; cont bigint; base date; venc date; dias int;
begin
 select m.papel into papel from public.gestao_membros m join public.axe_rumo_revisores rv on rv.usuario_id=m.usuario_id and rv.ativo where m.usuario_id=p_usuario and m.ativo;
 if papel is null then raise exception 'Usuário sem acesso às importações';end if;
 if acao='v2_opcoes' then return jsonb_build_object('editar',papel in ('ADMIN','EDITOR'),'fornecedores',(select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'nome',f.razao_social) order by f.razao_social),'[]') from public.fornecedores f where ativo));end if;
 if coalesce(t,'') not in ('pedidos','parcelas','embarques') then raise exception 'Seção inválida';end if;
 if acao='v2_detalhe' then
  resultado:=public.axe_imp_estrutura_detalhe(t,(p_dados->>'id')::uuid);
  if resultado is null then raise exception 'Registro não encontrado';end if;return resultado;
 elsif acao='v2_historico' then
  return jsonb_build_object('linhas',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from (select * from public.imp_estrutura_eventos where tipo=t and registro_id=(p_dados->>'id')::uuid order by id desc limit 100)z));
 elsif acao in ('v2_listar','v2_catalogo') then
  pagina:=coalesce((p_dados->>'pagina')::int,0);busca:=left(coalesce(p_dados->>'busca',''),200);
  if pagina<0 or pagina>100000 then raise exception 'Página inválida';end if;
  if acao='v2_catalogo' then
   fornecedor:=(p_dados->>'fornecedor_id')::bigint;
   select count(*) into cont from public.imp_pedido_itens x join public.imp_pedidos p on p.id=x.pedido_id where p.fornecedor_id=fornecedor and p.status<>'Cancelado' and (busca='' or (p.referencia||' '||x.descricao||' '||coalesce(x.codigo_fornecedor,'')) ilike '%'||busca||'%');
   select coalesce(jsonb_agg(to_jsonb(z)),'[]') into linhas from (
    select x.*,p.referencia pedido,p.moeda,
    coalesce((select sum(ei.quantidade) from public.imp_embarque_itens ei join public.imp_embarques e on e.id=ei.embarque_id where ei.pedido_item_id=x.id and e.status<>'Cancelado' and e.id is distinct from nullif(p_dados->>'embarque_id','')::uuid),0) reservada
    from public.imp_pedido_itens x join public.imp_pedidos p on p.id=x.pedido_id where p.fornecedor_id=fornecedor and p.status<>'Cancelado' and (busca='' or (p.referencia||' '||x.descricao||' '||coalesce(x.codigo_fornecedor,'')) ilike '%'||busca||'%') order by p.referencia,x.linha limit 30 offset pagina*30)z;
  elsif t='pedidos' then
  if acao='v2_salvar' then d:=public.axe_imp_pedido_catalogo(d);end if;
   select count(*) into cont from public.imp_pedidos where referencia ilike '%'||busca||'%';
   select coalesce(jsonb_agg(to_jsonb(z)),'[]') into linhas from (
    select p.*,f.razao_social fornecedor,
    (select coalesce(sum(round(x.quantidade*x.valor_unitario,2)),0) from public.imp_pedido_itens x where x.pedido_id=p.id) total,
    (select coalesce(sum(x.valor),0) from public.imp_parcelas x where x.pedido_id=p.id and x.status<>'Cancelada') parcelado,
    (select coalesce(sum(x.valor_pago),0) from public.imp_parcelas x where x.pedido_id=p.id) pago
    from public.imp_pedidos p join public.fornecedores f on f.id=p.fornecedor_id where p.referencia ilike '%'||busca||'%' order by p.atualizado_em desc,p.id limit 30 offset pagina*30)z;
  elsif t='parcelas' then
   select count(*) into cont from public.imp_parcelas x join public.imp_pedidos p on p.id=x.pedido_id where (x.referencia||' '||p.referencia) ilike '%'||busca||'%';
   select coalesce(jsonb_agg(to_jsonb(z)),'[]') into linhas from (
    select x.*,p.referencia pedido,p.moeda from public.imp_parcelas x join public.imp_pedidos p on p.id=x.pedido_id where (x.referencia||' '||p.referencia) ilike '%'||busca||'%' order by x.vencimento nulls last,x.id limit 30 offset pagina*30)z;
  else
   select count(*) into cont from public.imp_embarques where referencia ilike '%'||busca||'%';
   select coalesce(jsonb_agg(to_jsonb(z)),'[]') into linhas from (
    select e.*,f.razao_social fornecedor,
    (select coalesce(sum(round(x.quantidade*pi.valor_unitario,2)),0) from public.imp_embarque_itens x join public.imp_pedido_itens pi on pi.id=x.pedido_item_id where x.embarque_id=e.id) total
    from public.imp_embarques e join public.fornecedores f on f.id=e.fornecedor_id where e.referencia ilike '%'||busca||'%' order by e.atualizado_em desc,e.id limit 30 offset pagina*30)z;
  end if;
  return jsonb_build_object('linhas',linhas,'total',cont);
 end if;
 if acao is distinct from 'v2_salvar' then raise exception 'Ação inválida';end if;
 if papel not in ('ADMIN','EDITOR') then raise exception 'Sem permissão para editar';end if;
 if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>400000 then raise exception 'Dados inválidos ou muito extensos';end if;
 req:=(p_dados->>'requisicao_id')::uuid;if req is null then raise exception 'Identificador da operação obrigatório';end if;
 -- Serializes allocations, schedule totals and order edits consistently.
 perform pg_advisory_xact_lock(728102826);
 select * into r from public.imp_requisicoes where usuario_id=p_usuario and requisicao_id=req;
 if found then if r.dados is distinct from p_dados then raise exception 'Identificador reutilizado com outros dados';end if;return r.resultado;end if;
 i:=nullif(p_dados->>'id','')::uuid;
 if i is not null then
  antes:=public.axe_imp_estrutura_detalhe(t,i);
  if antes is null then raise exception 'Registro não encontrado';end if;
  if (antes->>'versao')::int is distinct from (p_dados->>'versao')::int then raise exception 'Registro alterado. Reabra antes de salvar';end if;
 else i:=gen_random_uuid();end if;
 if nullif(btrim(d->>'referencia'),'') is null or length(d->>'referencia')>200 then raise exception 'Informe referência de até 200 caracteres';end if;
 if t='pedidos' then
  if acao='v2_salvar' then d:=public.axe_imp_pedido_catalogo(d);end if;
  fornecedor:=(d->>'fornecedor_id')::bigint;moeda:=d->>'moeda';st:=d->>'status';
  if fornecedor is null or moeda is null or st is null then raise exception 'Fornecedor, moeda e situação obrigatórios';end if;
  if antes is not null and ((antes->>'fornecedor_id')::bigint<>fornecedor or antes->>'moeda'<>moeda) then
   if exists(select 1 from public.imp_parcelas where pedido_id=i) or exists(select 1 from public.imp_pedido_itens pi join public.imp_embarque_itens ei on ei.pedido_item_id=pi.id where pi.pedido_id=i) then raise exception 'Fornecedor e moeda não podem mudar após parcelas ou embarques';end if;
  end if;
  if jsonb_typeof(d->'itens') is distinct from 'array' or jsonb_array_length(d->'itens') not between 1 and 100 then raise exception 'Informe de 1 a 100 itens';end if;
  if exists(select 1 from public.imp_pedido_itens pi where pi.pedido_id=i and not exists(select 1 from jsonb_array_elements(d->'itens') z where nullif(z->>'id','')::uuid=pi.id) and exists(select 1 from public.imp_embarque_itens ei where ei.pedido_item_id=pi.id)) then raise exception 'Item com histórico de embarque não pode ser removido';end if;
  if exists(select 1 from jsonb_array_elements(d->'itens') z group by z->>'id' having count(*)>1) or exists(select 1 from jsonb_array_elements(d->'itens') z group by z->>'linha' having count(*)>1) then raise exception 'ID ou linha de item duplicado';end if;
  total:=0;
  for x in select value from jsonb_array_elements(d->'itens') loop
   itemid:=(x->>'id')::uuid;qtd:=(x->>'quantidade')::numeric;valor:=(x->>'valor_unitario')::numeric;pronta:=coalesce(nullif(x->>'disponibilizada','')::numeric,0);
   if itemid is null or nullif(btrim(x->>'linha'),'') is null or nullif(btrim(x->>'descricao'),'') is null or nullif(btrim(x->>'unidade'),'') is null or qtd is null or qtd<=0 or qtd>=1e12 or valor is null or valor<0 or valor>=1e12 or pronta<0 or pronta>qtd then raise exception 'Revise identificação, unidade, quantidades e preço dos itens';end if;
   if exists(select 1 from public.imp_pedido_itens pi where pi.id=itemid and (pi.valor_unitario<>valor or pi.unidade<>x->>'unidade') and exists(select 1 from public.imp_embarque_itens ei where ei.pedido_item_id=pi.id)) then raise exception 'Preço e unidade de item com embarque devem ser preservados';end if;
   if exists(select 1 from public.imp_pedido_itens where id=itemid and pedido_id<>i) then raise exception 'Item pertence a outro pedido';end if;
   select coalesce(sum(ei.quantidade),0) into usada from public.imp_embarque_itens ei join public.imp_embarques e on e.id=ei.embarque_id where ei.pedido_item_id=itemid and e.status<>'Cancelado';
   if qtd<usada then raise exception 'Quantidade menor que o total já reservado em embarques';end if;
   select coalesce(sum(ei.quantidade),0) into usada from public.imp_embarque_itens ei join public.imp_embarques e on e.id=ei.embarque_id where ei.pedido_item_id=itemid and e.status not in ('Cancelado','Planejamento');
   if pronta<usada then raise exception 'Disponibilidade menor que a quantidade dos embarques liberados';end if;
   total:=total+round(qtd*valor,2);
  end loop;
  select coalesce(sum(pp.valor),0) into valor from public.imp_parcelas pp where pp.pedido_id=i and pp.status<>'Cancelada';
  if total<valor then raise exception 'Total do pedido menor que as parcelas já programadas';end if;
  if st='Cancelado' and (exists(select 1 from public.imp_parcelas where pedido_id=i and status<>'Cancelada') or exists(select 1 from public.imp_pedido_itens pi join public.imp_embarque_itens ei on ei.pedido_item_id=pi.id join public.imp_embarques e on e.id=ei.embarque_id where pi.pedido_id=i and e.status<>'Cancelado')) then raise exception 'Cancele as parcelas e embarques antes do pedido';end if;
  if st='Aceito -ACK' and (nullif(btrim(d->>'ack_numero'),'') is null or nullif(d->>'ack_data','') is null) then raise exception 'Informe número e data do ACK';end if;
  insert into public.imp_pedidos(id,fornecedor_id,referencia,moeda,status,data_pedido,ack_numero,ack_data,condicao_pagamento,observacoes,atualizado_por)
   values(i,fornecedor,btrim(d->>'referencia'),moeda,st,nullif(d->>'data_pedido','')::date,d->>'ack_numero',nullif(d->>'ack_data','')::date,d->>'condicao_pagamento',d->>'observacoes',p_usuario)
   on conflict(id) do update set fornecedor_id=excluded.fornecedor_id,referencia=excluded.referencia,moeda=excluded.moeda,status=excluded.status,data_pedido=excluded.data_pedido,ack_numero=excluded.ack_numero,ack_data=excluded.ack_data,condicao_pagamento=case when d ? 'condicao_pagamento' then excluded.condicao_pagamento else imp_pedidos.condicao_pagamento end,observacoes=excluded.observacoes,versao=imp_pedidos.versao+1,atualizado_por=p_usuario,atualizado_em=clock_timestamp();
  delete from public.imp_pedido_itens pi where pi.pedido_id=i and not exists(select 1 from jsonb_array_elements(d->'itens') z where (z->>'id')::uuid=pi.id);
  for x in select value from jsonb_array_elements(d->'itens') loop
   insert into public.imp_pedido_itens(produto_id,id,pedido_id,linha,codigo_axe,codigo_fornecedor,descricao,unidade,quantidade,valor_unitario,peso_bruto_unitario,disponibilizada,data_disponibilidade)
   values((x->>'produto_id')::bigint,(x->>'id')::uuid,i,btrim(x->>'linha'),x->>'codigo_axe',x->>'codigo_fornecedor',x->>'descricao',x->>'unidade',(x->>'quantidade')::numeric,(x->>'valor_unitario')::numeric,nullif(x->>'peso_bruto_unitario','')::numeric,coalesce(nullif(x->>'disponibilizada','')::numeric,0),nullif(x->>'data_disponibilidade','')::date)
   on conflict(id) do update set produto_id=excluded.produto_id,linha=excluded.linha,codigo_axe=excluded.codigo_axe,codigo_fornecedor=excluded.codigo_fornecedor,descricao=excluded.descricao,unidade=excluded.unidade,quantidade=excluded.quantidade,valor_unitario=excluded.valor_unitario,peso_bruto_unitario=excluded.peso_bruto_unitario,disponibilizada=excluded.disponibilizada,data_disponibilidade=excluded.data_disponibilidade;
  end loop;
 elsif t='parcelas' then
  select * into pedido from public.imp_pedidos where id=(d->>'pedido_id')::uuid;
  if not found or pedido.status='Cancelado' then raise exception 'Pedido não encontrado ou cancelado';end if;
  if antes is not null and antes->>'pedido_id'<>pedido.id::text then raise exception 'Não é possível trocar o pedido da parcela';end if;
  select coalesce(sum(round(pi.quantidade*pi.valor_unitario,2)),0) into total from public.imp_pedido_itens pi where pi.pedido_id=pedido.id;
  if d->>'modo'='Percentual' then pct:=(d->>'percentual')::numeric;if pct is null or pct<=0 or pct>100 then raise exception 'Percentual deve ser maior que zero e até 100';end if;valor:=round(total*pct/100,2);
  elsif d->>'modo'='Valor' then valor:=(d->>'valor')::numeric;
  else raise exception 'Modo da parcela inválido';end if;
  if valor is null or valor<=0 or valor>=1e12 then raise exception 'Valor da parcela inválido';end if;
  if d->>'status'='Prevista' and valor+(select coalesce(sum(p.valor),0) from public.imp_parcelas p where p.pedido_id=pedido.id and p.id<>i and p.status<>'Cancelada')>total then raise exception 'Parcelas ultrapassam o valor do pedido';end if;
  pago:=coalesce(nullif(d->>'valor_pago','')::numeric,0);
  if pago<0 or pago>valor or pago::text in ('NaN','Infinity','-Infinity') then raise exception 'Pagamento deve estar entre zero e o valor da parcela';end if;
  dias:=coalesce(nullif(d->>'dias','')::int,0);base:=nullif(d->>'data_base','')::date;
  if d->>'marco'='Manual' then venc:=nullif(d->>'vencimento','')::date;else venc:=base+dias;end if;
  insert into public.imp_parcelas(id,pedido_id,referencia,modo,percentual,valor,marco,data_base,dias,vencimento,proforma,status,valor_pago,data_pagamento,cambio,contrato_cambio,observacoes,atualizado_por)
  values(i,pedido.id,d->>'referencia',d->>'modo',pct,valor,d->>'marco',base,dias,venc,d->>'proforma',d->>'status',pago,nullif(d->>'data_pagamento','')::date,nullif(d->>'cambio','')::numeric,d->>'contrato_cambio',d->>'observacoes',p_usuario)
  on conflict(id) do update set referencia=excluded.referencia,modo=excluded.modo,percentual=excluded.percentual,valor=excluded.valor,marco=excluded.marco,data_base=excluded.data_base,dias=excluded.dias,vencimento=excluded.vencimento,proforma=excluded.proforma,status=excluded.status,valor_pago=excluded.valor_pago,data_pagamento=excluded.data_pagamento,cambio=excluded.cambio,contrato_cambio=excluded.contrato_cambio,observacoes=excluded.observacoes,versao=imp_parcelas.versao+1,atualizado_por=p_usuario,atualizado_em=clock_timestamp();
 else
  fornecedor:=(d->>'fornecedor_id')::bigint;moeda:=d->>'moeda';st:=d->>'status';
  if fornecedor is null or moeda is null or st is null then raise exception 'Fornecedor, moeda e situação obrigatórios';end if;
  if jsonb_typeof(d->'itens') is distinct from 'array' or jsonb_array_length(d->'itens') not between 1 and 100 then raise exception 'Selecione de 1 a 100 itens de pedidos';end if;
  if exists(select 1 from jsonb_array_elements(d->'itens') z group by z->>'pedido_item_id' having count(*)>1) then raise exception 'Item duplicado no embarque';end if;
  if exists(select 1 from public.imp_embarque_itens ei where ei.embarque_id=i and ei.recebida>0 and (not exists(select 1 from jsonb_array_elements(d->'itens') z where (z->>'pedido_item_id')::uuid=ei.pedido_item_id) or st='Cancelado')) then raise exception 'Embarque com recebimento não pode ser cancelado nem perder o item recebido';end if;
  foreach k in array array['data_coleta','previsao_coleta','previsao_chegada','data_envio_despachante'] loop perform nullif(d->'dados'->>k,'')::date;end loop;
  if st in ('Em trânsito','Em desembaraço','Recebido') and nullif(d->'dados'->>'data_coleta','') is null then raise exception 'Informe a data efetiva da coleta';end if;
  if d->'dados'->>'urgente'='Sim' and nullif(btrim(d->'dados'->>'motivo'),'') is null then raise exception 'Informe o motivo da urgência';end if;
  if st='Cancelado' and nullif(btrim(d->'dados'->>'motivo'),'') is null then raise exception 'Informe o motivo do cancelamento';end if;
  for x in select value from jsonb_array_elements(d->'itens') loop
   select * into item from public.imp_pedido_itens where id=(x->>'pedido_item_id')::uuid;
   if not found then raise exception 'Item de pedido inexistente';end if;
   select * into pedido from public.imp_pedidos where id=item.pedido_id;
   if pedido.fornecedor_id<>fornecedor or pedido.moeda<>moeda or pedido.status='Cancelado' then raise exception 'Use itens de pedidos ativos do mesmo fornecedor e moeda';end if;
   qtd:=(x->>'quantidade')::numeric;receb:=coalesce(nullif(x->>'recebida','')::numeric,0);
   if qtd is null or qtd<=0 or qtd>=1e12 or receb<0 or receb>qtd or receb::text in ('NaN','Infinity','-Infinity') then raise exception 'Quantidade ou recebimento inválido';end if;
   select coalesce(sum(ei.quantidade),0) into usada from public.imp_embarque_itens ei join public.imp_embarques e on e.id=ei.embarque_id where ei.pedido_item_id=item.id and e.id<>i and e.status<>'Cancelado';
   if st<>'Cancelado' and usada+qtd>item.quantidade then raise exception 'Quantidade ultrapassa o saldo do item no pedido';end if;
   if st not in ('Planejamento','Cancelado') and usada+qtd>item.disponibilizada then raise exception 'Quantidade ainda não disponibilizada pelo fornecedor';end if;
   if st='Recebido' and receb<>qtd then raise exception 'Confirme o recebimento integral dos itens';end if;
   if receb>0 and st not in ('Em trânsito','Em desembaraço','Recebido') then raise exception 'Recebimento requer embarque em trânsito ou posterior';end if;
  end loop;
  insert into public.imp_embarques(id,referencia,fornecedor_id,moeda,status,dados,atualizado_por)
  values(i,d->>'referencia',fornecedor,moeda,st,coalesce(d->'dados','{}'),p_usuario)
  on conflict(id) do update set referencia=excluded.referencia,fornecedor_id=excluded.fornecedor_id,moeda=excluded.moeda,status=excluded.status,dados=excluded.dados,versao=imp_embarques.versao+1,atualizado_por=p_usuario,atualizado_em=clock_timestamp();
  delete from public.imp_embarque_itens where embarque_id=i;
  for x in select value from jsonb_array_elements(d->'itens') loop
   insert into public.imp_embarque_itens(embarque_id,pedido_item_id,quantidade,recebida,data_recebimento,invoice,invoice_data,peso_bruto)
   values(i,(x->>'pedido_item_id')::uuid,(x->>'quantidade')::numeric,coalesce(nullif(x->>'recebida','')::numeric,0),nullif(x->>'data_recebimento','')::date,x->>'invoice',nullif(x->>'invoice_data','')::date,nullif(x->>'peso_bruto','')::numeric);
  end loop;
 end if;
 atual:=public.axe_imp_estrutura_detalhe(t,i);
 insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual) values(t,i,p_usuario,antes,atual);
 resultado:=jsonb_build_object('id',i,'versao',atual->'versao');
 insert into public.imp_requisicoes values(p_usuario,req,p_dados,resultado,now());
 return resultado;
end $function$;

CREATE OR REPLACE FUNCTION public.axe_documentos_entrada_base(p_dados jsonb, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
 a text:=p_dados->>'acao'; papel text; pedido public.imp_pedidos; f public.imp_acks; m public.axe_email_mensagens;
 req uuid; i uuid; anterior jsonb; resultado jsonb; r record; x jsonb; rev jsonb;
begin
 select gm.papel into papel from public.gestao_membros gm join public.axe_rumo_revisores rv on rv.usuario_id=gm.usuario_id and rv.ativo where gm.usuario_id=p_usuario and gm.ativo;
 if papel is null then raise exception 'Usuário sem acesso aos documentos';end if;
 if a='ack_listar' then
  return jsonb_build_object('linhas',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select id,nome,sha256,revisado,criado_em,aplicado_em,email_id,anexo_id,pronto from public.imp_acks where pedido_id=(p_dados->>'pedido_id')::uuid and pronto order by criado_em desc)z));
 elsif a='ack_arquivo' then
  select * into f from public.imp_acks where id=(p_dados->>'id')::uuid and pronto;
  if not found then raise exception 'Anexo não encontrado';end if;return jsonb_build_object('caminho',f.caminho,'nome',f.nome);
 elsif a='email_listar' then
  return jsonb_build_object('linhas',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select id,conta,mensagem_id,remetente,assunto,recebido_em,anexos from public.axe_email_mensagens order by recebido_em desc limit 100 offset greatest(0,least(100000,coalesce((p_dados->>'pagina')::int,0)))*100)z));
 elsif a='email_detalhe' then
  select * into m from public.axe_email_mensagens where id=(p_dados->>'id')::uuid;
  if not found then raise exception 'Mensagem não encontrada';end if;
  return to_jsonb(m)||jsonb_build_object('processamentos',(select coalesce(jsonb_agg(to_jsonb(e)),'[]') from public.axe_email_processamentos e where e.mensagem_id=m.id));
 end if;
 if papel not in ('ADMIN','EDITOR') then raise exception 'Sem permissão para editar';end if;
 if a='ack_autorizar' then return jsonb_build_object('ok',true);end if;
 if octet_length(p_dados::text)>1500000 then raise exception 'Dados excedem o limite';end if;
 perform pg_advisory_xact_lock(728102826);
 if a='email_registrar' then
  x:=p_dados->'mensagem';
  if jsonb_typeof(x) is distinct from 'object' or nullif(btrim(x->>'conta'),'') is null or nullif(btrim(x->>'mensagem_id'),'') is null or nullif(btrim(x->>'remetente'),'') is null or nullif(x->>'recebido_em','') is null or jsonb_typeof(x->'anexos') is distinct from 'array' then raise exception 'Informe conta, mensagem, remetente, recebimento e anexos da coleta compartilhada';end if;
  if jsonb_array_length(x->'anexos')>100 or exists(select 1 from jsonb_array_elements(x->'anexos') z where nullif(z->>'anexo_id','') is null or z->>'sha256' is null or z->>'sha256' !~ '^[a-f0-9]{64}$') or exists(select 1 from jsonb_array_elements(x->'anexos') z group by z->>'anexo_id' having count(*)>1) then raise exception 'Identificação ou integridade dos anexos inválida';end if;
  select * into m from public.axe_email_mensagens where conta=x->>'conta' and mensagem_id=x->>'mensagem_id';
  if found then
   if m.remetente is distinct from x->>'remetente' or m.assunto is distinct from coalesce(x->>'assunto','') or m.recebido_em is distinct from (x->>'recebido_em')::timestamptz or m.corpo_texto is distinct from coalesce(x->>'corpo_texto','') or m.anexos is distinct from x->'anexos' then raise exception 'Mensagem já coletada com conteúdo diferente. Preserve a origem';end if;
   return jsonb_build_object('id',m.id,'duplicado',true);
  end if;
  insert into public.axe_email_mensagens(conta,mensagem_id,remetente,assunto,recebido_em,corpo_texto,anexos,criado_por) values(x->>'conta',x->>'mensagem_id',x->>'remetente',coalesce(x->>'assunto',''),(x->>'recebido_em')::timestamptz,coalesce(x->>'corpo_texto',''),x->'anexos',p_usuario) returning id into i;
  return jsonb_build_object('id',i,'duplicado',false);
 elsif a='email_resultado' then
  if nullif(btrim(p_dados->>'agente'),'') is null or nullif(btrim(p_dados->>'chave_processo'),'') is null or jsonb_typeof(p_dados->'resultado') is distinct from 'object' then raise exception 'Identifique agente, processo e resultado';end if;
  select * into r from public.axe_email_processamentos where mensagem_id=(p_dados->>'mensagem_id')::uuid and agente=p_dados->>'agente' and chave_processo=p_dados->>'chave_processo';
  if found then if r.resultado is distinct from p_dados->'resultado' then raise exception 'Resultado já registrado; use outra chave de etapa para preservar o histórico';end if;return jsonb_build_object('ok',true,'duplicado',true);end if;
  insert into public.axe_email_processamentos(mensagem_id,agente,chave_processo,resultado,usuario_id) values((p_dados->>'mensagem_id')::uuid,p_dados->>'agente',p_dados->>'chave_processo',p_dados->'resultado',p_usuario);
  return jsonb_build_object('ok',true,'duplicado',false);
 elsif a='ack_reservar' then
  select * into pedido from public.imp_pedidos where id=(p_dados->>'pedido_id')::uuid;
  if not found or pedido.status='Cancelado' then raise exception 'Selecione um pedido ativo';end if;
  rev:=p_dados->'revisado';
  if rev->>'pedido' is distinct from pedido.referencia or nullif(btrim(rev->>'ack_numero'),'') is null or nullif(rev->>'ack_data','') is null then raise exception 'Confira o pedido, número e data do ACK';end if;
  if (p_dados->'extraido'->>'moeda') is not null and p_dados->'extraido'->>'moeda'<>pedido.moeda then raise exception 'Moeda do ACK diverge do pedido';end if;
  if nullif(p_dados->>'email_id','') is not null then
   select * into m from public.axe_email_mensagens where id=(p_dados->>'email_id')::uuid;
   if not found or not exists(select 1 from jsonb_array_elements(m.anexos) z where z->>'anexo_id'=p_dados->>'anexo_id' and z->>'sha256'=p_dados->>'sha256') then raise exception 'Anexo não pertence à mensagem compartilhada';end if;
  elsif nullif(p_dados->>'anexo_id','') is not null then raise exception 'Identifique a mensagem de origem';end if;
  select * into f from public.imp_acks where sha256=p_dados->>'sha256' or id=(p_dados->>'requisicao_id')::uuid;
  if found then
   if f.sha256 is distinct from p_dados->>'sha256' or f.pedido_id<>pedido.id or f.revisado is distinct from rev or f.extraido is distinct from p_dados->'extraido' or f.email_id is distinct from nullif(p_dados->>'email_id','')::uuid or f.anexo_id is distinct from nullif(p_dados->>'anexo_id','') then raise exception 'ACK já registrado com outro vínculo ou revisão. Consulte o anexo existente';end if;
   return to_jsonb(f);
  end if;
  i:=(p_dados->>'requisicao_id')::uuid;
  insert into public.imp_acks(id,pedido_id,nome,caminho,sha256,tamanho,extraido,revisado,paginas,email_id,anexo_id,criado_por) values(i,pedido.id,left(p_dados->>'nome',240),pedido.id::text||'/'||i::text||'.pdf',p_dados->>'sha256',(p_dados->>'tamanho')::int,p_dados->'extraido',rev,p_dados->'paginas',nullif(p_dados->>'email_id','')::uuid,nullif(p_dados->>'anexo_id',''),p_usuario) returning * into f;
  return to_jsonb(f);
 elsif a='ack_confirmar_arquivo' then
  update public.imp_acks set pronto=true where id=(p_dados->>'id')::uuid;return jsonb_build_object('ok',true);
 elsif a='ack_aplicar' then
  if p_dados->>'confirmado' is distinct from 'true' then raise exception 'Confirme a atualização do pedido';end if;
  req:=(p_dados->>'requisicao_id')::uuid;if req is null then raise exception 'Identifique a operação';end if;
  select * into r from public.imp_requisicoes where usuario_id=p_usuario and requisicao_id=req;
  if found then if r.dados is distinct from p_dados then raise exception 'Identificador reutilizado com outros dados';end if;return r.resultado;end if;
  select * into f from public.imp_acks where id=(p_dados->>'id')::uuid and pronto;
  if not found then raise exception 'Envie o anexo antes de confirmar';end if;
  if f.aplicado_em is not null then return jsonb_build_object('id',f.pedido_id,'ack_id',f.id,'duplicado',true);end if;
  select * into pedido from public.imp_pedidos where id=f.pedido_id for update;
  if pedido.status='Cancelado' then raise exception 'Pedido cancelado';end if;
  if pedido.versao is distinct from (p_dados->>'versao')::int then raise exception 'Pedido alterado. Reabra e confira antes de confirmar o ACK';end if;
  if pedido.referencia is distinct from f.revisado->>'pedido' then raise exception 'Referência do pedido alterada. Revise o documento';end if;
  anterior:=public.axe_imp_estrutura_detalhe('pedidos',pedido.id);
  update public.imp_pedidos set status='Aceito -ACK',ack_numero=f.revisado->>'ack_numero',ack_data=(f.revisado->>'ack_data')::date,versao=versao+1,atualizado_por=p_usuario,atualizado_em=clock_timestamp() where id=pedido.id;
  update public.imp_acks set aplicado_em=clock_timestamp(),aplicado_por=p_usuario where id=f.id;
  resultado:=jsonb_build_object('id',pedido.id,'ack_id',f.id);
  insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual) values('pedidos',pedido.id,p_usuario,anterior,public.axe_imp_estrutura_detalhe('pedidos',pedido.id)||jsonb_build_object('origem','ACK','ack_id',f.id,'revisao',f.revisado,'resposta','ACK revisado e confirmação explícita de atualização','email_id',f.email_id,'anexo_id',f.anexo_id));
  if f.email_id is not null then insert into public.axe_email_processamentos(mensagem_id,agente,chave_processo,resultado,usuario_id) values(f.email_id,'importacoes.ack',f.id::text,resultado,p_usuario);end if;
  insert into public.imp_requisicoes(usuario_id,requisicao_id,dados,resultado) values(p_usuario,req,p_dados,resultado);
  return resultado;
 end if;
 raise exception 'Ação inválida';
end;$function$;

do $run$ declare p record;begin for p in select id from public.imp_pedidos loop perform public.axe_imp_recalcular_status_pedido(p.id);end loop;end $run$;
CREATE OR REPLACE FUNCTION public.axe_imp_estrutura_detalhe(t text, i uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select case t
 when 'pedidos' then (
 select to_jsonb(p)||jsonb_build_object('fornecedor',f.razao_social,'fornecedor_pais',f.pais,
 'total',(select coalesce(sum(round(x.quantidade*x.valor_unitario,2)),0) from public.imp_pedido_itens x where x.pedido_id=p.id),
 'itens',(select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object(
 'reservada',(select coalesce(sum(ei.quantidade),0) from public.imp_embarque_itens ei join public.imp_embarques e on e.id=ei.embarque_id where ei.pedido_item_id=x.id and e.status<>'Cancelado'),
 'recebida',(select coalesce(sum(ei.recebida),0) from public.imp_embarque_itens ei join public.imp_embarques e on e.id=ei.embarque_id where ei.pedido_item_id=x.id and e.status<>'Cancelado')) order by x.linha),'[]') from public.imp_pedido_itens x where x.pedido_id=p.id),
 'parcelas',(select coalesce(jsonb_agg(to_jsonb(x) order by x.vencimento nulls last,x.criado_em),'[]') from public.imp_parcelas x where x.pedido_id=p.id))
 from public.imp_pedidos p join public.fornecedores f on f.id=p.fornecedor_id where p.id=i)
 when 'parcelas' then (select to_jsonb(p)||jsonb_build_object('pedido',o.referencia,'moeda',o.moeda) from public.imp_parcelas p join public.imp_pedidos o on o.id=p.pedido_id where p.id=i)
 when 'embarques' then (
 select to_jsonb(e)||jsonb_build_object('fornecedor',f.razao_social,'participantes',(select coalesce(jsonb_agg(jsonb_build_object('papel',ep.papel,'id',ep.fornecedor_id,'nome',emp.razao_social)),'[]') from public.imp_embarque_participantes ep join public.fornecedores emp on emp.id=ep.fornecedor_id where ep.embarque_id=e.id),'itens',(
 select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('pedido',p.referencia,'linha',pi.linha,'descricao',pi.descricao,'produto_id',pi.produto_id,'unidade',pi.unidade,'valor_unitario',pi.valor_unitario) order by p.referencia,pi.linha),'[]')
 from public.imp_embarque_itens x join public.imp_pedido_itens pi on pi.id=x.pedido_item_id join public.imp_pedidos p on p.id=pi.pedido_id where x.embarque_id=e.id))
 from public.imp_embarques e join public.fornecedores f on f.id=e.fornecedor_id where e.id=i)
 end
$function$;

commit;
