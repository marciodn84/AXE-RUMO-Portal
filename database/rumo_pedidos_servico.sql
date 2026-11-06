alter table public.comercial_pedidos add column tipo_atendimento text not null default 'PRODUTO'
 check (tipo_atendimento in ('PRODUTO','SERVICO'));

create table public.comercial_execucao_servico (
 pedido_item_id bigint primary key references public.comercial_pedido_itens(id),
 quantidade numeric not null check (quantidade>0),
 etapa text not null default 'PLANEJAMENTO' check (etapa in ('PLANEJAMENTO','EM_EXECUCAO','CONCLUIDO')),
 atualizado_em timestamptz not null default now()
);
alter table public.comercial_execucao_servico enable row level security;
revoke all on public.comercial_execucao_servico from public,anon,authenticated;
grant select,insert,update on public.comercial_execucao_servico to service_role;

alter function public.axe_venda_rumo(jsonb,uuid) rename to axe_venda_rumo_produto;
revoke all on function public.axe_venda_rumo_produto(jsonb,uuid) from public,anon,authenticated;

create function public.axe_venda_rumo(p_dados jsonb,p_usuario uuid) returns jsonb
language plpgsql set search_path='' as $$
declare
 a text:=p_dados->>'acao';
 p public.comercial_pedidos;
 tipo text;
 fonte jsonb;
 item record;
 etapa_servico text;
 anterior jsonb;
 atual jsonb;
 resposta jsonb;
 total_exec integer:=0;
begin
 if a not in ('rumo_salvar','rumo_aprovar','rumo_detalhe','rumo_recarregar') then
  return public.axe_venda_rumo_produto(p_dados,p_usuario);
 end if;
 if not exists(select 1 from public.axe_rumo_revisores where usuario_id=p_usuario and ativo)
 or not exists(select 1 from public.gestao_membros where usuario_id=p_usuario and ativo and papel in ('ADMIN','EDITOR')) then
  raise exception 'Usuário sem permissão para pedido de venda';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('axe_venda_rumo',0));
 select * into p from public.comercial_pedidos where id=(p_dados->>'id')::bigint and origem='RUMO' for update;
 if not found then raise exception 'Pedido de venda não encontrado'; end if;
 tipo:=case when a='rumo_salvar' then coalesce(p_dados->>'tipo_atendimento',p.tipo_atendimento) else p.tipo_atendimento end;
 if tipo not in ('PRODUTO','SERVICO') then raise exception 'Tipo de atendimento inválido'; end if;
 if a<>'rumo_detalhe' and p.versao is distinct from (p_dados->>'versao')::int then
  raise exception 'Pedido alterado. Atualize antes de continuar';
 end if;

 if a='rumo_salvar' and p_dados ? 'execucao_servico' then
  if p.estado<>'APROVADO' or p.tipo_atendimento<>'SERVICO' then raise exception 'Execução disponível para serviço aprovado';end if;
  etapa_servico:=p_dados#>>'{execucao_servico,etapa}';
  if etapa_servico is null or etapa_servico not in ('PLANEJAMENTO','EM_EXECUCAO','CONCLUIDO') then
   raise exception 'Etapa de serviço inválida';
  end if;
  select to_jsonb(e) into anterior from public.comercial_execucao_servico e
  join public.comercial_pedido_itens i on i.id=e.pedido_item_id
  where i.pedido_id=p.id and i.id=(p_dados#>>'{execucao_servico,item_id}')::bigint;
  if not found then raise exception 'Execução de serviço não encontrada no pedido';end if;
  update public.comercial_execucao_servico e set etapa=etapa_servico,atualizado_em=now()
   where e.pedido_item_id=(anterior->>'pedido_item_id')::bigint returning to_jsonb(e) into atual;
  update public.comercial_pedidos set versao=versao+1 where id=p.id;
  insert into public.comercial_eventos(tipo,registro_id,acao,usuario_id,evidencia,anterior,atual)
   values('pedido',p.id,'ATUALIZAR_EXECUCAO_SERVICO',p_usuario,'Etapa de execução do serviço',anterior,atual);
 elsif a='rumo_salvar' and tipo is distinct from p.tipo_atendimento then
  if p.estado<>'RASCUNHO' then raise exception 'Somente rascunhos podem ser classificados';end if;
  update public.comercial_pedidos set tipo_atendimento=tipo,versao=versao+1 where id=p.id returning to_jsonb(comercial_pedidos) into atual;
  if tipo='SERVICO' then
   update public.comercial_pedido_itens set produto_id=null,fator_conversao=null,referencia_cliente_id=null where pedido_id=p.id;
  end if;
  insert into public.comercial_eventos(tipo,registro_id,acao,usuario_id,evidencia,anterior,atual)
   values('pedido',p.id,'CLASSIFICAR_PEDIDO_RUMO',p_usuario,'Classificação do atendimento',to_jsonb(p),atual);
  if tipo='PRODUTO' then
   return public.axe_venda_rumo_produto(jsonb_set(p_dados,'{versao}',atual->'versao'),p_usuario);
  end if;
 elsif a='rumo_aprovar' and tipo='SERVICO' then
  if p.estado<>'RASCUNHO' then raise exception 'Somente rascunhos podem ser aprovados';end if;
  perform public.axe_exigir_cliente_liberado(p.cliente_id);
  fonte:=public.axe_venda_rumo_fonte(p.pedido_rumo_id);
  if public.axe_rumo_hash_json(fonte) is distinct from p.fonte_hash then
   raise exception 'O pedido RUMO mudou. Recarregue os dados de origem e confira antes de aprovar';
  end if;
  if (select count(*) from public.comercial_pedido_itens where pedido_id=p.id)<>jsonb_array_length(fonte->'itens') then
   raise exception 'A composição do pedido RUMO mudou';
  end if;
  for item in
   select v.*,i.fase_status_sap,case when i.fase_status_sap='ENTREGUE' then 0 else i.quantidade_pendente end saldo
   from public.comercial_pedido_itens v join public.pedido_itens i on i.id=v.item_rumo_id
   where v.pedido_id=p.id order by v.id for update of v,i
  loop
   if item.fase_status_sap is null or item.fase_status_sap not in ('ACEITO','ENTREGUE') then
    raise exception 'Item % ainda não está aceito ou entregue no SAP',item.numero_item;
   end if;
   if nullif(item.nome_cliente,'') is null or item.quantidade is null or item.preco_unitario is null or item.moeda is null or item.unidade_cliente is null then
    raise exception 'Item %: faltam dados no documento de origem',item.numero_item;
   end if;
   if item.saldo is null or item.saldo<0 or item.saldo>item.quantidade then
    raise exception 'Saldo do item % não confiável. Confira o SAP antes de liberar',item.numero_item;
   end if;
   if item.saldo>0 then
    insert into public.comercial_execucao_servico(pedido_item_id,quantidade) values(item.id,item.saldo);
    total_exec:=total_exec+1;
   end if;
  end loop;
  if total_exec=0 then raise exception 'Pedido já entregue ou sem saldo para iniciar execução';end if;
  update public.comercial_pedidos set estado='APROVADO',versao=versao+1,aprovado_em=now(),aprovado_por=p_usuario
   where id=p.id returning to_jsonb(comercial_pedidos) into atual;
  insert into public.comercial_eventos(tipo,registro_id,acao,usuario_id,evidencia,atual)
   values('pedido',p.id,'APROVAR_SERVICO_RUMO',p_usuario,'Execução de serviço aberta para acompanhamento',atual);
 elsif a='rumo_recarregar' and tipo='SERVICO' then
  perform public.axe_venda_rumo_produto(p_dados,p_usuario);
  update public.comercial_pedido_itens set produto_id=null,fator_conversao=null,referencia_cliente_id=null where pedido_id=p.id;
 elsif a='rumo_salvar' and tipo='SERVICO' then
  if p.estado<>'RASCUNHO' then raise exception 'Somente rascunhos podem ser alterados';end if;
 elsif a<>'rumo_detalhe' then
  return public.axe_venda_rumo_produto(p_dados,p_usuario);
 end if;

 resposta:=public.axe_venda_rumo_produto(jsonb_build_object('acao','rumo_detalhe','id',p.id),p_usuario);
 if tipo='SERVICO' then
  resposta:=jsonb_set(resposta,'{itens}',(
   select coalesce(jsonb_agg(x.item||jsonb_build_object('execucao',to_jsonb(e)) order by x.ord),'[]')
   from jsonb_array_elements(resposta->'itens') with ordinality x(item,ord)
   left join public.comercial_execucao_servico e on e.pedido_item_id=(x.item->>'id')::bigint
  ));
 end if;
 return resposta;
end;
$$;
revoke all on function public.axe_venda_rumo(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_venda_rumo(jsonb,uuid) to service_role;

do $$
declare
 alvo public.comercial_pedidos;
 responsavel uuid;
begin
 select v.* into alvo from public.comercial_pedidos v join public.pedidos p on p.id=v.pedido_rumo_id
 where p.numero_pedido='4502071803' and v.origem='RUMO' and v.estado='RASCUNHO';
 if found then
  select m.usuario_id into strict responsavel from public.gestao_membros m
  join public.axe_rumo_revisores r using(usuario_id)
  where m.ativo and r.ativo and m.papel='ADMIN' order by m.usuario_id limit 1;
  perform public.axe_venda_rumo(jsonb_build_object('acao','rumo_salvar','id',alvo.id,'versao',alvo.versao,'tipo_atendimento','SERVICO'),responsavel);
 end if;
end;
$$;
