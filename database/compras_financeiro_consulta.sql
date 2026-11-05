create or replace function public.axe_imp_estrutura(p_dados jsonb,p_usuario uuid) returns jsonb language plpgsql set search_path='' as $$
declare r jsonb;d jsonb:=p_dados->'dados';national boolean;plano jsonb;forma text;pid uuid;pa public.imp_parcelas;x jsonb;anterior_programacao jsonb;pagina int:=coalesce((p_dados->>'pagina')::int,0);term text:=left(coalesce(p_dados->>'busca',''),200);abertas boolean:=coalesce((p_dados->>'somente_abertas')::boolean,false);begin
 if p_dados->>'acao'='v2_listar'and p_dados->>'tipo'='parcelas'and p_dados->>'origem'='nacional'then
 r:=public.axe_imp_estrutura_sem_financeiro_nacional(jsonb_build_object('acao','v2_opcoes'),p_usuario);
 if pagina<0 or pagina>100000 then raise exception 'Página inválida';end if;
 return jsonb_build_object('editar',r->'editar','total',(select count(*)from public.imp_parcelas cp join public.imp_pedidos po on po.id=cp.pedido_id join public.fornecedores f on f.id=po.fornecedor_id where f.pais='BR'and po.moeda='BRL'and po.status<>'Cancelado'and cp.status<>'Cancelada'and(not abertas or cp.valor_pago<cp.valor)and(po.referencia||' '||f.razao_social||' '||cp.referencia)ilike '%'||term||'%'),
 'linhas',(select coalesce(jsonb_agg(to_jsonb(z)),'[]')from(select cp.*,po.referencia pedido,f.razao_social fornecedor,po.moeda,
 (select string_agg(n.documento->>'numero',' / ' order by n.criado_em)from public.compras_nfe_parcelas l join public.compras_nfe_entradas n on n.id=l.entrada_id where l.parcela_id=cp.id and l.ativo)notas
 from public.imp_parcelas cp join public.imp_pedidos po on po.id=cp.pedido_id join public.fornecedores f on f.id=po.fornecedor_id where f.pais='BR'and po.moeda='BRL'and po.status<>'Cancelado'and cp.status<>'Cancelada'and(not abertas or cp.valor_pago<cp.valor)and(po.referencia||' '||f.razao_social||' '||cp.referencia)ilike '%'||term||'%'order by cp.vencimento nulls last,cp.id limit 30 offset pagina*30)z));
 end if;
 if not public.axe_compra_fin_autorizado(p_usuario)then return public.axe_imp_estrutura_sem_financeiro_nacional(p_dados,p_usuario);end if;
 if p_dados->>'acao'='v2_opcoes'then
 r:=public.axe_imp_estrutura_sem_financeiro_nacional(p_dados,p_usuario);
 return r||jsonb_build_object('fornecedores',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'nome',razao_social,'pais',pais) order by razao_social),'[]')from public.fornecedores where ativo));end if;
 if p_dados->>'acao'='v2_salvar'then
 perform pg_advisory_xact_lock(728102826);
 if exists(select 1 from public.imp_requisicoes where usuario_id=p_usuario and requisicao_id=(p_dados->>'requisicao_id')::uuid)then return public.axe_imp_estrutura_sem_financeiro_nacional(p_dados,p_usuario);end if;
 if p_dados->>'tipo'='pedidos'then
 select upper(btrim(pais))='BR' into national from public.fornecedores where id=(d->>'fornecedor_id')::bigint;
 if national then
 if nullif(d->>'meio_pagamento_previsto','')is not null and d->>'meio_pagamento_previsto'not in('PIX','CARTAO','BOLETO','TRANSFERENCIA_BANCARIA')then raise exception 'Escolha o meio de pagamento nacional';end if;
 forma:=d->>'forma_pagamento';plano:=coalesce(d->'programacao_financeira','[]');
 if jsonb_typeof(plano)<>'array' or jsonb_array_length(plano)>24 then raise exception 'Confira a programação financeira';end if;
 if d->>'status' not in('Elaboração','Cancelado')then
 if forma is null or forma not in('ANTECIPADO','PARCELADO','NA_ENTREGA','A_PRAZO')then raise exception 'Informe a forma de pagamento do pedido nacional';end if;
 if forma='ANTECIPADO'and nullif(d->>'data_pedido','')is null then raise exception 'Informe a data do pedido para o adiantamento';end if;
 if forma<>'ANTECIPADO'and nullif(d->>'previsao_entrega','')is null then raise exception 'Informe a previsão de entrega para o provisionamento';end if;
 if forma in('PARCELADO','A_PRAZO')and (jsonb_array_length(plano)=0 or (select sum((z->>'percentual')::numeric)from jsonb_array_elements(plano)z)<>100)then raise exception 'Distribua 100%% do pedido nas parcelas previstas';end if;
 end if;
 for x in select value from jsonb_array_elements(plano)loop
 if coalesce(x->>'base','')not in('Pedido','Entrega')or coalesce((x->>'dias')::int,-1)not between 0 and 3650 or coalesce((x->>'percentual')::numeric,0)<=0 or (x->>'percentual')::numeric>100 or (x->>'percentual')::numeric::text='NaN' then raise exception 'Confira base, prazo e percentual das parcelas';end if;end loop;
 end if;
 elsif p_dados->>'tipo'='parcelas'and nullif(p_dados->>'id','')is not null then
 select * into pa from public.imp_parcelas where id=(p_dados->>'id')::uuid for update;
 if exists(select 1 from public.compras_nfe_parcelas where parcela_id=pa.id and ativo)and (d->>'status'='Cancelada' or (d->>'valor')::numeric is distinct from pa.valor or nullif(d->>'vencimento','')::date is distinct from pa.vencimento or d->>'modo'<>'Valor' or d->>'marco'<>'Manual')then raise exception 'Parcela vinculada à NF-e: preserve o título confirmado. Correções exigem estorno da nota e nova conferência';end if;
 end if;
 end if;
 r:=public.axe_imp_estrutura_sem_financeiro_nacional(p_dados,p_usuario);
 if p_dados->>'acao'='v2_salvar'and p_dados->>'tipo'='parcelas' then update public.imp_parcelas set financeiro=financeiro||jsonb_build_object('automatico',false)where id=(r->>'id')::uuid;end if;
 if p_dados->>'acao'='v2_salvar'and p_dados->>'tipo'='pedidos'and national then
 pid:=(r->>'id')::uuid;
 select to_jsonb(po)into anterior_programacao from public.imp_pedidos po where po.id=pid;
 update public.imp_pedidos set previsao_entrega=nullif(d->>'previsao_entrega','')::date,programacao_financeira=plano,meio_pagamento_previsto=nullif(d->>'meio_pagamento_previsto','') where id=pid;
 insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('pedidos',pid,p_usuario,anterior_programacao,(select to_jsonb(po)from public.imp_pedidos po where po.id=pid));
 -- O gatilho diferido processa o pedido completo, incluindo os itens.
 end if;
 return r;
end $$;
