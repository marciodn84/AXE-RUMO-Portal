begin;
create table public.imp_importacao_processos(
 id uuid primary key default gen_random_uuid(),fornecedor_id bigint not null references public.fornecedores(id),moeda text not null,
 estado text not null default 'Aberto' check(estado in('Aberto','Encerrado','Cancelado','Consolidado')),
 consolidado_em uuid references public.imp_importacao_processos(id),criado_em timestamptz not null default now(),encerrado_em timestamptz,
 criado_por uuid not null references auth.users(id),check((estado='Consolidado')=(consolidado_em is not null)),check(id is distinct from consolidado_em)
);
create table public.imp_importacao_pedidos(processo_id uuid not null references public.imp_importacao_processos(id),pedido_id uuid not null references public.imp_pedidos(id),parcial integer not null check(parcial>0),primary key(processo_id,pedido_id),unique(pedido_id,parcial));
create table public.imp_importacao_itens(processo_id uuid not null references public.imp_importacao_processos(id),pedido_item_id uuid not null references public.imp_pedido_itens(id),quantidade numeric not null check(quantidade>0),primary key(processo_id,pedido_item_id));
create table public.imp_importacao_embarques(processo_id uuid not null references public.imp_importacao_processos(id),embarque_id uuid not null unique references public.imp_embarques(id),primary key(processo_id,embarque_id));
create index imp_importacao_pedidos_pedido on public.imp_importacao_pedidos(pedido_id,processo_id);
create index imp_importacao_itens_item on public.imp_importacao_itens(pedido_item_id,processo_id);
alter table public.imp_importacao_processos enable row level security;
alter table public.imp_importacao_pedidos enable row level security;
alter table public.imp_importacao_itens enable row level security;
alter table public.imp_importacao_embarques enable row level security;
revoke all on public.imp_importacao_processos,public.imp_importacao_pedidos,public.imp_importacao_itens,public.imp_importacao_embarques from public,anon,authenticated;
grant all on public.imp_importacao_processos,public.imp_importacao_pedidos,public.imp_importacao_itens,public.imp_importacao_embarques to service_role;
create or replace function public.axe_imp_processo_raiz(i uuid) returns uuid language sql stable set search_path='' as $fn$
 with recursive r as(select id,consolidado_em,1 n from public.imp_importacao_processos where id=i union all select p.id,p.consolidado_em,r.n+1 from public.imp_importacao_processos p join r on p.id=r.consolidado_em where r.n<100)select id from r where consolidado_em is null order by n desc limit 1;
$fn$;
create or replace function public.axe_imp_processos_reconciliar(uid uuid) returns void language plpgsql set search_path='' as $fn$
declare p record;emrow record;pr public.imp_importacao_processos;pid uuid;dest uuid;r record;pendentes uuid[];saldos numeric;seguinte uuid;
begin
 if not exists(select 1 from public.gestao_membros m join public.axe_rumo_revisores rv on rv.usuario_id=m.usuario_id and rv.ativo where m.usuario_id=uid and m.ativo and m.papel in('ADMIN','EDITOR')) then return;end if;
 perform pg_advisory_xact_lock(728102826);
 for p in select * from public.imp_pedidos where public.axe_imp_processo_iniciado(id) and status<>'Cancelado' loop
  select public.axe_imp_processo_raiz(pp.processo_id) into pid from public.imp_importacao_pedidos pp join public.imp_importacao_processos root on root.id=public.axe_imp_processo_raiz(pp.processo_id) and root.estado='Aberto' where pp.pedido_id=p.id order by pp.parcial desc limit 1;
  if pid is null then
   if not exists(select 1 from public.imp_pedido_itens pi where pi.pedido_id=p.id and pi.quantidade>coalesce((select sum(ei.recebida) from public.imp_embarque_itens ei join public.imp_embarques e on e.id=ei.embarque_id and e.status<>'Cancelado' where ei.pedido_item_id=pi.id),0)) then continue;end if;
   insert into public.imp_importacao_processos(fornecedor_id,moeda,criado_por)values(p.fornecedor_id,p.moeda,uid)returning id into pid;
   insert into public.imp_importacao_pedidos values(pid,p.id,(select coalesce(max(parcial),0)+1 from public.imp_importacao_pedidos where pedido_id=p.id));
   insert into public.imp_importacao_itens select pid,pi.id,pi.quantidade-coalesce((select sum(ei.recebida) from public.imp_embarque_itens ei join public.imp_embarques e on e.id=ei.embarque_id and e.status<>'Cancelado' where ei.pedido_item_id=pi.id),0) from public.imp_pedido_itens pi where pi.pedido_id=p.id and pi.quantidade>coalesce((select sum(ei.recebida) from public.imp_embarque_itens ei join public.imp_embarques e on e.id=ei.embarque_id and e.status<>'Cancelado' where ei.pedido_item_id=pi.id),0);
   insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('processos',pid,uid,null,jsonb_build_object('evento','Processo iniciado pelo envio do PO','pedido_id',p.id));
  end if;
 end loop;
 -- Um embarque consolidado pertence a um processo; os POs envolvidos são preservados.
 for emrow in select em.* from public.imp_embarques em where em.status<>'Cancelado' and not exists(select 1 from public.imp_importacao_embarques pe where pe.embarque_id=em.id) order by em.criado_em,em.id loop
  select array_agg(distinct public.axe_imp_processo_raiz(pp.processo_id)) into pendentes from public.imp_embarque_itens ei join public.imp_pedido_itens pi on pi.id=ei.pedido_item_id join public.imp_importacao_pedidos pp on pp.pedido_id=pi.pedido_id join public.imp_importacao_processos rp on rp.id=public.axe_imp_processo_raiz(pp.processo_id) and rp.estado='Aberto' where ei.embarque_id=emrow.id and rp.fornecedor_id=emrow.fornecedor_id and rp.moeda=emrow.moeda;
  if coalesce(array_length(pendentes,1),0)=0 then continue;end if;dest:=pendentes[1];
  foreach pid in array pendentes loop
   if pid<>dest then update public.imp_importacao_processos set estado='Consolidado',consolidado_em=dest where id=pid;insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('processos',pid,uid,jsonb_build_object('estado','Aberto'),jsonb_build_object('evento','Consolidação comprovada pelos itens do embarque','processo_destino',dest,'embarque_id',emrow.id));end if;
  end loop;
  insert into public.imp_importacao_embarques values(dest,emrow.id);
 end loop;
 for pr in select * from public.imp_importacao_processos where estado='Aberto' order by criado_em,id loop
  if not exists(select 1 from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=pr.id and po.status<>'Cancelado') then update public.imp_importacao_processos set estado='Cancelado' where id=pr.id;continue;end if;
  if exists(select 1 from public.imp_importacao_embarques pe join public.imp_embarques em on em.id=pe.embarque_id and em.status<>'Cancelado' where public.axe_imp_processo_raiz(pe.processo_id)=pr.id)
   and not exists(select 1 from public.imp_importacao_embarques pe join public.imp_embarques em on em.id=pe.embarque_id and em.status<>'Cancelado' where public.axe_imp_processo_raiz(pe.processo_id)=pr.id and (em.status<>'Recebido' or exists(select 1 from public.imp_embarque_itens ei where ei.embarque_id=em.id and ei.recebida<ei.quantidade) or not exists(select 1 from public.imp_fluxo_estoque_confirmacoes st where st.embarque_id=em.id) or not exists(select 1 from public.imp_custos c where c.embarque_id=em.id and c.estado='Final'))) then
   update public.imp_importacao_processos set estado='Encerrado',encerrado_em=clock_timestamp() where id=pr.id;
   insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('processos',pr.id,uid,jsonb_build_object('estado','Aberto'),jsonb_build_object('evento','Processo encerrado: estoque, custos e créditos concluídos','estado','Encerrado'));
   seguinte:=null;
   for p in select distinct po.* from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=pr.id and po.status<>'Cancelado' loop
    if exists(select 1 from public.imp_pedido_itens pi where pi.pedido_id=p.id and pi.quantidade>coalesce((select sum(ei.recebida) from public.imp_embarque_itens ei join public.imp_embarques em on em.id=ei.embarque_id and em.status<>'Cancelado' where ei.pedido_item_id=pi.id),0)) then
     if seguinte is null then insert into public.imp_importacao_processos(fornecedor_id,moeda,criado_por)values(pr.fornecedor_id,pr.moeda,uid)returning id into seguinte;end if;
     insert into public.imp_importacao_pedidos values(seguinte,p.id,(select coalesce(max(parcial),0)+1 from public.imp_importacao_pedidos where pedido_id=p.id));
     insert into public.imp_importacao_itens select seguinte,pi.id,pi.quantidade-coalesce((select sum(ei.recebida) from public.imp_embarque_itens ei join public.imp_embarques em on em.id=ei.embarque_id and em.status<>'Cancelado' where ei.pedido_item_id=pi.id),0) from public.imp_pedido_itens pi where pi.pedido_id=p.id and pi.quantidade>coalesce((select sum(ei.recebida) from public.imp_embarque_itens ei join public.imp_embarques em on em.id=ei.embarque_id and em.status<>'Cancelado' where ei.pedido_item_id=pi.id),0);
    end if;
   end loop;
   if seguinte is not null then insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('processos',seguinte,uid,null,jsonb_build_object('evento','Próxima parcial criada com o saldo a entregar','processo_anterior',pr.id));end if;
  end if;
 end loop;
end $fn$;
revoke all on function public.axe_imp_processo_raiz(uuid),public.axe_imp_processos_reconciliar(uuid) from public,anon,authenticated;
grant execute on function public.axe_imp_processo_raiz(uuid),public.axe_imp_processos_reconciliar(uuid) to service_role;
create or replace function public.axe_imp_processo_evento() returns trigger language plpgsql set search_path='' as $fn$
declare uid uuid;
begin
 if tg_table_name in('imp_pedidos','imp_embarques','imp_custos') then uid:=new.atualizado_por;
 elsif tg_table_name='imp_fluxo_estoque_confirmacoes' then uid:=new.usuario_id;
 elsif tg_table_name='imp_liberacoes' then uid:=new.criado_por;
 elsif tg_table_name='imp_pedido_itens' then if tg_op='DELETE' then select atualizado_por into uid from public.imp_pedidos where id=old.pedido_id;else select atualizado_por into uid from public.imp_pedidos where id=new.pedido_id;end if;
 else if tg_op='DELETE' then select p.atualizado_por into uid from public.imp_pedidos p join public.imp_pedido_itens pi on pi.pedido_id=p.id where pi.id=old.pedido_item_id;else select p.atualizado_por into uid from public.imp_pedidos p join public.imp_pedido_itens pi on pi.pedido_id=p.id where pi.id=new.pedido_item_id;end if;end if;
 perform public.axe_imp_processos_reconciliar(uid);return null;
end $fn$;
revoke all on function public.axe_imp_processo_evento() from public,anon,authenticated;
create constraint trigger importacao_processo_pedido after insert or update on public.imp_pedidos deferrable initially deferred for each row execute function public.axe_imp_processo_evento();
create constraint trigger importacao_processo_item after insert or update or delete on public.imp_pedido_itens deferrable initially deferred for each row execute function public.axe_imp_processo_evento();
create constraint trigger importacao_processo_embarque after insert or update on public.imp_embarques deferrable initially deferred for each row execute function public.axe_imp_processo_evento();
create constraint trigger importacao_processo_embarque_item after insert or update or delete on public.imp_embarque_itens deferrable initially deferred for each row execute function public.axe_imp_processo_evento();
create constraint trigger importacao_processo_custo after insert or update on public.imp_custos deferrable initially deferred for each row execute function public.axe_imp_processo_evento();
create constraint trigger importacao_processo_estoque after insert on public.imp_fluxo_estoque_confirmacoes deferrable initially deferred for each row execute function public.axe_imp_processo_evento();
create constraint trigger importacao_processo_liberacao after insert on public.imp_liberacoes deferrable initially deferred for each row execute function public.axe_imp_processo_evento();
create or replace function public.axe_imp_status_parcial(i uuid) returns text language sql stable set search_path='' as $fn$
select case when pr.estado in('Encerrado','Cancelado') then pr.estado
 when exists(select 1 from public.imp_importacao_embarques pe join public.imp_embarques em on em.id=pe.embarque_id and em.status<>'Cancelado' where public.axe_imp_processo_raiz(pe.processo_id)=pr.id)
 and not exists(select 1 from public.imp_importacao_embarques pe join public.imp_embarques em on em.id=pe.embarque_id and em.status<>'Cancelado' where public.axe_imp_processo_raiz(pe.processo_id)=pr.id and (em.status<>'Recebido' or exists(select 1 from public.imp_embarque_itens ei where ei.embarque_id=em.id and ei.recebida<ei.quantidade))) then 'Recebido'
 when exists(select 1 from public.imp_importacao_embarques pe join public.imp_embarque_itens ei on ei.embarque_id=pe.embarque_id and ei.recebida>0 where public.axe_imp_processo_raiz(pe.processo_id)=pr.id) then 'Recebimento Parcial'
 when exists(select 1 from public.imp_importacao_embarques pe join public.imp_liberacoes l on l.embarque_id=pe.embarque_id where public.axe_imp_processo_raiz(pe.processo_id)=pr.id and exists(select 1 from public.imp_liberacao_arquivos a where a.liberacao_id=l.id and a.categoria='INVOICE') and exists(select 1 from public.imp_liberacao_arquivos a where a.liberacao_id=l.id and a.categoria='PACKING')) then 'Mercadoria em trânsito'
 when exists(select 1 from public.imp_importacao_pedidos pp where public.axe_imp_processo_raiz(pp.processo_id)=pr.id and public.axe_imp_status_processo(pp.pedido_id)='Aguardando aceite') then 'Aguardando aceite'
 else 'Aguardando Entrega' end from public.imp_importacao_processos pr where pr.id=public.axe_imp_processo_raiz(i);
$fn$;
-- A raiz mantém todas as relações de origem durante uma consolidação.
alter function public.axe_imp_fluxo(jsonb,uuid) rename to axe_imp_fluxo_base;
create or replace function public.axe_imp_fluxo(p_dados jsonb,p_usuario uuid) returns jsonb language plpgsql set search_path='' as $fn$
declare a text:=p_dados->>'acao';papel text;pr public.imp_importacao_processos;src public.imp_importacao_processos;pid uuid;oid uuid;dest uuid;page integer:=coalesce((p_dados->>'pagina')::integer,0);term text:=left(coalesce(p_dados->>'busca',''),120);r jsonb;rr jsonb;x jsonb;ships jsonb:='[]';members jsonb;
begin
 select m.papel into papel from public.gestao_membros m join public.axe_rumo_revisores rv on rv.usuario_id=m.usuario_id and rv.ativo where m.usuario_id=p_usuario and m.ativo;if papel is null then raise exception 'Sem acesso às importações';end if;
 if a in('custo_fluxo_listar','custo_fluxo_processos_abertos') then
  if page<0 or page>100000 then raise exception 'Página inválida';end if;
  return jsonb_build_object('editar',papel in('ADMIN','EDITOR'),'total',(select count(*) from public.imp_importacao_processos q where q.estado<>'Consolidado' and (a<>'custo_fluxo_processos_abertos' or q.estado='Aberto' and q.fornecedor_id=(p_dados->>'fornecedor_id')::bigint and q.moeda=p_dados->>'moeda') and exists(select 1 from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=q.id and po.referencia ilike '%'||term||'%')),
  'linhas',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select q.id processo_id,(select pp.pedido_id from public.imp_importacao_pedidos pp where public.axe_imp_processo_raiz(pp.processo_id)=q.id order by pp.parcial,pp.pedido_id limit 1) id,
   (select string_agg(po.referencia,', ' order by po.referencia) from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=q.id) referencia,
   (select string_agg(case when (select count(*) from public.imp_importacao_pedidos p2 where public.axe_imp_processo_raiz(p2.processo_id)=q.id)>1 then po.referencia||': ' else '' end||lpad(pp.parcial::text,2,'0'),', ' order by po.referencia) from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=q.id) parcial,
   (select jsonb_agg(jsonb_build_object('id',po.id,'referencia',po.referencia,'parcial',pp.parcial)) from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=q.id) pedidos,
   public.axe_imp_status_parcial(q.id) status_processo,f.razao_social fornecedor,q.fornecedor_id,q.moeda,
   (select coalesce(sum(round(it.quantidade*pi.valor_unitario,2)),0) from public.imp_importacao_itens it join public.imp_pedido_itens pi on pi.id=it.pedido_item_id where public.axe_imp_processo_raiz(it.processo_id)=q.id) total,
   0::numeric pago,(select count(*) from public.imp_importacao_embarques pe where public.axe_imp_processo_raiz(pe.processo_id)=q.id) embarques
   from public.imp_importacao_processos q join public.fornecedores f on f.id=q.fornecedor_id where q.estado<>'Consolidado' and (a<>'custo_fluxo_processos_abertos' or q.estado='Aberto' and q.fornecedor_id=(p_dados->>'fornecedor_id')::bigint and q.moeda=p_dados->>'moeda') and exists(select 1 from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=q.id and po.referencia ilike '%'||term||'%') order by q.criado_em desc,q.id limit 30 offset page*30)z));
 end if;
 if a='custo_fluxo_consolidar' then
  if papel not in('ADMIN','EDITOR') then raise exception 'Sem permissão para consolidar';end if;perform pg_advisory_xact_lock(728102826);
  select * into pr from public.imp_importacao_processos where id=public.axe_imp_processo_raiz((p_dados->>'processo_id')::uuid) and estado='Aberto';
  select * into src from public.imp_importacao_processos where id=public.axe_imp_processo_raiz((p_dados->>'origem_id')::uuid) and estado='Aberto';
  if pr.id is null or src.id is null or pr.id=src.id or pr.fornecedor_id<>src.fornecedor_id or pr.moeda<>src.moeda then raise exception 'Selecione dois processos abertos do mesmo fornecedor e moeda';end if;
  update public.imp_importacao_processos set estado='Consolidado',consolidado_em=pr.id where id=src.id;
  insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('processos',src.id,p_usuario,jsonb_build_object('estado','Aberto'),jsonb_build_object('evento','Processo consolidado por escolha do usuário','processo_destino',pr.id));
  return jsonb_build_object('processo_id',pr.id);
 end if;
 if a<>'custo_fluxo_detalhe' then return public.axe_imp_fluxo_base(p_dados,p_usuario);end if;
 oid:=(p_dados->>'pedido_id')::uuid;pid:=public.axe_imp_processo_raiz(nullif(p_dados->>'processo_id','')::uuid);
 if pid is null then select public.axe_imp_processo_raiz(pp.processo_id) into pid from public.imp_importacao_pedidos pp where pp.pedido_id=oid order by pp.parcial desc limit 1;end if;
 select * into pr from public.imp_importacao_processos where id=pid;if not found then raise exception 'O processo inicia ao enviar o PO ao fornecedor estrangeiro';end if;
 if oid is null then select pp.pedido_id into oid from public.imp_importacao_pedidos pp where public.axe_imp_processo_raiz(pp.processo_id)=pid limit 1;end if;
 if not exists(select 1 from public.imp_importacao_pedidos pp where pp.pedido_id=oid and public.axe_imp_processo_raiz(pp.processo_id)=pid) then raise exception 'Pedido não pertence a este processo';end if;
 r:=public.axe_imp_fluxo_base(jsonb_build_object('acao','custo_fluxo_detalhe','pedido_id',oid),p_usuario);
 select jsonb_agg(public.axe_imp_estrutura_detalhe('pedidos',pp.pedido_id)||jsonb_build_object('parcial',pp.parcial)) into members from public.imp_importacao_pedidos pp where public.axe_imp_processo_raiz(pp.processo_id)=pid;
 for x in select value from jsonb_array_elements(members) loop
  rr:=public.axe_imp_fluxo_base(jsonb_build_object('acao','custo_fluxo_detalhe','pedido_id',x->>'id'),p_usuario);
  for x in select value from jsonb_array_elements(rr->'embarques') loop
   if exists(select 1 from public.imp_importacao_embarques pe where pe.embarque_id=(x->'embarque'->>'id')::uuid and public.axe_imp_processo_raiz(pe.processo_id)=pid) and not exists(select 1 from jsonb_array_elements(ships) s where s->'embarque'->>'id'=x->'embarque'->>'id') then ships:=ships||jsonb_build_array(x);end if;
  end loop;
 end loop;
 return r||jsonb_build_object('editar',(r->>'editar')::boolean and pr.estado='Aberto','pedido',(r->'pedido')||jsonb_build_object('status_processo',public.axe_imp_status_parcial(pid)),'processo',to_jsonb(pr),'pedidos',members,'embarques',ships,'processo_itens',(select coalesce(jsonb_agg(to_jsonb(it)),'[]') from public.imp_importacao_itens it where public.axe_imp_processo_raiz(it.processo_id)=pid));
end $fn$;
revoke all on function public.axe_imp_status_parcial(uuid),public.axe_imp_fluxo(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_imp_status_parcial(uuid),public.axe_imp_fluxo(jsonb,uuid) to service_role;

revoke all on function public.axe_imp_fluxo_base(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_imp_fluxo_base(jsonb,uuid) to service_role;

select public.axe_imp_processos_reconciliar('f296afe4-eca8-48ad-a79a-388188988730'::uuid);
commit;
