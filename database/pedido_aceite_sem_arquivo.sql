begin;
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
CREATE OR REPLACE FUNCTION public.axe_imp_estrutura_detalhe(t text, i uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select case t
 when 'pedidos' then (
 select to_jsonb(p)||jsonb_build_object('fornecedor',f.razao_social,'fornecedor_pais',f.pais,'aceite_confirmado',(p.status='Aceito -ACK' or exists(select 1 from public.imp_estrutura_eventos ev where ev.tipo='pedidos' and ev.registro_id=p.id and ev.atual->>'status'='Aceito -ACK')),
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
