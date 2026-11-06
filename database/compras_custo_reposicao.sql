alter function public.axe_imp_estrutura(jsonb,uuid) rename to axe_imp_estrutura_sem_custo_reposicao;
create function public.axe_imp_estrutura(p_dados jsonb,p_usuario uuid) returns jsonb
language plpgsql set search_path='' as $$
declare
 pid bigint;
 produto public.produtos_conciliacao;
 saldo jsonb;
 compra jsonb;
 invoice jsonb;
begin
 if p_dados->>'acao' is distinct from 'v2_produto_custo_reposicao' then
  return public.axe_imp_estrutura_sem_custo_reposicao(p_dados,p_usuario);
 end if;
 perform public.axe_imp_estrutura_sem_custo_reposicao('{"acao":"v2_opcoes"}',p_usuario);
 pid:=public.axe_cadastro_canonico('produto',(p_dados->>'produto_id')::bigint);
 select * into produto from public.produtos_conciliacao where id=pid;
 if produto.id is null then raise exception 'Produto não encontrado';end if;
 select jsonb_build_object('quantidade',s.quantidade,'unidade',s.unidade,
  'custo_medio',case when s.quantidade>0 then s.custo_medio end)
 into saldo from public.estoque_saldos s where s.produto_id=pid;

 select jsonb_build_object('origem','Estoque','moeda',l.fonte#>>'{embarque,moeda}',
  'valor_unitario',round((i#>>'{composicao,fob_me}')::numeric/m.quantidade,8),'unidade',m.unidade,
  'despesas_unitarias_brl',case when i#>>'{composicao,fob_brl}' is not null
    then round((m.valor_total-(i#>>'{composicao,fob_brl}')::numeric)/m.quantidade,8) end,
  'data',m.data_movimento,'pedido',i->>'pedido','linha',i->>'linha',
  'embarque',l.fonte#>>'{embarque,referencia}','fornecedor',f.razao_social)
 into compra
 from public.estoque_movimentos m join public.estoque_lotes_importacao l on l.id=m.lote_importacao_id
 join public.imp_embarques e on e.id=l.embarque_id join public.fornecedores f on f.id=e.fornecedor_id
 cross join lateral jsonb_array_elements(l.fonte->'itens') i
 where m.produto_id=pid and m.motivo='IMPORTACAO' and m.tipo='ENTRADA'
  and i->>'pedido_item_id'=m.pedido_item_id::text and (i#>>'{composicao,fob_me}')::numeric>0
  and l.fonte#>>'{embarque,moeda}' ~ '^[A-Z]{3}$' and l.fonte#>>'{embarque,moeda}'<>'BRL'
  and not exists(select 1 from public.estoque_movimentos x where x.estorno_de=m.id)
 order by m.data_movimento desc,m.ordem desc limit 1;

 select jsonb_build_object('origem','Invoice','moeda',e.moeda,'valor_unitario',li.valor_unitario,'unidade',produto.unidade_referencia,
   'data',coalesce(nullif(l.dados->>'data_invoice','')::date,(l.criado_em at time zone 'America/Sao_Paulo')::date),
   'pedido',p.referencia,'linha',pi.linha,'embarque',e.referencia,'fornecedor',f.razao_social)
  into invoice
  from public.imp_pedido_itens pi
  join public.imp_liberacao_itens li on li.pedido_item_id=pi.id
  join public.imp_liberacoes l on l.id=li.liberacao_id
  join public.imp_pedidos p on p.id=pi.pedido_id
  join public.imp_embarques e on e.id=l.embarque_id
  join public.fornecedores f on f.id=p.fornecedor_id
  where pi.produto_id=pid and p.status<>'Cancelado' and e.status<>'Cancelado'
   and e.moeda ~ '^[A-Z]{3}$' and e.moeda<>'BRL' and upper(btrim(f.pais))<>'BR'
   and not exists(select 1 from public.estoque_lotes_importacao l2 join public.estoque_movimentos m2 on m2.lote_importacao_id=l2.id
     where l2.embarque_id=e.id and m2.pedido_item_id=pi.id)
   and li.valor_unitario>0 and upper(btrim(pi.unidade))=upper(btrim(produto.unidade_referencia))
  order by coalesce(nullif(l.dados->>'data_invoice','')::date,(l.criado_em at time zone 'America/Sao_Paulo')::date) desc,l.criado_em desc,pi.id
  limit 1;
 if invoice is not null and (compra is null or (invoice->>'data')::date>(compra->>'data')::date) then compra:=invoice;end if;
 return jsonb_build_object('saldo',saldo,'compra',compra,
  'importado',produto.forma_obtencao='IMP' or compra is not null);
end $$;
revoke all on function public.axe_imp_estrutura(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_imp_estrutura(jsonb,uuid) to service_role;
