CREATE OR REPLACE FUNCTION public.axe_imp_programar_parcelas(pid uuid, uid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare p public.imp_pedidos;total numeric;termos text;partes jsonb:='[]';r record;x jsonb;pct numeric;valor numeric;acumulado numeric:=0;idx int:=0;marco text;base date;dias int;cond text;lib record;usado numeric;parid uuid;
begin
 if not exists(select 1 from public.gestao_membros m join public.axe_rumo_revisores rv on rv.usuario_id=m.usuario_id and rv.ativo where m.usuario_id=uid and m.ativo and m.papel in ('ADMIN','EDITOR')) then return;end if;
 perform pg_advisory_xact_lock(728102826);
 select * into p from public.imp_pedidos where id=pid for update;if not found or p.status='Cancelado' or p.forma_pagamento is null then return;end if;
 select coalesce(sum(round(quantidade*valor_unitario,2)),0) into total from public.imp_pedido_itens where pedido_id=pid;if total<=0 then return;end if;
 termos:=nullif(btrim(p.condicao_pagamento),'');
 select coalesce((select string_agg(value,'; ') from jsonb_array_elements_text(a.extraido->'condicoes')),termos) into cond from public.imp_acks a where a.pedido_id=pid and a.aplicado_em is not null order by a.aplicado_em desc limit 1;
 if cond is not null and public.axe_imp_forma_pagamento_sugerida(cond) is not null and public.axe_imp_forma_pagamento_sugerida(cond)<>p.forma_pagamento then return;end if;
 termos:=lower(coalesce(cond,termos,case when p.forma_pagamento='ANTECIPADO' then '100% antecipado' else '' end));
 if p.forma_pagamento in ('ANTECIPADO','PARCELADO') then
  if exists(select 1 from public.imp_parcelas where pedido_id=pid and status<>'Cancelada') then return;end if;
  if p.forma_pagamento='ANTECIPADO' and (termos ~ '(parcial|partial|saldo|restante|balance)' or termos ~ '%.*%' or (termos ~ '%' and coalesce(replace(substring(termos from '([0-9]+(?:[.,][0-9]+)?)\s*%'),',','.')::numeric,0)<>100) or termos ~ '(usd|us\$|r\$|brl)[[:space:]]*[0-9]') then return;end if;
  if p.forma_pagamento='ANTECIPADO' then partes:=jsonb_build_array(jsonb_build_object('pct',100,'termos',termos));
  else
   for r in select regexp_matches(termos,'([0-9]+?(?:[.,][0-9]+)?)\s*%\s*([\s\S]*?)(?=[0-9]+(?:[.,][0-9]+)?\s*%|$)','g') m loop
    pct:=replace(r.m[1],',','.')::numeric;if pct<=0 or pct>100 then return;end if;partes:=partes||jsonb_build_array(jsonb_build_object('pct',pct,'termos',r.m[2]));
   end loop;
   if jsonb_array_length(partes) not between 1 and 12 or (select sum((value->>'pct')::numeric) from jsonb_array_elements(partes))<>100 then return;end if;
  end if;
  for x in select value from jsonb_array_elements(partes) loop
   idx:=idx+1;pct:=(x->>'pct')::numeric;valor:=case when idx=jsonb_array_length(partes) then total-acumulado else round(total*pct/100,2) end;acumulado:=acumulado+valor;
   marco:=case when x->>'termos' ~ '(antecip|advance|pedido|order)' then 'Pedido' when x->>'termos' ~ '(entrega|delivery|embarque|shipment|invoice|coleta|disponib|due|net)' then 'Disponibilização / invoice' else 'Manual' end;
   base:=case when marco='Pedido' then p.data_pedido else null end;
   dias:=coalesce(substring(x->>'termos' from '([0-9]{1,3})\s*(?:due|dias|days)')::int,substring(x->>'termos' from 'net\s*([0-9]{1,3})')::int,0);
   perform public.axe_imp_estrutura(jsonb_build_object('acao','v2_salvar','tipo','parcelas','requisicao_id',gen_random_uuid(),'dados',jsonb_build_object('pedido_id',pid,'referencia',p.referencia||' / parcela '||idx,'modo','Valor','valor',valor,'marco',marco,'data_base',base,'dias',dias,'status','Prevista','valor_pago',0)),uid);
  end loop;
 else
  for lib in select l.* from public.imp_liberacoes l join public.imp_embarques e on e.id=l.embarque_id and e.status<>'Cancelado' where l.pedido_id=pid order by l.criado_em,l.id loop
   select coalesce(sum(lp.valor),0) into usado from public.imp_liberacao_parcelas lp where lp.liberacao_id=lib.id;
   valor:=(lib.dados->>'valor')::numeric-usado;if valor<=0 then continue;end if;
   -- Parcelas existentes cobrem o pedido: não acrescente uma cobrança duplicada.
   if (select coalesce(sum(pa.valor),0) from public.imp_parcelas pa where pa.pedido_id=pid and pa.status<>'Cancelada')+valor>total then continue;end if;
   base:=nullif(lib.dados->>'data_invoice','')::date;
   dias:=case when p.forma_pagamento='NA_ENTREGA' then 0 else coalesce(nullif(lib.dados->>'dias','')::int,substring(termos from '([0-9]{1,3})\s*(?:due|dias|days)')::int,substring(termos from 'net\s*([0-9]{1,3})')::int) end;
   marco:=case when dias is null then 'Manual' else 'Disponibilização / invoice' end;
   x:=public.axe_imp_estrutura(jsonb_build_object('acao','v2_salvar','tipo','parcelas','requisicao_id',gen_random_uuid(),'dados',jsonb_build_object('pedido_id',pid,'referencia',p.referencia||' / invoice '||lib.invoice,'modo','Valor','valor',valor,'marco',marco,'data_base',base,'dias',coalesce(dias,0),'proforma',lib.invoice,'status','Prevista','valor_pago',0)),uid);
   parid:=(x->>'id')::uuid;insert into public.imp_liberacao_parcelas(liberacao_id,parcela_id,valor)values(lib.id,parid,valor);
  end loop;
 end if;
end $function$
;