create function public.axe_dhl_embarques(awb text) returns jsonb
language sql stable set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'referencia',e.referencia) order by e.referencia,e.id),'[]')
 from public.imp_embarques e
 where awb ~ '^[0-9]{10}$' and e.status<>'Cancelado' and (
  regexp_replace(coalesce(e.dados->>'rastreio',''),'[^0-9]','','g')=awb or
  exists(select 1 from public.imp_transporte_revisoes t where t.embarque_id=e.id
   and t.versao=(select max(x.versao) from public.imp_transporte_revisoes x where x.embarque_id=e.id)
   and regexp_replace(coalesce(t.dados->>'awb',''),'[^0-9]','','g')=awb)
 )
$$;
revoke all on function public.axe_dhl_embarques(text) from public,anon,authenticated;
grant execute on function public.axe_dhl_embarques(text) to service_role;

alter function public.axe_documentos_entrada(jsonb,uuid) rename to axe_documentos_entrada_sem_dhl;
create function public.axe_documentos_entrada(p_dados jsonb,p_usuario uuid) returns jsonb
language plpgsql set search_path='' as $$
declare
 a text:=p_dados->>'acao';
 d jsonb:=p_dados->'aplicacao';
 p public.axe_email_propostas;
 f public.axe_email_arquivos;
 r jsonb;
 candidatos jsonb;
 eid uuid;
 mid uuid;
 arquivo_id uuid;
 pend jsonb:='[]';
begin
 if a not in ('email_propor','email_proposta_detalhe','email_decidir') then
  return public.axe_documentos_entrada_sem_dhl(p_dados,p_usuario);
 end if;
 if a<>'email_propor' then
  select * into p from public.axe_email_propostas where id=(p_dados->>'id')::uuid;
  if p.tipo is distinct from 'FATURA_TRANSPORTADORA' then return public.axe_documentos_entrada_sem_dhl(p_dados,p_usuario);end if;
 elsif p_dados->>'tipo' is distinct from 'FATURA_TRANSPORTADORA' then
  return public.axe_documentos_entrada_sem_dhl(p_dados,p_usuario);
 end if;
 perform public.axe_documentos_entrada_sem_dhl('{"acao":"email_propostas_listar"}',p_usuario);
 if a='email_propor' then
  mid:=(p_dados->>'mensagem_id')::uuid;
  arquivo_id:=(d->>'arquivo_id')::uuid;
  select * into f from public.axe_email_arquivos where id=arquivo_id and mensagem_id=mid;
  if not found or substring(f.conteudo from 1 for 5)<>convert_to('%PDF-','UTF8') then raise exception 'Anexe o original da fatura à mensagem';end if;
  if coalesce(d->>'numero','') !~ '^GRU[A-Z0-9]{5,30}$' or coalesce(d->>'awb','') !~ '^[0-9]{10}$'
    or coalesce(d->>'emissao','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or coalesce(d->>'vencimento','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or coalesce(d->>'valor','') !~ '^[0-9]{1,12}\.[0-9]{2}$' then raise exception 'Campos da fatura DHL incompletos';end if;
  if octet_length(f.conteudo)>350000 then pend:=jsonb_build_array('O PDF excede o limite de 350 KB da entrada de faturas.');end if;
  d:=jsonb_build_object('arquivo_id',arquivo_id,'numero',d->>'numero','awb',d->>'awb','valor',d->>'valor','emissao',d->>'emissao','vencimento',d->>'vencimento');
  insert into public.axe_email_propostas(id,mensagem_id,agente,chave_processo,tipo,resumo,aplicacao,pendencias,criado_por)
  values(gen_random_uuid(),mid,'faturas_dhl',arquivo_id::text,'FATURA_TRANSPORTADORA','DHL '||(d->>'numero')||' · AWB '||(d->>'awb'),d,pend,p_usuario)
  on conflict(mensagem_id,agente,chave_processo) do nothing returning * into p;
  if not found then select * into p from public.axe_email_propostas where mensagem_id=mid and agente='faturas_dhl' and chave_processo=arquivo_id::text;end if;
  return jsonb_build_object('id',p.id,'estado',p.estado);
 end if;
 if a='email_decidir' and p_dados->>'decisao'='Rejeitar' then
  return public.axe_documentos_entrada_sem_dhl(p_dados,p_usuario);
 end if;
 if a='email_decidir' then
  if not public.axe_compra_fin_autorizado(p_usuario) or p_dados->>'decisao' is distinct from 'Aprovar'
    or p_dados->>'confirmado' is distinct from 'true' or p_dados->>'contratacao_direta' is distinct from 'true' then raise exception 'Confirme que a fatura é de frete contratado diretamente';end if;
  perform pg_advisory_xact_lock(728102826);
  select * into p from public.axe_email_propostas where id=p.id for update;
  if p.estado='Aprovado' then return jsonb_build_object('id',p.id,'estado',p.estado,'resultado',p.resultado);end if;
  if p.estado<>'Pendente' or p.substituida_por is not null then raise exception 'Pré-cadastro indisponível para aceite';end if;
 end if;
 d:=p.aplicacao;
 candidatos:=public.axe_dhl_embarques(d->>'awb');
 if jsonb_array_length(candidatos)=1 then eid:=(candidatos->0->>'id')::uuid;end if;
 pend:=p.pendencias;
 if eid is null then
  pend:=pend||jsonb_build_array(case when candidatos='[]' then 'AWB sem vínculo. Cadastre o AWB no embarque correto e volte para conferir.' else 'AWB em mais de um embarque. Corrija o vínculo e volte para conferir.' end);
 elsif not exists(select 1 from public.imp_embarque_participantes ep join public.fornecedores fo on fo.id=ep.fornecedor_id
  where ep.embarque_id=eid and ep.papel='transportador' and (regexp_replace(coalesce(nullif(fo.cnpj,''),fo.documento_fiscal,''),'[^0-9]','','g')='58890252000113'
    or (nullif(btrim(coalesce(nullif(fo.cnpj,''),fo.documento_fiscal,'')),'') is null
     and fo.pais='BR' and upper(btrim(fo.razao_social))='DHL BRASIL'))) then
  pend:=pend||jsonb_build_array('Confirme o cadastro da DHL Express como transportadora do embarque.');
 end if;
 if a='email_proposta_detalhe' then
  r:=public.axe_documentos_entrada_sem_dhl(p_dados,p_usuario);
  return r||jsonb_build_object('pendencias',case when p.estado='Pendente' then pend else p.pendencias end,
    'embarque_conferido',eid,'aplicacao',(d-'arquivo_id')||jsonb_build_object('embarque',candidatos->0->>'referencia'));
 end if;
 if pend<>'[]' then raise exception '%',pend->>0;end if;
 if p_dados->>'embarque_conferido' is distinct from eid::text then raise exception 'O vínculo do AWB mudou. Reabra a conferência';end if;
 select * into strict f from public.axe_email_arquivos where id=(d->>'arquivo_id')::uuid and mensagem_id=p.mensagem_id;
 r:=public.axe_imp_estrutura((d-'arquivo_id'-'awb')||jsonb_build_object('acao','v2_frete_fatura_salvar','embarque_id',eid,
  'requisicao_id',p.id,'contratacao_direta',true,'nome',f.nome,'pdf',replace(encode(f.conteudo,'base64'),chr(10),'')),p_usuario);
 update public.axe_email_propostas set estado='Aprovado',resultado=r,decidido_por=p_usuario,decidido_em=clock_timestamp() where id=p.id;
 return jsonb_build_object('id',p.id,'estado','Aprovado','resultado',r);
end $$;
revoke all on function public.axe_documentos_entrada(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_documentos_entrada(jsonb,uuid) to service_role;

create function public.axe_dhl_email_arquivos(p_usuario uuid) returns jsonb
language plpgsql set search_path='' as $$
begin
 perform public.axe_documentos_entrada_sem_dhl('{"acao":"email_propostas_listar"}',p_usuario);
 return (select coalesce(jsonb_agg(to_jsonb(z)),'[]') from (
  select f.id arquivo_id,f.mensagem_id,encode(f.conteudo,'base64') pdf
  from public.axe_email_arquivos f join public.axe_email_mensagens m on m.id=f.mensagem_id
  where f.nome ~* '\.pdf$' and octet_length(f.conteudo) between 5 and 350000
   and (f.nome ~* '^GRU' or m.remetente ilike '%@dhl.com%' or m.assunto ilike '%DHL%')
   and not exists(select 1 from public.axe_email_propostas p where p.mensagem_id=f.mensagem_id
    and p.agente='faturas_dhl' and p.chave_processo=f.id::text)
  order by (f.nome ~* '^GRU') desc,m.recebido_em desc,f.id limit 8
 ) z);
end $$;
revoke all on function public.axe_dhl_email_arquivos(uuid) from public,anon,authenticated;
grant execute on function public.axe_dhl_email_arquivos(uuid) to service_role;
