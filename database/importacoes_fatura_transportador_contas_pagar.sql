alter table public.imp_faturas_transportador
 alter column data_pagamento drop not null,
 drop constraint imp_faturas_transportador_situacao_check,
 alter column situacao set default 'A pagar',
 add column vencimento date check(vencimento>=emissao),
 add column pago_por uuid,
 add column pago_em timestamptz,
 add constraint imp_fatura_estado_pagamento check(
  (situacao='A pagar' and data_pagamento is null and vencimento is not null)
  or (situacao='Pago' and data_pagamento is not null)
 );
grant update(situacao,data_pagamento,pago_por,pago_em) on public.imp_faturas_transportador to service_role;

create or replace function public.axe_transporte_frete_custo(eid uuid) returns jsonb
language sql stable set search_path='' as $$
 select coalesce(
  (select jsonb_build_object('id',f.id,'origem_transporte',f.id,'origem_fatura',f.id,
    'referencia','Fatura de frete '||f.numero,'categoria','Frete','valor',f.valor_brl,
    'valor_brl',f.valor_brl,'moeda','BRL','situacao','Confirmada','data',f.emissao,
    'criterio','Peso real bruto dos itens')
   from public.imp_faturas_transportador f where f.embarque_id=eid),
  public.axe_transporte_frete(eid))
$$;
revoke all on function public.axe_transporte_frete_custo(uuid) from public,anon,authenticated;
grant execute on function public.axe_transporte_frete_custo(uuid) to service_role;

create or replace function public.axe_imp_estrutura(p_dados jsonb,p_usuario uuid) returns jsonb
language plpgsql set search_path='' as $$
declare
 a text:=p_dados->>'acao';
 eid uuid;
 f public.imp_faturas_transportador;
 c public.imp_custos;
 d jsonb;
 resultado jsonb;
 transportador bigint;
 v numeric;
 numero_fatura text;
 nome text;
 pdf bytea;
 emissao_doc date;
 pagamento date;
 vencimento_doc date;
 req uuid;
 anterior jsonb;
 solicitacao jsonb;
begin
 if coalesce(a,'') not in ('v2_frete_fatura_ler','v2_frete_fatura_salvar','v2_frete_fatura_baixar','v2_frete_fatura_financeiro','v2_frete_fatura_baixar_pagamento') then
  return public.axe_imp_estrutura_sem_fatura_transporte(p_dados,p_usuario);
 end if;
 perform public.axe_imp_estrutura_sem_fatura_transporte('{"acao":"v2_opcoes"}',p_usuario);
 if a='v2_frete_fatura_financeiro' then
  return jsonb_build_object('linhas',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from (
   select ft.numero,ft.valor_brl,ft.emissao,ft.vencimento,ft.data_pagamento,ft.situacao,ft.meio_pagamento,
    e.referencia embarque,fo.razao_social transportadora
   from public.imp_faturas_transportador ft join public.imp_embarques e on e.id=ft.embarque_id
    join public.fornecedores fo on fo.id=ft.fornecedor_id
   where not coalesce((p_dados->>'somente_abertas')::boolean,false) or ft.situacao='A pagar'
   order by coalesce(ft.data_pagamento,ft.vencimento,ft.emissao) desc,ft.id limit 30 offset greatest(0,least(100000,coalesce((p_dados->>'pagina')::int,0)))*30
  ) z));
 end if;
 eid:=(p_dados->>'embarque_id')::uuid;
 if a in ('v2_frete_fatura_salvar','v2_frete_fatura_baixar_pagamento') then
  if not public.axe_compra_fin_autorizado(p_usuario) then raise exception 'Sem permissão para registrar fatura e pagamento';end if;
  perform pg_advisory_xact_lock(728102826);
 end if;
 if not exists(select 1 from public.imp_embarques e where e.id=eid and e.status<>'Cancelado') then raise exception 'Selecione um embarque ativo';end if;
 select * into f from public.imp_faturas_transportador where embarque_id=eid;
 if a='v2_frete_fatura_ler' then
  return jsonb_build_object('fatura',to_jsonb(f)-'arquivo_pdf',
    'transportadora',(select fo.razao_social from public.imp_embarque_participantes ep join public.fornecedores fo on fo.id=ep.fornecedor_id
     where ep.embarque_id=eid and ep.papel='transportador'),
    'editar',public.axe_compra_fin_autorizado(p_usuario),
    'frete_no_numerario',public.axe_frete_no_numerario(eid),
    'custo_final',exists(select 1 from public.imp_custos where embarque_id=eid and estado='Final'));
 elsif a='v2_frete_fatura_baixar' then
  if f.id is null then raise exception 'Fatura não cadastrada';end if;
  return jsonb_build_object('nome',f.arquivo_nome,'pdf',encode(f.arquivo_pdf,'base64'));
 end if;

 req:=(p_dados->>'requisicao_id')::uuid;
 if req is null then raise exception 'Identificador de operação obrigatório';end if;
 solicitacao:=(p_dados-'pdf')||jsonb_build_object('pdf_hash',sha256(convert_to(coalesce(p_dados->>'pdf',''),'UTF8'))::text);
 select r.dados,r.resultado into anterior,resultado from public.imp_requisicoes r where usuario_id=p_usuario and requisicao_id=req;
 if found then
  if anterior is distinct from solicitacao then raise exception 'Identificador reutilizado';end if;
  return resultado;
 end if;
 if a='v2_frete_fatura_baixar_pagamento' then
  if f.id is null then raise exception 'Fatura não cadastrada';end if;
  pagamento:=nullif(p_dados->>'data_pagamento','')::date;
  if p_dados->>'confirmou_pagamento' is distinct from 'true' or pagamento is null or pagamento<f.emissao
     or pagamento>(now() at time zone 'America/Sao_Paulo')::date then
   raise exception 'Confirme o pagamento e informe a data efetiva do boleto';
  end if;
  if f.situacao='Pago' then
   if f.data_pagamento is distinct from pagamento then raise exception 'A fatura já tem baixa em outra data';end if;
  else
   update public.imp_faturas_transportador set situacao='Pago',data_pagamento=pagamento,pago_por=p_usuario,pago_em=clock_timestamp()
   where id=f.id returning * into f;
  end if;
  resultado:=jsonb_build_object('fatura',to_jsonb(f)-'arquivo_pdf');
  insert into public.imp_requisicoes values(p_usuario,req,solicitacao,resultado,now());
  return resultado;
 end if;
 if f.id is not null then raise exception 'Já existe uma fatura de frete registrada neste embarque';end if;
 if public.axe_frete_no_numerario(eid) then raise exception 'Já existe frete no numerário ou no fechamento deste embarque. Confira o lançamento com o despachante';end if;
 select * into c from public.imp_custos where embarque_id=eid for update;
 if c.estado='Final' then raise exception 'Reabra o custo final com justificativa antes de lançar a fatura';end if;
 select fornecedor_id into transportador from public.imp_embarque_participantes where embarque_id=eid and papel='transportador';
 if transportador is null then raise exception 'Vincule a transportadora ao embarque antes de lançar a fatura';end if;
 numero_fatura:=upper(btrim(p_dados->>'numero'));
 nome:=btrim(p_dados->>'nome');
 v:=(p_dados->>'valor')::numeric;
 emissao_doc:=(p_dados->>'emissao')::date;
 vencimento_doc:=nullif(p_dados->>'vencimento','')::date;
 if coalesce(length(numero_fatura),0) not between 1 and 100 or coalesce(length(nome),0) not between 1 and 250
   or v is null or v<=0 or v>=1e12 or v<>round(v,2) or v::text='NaN'
   or emissao_doc is null or vencimento_doc is null or vencimento_doc<emissao_doc
   or p_dados->>'contratacao_direta' is distinct from 'true' then
  raise exception 'Confira número, valor em reais, emissão e vencimento do boleto';
 end if;
 if coalesce(length(p_dados->>'pdf'),0) not between 8 and 466668 then raise exception 'Anexe o PDF da fatura de até 350 KB';end if;
 pdf:=decode(p_dados->>'pdf','base64');
 if octet_length(pdf)>350000 or substring(pdf from 1 for 5)<>convert_to('%PDF-','UTF8') then raise exception 'Anexe um PDF válido de até 350 KB';end if;
 if exists(select 1 from public.imp_faturas_transportador where fornecedor_id=transportador and numero=numero_fatura) then
  raise exception 'Esta fatura já foi registrada para a transportadora';
 end if;
 insert into public.imp_faturas_transportador(embarque_id,fornecedor_id,numero,valor_brl,emissao,vencimento,arquivo_nome,arquivo_pdf,usuario_id)
 values(eid,transportador,numero_fatura,v,emissao_doc,vencimento_doc,nome,pdf,p_usuario) returning * into f;

 -- Atualiza a apuração provisória, sem alterar tributos ou vínculos de pagamentos FOB.
 d:=public.axe_transporte_despesas(eid,coalesce(c.dados,'{"pagamentos":[],"despesas":[],"tributos":[]}'::jsonb));
 resultado:=jsonb_set(public.axe_imp_custo_calcular(eid,d),'{embarque_fonte}',public.axe_imp_estrutura_detalhe('embarques',eid));
 insert into public.imp_custos(embarque_id,estado,dados,resultado,atualizado_por)
 values(eid,'Provisório',d,resultado,p_usuario)
 on conflict(embarque_id) do update set dados=excluded.dados,resultado=excluded.resultado,
  versao=imp_custos.versao+1,atualizado_por=excluded.atualizado_por,atualizado_em=clock_timestamp();
 insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)
 values('custos',eid,p_usuario,to_jsonb(c),(select to_jsonb(n) from public.imp_custos n where embarque_id=eid));
 resultado:=jsonb_build_object('fatura',to_jsonb(f)-'arquivo_pdf','pendencias',resultado->'pendencias');
 insert into public.imp_requisicoes values(p_usuario,req,solicitacao,resultado,now());
 return resultado;
end $$;
revoke all on function public.axe_imp_estrutura(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_imp_estrutura(jsonb,uuid) to service_role;
