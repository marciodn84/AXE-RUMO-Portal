CREATE OR REPLACE FUNCTION public.axe_transporte_documental(p_dados jsonb, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare a text:=p_dados->>'acao';papel text;eid uuid;e public.imp_embarques;r public.imp_transporte_revisoes;novo public.imp_transporte_revisoes;d jsonb:=p_dados->'dados';req uuid;previous jsonb;res jsonb;op record;f record;x jsonb;v numeric;di public.imp_fin_documentos;k text;carrier jsonb;carrier_old bigint;carrier_selected bigint;
begin
 select m.papel into papel from public.gestao_membros m join public.axe_rumo_revisores rv on rv.usuario_id=m.usuario_id and rv.ativo where m.usuario_id=p_usuario and m.ativo;if papel is null then raise exception 'Sem acesso ao transporte de importações';end if;
 if a='transp_resolver_transportador' then return public.axe_imp_transportador_resolver(p_dados->>'nome',p_dados->>'documento');end if;
 if a not in ('transp_contexto','transp_arquivo','transp_salvar') or a is null then raise exception 'Ação inválida';end if;
 if a='transp_arquivo' then select * into f from public.imp_transporte_arquivos where id=(p_dados->>'id')::uuid;if not found then raise exception 'Arquivo não encontrado';end if;return to_jsonb(f);end if;
 eid:=(p_dados->>'embarque_id')::uuid;perform pg_advisory_xact_lock(728102826);
 select * into e from public.imp_embarques where id=eid;if not found then raise exception 'Embarque não encontrado';end if;
 select * into r from public.imp_transporte_revisoes where embarque_id=eid order by versao desc limit 1;
 if a='transp_contexto' then return jsonb_build_object('editar',papel in ('ADMIN','EDITOR'),'embarque',public.axe_imp_estrutura_detalhe('embarques',eid),'atual',case when r.id is null then null else to_jsonb(r) end,'frete',public.axe_transporte_frete(eid),'custo_final',exists(select 1 from public.imp_custos where embarque_id=eid and estado='Final'),'historico',(select coalesce(jsonb_agg(to_jsonb(z) order by z.versao desc),'[]') from public.imp_transporte_revisoes z where z.embarque_id=eid),'arquivos',(select coalesce(jsonb_agg(to_jsonb(fa)),'[]') from public.imp_transporte_arquivos fa where fa.embarque_id=eid),'duimps',(select coalesce(jsonb_agg(jsonb_build_object('id',doc_di.id,'numero',doc_di.referencia,'data_registro',doc_di.dados->>'data_registro')),'[]') from public.imp_fin_documentos doc_di where doc_di.tipo='declaracoes' and doc_di.status='Ativo' and doc_di.fornecedor_id=e.fornecedor_id and doc_di.dados->>'especie'='DUIMP'));end if;
 if papel not in ('ADMIN','EDITOR') or p_dados->>'confirmado' is distinct from 'true' then raise exception 'Confirme a conferência dos documentos e valores';end if;
 req:=(p_dados->>'requisicao_id')::uuid;if req is null then raise exception 'Identificador obrigatório';end if;
 select * into op from public.imp_requisicoes where usuario_id=p_usuario and requisicao_id=req;if found then if op.dados is distinct from p_dados then raise exception 'Identificador reutilizado com outros dados';end if;return op.resultado;end if;
 if e.status='Cancelado' then raise exception 'Embarque cancelado';end if;
 if exists(select 1 from public.imp_custos where embarque_id=eid and estado='Final') then raise exception 'Reabra o custo final com justificativa antes de alterar o transporte';end if;
 if e.versao is distinct from (p_dados->>'versao_embarque')::int or r.id is distinct from nullif(p_dados->>'base_revisao_id','')::uuid then raise exception 'Transporte ou embarque alterado. Reabra antes de confirmar';end if;
 if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>50000 or coalesce(d->>'awb','')!~'^[A-Za-z0-9][A-Za-z0-9 -]{4,39}$' or nullif(btrim(d->>'transportador'),'') is null or nullif(btrim(d->>'servico'),'') is null then raise exception 'Confira AWB, transportadora e serviço';end if;
 foreach k in array array['peso_real_kg','peso_cubado_kg','peso_faturavel_kg','frete_usd'] loop
  v:=nullif(d->>k,'')::numeric;if v is null or v<=0 or v>=1e12 or v::text in ('NaN','Infinity','-Infinity') then raise exception 'Informe valor positivo para %',k;end if;
  if k='frete_usd' and v<>round(v,2) then raise exception 'Frete deve ter até duas casas decimais';end if;
 end loop;
 if nullif(d->>'data_documento','') is null then raise exception 'Informe a data do recibo';end if;perform (d->>'data_documento')::date;perform nullif(d->>'previsao_chegada','')::date;
 if coalesce((d->>'volumes')::int,0)<=0 then raise exception 'Informe a quantidade de volumes';end if;
 if r.id is not null and nullif(btrim(d->>'motivo'),'') is null then raise exception 'Informe o motivo da revisão; os valores anteriores serão preservados';end if;
 if nullif(d->>'duimp_id','') is not null or nullif(d->>'taxa_duimp','') is not null then
  select * into di from public.imp_fin_documentos where id=nullif(d->>'duimp_id','')::uuid and tipo='declaracoes' and status='Ativo' and fornecedor_id=e.fornecedor_id and dados->>'especie'='DUIMP';
  if not found or nullif(di.dados->>'data_registro','') is null then raise exception 'Selecione uma DUIMP deste fornecedor com data de registro preenchida';end if;
  v:=nullif(d->>'taxa_duimp','')::numeric;if v is null or v<=0 or v>=1e8 or v::text in ('NaN','Infinity','-Infinity') or nullif(btrim(d->>'fonte_taxa'),'') is null or p_dados->>'conferiu_duimp' is distinct from 'true' then raise exception 'Confira a taxa USD/BRL da DUIMP e sua referência documental';end if;
  d:=d||jsonb_build_object('data_registro_duimp',di.dados->>'data_registro','duimp_numero',di.referencia);
 else d:=d||jsonb_build_object('duimp_id',null,'duimp_numero',null,'taxa_duimp',null,'data_registro_duimp',null);end if;
 if r.id is not null and (r.dados->>'frete_usd')::numeric is distinct from (d->>'frete_usd')::numeric and jsonb_array_length(coalesce(p_dados->'arquivos','[]'))=0 then raise exception 'Anexe o recibo ou documento de ajuste que comprova o novo frete';end if;
 if r.id is null and jsonb_array_length(coalesce(p_dados->'arquivos','[]'))=0 then raise exception 'Anexe pelo menos um documento de transporte';end if;

 carrier:=public.axe_imp_transportador_resolver(p_dados->'extraido'->'dados'->>'transportador',p_dados->'extraido'->'dados'->>'transportador_documento');
 if p_dados->'extraido'->'dados'->>'transportador_conflito'='true' then carrier:=jsonb_build_object('estado','Conflito documental');end if;
 select ep.fornecedor_id into carrier_old from public.imp_embarque_participantes ep where ep.embarque_id=eid and ep.papel='transportador';
 carrier_selected:=nullif(d->>'transportador_id','')::bigint;
 if carrier_selected is null and carrier->>'estado'='Automático' and (carrier_old is null or carrier_old=(carrier->>'id')::bigint)then carrier_selected:=(carrier->>'id')::bigint;end if;
 if carrier_selected is null then raise exception 'Escolha o transportador do documento no cadastro existente ou cadastre o transportador ausente';end if;
 if coalesce((d->>'transportador_escolha_manual')::boolean,false) is not true and (
 (carrier->>'estado'='Automático' and carrier_selected<>(carrier->>'id')::bigint)
 or (carrier_old is not null and carrier_old<>carrier_selected)
 or (carrier->>'estado'<>'Automático'))then raise exception 'Confira a identificação do transportador e escolha explicitamente o cadastro correto';end if;
 if not exists(select 1 from public.fornecedores ff where ff.id=carrier_selected and ff.ativo and not ff.bloqueado_comercial)then raise exception 'Transportador inativo ou bloqueado: selecione um cadastro ativo e liberado';end if;
 d:=d||jsonb_build_object('transportador_id',carrier_selected,'transportador_identificacao',jsonb_build_object('origem',case when coalesce((d->>'transportador_escolha_manual')::boolean,false)then 'Escolha explícita do usuário' else carrier->>'criterio' end,'nome_documento',p_dados->'extraido'->'dados'->>'transportador','documento',p_dados->'extraido'->'dados'->>'transportador_documento','fornecedor_id',carrier_selected));
 if nullif(d->>'transportador_id','') is not null then
   if not exists(select 1 from public.fornecedores where id=(d->>'transportador_id')::bigint and ativo) then raise exception 'Selecione um transportador ativo no cadastro';end if;
   insert into public.imp_embarque_participantes(embarque_id,papel,fornecedor_id)values(eid,'transportador',(d->>'transportador_id')::bigint) on conflict on constraint imp_embarque_participantes_pkey do update set fornecedor_id=excluded.fornecedor_id;
  elsif not exists(select 1 from public.imp_embarque_participantes ep where ep.embarque_id=eid and ep.papel='transportador') then raise exception 'Selecione ou cadastre o transportador identificado no documento';end if;
  previous:=to_jsonb(e)||jsonb_build_object('transportador_id',carrier_old);
 insert into public.imp_transporte_revisoes(embarque_id,versao,dados,extraido,usuario_id) values(eid,coalesce(r.versao,0)+1,d,p_dados->'extraido',p_usuario) returning * into novo;
 if r.id is not null then insert into public.imp_transporte_revisao_arquivos select novo.id,arquivo_id from public.imp_transporte_revisao_arquivos where revisao_id=r.id;end if;
 for x in select value from jsonb_array_elements(coalesce(p_dados->'arquivos','[]')) loop
  if x->>'caminho' is distinct from 'entrada/'||p_usuario||'/'||req||'/'||(x->>'categoria')||'.pdf' or coalesce(length(x->>'nome'),0) not between 1 and 250 then raise exception 'Identificação do arquivo inválida';end if;
  insert into public.imp_transporte_arquivos(embarque_id,categoria,nome,sha256,tamanho,caminho) values(eid,x->>'categoria',x->>'nome',x->>'sha256',(x->>'tamanho')::int,x->>'caminho') on conflict(embarque_id,sha256) do nothing;
  select id into f from public.imp_transporte_arquivos where embarque_id=eid and sha256=x->>'sha256';
  insert into public.imp_transporte_revisao_arquivos values(novo.id,f.id) on conflict do nothing;
 end loop;
 update public.imp_embarques set dados=dados||jsonb_build_object('transporte_revisao_id',novo.id,'transportador',d->>'transportador','servico',case when d->>'transportador'='DHL' then 'DHL' else 'Agente de cargas' end,'servico_transportadora',d->>'servico','rastreio',d->>'awb','previsao_chegada',coalesce(nullif(d->>'previsao_chegada',''),dados->>'previsao_chegada')),versao=versao+1,atualizado_por=p_usuario,atualizado_em=clock_timestamp() where id=eid;
 insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual) values('embarques',eid,p_usuario,previous,jsonb_build_object('embarque',public.axe_imp_estrutura_detalhe('embarques',eid),'transporte',to_jsonb(novo)));
 res:=jsonb_build_object('id',novo.id,'versao',novo.versao,'embarque_id',eid,'frete',public.axe_transporte_frete(eid));insert into public.imp_requisicoes values(p_usuario,req,p_dados,res,now());return res;
end $function$
;
