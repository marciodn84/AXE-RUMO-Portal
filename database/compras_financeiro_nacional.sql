-- Financeiro nacional: provisão no pedido e consolidação atômica com a NF-e.
-- Aplicar uma vez. Os dados fiscais e financeiros continuam privados.
alter table public.imp_pedidos add column previsao_entrega date, add column programacao_financeira jsonb not null default '[]', add column meio_pagamento_previsto text references public.compras_meios_pagamento(codigo);
alter table public.imp_parcelas add column financeiro jsonb not null default '{}';
create table public.compras_nfe_parcelas(
 entrada_id uuid not null references public.compras_nfe_entradas(id),
 parcela_id uuid not null references public.imp_parcelas(id),valor numeric(18,2) not null check(valor>0),
 ativo boolean not null default true, primary key(entrada_id,parcela_id));
create index compras_nfe_parcelas_parcela on public.compras_nfe_parcelas(parcela_id);
create table public.compras_financeiro_conferencias(
 entrada_id uuid primary key references public.compras_nfe_entradas(id),pedido_id uuid not null references public.imp_pedidos(id),
 anterior jsonb not null,atual jsonb not null,plano jsonb not null,usuario_id uuid not null references auth.users(id),
 criado_em timestamptz not null default clock_timestamp(),estornado boolean not null default false);
create index compras_financeiro_conferencias_pedido on public.compras_financeiro_conferencias(pedido_id);
alter table public.compras_nfe_parcelas enable row level security;
alter table public.compras_financeiro_conferencias enable row level security;
revoke all on public.compras_nfe_parcelas,public.compras_financeiro_conferencias from public,anon,authenticated;
grant select,insert,update on public.compras_nfe_parcelas,public.compras_financeiro_conferencias to service_role;

create function public.axe_compra_fin_autorizado(uid uuid) returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from public.gestao_membros m join public.axe_rumo_revisores r on r.usuario_id=m.usuario_id and r.ativo where m.usuario_id=uid and m.ativo and m.papel in('ADMIN','EDITOR'));
$$;
create function public.axe_compra_fin_snapshot(pid uuid) returns jsonb language sql stable set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(p) order by p.id),'[]') from public.imp_parcelas p where p.pedido_id=pid and p.status<>'Cancelada';
$$;
create function public.axe_compra_fin_contexto(pid uuid,uid uuid) returns jsonb language plpgsql set search_path='' as $$
declare p public.imp_pedidos;begin
 if not public.axe_compra_fin_autorizado(uid) then raise exception 'Sem permissão para conferir o financeiro';end if;
 select * into p from public.imp_pedidos where id=pid;
 return jsonb_build_object('token',md5(public.axe_compra_fin_snapshot(pid)::text),'forma',p.forma_pagamento,'meio_pagamento',p.meio_pagamento_previsto,'data_pedido',p.data_pedido,'condicao',p.condicao_pagamento,'previsao_entrega',p.previsao_entrega,
 'parcelas',(select coalesce(jsonb_agg(to_jsonb(pa)||jsonb_build_object('confirmado',(select coalesce(sum(l.valor),0) from public.compras_nfe_parcelas l where l.parcela_id=pa.id and l.ativo)) order by pa.vencimento,pa.id),'[]') from public.imp_parcelas pa where pa.pedido_id=pid and pa.status<>'Cancelada'),
 'saldo_mercadorias',(select coalesce(sum(round(greatest(0,i.quantidade-public.axe_compra_nfe_recebida(i.id))*i.valor_unitario,2)),0) from public.imp_pedido_itens i where i.pedido_id=pid),
 'confirmado',(select coalesce(sum((n.documento->'totais'->>'vNF')::numeric),0) from public.compras_nfe_entradas n where n.pedido_id=pid and n.estado='Confirmada'));
end $$;

alter function public.axe_compra_nfe_ler(text) rename to axe_compra_nfe_ler_sem_pagamento;
create function public.axe_compra_nfe_ler(conteudo text) returns jsonb language plpgsql immutable set search_path='' as $$
declare res jsonb;d xml;r xml;pag jsonb:='[]';begin
 res:=public.axe_compra_nfe_ler_sem_pagamento(conteudo);d:=xmlparse(document conteudo);
 foreach r in array xpath('/n:nfeProc/n:NFe/n:infNFe/n:pag/n:detPag',d,array[array['n','http://www.portalfiscal.inf.br/nfe']])loop
 pag:=pag||jsonb_build_array(jsonb_build_object('codigo',public.axe_nfe_texto(r,'/n:detPag/n:tPag/text()'),'descricao',public.axe_nfe_texto(r,'/n:detPag/n:xPag/text()'),'valor',public.axe_nfe_numero(public.axe_nfe_texto(r,'/n:detPag/n:vPag/text()'))));end loop;
 return res||jsonb_build_object('pagamentos',pag,'troco',public.axe_nfe_numero(public.axe_nfe_texto(d,'/n:nfeProc/n:NFe/n:infNFe/n:pag/n:vTroco/text()')));
end $$;

alter function public.axe_imp_programar_parcelas(uuid,uuid) rename to axe_imp_programar_parcelas_importacao;
create function public.axe_imp_programar_parcelas(pid uuid,uid uuid) returns void language plpgsql set search_path='' as $$
declare p public.imp_pedidos;x jsonb;pa public.imp_parcelas;total numeric;v numeric;ac numeric:=0;idx int:=0;base date;old jsonb;plano jsonb;begin
 if not public.axe_compra_fin_autorizado(uid)then return;end if;
 perform pg_advisory_xact_lock(728102826);
 select * into p from public.imp_pedidos where id=pid for update;if not found then return;end if;
 if not exists(select 1 from public.fornecedores where id=p.fornecedor_id and upper(btrim(pais))='BR')then perform public.axe_imp_programar_parcelas_importacao(pid,uid);return;end if;
 if p.status in('Elaboração','Cancelado')or p.forma_pagamento is null then return;end if;
 if exists(select 1 from public.compras_nfe_entradas where pedido_id=pid and estado='Confirmada')then return;end if;
 select coalesce(sum(round(quantidade*valor_unitario,2)),0) into total from public.imp_pedido_itens where pedido_id=pid;if total<=0 then return;end if;
 -- Preserva parcelas manuais/pagas e provisiona apenas eventual acréscimo do pedido.
 if exists(select 1 from public.imp_parcelas where pedido_id=pid and status<>'Cancelada' and (valor_pago>0 or financeiro->>'automatico' is distinct from 'true'))then
 select total-coalesce(sum(pp.valor),0) into v from public.imp_parcelas pp where pp.pedido_id=pid and pp.status<>'Cancelada' and not(coalesce(pp.financeiro->>'complemento','false')='true'and pp.financeiro->>'automatico'='true'and pp.valor_pago=0);
 if v<0 then raise exception 'As parcelas manuais ou pagas ultrapassam o pedido. Resolva a programação antes de salvar';end if;
 select * into pa from public.imp_parcelas where pedido_id=pid and status<>'Cancelada'and financeiro->>'complemento'='true'and financeiro->>'automatico'='true'and valor_pago=0 order by criado_em limit 1 for update;old:=to_jsonb(pa);
 base:=case when p.forma_pagamento='ANTECIPADO'then p.data_pedido else p.previsao_entrega end;
 if v>0 and base is null then raise exception 'Informe a data-base para provisionar o saldo do pedido';end if;
 if v>0 and pa.id is null then insert into public.imp_parcelas(pedido_id,referencia,modo,valor,marco,data_base,dias,vencimento,status,valor_pago,atualizado_por,financeiro)values(pid,p.referencia||' / saldo previsto','Valor',v,'Manual',base,0,base,'Prevista',0,uid,jsonb_build_object('automatico',true,'complemento',true,'fase','Provisionado'))returning * into pa;
 elsif pa.id is not null then update public.imp_parcelas set valor=case when v>0 then v else valor end,status=case when v=0 then 'Cancelada'else 'Prevista'end,vencimento=base,versao=versao+1,atualizado_por=uid,atualizado_em=clock_timestamp()where id=pa.id and (valor is distinct from v or vencimento is distinct from base) returning * into pa;end if;
 if pa.id is not null and pa.meio_pagamento is distinct from p.meio_pagamento_previsto then update public.imp_parcelas set meio_pagamento=p.meio_pagamento_previsto,versao=versao+1,atualizado_por=uid,atualizado_em=clock_timestamp() where id=pa.id returning * into pa;end if;
 if pa.id is not null and old is distinct from to_jsonb(pa)then insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('parcelas',pa.id,uid,old,to_jsonb(pa));end if;return;
 end if;
 plano:=p.programacao_financeira;
 if p.forma_pagamento='ANTECIPADO' then plano:='[{"percentual":100,"dias":0,"base":"Pedido"}]';
 elsif p.forma_pagamento='NA_ENTREGA' then plano:='[{"percentual":100,"dias":0,"base":"Entrega"}]';end if;
 if jsonb_array_length(plano)=0 then return;end if;
 for x in select value from jsonb_array_elements(plano)loop
 idx:=idx+1;base:=case when x->>'base'='Pedido' then p.data_pedido else p.previsao_entrega end;
 if base is null then raise exception 'Informe a data do pedido e a previsão de entrega para programar o financeiro';end if;
 v:=case when idx=jsonb_array_length(plano)then total-ac else round(total*(x->>'percentual')::numeric/100,2)end;ac:=ac+v;
 select * into pa from public.imp_parcelas where pedido_id=pid and financeiro->>'automatico'='true' and (financeiro->>'indice')::int=idx order by criado_em limit 1 for update;old:=to_jsonb(pa);
 if pa.id is null then
 insert into public.imp_parcelas(pedido_id,referencia,modo,valor,marco,data_base,dias,vencimento,status,valor_pago,atualizado_por,financeiro)
 values(pid,p.referencia||' / parcela '||idx,'Valor',v,'Manual',base,(x->>'dias')::int,base+(x->>'dias')::int,'Prevista',0,uid,jsonb_build_object('automatico',true,'indice',idx,'base',x->>'base','dias',x->'dias','fase',case when x->>'base'='Pedido'then 'Adiantamento'else 'Provisionado'end))returning * into pa;
 else update public.imp_parcelas set valor=v,data_base=base,dias=(x->>'dias')::int,vencimento=base+(x->>'dias')::int,status='Prevista',financeiro=jsonb_build_object('automatico',true,'indice',idx,'base',x->>'base','dias',x->'dias','fase',case when x->>'base'='Pedido'then 'Adiantamento'else 'Provisionado'end),versao=versao+1,atualizado_por=uid,atualizado_em=clock_timestamp() where id=pa.id and (valor is distinct from v or vencimento is distinct from base+(x->>'dias')::int or status='Cancelada' or financeiro->>'base' is distinct from x->>'base') returning * into pa;
 end if;
 if pa.id is not null and pa.meio_pagamento is distinct from p.meio_pagamento_previsto then update public.imp_parcelas set meio_pagamento=p.meio_pagamento_previsto,versao=versao+1,atualizado_por=uid,atualizado_em=clock_timestamp() where id=pa.id returning * into pa;end if;
 if pa.id is not null and old is distinct from to_jsonb(pa)then insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('parcelas',pa.id,uid,old,to_jsonb(pa));end if;
 end loop;
 for pa in select * from public.imp_parcelas where pedido_id=pid and status<>'Cancelada' and financeiro->>'automatico'='true' and (financeiro->>'indice')::int>idx loop
 update public.imp_parcelas set status='Cancelada',versao=versao+1,atualizado_por=uid where id=pa.id;
 insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('parcelas',pa.id,uid,to_jsonb(pa),jsonb_build_object('evento','Substituição da programação automática','status','Cancelada'));
 end loop;
end $$;

alter function public.axe_imp_estrutura(jsonb,uuid) rename to axe_imp_estrutura_sem_financeiro_nacional;
create function public.axe_imp_estrutura(p_dados jsonb,p_usuario uuid) returns jsonb language plpgsql set search_path='' as $$
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

create function public.axe_compra_fin_aplicar(nid uuid,plano jsonb,antes jsonb,uid uuid) returns void language plpgsql set search_path='' as $$
declare n public.compras_nfe_entradas;p public.imp_pedidos;x jsonb;pa public.imp_parcelas;v numeric;vnota numeric;prev numeric;total numeric:=0;alocado numeric:=0;esperado numeric;idp uuid;old jsonb;locked boolean;begin
 if not public.axe_compra_fin_autorizado(uid)then raise exception 'Sem permissão para consolidar financeiro';end if;
 select * into n from public.compras_nfe_entradas where id=nid and estado='Confirmada'for update;
 if not found then raise exception 'Nota confirmada não encontrada';end if;
 select * into p from public.imp_pedidos where id=n.pedido_id for update;
 if p.moeda<>'BRL'or not exists(select 1 from public.fornecedores where id=p.fornecedor_id and pais='BR')then raise exception 'Financeiro exclusivo da compra nacional em reais';end if;
 if plano->>'conferido' is distinct from 'true'or length(btrim(coalesce(plano->>'justificativa','')))<5 then raise exception 'Confira o financeiro e justifique a consolidação com o pedido e o XML';end if;
 if jsonb_typeof(plano->'parcelas')is distinct from 'array'or jsonb_array_length(plano->'parcelas')not between 0 and 100 then raise exception 'Confira as parcelas e provisões';end if;
 if (select count(distinct z->>'id')from jsonb_array_elements(plano->'parcelas')z)<>jsonb_array_length(plano->'parcelas')then raise exception 'Parcela repetida ou sem identificação';end if;
 if exists(select 1 from public.imp_parcelas a where a.pedido_id=p.id and a.status<>'Cancelada'and not exists(select 1 from jsonb_array_elements(plano->'parcelas')z where z->>'id'=a.id::text))then raise exception 'Inclua todas as parcelas existentes na conferência';end if;
 select coalesce(sum(round(greatest(0,i.quantidade-public.axe_compra_nfe_recebida(i.id))*i.valor_unitario,2)),0) into esperado from public.imp_pedido_itens i where i.pedido_id=p.id;
 esperado:=esperado+(n.documento->'totais'->>'vNF')::numeric+(select coalesce(sum((nn.documento->'totais'->>'vNF')::numeric),0)from public.compras_nfe_entradas nn where nn.pedido_id=p.id and nn.estado='Confirmada'and nn.id<>nid);
 for x in select value from jsonb_array_elements(plano->'parcelas')loop
 idp:=(x->>'id')::uuid;v:=(x->>'valor')::numeric;vnota:=(x->>'valor_nota')::numeric;
 if idp is null or v is null or vnota is null or v<0 or v>=1e12 or vnota<0 or vnota>v or round(v,2)<>v or round(vnota,2)<>vnota or v::text='NaN'or vnota::text='NaN'then raise exception 'Confira os valores das parcelas';end if;
 select * into pa from public.imp_parcelas where id=idp for update;old:=case when found then to_jsonb(pa)else null end;
 if pa.id is not null and (pa.pedido_id<>p.id or pa.status='Cancelada')then raise exception 'Selecione uma parcela ativa deste pedido';end if;
 select coalesce(sum(valor),0) into prev from public.compras_nfe_parcelas where parcela_id=idp and ativo;
 locked:=coalesce(pa.valor_pago,0)>0 or prev>0;
 if locked and (v is distinct from pa.valor or nullif(x->>'vencimento','')::date is distinct from pa.vencimento or x->>'referencia' is distinct from pa.referencia or nullif(x->>'meio_pagamento','') is distinct from pa.meio_pagamento)then raise exception 'Preserve valores, datas e meio das parcelas já pagas ou confirmadas';end if;
 if v<greatest(prev,coalesce(pa.valor_pago,0))or vnota>v-prev then raise exception 'Valor já pago ou vinculado a outra nota. Resolva a diferença sem duplicar títulos';end if;
 if v>0 and (nullif(btrim(x->>'referencia'),'')is null or length(x->>'referencia')>240 or nullif(x->>'vencimento','')is null or coalesce(x->>'meio_pagamento','') not in('PIX','CARTAO','BOLETO','TRANSFERENCIA_BANCARIA'))then raise exception 'Informe identificação, vencimento e meio de todas as parcelas';end if;
 total:=total+v;alocado:=alocado+vnota;
 if v=0 then
 if old is not null then update public.imp_parcelas set status='Cancelada',versao=versao+1,atualizado_por=uid,atualizado_em=clock_timestamp()where id=idp;end if;
 elsif not locked then
 insert into public.imp_parcelas(id,pedido_id,referencia,modo,valor,marco,data_base,dias,vencimento,status,valor_pago,meio_pagamento,atualizado_por,financeiro)
 values(idp,p.id,x->>'referencia','Valor',v,'Manual',n.data_entrada,0,(x->>'vencimento')::date,'Prevista',0,x->>'meio_pagamento',uid,jsonb_build_object('automatico',false,'fase',case when vnota=v then 'Confirmado'when vnota>0 then 'Parcialmente confirmado'else 'Provisionado'end))
 on conflict(id)do update set referencia=excluded.referencia,modo='Valor',percentual=null,valor=excluded.valor,marco='Manual',data_base=excluded.data_base,dias=0,vencimento=excluded.vencimento,meio_pagamento=excluded.meio_pagamento,financeiro=excluded.financeiro,versao=imp_parcelas.versao+1,atualizado_por=uid,atualizado_em=clock_timestamp();
 end if;
 if vnota>0 then insert into public.compras_nfe_parcelas(entrada_id,parcela_id,valor)values(nid,idp,vnota);if locked then update public.imp_parcelas set financeiro=financeiro||jsonb_build_object('fase',case when prev+vnota=pa.valor then 'Confirmado'else 'Parcialmente confirmado'end),versao=versao+1,atualizado_por=uid,atualizado_em=clock_timestamp()where id=idp;end if;end if;
 if true then insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('parcelas',idp,uid,old,(select to_jsonb(z)from public.imp_parcelas z where z.id=idp));end if;
 end loop;
 if alocado<>(n.documento->'totais'->>'vNF')::numeric then raise exception 'Vincule exatamente o total da NF-e às parcelas, incluindo adiantamentos';end if;
 if total<>esperado then raise exception 'O financeiro deve somar R$ %: notas confirmadas mais saldo de mercadorias. Resolva o provisionamento restante',esperado;end if;
 insert into public.compras_financeiro_conferencias(entrada_id,pedido_id,anterior,atual,plano,usuario_id)values(nid,p.id,antes,public.axe_compra_fin_snapshot(p.id),plano,uid);
end $$;

alter function public.axe_compra_nfe(jsonb,uuid) rename to axe_compra_nfe_sem_financeiro;
create function public.axe_compra_nfe(p_dados jsonb,p_usuario uuid)returns jsonb language plpgsql set search_path='' as $$
declare a text:=p_dados->>'acao';r jsonb;antes jsonb;c public.estoque_requisicoes;conf public.compras_financeiro_conferencias;pid uuid:=(p_dados->>'pedido_id')::uuid;pa public.imp_parcelas;x jsonb;begin
 if a not in('compra_nf_ler','compra_nf_confirmar','compra_nf_estornar')then return public.axe_compra_nfe_sem_financeiro(p_dados,p_usuario);end if;
 if not public.axe_compra_fin_autorizado(p_usuario)then raise exception 'Sem permissão para conferir entradas e financeiro';end if;
 perform set_config('lock_timeout','5s',true);perform pg_advisory_xact_lock(728102826);perform 1 from public.imp_pedidos where id=pid for update;
 if a<>'compra_nf_ler'then
 select * into c from public.estoque_requisicoes where id=(p_dados->>'requisicao_id')::uuid;
 if found then if c.usuario_id<>p_usuario or c.dados<>p_dados then raise exception 'Identificador reutilizado com outros dados';end if;return c.resultado;end if;end if;
 if a='compra_nf_ler'then r:=public.axe_compra_nfe_sem_financeiro(p_dados,p_usuario);return r||jsonb_build_object('financeiro',public.axe_compra_fin_contexto(pid,p_usuario));end if;
 antes:=public.axe_compra_fin_snapshot(pid);
 if a='compra_nf_confirmar'then
 if p_dados->'financeiro'->>'token' is distinct from md5(antes::text)then raise exception 'O financeiro mudou desde a leitura. Reabra o XML e confira as parcelas';end if;
 r:=public.axe_compra_nfe_sem_financeiro(p_dados,p_usuario);
 perform public.axe_compra_fin_aplicar((r->>'id')::uuid,p_dados->'financeiro',antes,p_usuario);
 r:=r||jsonb_build_object('financeiro_consolidado',true);
 update public.estoque_requisicoes set resultado=r where id=(p_dados->>'requisicao_id')::uuid;return r;
 end if;
 select * into conf from public.compras_financeiro_conferencias where entrada_id=(p_dados->>'id')::uuid and pedido_id=pid and not estornado for update;
 if found and (select coalesce(jsonb_agg(z-'versao'-'atualizado_em'-'atualizado_por' order by z->>'id'),'[]')from jsonb_array_elements(antes)z) is distinct from (select coalesce(jsonb_agg(z-'versao'-'atualizado_em'-'atualizado_por' order by z->>'id'),'[]')from jsonb_array_elements(conf.atual)z) then raise exception 'O financeiro mudou após a nota. Resolva pagamentos e notas posteriores antes do estorno';end if;
 r:=public.axe_compra_nfe_sem_financeiro(p_dados,p_usuario);
 if conf.entrada_id is not null then
 update public.compras_nfe_parcelas set ativo=false where entrada_id=conf.entrada_id;
 for pa in select * from public.imp_parcelas where pedido_id=pid loop
 select z into x from jsonb_array_elements(conf.anterior)z where z->>'id'=pa.id::text;
 if x is null then update public.imp_parcelas set status='Cancelada',versao=versao+1,atualizado_por=p_usuario,atualizado_em=clock_timestamp()where id=pa.id;
 else update public.imp_parcelas set referencia=x->>'referencia',modo=x->>'modo',percentual=(x->>'percentual')::numeric,valor=(x->>'valor')::numeric,marco=x->>'marco',data_base=(x->>'data_base')::date,dias=(x->>'dias')::int,vencimento=(x->>'vencimento')::date,status=x->>'status',meio_pagamento=x->>'meio_pagamento',financeiro=x->'financeiro',versao=versao+1,atualizado_por=p_usuario,atualizado_em=clock_timestamp()where id=pa.id;end if;
 insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('parcelas',pa.id,p_usuario,to_jsonb(pa),(select to_jsonb(z)from public.imp_parcelas z where z.id=pa.id));
 end loop;
 update public.compras_financeiro_conferencias set estornado=true where entrada_id=conf.entrada_id;
 end if;return r;
end $$;

-- Every helper remains behind the authenticated backend's membership checks.
revoke all on function public.axe_compra_fin_autorizado(uuid),public.axe_compra_fin_snapshot(uuid),public.axe_compra_fin_contexto(uuid,uuid),public.axe_compra_fin_aplicar(uuid,jsonb,jsonb,uuid),public.axe_compra_nfe_ler(text),public.axe_imp_programar_parcelas(uuid,uuid),public.axe_imp_estrutura(jsonb,uuid),public.axe_compra_nfe(jsonb,uuid)from public,anon,authenticated;
grant execute on function public.axe_compra_fin_autorizado(uuid),public.axe_compra_fin_snapshot(uuid),public.axe_compra_fin_contexto(uuid,uuid),public.axe_compra_fin_aplicar(uuid,jsonb,jsonb,uuid),public.axe_compra_nfe_ler(text),public.axe_imp_programar_parcelas(uuid,uuid),public.axe_imp_estrutura(jsonb,uuid),public.axe_compra_nfe(jsonb,uuid)to service_role;

-- Mantém a validação original, reconhecendo o valor fiscal consolidado no limite financeiro.
CREATE OR REPLACE FUNCTION public.axe_imp_estrutura_sem_financeiro_nacional(p_dados jsonb, p_usuario uuid)
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
 if acao='v2_opcoes' then return jsonb_build_object('editar',papel in ('ADMIN','EDITOR'),'meios_pagamento',(select coalesce(jsonb_agg(to_jsonb(mp) order by mp.nome),'[]') from public.compras_meios_pagamento mp),'formas_pagamento',(select coalesce(jsonb_agg(to_jsonb(fp) order by fp.ordem),'[]') from public.compras_formas_pagamento fp),'fornecedores',(select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'nome',f.razao_social) order by f.razao_social),'[]') from public.fornecedores f where ativo));end if;
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
  select coalesce(sum(pp.valor),0) into valor from public.imp_parcelas pp where pp.pedido_id=i and pp.status<>'Cancelada' and not(pp.valor_pago=0 and coalesce(pp.financeiro->>'automatico','false')='true' and exists(select 1 from public.fornecedores f where f.id=fornecedor and f.pais='BR') and not exists(select 1 from public.compras_nfe_entradas nn where nn.pedido_id=i and nn.estado='Confirmada'));
  if total<valor and not (total=coalesce((antes->>'total')::numeric,-1) and exists(select 1 from public.compras_financeiro_conferencias where pedido_id=i and not estornado)) then raise exception 'Total do pedido menor que as parcelas já programadas';end if;
  if st='Cancelado' and (exists(select 1 from public.imp_parcelas where pedido_id=i and status<>'Cancelada') or exists(select 1 from public.imp_pedido_itens pi join public.imp_embarque_itens ei on ei.pedido_item_id=pi.id join public.imp_embarques e on e.id=ei.embarque_id where pi.pedido_id=i and e.status<>'Cancelado')) then raise exception 'Cancele as parcelas e embarques antes do pedido';end if;
  insert into public.imp_pedidos(id,fornecedor_id,referencia,moeda,status,data_pedido,ack_numero,ack_data,condicao_pagamento,forma_pagamento,observacoes,atualizado_por)
   values(i,fornecedor,btrim(d->>'referencia'),moeda,st,nullif(d->>'data_pedido','')::date,d->>'ack_numero',nullif(d->>'ack_data','')::date,d->>'condicao_pagamento',case when d ? 'forma_pagamento' then nullif(d->>'forma_pagamento','') else public.axe_imp_forma_pagamento_sugerida(d->>'condicao_pagamento') end,d->>'observacoes',p_usuario)
   on conflict(id) do update set fornecedor_id=excluded.fornecedor_id,referencia=excluded.referencia,moeda=excluded.moeda,status=excluded.status,data_pedido=excluded.data_pedido,ack_numero=excluded.ack_numero,ack_data=excluded.ack_data,condicao_pagamento=case when d ? 'condicao_pagamento' then excluded.condicao_pagamento else imp_pedidos.condicao_pagamento end,forma_pagamento=case when d ? 'forma_pagamento' then excluded.forma_pagamento else coalesce(imp_pedidos.forma_pagamento,excluded.forma_pagamento) end,observacoes=excluded.observacoes,versao=imp_pedidos.versao+1,atualizado_por=p_usuario,atualizado_em=clock_timestamp();
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
  if exists(select 1 from public.fornecedores where id=pedido.fornecedor_id and pais='BR') and exists(select 1 from public.compras_financeiro_conferencias where pedido_id=pedido.id and not estornado) then select greatest(total,coalesce(sum(fp.valor),0)) into total from public.imp_parcelas fp where fp.pedido_id=pedido.id and fp.status<>'Cancelada';end if;
  if d->>'modo'='Percentual' then pct:=(d->>'percentual')::numeric;if pct is null or pct<=0 or pct>100 then raise exception 'Percentual deve ser maior que zero e até 100';end if;valor:=round(total*pct/100,2);
  elsif d->>'modo'='Valor' then valor:=(d->>'valor')::numeric;
  else raise exception 'Modo da parcela inválido';end if;
  if valor is null or valor<=0 or valor>=1e12 then raise exception 'Valor da parcela inválido';end if;
  if d->>'status'='Prevista' and valor+(select coalesce(sum(p.valor),0) from public.imp_parcelas p where p.pedido_id=pedido.id and p.id<>i and p.status<>'Cancelada')>total then raise exception 'Parcelas ultrapassam o valor do pedido';end if;
  pago:=coalesce(nullif(d->>'valor_pago','')::numeric,0);
  if pago<0 or pago>valor or pago::text in ('NaN','Infinity','-Infinity') then raise exception 'Pagamento deve estar entre zero e o valor da parcela';end if;
  dias:=coalesce(nullif(d->>'dias','')::int,0);base:=nullif(d->>'data_base','')::date;
  if d->>'marco'='Manual' then venc:=nullif(d->>'vencimento','')::date;else venc:=base+dias;end if;
  insert into public.imp_parcelas(id,pedido_id,referencia,modo,percentual,valor,marco,data_base,dias,vencimento,proforma,status,valor_pago,data_pagamento,cambio,contrato_cambio,meio_pagamento,observacoes,atualizado_por)
  values(i,pedido.id,d->>'referencia',d->>'modo',pct,valor,d->>'marco',base,dias,venc,d->>'proforma',d->>'status',pago,nullif(d->>'data_pagamento','')::date,nullif(d->>'cambio','')::numeric,d->>'contrato_cambio',nullif(d->>'meio_pagamento',''),d->>'observacoes',p_usuario)
  on conflict(id) do update set referencia=excluded.referencia,modo=excluded.modo,percentual=excluded.percentual,valor=excluded.valor,marco=excluded.marco,data_base=excluded.data_base,dias=excluded.dias,vencimento=excluded.vencimento,proforma=excluded.proforma,status=excluded.status,valor_pago=excluded.valor_pago,data_pagamento=excluded.data_pagamento,cambio=excluded.cambio,contrato_cambio=excluded.contrato_cambio,meio_pagamento=case when d ? 'meio_pagamento' then excluded.meio_pagamento else imp_parcelas.meio_pagamento end,observacoes=excluded.observacoes,versao=imp_parcelas.versao+1,atualizado_por=p_usuario,atualizado_em=clock_timestamp();
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
end $function$


;
