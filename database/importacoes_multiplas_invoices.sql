alter table public.imp_liberacao_arquivos drop constraint imp_liberacao_arquivos_liberacao_id_categoria_key;
create unique index imp_liberacao_arquivo_compartilhado on public.imp_liberacao_arquivos(liberacao_id,categoria) where categoria<>'INVOICE';

create table public.imp_liberacao_invoices(
 liberacao_id uuid not null references public.imp_liberacoes(id),
 pedido_id uuid not null references public.imp_pedidos(id),
 numero text not null,
 arquivo_id uuid not null unique references public.imp_liberacao_arquivos(id),
 dados jsonb not null,
 primary key(pedido_id,numero)
);
alter table public.imp_liberacao_invoices enable row level security;
revoke all on public.imp_liberacao_invoices from public,anon,authenticated;
grant select,insert on public.imp_liberacao_invoices to service_role;

CREATE OR REPLACE FUNCTION public.axe_liberacao_documental(p_dados jsonb, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare a text:=p_dados->>'acao'; papel text; p jsonb; d jsonb:=p_dados->'dados'; i uuid; req uuid; r record; x jsonb; y record; valor numeric; total numeric:=0; atribuido numeric:=0; q numeric; previa numeric; novo numeric; par public.imp_parcelas; parc jsonb; emb jsonb; parcelas jsonb:='[]'; antes jsonb; result jsonb; parcela_req uuid; embarque_req uuid; f record; lote jsonb; doc jsonb; pos int;
begin
 select m.papel into papel from public.gestao_membros m join public.axe_rumo_revisores rv on rv.usuario_id=m.usuario_id and rv.ativo where m.usuario_id=p_usuario and m.ativo;
 if papel is null then raise exception 'Usuário sem acesso às importações';end if;
 if a not in ('lib_contexto','lib_aprovar','lib_arquivo') or a is null then raise exception 'Ação inválida';end if;
 if a='lib_arquivo' then select * into f from public.imp_liberacao_arquivos where id=(p_dados->>'id')::uuid;if not found then raise exception 'Arquivo não encontrado';end if;return to_jsonb(f);end if;
 perform pg_advisory_xact_lock(728102826);
 p:=public.axe_imp_estrutura_detalhe('pedidos',(p_dados->>'pedido_id')::uuid);if p is null or p->>'status'='Cancelado' then raise exception 'Pedido inexistente ou cancelado';end if;
 if a='lib_contexto' then return jsonb_build_object('pedido',p,'editar',papel in ('ADMIN','EDITOR'),'liberacoes',(select coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object('parcelas',(select coalesce(jsonb_agg(to_jsonb(lp)),'[]') from public.imp_liberacao_parcelas lp where lp.liberacao_id=l.id),'arquivos',(select coalesce(jsonb_agg(jsonb_build_object('id',fa.id,'nome',fa.nome,'categoria',fa.categoria)),'[]') from public.imp_liberacao_arquivos fa where fa.liberacao_id=l.id)) order by l.criado_em desc),'[]') from public.imp_liberacoes l where l.pedido_id=(p->>'id')::uuid),'creditos',(select coalesce(jsonb_agg(to_jsonb(pa)||jsonb_build_object('utilizado',(select coalesce(sum(lp.valor),0) from public.imp_liberacao_parcelas lp where lp.parcela_id=pa.id))),'[]') from public.imp_parcelas pa where pa.pedido_id=(p->>'id')::uuid and pa.status<>'Cancelada'));end if;
 if papel not in ('ADMIN','EDITOR') or p_dados->>'confirmado' is distinct from 'true' then raise exception 'Confirme a conferência dos documentos e da parcial';end if;
 req:=(p_dados->>'requisicao_id')::uuid;if req is null then raise exception 'Identificador obrigatório';end if;
 select * into r from public.imp_requisicoes where usuario_id=p_usuario and requisicao_id=req;
 if found then if r.dados is distinct from p_dados then raise exception 'Identificador reutilizado com outros dados';end if;return r.resultado;end if;
 if (p->>'versao')::int is distinct from (p_dados->>'versao')::int then raise exception 'Pedido alterado. Reabra os documentos antes de aprovar';end if;
 if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>300000 then raise exception 'Dados inválidos';end if;
 lote:=d->'invoices';
 if lote is not null then
  if jsonb_typeof(lote) is distinct from 'array' or jsonb_array_length(lote) not between 2 and 12 then raise exception 'Informe de 2 a 12 invoices';end if;
  if exists(select 1 from jsonb_array_elements(lote) v group by upper(btrim(v->>'invoice')) having count(*)>1) then raise exception 'Há números de invoice repetidos';end if;
  for doc in select value from jsonb_array_elements(lote) loop
   if coalesce(length(btrim(doc->>'invoice')),0) not between 1 and 100 or doc->>'moeda' is distinct from p->>'moeda'
    or jsonb_typeof(doc->'itens') is distinct from 'array' or jsonb_array_length(doc->'itens') not between 1 and 100
    or exists(select 1 from jsonb_array_elements(doc->'itens') z group by (z->>'pedido_item_id')::uuid having count(*)>1)
    or exists(select 1 from jsonb_array_elements(doc->'itens') z
      left join public.imp_pedido_itens pi on pi.id=(z->>'pedido_item_id')::uuid and pi.pedido_id=(p->>'id')::uuid
      where pi.id is null or (z->>'valor_unitario')::numeric is distinct from pi.valor_unitario
       or coalesce((z->>'quantidade')::numeric,0)<=0 or (z->>'quantidade')::numeric>pi.quantidade
       or (z->>'quantidade')::numeric<>round((z->>'quantidade')::numeric,6))
    or coalesce((doc->>'valor')::numeric,0)<=0
    or (doc->>'valor')::numeric is distinct from (select sum(round((z->>'quantidade')::numeric*(z->>'valor_unitario')::numeric,2)) from jsonb_array_elements(doc->'itens') z)
   then raise exception 'Confira os itens, os preços e o total da invoice %',doc->>'invoice';end if;
   if exists(select 1 from public.imp_liberacoes l where l.pedido_id=(p->>'id')::uuid and l.invoice=upper(btrim(doc->>'invoice')))
    or exists(select 1 from public.imp_liberacao_invoices n where n.pedido_id=(p->>'id')::uuid and n.numero=upper(btrim(doc->>'invoice')))
   then raise exception 'A invoice % já foi vinculada a este pedido',doc->>'invoice';end if;
  end loop;
  d:=d||jsonb_build_object('invoice',lote->0->>'invoice','data_invoice',lote->0->>'data_invoice','moeda',p->>'moeda',
    'valor',(select sum((v->>'valor')::numeric) from jsonb_array_elements(lote) v),
    'itens',(select jsonb_agg(to_jsonb(t) order by pedido_item_id) from (
      select (z->>'pedido_item_id')::uuid pedido_item_id,sum((z->>'quantidade')::numeric) quantidade,
       max((z->>'valor_unitario')::numeric) valor_unitario
      from jsonb_array_elements(lote) v cross join lateral jsonb_array_elements(v->'itens') z group by 1
    ) t));
 end if;
 if exists(select 1 from public.imp_liberacao_invoices n where n.pedido_id=(p->>'id')::uuid and n.numero=upper(btrim(d->>'invoice'))) then
  raise exception 'Esta invoice já foi vinculada a este pedido';
 end if;
 if nullif(btrim(d->>'invoice'),'') is null or length(d->>'invoice')>100 or d->>'moeda' is distinct from p->>'moeda' then raise exception 'Confira número da invoice e moeda do pedido';end if;
 if exists(select 1 from public.imp_liberacoes l where l.pedido_id=(p->>'id')::uuid and l.invoice=upper(btrim(d->>'invoice'))) then raise exception 'Esta invoice já gerou parcela e embarque neste pedido. Consulte a parcial existente';end if;
 if jsonb_typeof(d->'itens') is distinct from 'array' or jsonb_array_length(d->'itens') not between 1 and 100 or exists(select 1 from jsonb_array_elements(d->'itens') z group by z->>'pedido_item_id' having count(*)>1) then raise exception 'Selecione os itens da parcial, sem repetição';end if;
 for x in select value from jsonb_array_elements(d->'itens') loop
  select * into y from public.imp_pedido_itens where id=(x->>'pedido_item_id')::uuid and pedido_id=(p->>'id')::uuid;
  if not found then raise exception 'Item não pertence ao pedido';end if;
  if y.produto_id is null then raise exception 'Linha %: vincule o produto do cadastro antes de importar a parcial',y.linha;end if;
  q:=(x->>'quantidade')::numeric;valor:=(x->>'valor_unitario')::numeric;
  if lote is not null and q>y.quantidade-(select coalesce(sum(ei.quantidade),0) from public.imp_embarque_itens ei
    join public.imp_embarques e on e.id=ei.embarque_id and e.status<>'Cancelado' where ei.pedido_item_id=y.id) then
   raise exception 'Linha %: soma das invoices ultrapassa o saldo disponível para embarcar',y.linha;
  end if;
  if q is null or q<=0 or q>y.quantidade or q::text in ('NaN','Infinity','-Infinity') then raise exception 'Linha %: quantidade da parcial %; quantidade pedida %. Confira o item antes de aprovar',y.linha,q,y.quantidade;end if;
  if valor is distinct from y.valor_unitario then raise exception 'Linha %: preço no pedido %; preço na invoice %. Corrija a divergência antes de aprovar',y.linha,y.valor_unitario,valor;end if;
  if nullif(x->>'peso_bruto','') is not null and ((x->>'peso_bruto')!~'^\d+(\.\d+)?$' or (x->>'peso_bruto')::numeric<=0) then raise exception 'Peso bruto deve ser positivo';end if;
  total:=total+round(q*valor,2);
 end loop;
 valor:=(d->>'valor')::numeric;if valor is null or valor<=0 or valor<>round(valor,2) or (lote is null and valor is distinct from total) then raise exception 'Valor da parcial deve corresponder ao FOB dos itens selecionados';end if;
 if jsonb_typeof(d->'creditos') is distinct from 'array' or jsonb_array_length(d->'creditos')>30 or exists(select 1 from jsonb_array_elements(d->'creditos') z group by z->>'parcela_id' having count(*)>1) then raise exception 'Vínculos de parcelas inválidos';end if;
 for x in select value from jsonb_array_elements(d->'creditos') loop
  select * into par from public.imp_parcelas where id=(x->>'parcela_id')::uuid and pedido_id=(p->>'id')::uuid and status<>'Cancelada';if not found then raise exception 'Parcela existente inválida';end if;
  q:=(x->>'valor')::numeric;select coalesce(sum(lp.valor),0) into previa from public.imp_liberacao_parcelas lp where lp.parcela_id=par.id;
  if q is null or q<=0 or q<>round(q,2) or previa+q>par.valor then raise exception 'Valor ultrapassa o saldo da parcela para documentos de embarque';end if;atribuido:=atribuido+q;
 end loop;
 if atribuido>valor then raise exception 'Parcelas vinculadas ultrapassam a invoice';end if;
 if exists(select 1 from public.imp_parcelas pa where pa.pedido_id=(p->>'id')::uuid and pa.status<>'Cancelada') and p_dados->>'conferiu_parcelas' is distinct from 'true' then raise exception 'Confira as parcelas existentes para evitar criar uma cobrança duplicada';end if;
 if lote is null then
 if jsonb_typeof(p_dados->'arquivos') is distinct from 'array' or jsonb_array_length(p_dados->'arquivos') not between 2 and 3 or (select count(distinct z->>'categoria') from jsonb_array_elements(p_dados->'arquivos') z)<>jsonb_array_length(p_dados->'arquivos') or not exists(select 1 from jsonb_array_elements(p_dados->'arquivos') z where z->>'categoria'='INVOICE') or not exists(select 1 from jsonb_array_elements(p_dados->'arquivos') z where z->>'categoria'='PACKING') then raise exception 'Invoice e packing list são obrigatórios';end if;
 for x in select value from jsonb_array_elements(p_dados->'arquivos') loop
  if x->>'caminho' is distinct from 'entrada/'||p_usuario||'/'||req||'/'||(x->>'categoria')||'.pdf' or coalesce(length(x->>'nome'),0) not between 1 and 250 then raise exception 'Identificação de arquivo inválida';end if;
 end loop;
 else
  if jsonb_typeof(p_dados->'arquivos') is distinct from 'array'
    or (select count(*) from jsonb_array_elements(p_dados->'arquivos') z where z->>'categoria'='PACKING')<>1
    or (select count(*) from jsonb_array_elements(p_dados->'arquivos') z where z->>'categoria'='PESOS')>1
    or (select count(*) from jsonb_array_elements(p_dados->'arquivos') z where z->>'categoria'='INVOICE')<>jsonb_array_length(lote)
    or exists(select 1 from jsonb_array_elements(p_dados->'arquivos') z where coalesce(z->>'categoria','') not in ('INVOICE','PACKING','PESOS'))
  then raise exception 'Anexe todas as invoices e uma packing list';end if;
  for x in select value from jsonb_array_elements(p_dados->'arquivos') loop
   if x->>'caminho' is distinct from 'entrada/'||p_usuario||'/'||req||'/'||(x->>'categoria')||
    (case when x->>'categoria'='INVOICE' then '-'||(x->>'posicao') else '' end)||'.pdf'
    or coalesce(length(x->>'nome'),0) not between 1 and 250 then raise exception 'Identificação de arquivo inválida';end if;
  end loop;
 end if;
 i:=gen_random_uuid();novo:=valor-atribuido;
 -- Invoice/packing create logistics only; uncovered value remains a financial balance.
 parcelas:=parcelas||(d->'creditos');
 embarque_req:=gen_random_uuid();
 emb:=public.axe_imp_estrutura(jsonb_build_object('acao','v2_salvar','tipo','embarques','requisicao_id',embarque_req,'dados',jsonb_build_object('referencia',d->>'embarque_ref','fornecedor_id',p->'fornecedor_id','moeda',p->>'moeda','status','Planejamento','dados',jsonb_build_object('liberacao_id',i,'invoice',d->>'invoice','peso_bruto_total',d->'peso_bruto_total','observacoes','Carga pronta: aguarda definição de transporte e coleta. Sem confirmação de pagamento.'),'itens',(select jsonb_agg(z||jsonb_build_object('invoice',case when lote is null then d->>'invoice' else (select string_agg(v->>'invoice',' / ' order by n) from jsonb_array_elements(lote) with ordinality f(v,n) where exists(select 1 from jsonb_array_elements(v->'itens') k where k->>'pedido_item_id'=z->>'pedido_item_id')) end,'invoice_data',case when lote is null then d->>'data_invoice' end,'recebida',0)) from jsonb_array_elements(d->'itens') z))),p_usuario);
 insert into public.imp_liberacoes(id,pedido_id,invoice,embarque_id,dados,extraido,criado_por) values(i,(p->>'id')::uuid,upper(btrim(d->>'invoice')),(emb->>'id')::uuid,d,p_dados->'extraido',p_usuario);
 insert into public.imp_liberacao_itens select i,(z->>'pedido_item_id')::uuid,(z->>'quantidade')::numeric,(z->>'valor_unitario')::numeric,nullif(z->>'peso_bruto','')::numeric from jsonb_array_elements(d->'itens') z;
 insert into public.imp_liberacao_parcelas select i,(z->>'parcela_id')::uuid,(z->>'valor')::numeric from jsonb_array_elements(parcelas) z;
 insert into public.imp_liberacao_arquivos(liberacao_id,categoria,nome,sha256,tamanho,caminho) select i,z->>'categoria',z->>'nome',z->>'sha256',(z->>'tamanho')::int,z->>'caminho' from jsonb_array_elements(p_dados->'arquivos') z;
 if lote is not null then
  insert into public.imp_liberacao_invoices(liberacao_id,pedido_id,numero,arquivo_id,dados)
  select i,(p->>'id')::uuid,upper(btrim(v->>'invoice')),af.id,v
  from jsonb_array_elements(lote) with ordinality docs(v,n)
  join public.imp_liberacao_arquivos af on af.liberacao_id=i and af.caminho='entrada/'||p_usuario||'/'||req||'/INVOICE-'||n||'.pdf';
  get diagnostics pos=row_count;
  if pos<>jsonb_array_length(lote) then raise exception 'Cada invoice deve ter seu PDF vinculado';end if;
 end if;
 antes:=public.axe_imp_estrutura_detalhe('pedidos',(p->>'id')::uuid);
 for x in select value from jsonb_array_elements(d->'itens') loop
  select coalesce(sum(li.quantidade),0) into previa from public.imp_liberacao_itens li join public.imp_liberacoes l on l.id=li.liberacao_id where l.pedido_id=(p->>'id')::uuid and li.pedido_item_id=(x->>'pedido_item_id')::uuid;
  update public.imp_pedido_itens set disponibilizada=greatest(disponibilizada,previa),data_disponibilidade=case when nullif(d->>'data_invoice','') is null then data_disponibilidade else greatest(data_disponibilidade,(d->>'data_invoice')::date) end where id=(x->>'pedido_item_id')::uuid;
 end loop;
 update public.imp_pedidos set versao=versao+1,atualizado_em=clock_timestamp(),atualizado_por=p_usuario where id=(p->>'id')::uuid;
 insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual) values('pedidos',(p->>'id')::uuid,p_usuario,antes,public.axe_imp_estrutura_detalhe('pedidos',(p->>'id')::uuid));
 result:=jsonb_build_object('id',i,'embarque_id',emb->>'id','parcelas',parcelas);
 result:=result||jsonb_build_object('pagamento_automatico',case when lote is null then public.axe_imp_swift_invoice_automatico((p->>'id')::uuid,p_usuario) end);insert into public.imp_requisicoes values(p_usuario,req,p_dados,result,now());return result;
end $function$
;

-- Lotes com várias invoices são conferidos pelo valor de cada documento.
-- O vínculo automático legado só conhece o valor do lote inteiro.
do $$
declare
 definicao text:=pg_get_functiondef('public.axe_imp_swift_invoice_automatico(uuid,uuid)'::regprocedure);
 trecho constant text:='where li.pedido_id=pid and e.status<>''Cancelado''';
 contagem constant text:='where ll.pedido_id=pid and ee.status<>''Cancelado''';
begin
 if strpos(definicao,trecho)=0 or strpos(definicao,contagem)=0 then raise exception 'Conciliação automática incompatível';end if;
 definicao:=replace(definicao,trecho,trecho||' and not (li.dados ? ''invoices'')');
 execute replace(definicao,contagem,contagem||' and not (ll.dados ? ''invoices'')');
end
$$;

-- O vencimento de um lote não pode ser inferido pela data da primeira invoice.
do $$
declare
 definicao text:=pg_get_functiondef('public.axe_imp_programar_parcelas_importacao(uuid,uuid)'::regprocedure);
 trecho constant text:='where l.pedido_id=pid order by l.criado_em,l.id loop';
begin
 if strpos(definicao,trecho)=0 then raise exception 'Programação de parcelas incompatível';end if;
 execute replace(definicao,trecho,'where l.pedido_id=pid and not (l.dados ? ''invoices'') order by l.criado_em,l.id loop');
end
$$;

