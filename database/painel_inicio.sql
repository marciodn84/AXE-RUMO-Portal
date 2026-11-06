alter function public.axe_imp_estrutura(jsonb,uuid) rename to axe_imp_estrutura_sem_painel_inicio;
create function public.axe_imp_estrutura(p_dados jsonb,p_usuario uuid) returns jsonb
language plpgsql set search_path='' as $$
declare
 hoje date:=(now() at time zone 'America/Sao_Paulo')::date;
 mes date:=date_trunc('month',hoje::timestamp)::date;
 inicio date:=(mes-interval '5 months')::date;
 dias integer:=case when p_dados->>'dias'='30' then 30 else 7 end;
 resultado jsonb;
begin
 if p_dados->>'acao' is distinct from 'v2_painel_inicio' then
  return public.axe_imp_estrutura_sem_painel_inicio(p_dados,p_usuario);
 end if;
 perform public.axe_imp_estrutura_sem_painel_inicio('{"acao":"v2_opcoes"}',p_usuario);

 with parcelas as (
  select a.id,a.pedido_id,a.referencia,p.moeda,a.vencimento,a.valor,a.valor_pago,a.data_pagamento,
   p.referencia pedido,f.razao_social fornecedor
  from public.imp_parcelas a join public.imp_pedidos p on p.id=a.pedido_id join public.fornecedores f on f.id=p.fornecedor_id
  where a.status<>'Cancelada' and p.status<>'Cancelado'
 ), fretes as (
  select ft.id,ft.embarque_id,ft.vencimento,ft.valor_brl,ft.data_pagamento,ft.situacao,
   'Fatura de frete '||ft.numero referencia,f.razao_social fornecedor,
   (select pi.pedido_id from public.imp_embarque_itens ei join public.imp_pedido_itens pi on pi.id=ei.pedido_item_id
     where ei.embarque_id=ft.embarque_id order by pi.pedido_id limit 1) pedido_id
  from public.imp_faturas_transportador ft join public.fornecedores f on f.id=ft.fornecedor_id
 ), aberto as (
  select vencimento,moeda,valor-valor_pago valor,referencia,fornecedor,pedido_id,null::uuid embarque_id
  from parcelas where valor>valor_pago
  union all
  select vencimento,'BRL',valor_brl,referencia,fornecedor,pedido_id,embarque_id from fretes where situacao='A pagar'
 ), eventos as (
  select x.registro_id,
   (x.atual->>'data_pagamento')::date data,
   coalesce((x.atual->>'valor_pago')::numeric,0)-coalesce((x.anterior->>'valor_pago')::numeric,0) valor
  from public.imp_estrutura_eventos x join parcelas p on p.id=x.registro_id and p.valor_pago>0
  where x.tipo='parcelas' and x.atual->>'data_pagamento' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
 ), conferidos as (
  select p.id from parcelas p join eventos ev on ev.registro_id=p.id
  where ev.valor<>0 group by p.id,p.valor_pago
  having sum(ev.valor)=p.valor_pago and min(ev.valor)>0
 ), pagos as (
  select ev.data,p.moeda,ev.valor from eventos ev join conferidos c on c.id=ev.registro_id
   join parcelas p on p.id=c.id where ev.valor>0
  union all
  select p.data_pagamento,p.moeda,p.valor_pago from parcelas p
  where p.valor_pago>0 and p.data_pagamento is not null and not exists(select 1 from conferidos c where c.id=p.id)
  union all
  select data_pagamento,'BRL',valor_brl from fretes where situacao='Pago'
  union all
  select n.data,'BRL',n.valor from public.financeiro_num_movimentos n where not n.estornado and n.tipo in ('Adiantamento','Complemento')
 ), entrega as (
  select p.id,p.referencia,p.previsao_entrega data,f.razao_social fornecedor from public.imp_pedidos p
   join public.fornecedores f on f.id=p.fornecedor_id
   where p.status not in ('Cancelado','Recebido','Elaboração') and p.previsao_entrega>=hoje and p.previsao_entrega<hoje+dias
 ), agenda as (
  select 'Pagamento' tipo, a.vencimento data, a.referencia titulo,a.fornecedor descricao,a.moeda,a.valor,a.pedido_id,a.embarque_id,null::uuid tarefa_id
  from aberto a where a.vencimento>=hoje and a.vencimento<hoje+dias
  union all
  select 'Entrega',data,referencia,fornecedor,null,null,id,null,null from entrega
  union all
  select 'Tarefa',g.prazo,coalesce(nullif(g.codigo,'')||' · ','')||g.titulo,g.area,null,null,null,null,g.id
  from public.gestao_itens g where g.tipo='tarefas' and not g.arquivado
   and coalesce(g.status,'') not in ('Concluída','Cancelada') and g.prazo>=hoje and g.prazo<hoje+dias
   and public.axe_gestao_pode(g.id,p_usuario)
 ), meses as (
  select m::date mes from generate_series(inicio::timestamp,mes::timestamp,interval '1 month') m
 )
 select jsonb_build_object('hoje',hoje,'dias',dias,
  'a_pagar_hoje',(select coalesce(jsonb_agg(to_jsonb(z) order by z.moeda),'[]') from
   (select moeda,sum(valor) valor,count(*) quantidade from aberto where vencimento=hoje group by moeda) z),
  'vencidos',(select coalesce(jsonb_agg(to_jsonb(z) order by z.moeda),'[]') from
   (select moeda,sum(valor) valor,count(*) quantidade from aberto where vencimento<hoje group by moeda) z),
  'pago_mes',(select coalesce(jsonb_agg(to_jsonb(z) order by z.moeda),'[]') from
   (select moeda,sum(valor) valor,count(*) quantidade from pagos where data between mes and hoje group by moeda) z),
  'entregas',(select count(*) from entrega),
  'meses',(select coalesce(jsonb_agg(jsonb_build_object('mes',m.mes,
   'compras',(select count(*) from public.imp_pedidos p where p.status not in ('Cancelado','Elaboração')
    and p.data_pedido>=m.mes and p.data_pedido<m.mes+interval '1 month' and p.data_pedido<=hoje),
   'vendas',(select count(*) from public.comercial_pedidos p where coalesce(p.estado,'') not in ('CANCELADO','RASCUNHO')
    and (p.criado_em at time zone 'America/Sao_Paulo')::date>=m.mes
    and (p.criado_em at time zone 'America/Sao_Paulo')::date<m.mes+interval '1 month'
    and (p.criado_em at time zone 'America/Sao_Paulo')::date<=hoje),
   'pagamentos',(select coalesce(jsonb_object_agg(z.moeda,z.valor),'{}') from
    (select moeda,sum(valor) valor from pagos where data>=m.mes and data<m.mes+interval '1 month' and data<=hoje group by moeda) z)
  ) order by m.mes),'[]') from meses m),
  'agenda',(select coalesce(jsonb_agg(to_jsonb(z) order by z.data,z.tipo,z.titulo),'[]') from
   (select * from agenda order by data,tipo,titulo limit 80) z),
  'agenda_total',(select count(*) from agenda)
 ) into resultado;
 return resultado;
end $$;
revoke all on function public.axe_imp_estrutura(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_imp_estrutura(jsonb,uuid) to service_role;
