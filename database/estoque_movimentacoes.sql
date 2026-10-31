begin;
create table public.estoque_lotes_importacao(
 id uuid primary key default gen_random_uuid(),embarque_id uuid not null references public.imp_embarques(id),nota_id uuid not null references public.imp_notas(id),custo_versao integer not null,custo_hash text not null,fonte jsonb not null,usuario_id uuid not null references auth.users(id),criado_em timestamptz not null default clock_timestamp(),unique(embarque_id,custo_versao));
create table public.estoque_movimentos(
 id uuid primary key default gen_random_uuid(),ordem bigint generated always as identity unique,produto_id bigint not null references public.produtos_conciliacao(id),tipo text not null check(tipo in('ENTRADA','SAIDA')),quantidade numeric(24,6)not null check(quantidade>0),valor_total numeric(24,6)not null check(valor_total>=0),custo_unitario numeric(24,8)not null check(custo_unitario>=0),unidade text not null,data_movimento date not null,motivo text not null check(motivo in('SALDO_INICIAL','COMPRA_NACIONAL','DEVOLUCAO_CLIENTE','AJUSTE_ENTRADA','VENDA','CONSUMO','DEVOLUCAO_FORNECEDOR','AJUSTE_SAIDA','IMPORTACAO','ESTORNO')),referencia text not null check(length(btrim(referencia))between 1 and 240),lote_importacao_id uuid references public.estoque_lotes_importacao(id),pedido_item_id uuid references public.imp_pedido_itens(id),estorno_de uuid unique references public.estoque_movimentos(id),cadastro_original jsonb not null,usuario_id uuid not null references auth.users(id),criado_em timestamptz not null default clock_timestamp(),unique(lote_importacao_id,pedido_item_id),check((motivo='IMPORTACAO')=(lote_importacao_id is not null)),check((motivo='ESTORNO')=(estorno_de is not null)));
create index estoque_movimentos_produto_ordem on public.estoque_movimentos(produto_id,ordem desc);
create index estoque_movimentos_lote on public.estoque_movimentos(lote_importacao_id)where lote_importacao_id is not null;
create table public.estoque_requisicoes(id uuid primary key,usuario_id uuid not null references auth.users(id),dados jsonb not null,resultado jsonb not null,criado_em timestamptz not null default clock_timestamp());
alter table public.estoque_lotes_importacao enable row level security;
alter table public.estoque_movimentos enable row level security;
alter table public.estoque_requisicoes enable row level security;
revoke all on public.estoque_lotes_importacao,public.estoque_movimentos,public.estoque_requisicoes from public,anon,authenticated;
grant select,insert,update on public.estoque_movimentos to service_role;
grant select,insert on public.estoque_lotes_importacao,public.estoque_requisicoes to service_role;
grant usage,select on sequence public.estoque_movimentos_ordem_seq to service_role;
create view public.estoque_saldos with(security_invoker=true)as
select p.id produto_id,p.codigo_axe,p.descricao_referencia,p.unidade_referencia unidade,p.ativo,p.bloqueado_comercial,
coalesce(s.quantidade,0)quantidade,coalesce(s.valor,0)valor_estoque,case when s.quantidade>0 then round(s.valor/s.quantidade,8)else 0 end custo_medio,
ult.custo_unitario custo_reposicao,ult.data_movimento ultima_entrada,coalesce(s.movimentos,0)movimentos
from public.produtos_conciliacao p left join lateral(select sum(case when tipo='ENTRADA'then quantidade else -quantidade end)quantidade,sum(case when tipo='ENTRADA'then valor_total else -valor_total end)valor,count(*)movimentos from public.estoque_movimentos m where m.produto_id=p.id)s on true
left join lateral(select m.custo_unitario,m.data_movimento from public.estoque_movimentos m where m.produto_id=p.id and m.tipo='ENTRADA'and m.estorno_de is null and not exists(select 1 from public.estoque_movimentos es where es.estorno_de=m.id)order by m.ordem desc limit 1)ult on true
where p.mesclado_em_id is null;
revoke all on public.estoque_saldos from public,anon,authenticated;grant select on public.estoque_saldos to service_role;
create function public.axe_estoque_movimento_guard()returns trigger language plpgsql set search_path=''as $$
begin
 if TG_OP='UPDATE'and current_user='service_role'and public.axe_mesclagem_vinculo_permitido(TG_TABLE_NAME,to_jsonb(OLD),to_jsonb(NEW))then return NEW;end if;
 raise exception 'Movimentação imutável. Use um estorno para corrigir; o histórico deve ser preservado';
end $$;
create trigger estoque_movimento_imutavel before update or delete on public.estoque_movimentos for each row execute function public.axe_estoque_movimento_guard();
create trigger aaa_mesclagem_referencias before insert or update on public.estoque_movimentos for each row execute function public.axe_mesclagem_referencias_guard();
create function public.axe_estoque_unidade_guard()returns trigger language plpgsql set search_path=''as $$
begin if upper(btrim(coalesce(NEW.unidade_referencia,'')))is distinct from upper(btrim(coalesce(OLD.unidade_referencia,'')))and exists(select 1 from public.estoque_movimentos where produto_id=OLD.id)then raise exception 'Produto com movimentações: preserve a unidade de estoque';end if;return NEW;end $$;
create trigger estoque_unidade_guard before update of unidade_referencia on public.produtos_conciliacao for each row execute function public.axe_estoque_unidade_guard();
create function public.axe_estoque_mesclagem_previa(origem bigint,destino bigint)returns jsonb language sql stable set search_path=''as $$
select jsonb_build_object('origem',to_jsonb(a),'destino',to_jsonb(b),'unificado',jsonb_build_object('quantidade',a.quantidade+b.quantidade,'valor_estoque',a.valor_estoque+b.valor_estoque,'custo_medio',case when a.quantidade+b.quantidade>0 then round((a.valor_estoque+b.valor_estoque)/(a.quantidade+b.quantidade),8)else 0 end),'regra','Movimentos mantêm seus IDs, datas, documentos e custos registrados. O saldo e o valor são reunidos; o novo custo médio será usado nas próximas saídas.')from public.estoque_saldos a cross join public.estoque_saldos b where a.produto_id=origem and b.produto_id=destino $$;
create function public.axe_estoque_importacao_previa(eid uuid)returns jsonb language plpgsql set search_path=''as $$
declare c public.imp_custos;e public.imp_embarques;conf public.imp_fluxo_estoque_confirmacoes;items jsonb:='[]';pend jsonb:='[]';x record;r jsonb;pr public.produtos_conciliacao;q numeric;v numeric;un text;source jsonb;finger text;posted boolean;notas jsonb;begin
 select * into e from public.imp_embarques where id=eid;if not found then raise exception 'Embarque não encontrado';end if;
 select * into c from public.imp_custos where embarque_id=eid;select * into conf from public.imp_fluxo_estoque_confirmacoes where embarque_id=eid;
 select coalesce(jsonb_agg(jsonb_build_object('id',n.id,'chave',n.chave)),'[]')into notas from public.imp_notas n where n.embarque_id=eid and n.estado='Conciliada';
 if e.status<>'Recebido' then pend:=pend||jsonb_build_array('Confirme o recebimento integral do embarque');end if;
 if c.estado is distinct from 'Final' then pend:=pend||jsonb_build_array('Finalize os custos e créditos da importação');end if;
 if jsonb_array_length(notas)=0 then pend:=pend||jsonb_build_array('Concilie a nota fiscal de entrada');end if;
 if c.estado='Final'and(c.resultado->>'custo_total'is null or jsonb_array_length(coalesce(c.resultado->'itens','[]'))=0)then pend:=pend||jsonb_build_array('Custo final sem itens ou total calculado');end if;
 if (select count(*)from public.imp_embarque_itens where embarque_id=eid)<>jsonb_array_length(coalesce(c.resultado->'itens','[]'))then pend:=pend||jsonb_build_array('Os itens do custo não correspondem ao embarque atual');end if;
 for x in select ei.*,pi.produto_id,pi.unidade,pi.linha,pi.pedido_id,pi.descricao,p.referencia pedido from public.imp_embarque_itens ei join public.imp_pedido_itens pi on pi.id=ei.pedido_item_id join public.imp_pedidos p on p.id=pi.pedido_id where ei.embarque_id=eid order by pi.pedido_id,pi.linha loop
 r:=null;select it into r from jsonb_array_elements(coalesce(c.resultado->'itens','[]'))it where it->>'pedido_item_id'=x.pedido_item_id::text;
 select * into pr from public.produtos_conciliacao where id=public.axe_cadastro_canonico('produto',x.produto_id);
 if pr.id is null or nullif(btrim(pr.unidade_referencia),'')is null then pend:=pend||jsonb_build_array('Item '||x.linha||': vincule um produto com unidade de estoque');end if;
 if pr.controla_estoque=false then pend:=pend||jsonb_build_array('Item '||x.linha||': produto configurado para não controlar estoque');end if;
 if e.status='Recebido'and x.recebida<>x.quantidade then pend:=pend||jsonb_build_array('Item '||x.linha||': recebimento incompleto');end if;
 if c.estado='Final'and(r is null or nullif(r->>'custo_total','')is null or nullif(r->>'quantidade','')::numeric is distinct from x.quantidade)then pend:=pend||jsonb_build_array('Item '||x.linha||': custo final ausente ou quantidade divergente');end if;
 select sum(nv.quantidade_axe)into q from public.imp_nota_vinculos nv join public.imp_notas n on n.id=nv.nota_id and n.embarque_id=eid and n.estado='Conciliada'where nv.pedido_item_id=x.pedido_item_id and public.axe_cadastro_canonico('produto',nv.produto_id)=pr.id;
 if jsonb_array_length(notas)>0 and(q is null or q<=0)then pend:=pend||jsonb_build_array('Item '||x.linha||': quantidade do produto não conciliada com a nota');end if;
 if q is not null and upper(btrim(x.unidade))=upper(btrim(pr.unidade_referencia))and q is distinct from x.quantidade then pend:=pend||jsonb_build_array('Item '||x.linha||': quantidade da nota diverge do recebimento');end if;
 if q is not null and q<>round(q,6)then pend:=pend||jsonb_build_array('Item '||x.linha||': quantidade da nota excede 6 casas decimais');end if;
 v:=nullif(r->>'custo_total','')::numeric;if v<0 then pend:=pend||jsonb_build_array('Item '||x.linha||': custo negativo');end if;
 items:=items||jsonb_build_array(jsonb_build_object('produto_id',pr.id,'codigo',pr.codigo_axe,'descricao',pr.descricao_referencia,'pedido_item_id',x.pedido_item_id,'pedido',x.pedido,'linha',x.linha,'quantidade',q,'unidade',pr.unidade_referencia,'quantidade_documento',x.quantidade,'unidade_documento',x.unidade,'valor_total',v,'custo_unitario',case when q>0 then round(v/q,8)end,'composicao',r));
 end loop;
 if c.estado='Final'and(select sum((i->>'valor_total')::numeric)from jsonb_array_elements(items)i)is distinct from(c.resultado->>'custo_total')::numeric then pend:=pend||jsonb_build_array('A soma dos custos dos itens diverge do total final');end if;
 select exists(select 1 from public.estoque_lotes_importacao l where l.embarque_id=eid and exists(select 1 from public.estoque_movimentos m where m.lote_importacao_id=l.id and not exists(select 1 from public.estoque_movimentos es where es.estorno_de=m.id)))into posted;
 if not posted and exists(select 1 from public.estoque_lotes_importacao where embarque_id=eid and custo_versao=c.versao)then pend:=pend||jsonb_build_array('Esta versão de custo foi estornada. Reabra e finalize o custo antes de registrar uma nova entrada');end if;
 source:=jsonb_build_object('embarque',to_jsonb(e),'custo',to_jsonb(c),'confirmacao',to_jsonb(conf),'notas',notas,'itens',items);finger:=md5(source::text);
 return jsonb_build_object('embarque_id',eid,'referencia',e.referencia,'itens',items,'pendencias',pend,'apto',jsonb_array_length(pend)=0,'integrado',posted,'versao',finger,'custo_versao',c.versao,'custo_hash',md5(c.resultado::text),'data_entrada',coalesce(conf.data_entrada,(select max(data_recebimento)from public.imp_embarque_itens where embarque_id=eid)),'nota_id',conf.nota_id,'notas',notas,'fonte',source);
end $$;
create function public.axe_estoque_importacao_integrar(eid uuid,uid uuid)returns jsonb language plpgsql set search_path=''as $$
declare r jsonb;it jsonb;lid uuid;conf public.imp_fluxo_estoque_confirmacoes;pr public.produtos_conciliacao;begin
 perform pg_advisory_xact_lock(728102826);select * into conf from public.imp_fluxo_estoque_confirmacoes where embarque_id=eid;
 if conf.embarque_id is null then return jsonb_build_object('pendente','Confirme a data da entrada');end if;
 r:=public.axe_estoque_importacao_previa(eid);
 if (r->>'integrado')::boolean then return jsonb_build_object('sem_alteracao',true,'embarque_id',eid);end if;
 if not(r->>'apto')::boolean then if r#>>'{fonte,custo,estado}'='Final'and r#>>'{fonte,embarque,status}'='Recebido'and jsonb_array_length(r->'notas')>0 then raise exception 'Estoque não integrado: %',r->'pendencias';end if;return jsonb_build_object('pendencias',r->'pendencias');end if;
 if exists(select 1 from public.estoque_lotes_importacao where embarque_id=eid and custo_versao=(r->>'custo_versao')::int)then return jsonb_build_object('pendente','Esta versão de custo já foi integrada e estornada. Revise o custo antes de registrar uma nova entrada');end if;
 if conf.data_entrada>(clock_timestamp()at time zone 'America/Sao_Paulo')::date then raise exception 'Data da entrada não pode ser futura';end if;
 insert into public.estoque_lotes_importacao(embarque_id,nota_id,custo_versao,custo_hash,fonte,usuario_id)values(eid,conf.nota_id,(r->>'custo_versao')::int,r->>'custo_hash',r->'fonte',uid)returning id into lid;
 for it in select * from jsonb_array_elements(r->'itens')loop
 select * into pr from public.produtos_conciliacao where id=(it->>'produto_id')::bigint;
 insert into public.estoque_movimentos(produto_id,tipo,quantidade,valor_total,custo_unitario,unidade,data_movimento,motivo,referencia,lote_importacao_id,pedido_item_id,cadastro_original,usuario_id)values(pr.id,'ENTRADA',(it->>'quantidade')::numeric,(it->>'valor_total')::numeric,(it->>'custo_unitario')::numeric,pr.unidade_referencia,conf.data_entrada,'IMPORTACAO',left((r->>'referencia')||' · '||(it->>'pedido')||' / '||(it->>'linha'),240),lid,(it->>'pedido_item_id')::uuid,jsonb_build_object('id',pr.id,'codigo',pr.codigo_axe,'descricao',pr.descricao_referencia,'unidade',pr.unidade_referencia),uid);
 end loop;return jsonb_build_object('lote_id',lid,'embarque_id',eid,'itens',jsonb_array_length(r->'itens'));
end $$;
create function public.axe_estoque_importacao_hook()returns trigger language plpgsql set search_path=''as $$
declare uid uuid;begin if TG_TABLE_NAME='imp_custos'then uid:=NEW.atualizado_por;else uid:=NEW.usuario_id;end if;perform public.axe_estoque_importacao_integrar(NEW.embarque_id,uid);return NEW;end $$;
create trigger estoque_importacao_custo after insert or update on public.imp_custos for each row execute function public.axe_estoque_importacao_hook();
create trigger estoque_importacao_confirmacao after insert on public.imp_fluxo_estoque_confirmacoes for each row execute function public.axe_estoque_importacao_hook();
create function public.axe_estoque_proteger_importacao()returns trigger language plpgsql set search_path=''as $$
declare eid uuid;begin perform pg_advisory_xact_lock(728102826);eid:=OLD.embarque_id;
 if TG_OP='UPDATE'and to_jsonb(NEW)=to_jsonb(OLD)then return NEW;end if;
 if exists(select 1 from public.estoque_lotes_importacao l join public.estoque_movimentos m on m.lote_importacao_id=l.id where l.embarque_id=eid and not exists(select 1 from public.estoque_movimentos es where es.estorno_de=m.id))then raise exception 'Importação já lançada no estoque. Estorne o lote antes de alterar o custo ou a confirmação de entrada';end if;
 return case when TG_OP='DELETE'then OLD else NEW end;end $$;
create trigger estoque_custo_origem_guard before update or delete on public.imp_custos for each row execute function public.axe_estoque_proteger_importacao();
create trigger estoque_nota_origem_guard before update or delete on public.imp_notas for each row execute function public.axe_estoque_proteger_importacao();
create trigger estoque_confirmacao_origem_guard before update or delete on public.imp_fluxo_estoque_confirmacoes for each row execute function public.axe_estoque_proteger_importacao();
create function public.axe_estoque(p_dados jsonb,p_usuario uuid)returns jsonb language plpgsql set search_path=''as $$
declare a text:=p_dados->>'acao';papel text;pagina int:=coalesce((p_dados->>'pagina')::int,0);q text:=left(coalesce(p_dados->>'busca',''),100);pid bigint;pr public.produtos_conciliacao;req uuid;cached public.estoque_requisicoes;res jsonb;prev jsonb;dt date;tipo text;motivo text;qty numeric;val numeric;unit numeric;saldo numeric;total numeric;old public.estoque_movimentos;rid uuid;eid uuid;row record;items jsonb:='[]';nid uuid;ref text;begin
 if not exists(select 1 from public.axe_rumo_revisores where usuario_id=p_usuario and ativo)then raise exception 'Usuário não autorizado';end if;
 select m.papel into papel from public.gestao_membros m where m.usuario_id=p_usuario and m.ativo;if papel is null then raise exception 'Usuário não autorizado';end if;
 if pagina<0 or pagina>100000 then raise exception 'Página inválida';end if;
 if a='stock_listar'then return jsonb_build_object('editar',papel in('ADMIN','EDITOR'),'total',(select count(*)from public.estoque_saldos s where concat_ws(' ',s.produto_id,s.codigo_axe,s.descricao_referencia,public.axe_cadastro_aliases('produto',s.produto_id))ilike '%'||q||'%'and(p_dados->>'com_saldo'is distinct from 'true'or s.quantidade<>0)),
 'linhas',(select coalesce(jsonb_agg(to_jsonb(z)),'[]')from(select s.* from public.estoque_saldos s where concat_ws(' ',s.produto_id,s.codigo_axe,s.descricao_referencia,public.axe_cadastro_aliases('produto',s.produto_id))ilike '%'||q||'%'and(p_dados->>'com_saldo'is distinct from 'true'or s.quantidade<>0)order by s.produto_id limit 50 offset pagina*50)z),'painel',jsonb_build_object('produtos_com_saldo',(select count(*)from public.estoque_saldos where quantidade>0),'valor_estoque',(select coalesce(sum(valor_estoque),0)from public.estoque_saldos),'movimentos',(select count(*)from public.estoque_movimentos)));end if;
 if a in('stock_detalhe','stock_movimentos')then pid:=case when a='stock_detalhe'then public.axe_cadastro_canonico('produto',(p_dados->>'produto_id')::bigint)end;return jsonb_build_object('produto',(select to_jsonb(s)from public.estoque_saldos s where produto_id=pid),'editar',papel in('ADMIN','EDITOR'),'total',(select count(*)from public.estoque_movimentos m join public.produtos_conciliacao p on p.id=m.produto_id where(pid is null or m.produto_id=pid)and concat_ws(' ',m.produto_id,m.referencia,m.cadastro_original::text,p.codigo_axe,p.descricao_referencia)ilike '%'||q||'%'),'linhas',(select coalesce(jsonb_agg(to_jsonb(z)),'[]')from(select m.*,l.embarque_id,e.referencia embarque,n.chave nota_chave,exists(select 1 from public.estoque_movimentos es where es.estorno_de=m.id)estornado from public.estoque_movimentos m left join public.estoque_movimentos original on original.id=m.estorno_de left join public.estoque_lotes_importacao l on l.id=coalesce(m.lote_importacao_id,original.lote_importacao_id)left join public.imp_embarques e on e.id=l.embarque_id left join public.imp_notas n on n.id=l.nota_id where(pid is null or m.produto_id=pid)and concat_ws(' ',m.produto_id,m.referencia,m.cadastro_original::text,(select p.codigo_axe||' '||p.descricao_referencia from public.produtos_conciliacao p where p.id=m.produto_id))ilike '%'||q||'%'order by m.ordem desc limit 50 offset pagina*50)z));end if;
 if a='stock_importacoes'then return jsonb_build_object('editar',papel in('ADMIN','EDITOR'),'linhas',(select coalesce(jsonb_agg(to_jsonb(z)),'[]')from(select e.id,e.referencia,e.status,c.estado custo_estado,exists(select 1 from public.estoque_lotes_importacao l where l.embarque_id=e.id and exists(select 1 from public.estoque_movimentos m where m.lote_importacao_id=l.id and not exists(select 1 from public.estoque_movimentos es where es.estorno_de=m.id)))integrado from public.imp_embarques e left join public.imp_custos c on c.embarque_id=e.id where e.status<>'Cancelado'and e.referencia ilike '%'||q||'%'order by e.criado_em desc limit 50 offset pagina*50)z),'total',(select count(*)from public.imp_embarques where status<>'Cancelado'and referencia ilike '%'||q||'%'));end if;
 if a='stock_importacao_previa'then return public.axe_estoque_importacao_previa((p_dados->>'embarque_id')::uuid)-'fonte';end if;
 if papel not in('ADMIN','EDITOR')then raise exception 'Sem permissão para movimentar estoque';end if;
 if a not in('stock_movimentar','stock_estornar','stock_importar','stock_estornar_importacao')then raise exception 'Ação inválida';end if;
 req:=(p_dados->>'requisicao_id')::uuid;if req is null then raise exception 'Identificador da operação obrigatório';end if;
 perform set_config('lock_timeout','5s',true);perform pg_advisory_xact_lock(728102826);
 select * into cached from public.estoque_requisicoes where id=req;if found then if cached.usuario_id<>p_usuario or cached.dados<>p_dados then raise exception 'Identificador reutilizado com outros dados';end if;return cached.resultado;end if;
 if a='stock_importar'then
 eid:=(p_dados->>'embarque_id')::uuid;prev:=public.axe_estoque_importacao_previa(eid);
 if p_dados->>'versao'is distinct from prev->>'versao'then raise exception 'Os documentos ou custos mudaram. Confira novamente a entrada';end if;
 if not(prev->>'apto')::boolean then raise exception '%',prev->'pendencias';end if;
 if(prev->>'integrado')::boolean then raise exception 'Embarque já integrado ao estoque';end if;
 if prev->>'nota_id'is null then
 dt:=(p_dados->>'data_movimento')::date;nid:=(p_dados->>'nota_id')::uuid;
 if dt is null or dt>(clock_timestamp()at time zone 'America/Sao_Paulo')::date then raise exception 'Informe uma data de entrada válida';end if;
 if not exists(select 1 from public.imp_notas where id=nid and embarque_id=eid and estado='Conciliada')then raise exception 'Selecione uma nota conciliada deste embarque';end if;
 insert into public.imp_fluxo_estoque_confirmacoes(embarque_id,nota_id,data_entrada,referencia,usuario_id)values(eid,nid,dt,(select 'NF-e '||chave from public.imp_notas where id=nid),p_usuario);
 end if;
 res:=public.axe_estoque_importacao_integrar(eid,p_usuario);
 if not exists(select 1 from public.estoque_lotes_importacao where embarque_id=eid and custo_versao=(prev->>'custo_versao')::int)then raise exception 'Entrada não integrada: %',res;end if;
 elsif a='stock_movimentar'then
 pid:=public.axe_cadastro_canonico('produto',(p_dados->>'produto_id')::bigint);select * into pr from public.produtos_conciliacao where id=pid for update;
 if pr.id is null or pr.mesclado_em_id is not null or not pr.ativo or pr.bloqueado_comercial or pr.controla_estoque=false then raise exception 'Selecione um produto ativo, liberado e com controle de estoque';end if;
 if nullif(btrim(pr.unidade_referencia),'')is null then raise exception 'Cadastre a unidade de estoque do produto';end if;
 dt:=(p_dados->>'data_movimento')::date;qty:=(p_dados->>'quantidade')::numeric;tipo:=p_dados->>'tipo';motivo:=p_dados->>'motivo';ref:=btrim(p_dados->>'referencia');
 if dt is null or dt>(clock_timestamp()at time zone 'America/Sao_Paulo')::date or qty is null or qty<=0 or qty<>round(qty,6)or qty>1000000000000 or length(coalesce(ref,''))not between 1 and 240 then raise exception 'Confira data, quantidade (até 6 casas) e referência';end if;
 select quantidade,valor_estoque into saldo,total from public.estoque_saldos where produto_id=pid;
 if tipo='ENTRADA'then
 if motivo not in('SALDO_INICIAL','COMPRA_NACIONAL','DEVOLUCAO_CLIENTE','AJUSTE_ENTRADA')or motivo is null then raise exception 'Motivo de entrada inválido';end if;
 if motivo='SALDO_INICIAL'and exists(select 1 from public.estoque_movimentos where produto_id=pid)then raise exception 'Saldo inicial permitido apenas antes da primeira movimentação';end if;
 unit:=(p_dados->>'custo_unitario')::numeric;if unit is null or unit<0 or unit>1000000000000 then raise exception 'Informe o custo unitário em reais';end if;val:=round(unit*qty,6);
 elsif tipo='SAIDA'then
 if motivo not in('VENDA','CONSUMO','DEVOLUCAO_FORNECEDOR','AJUSTE_SAIDA')or motivo is null then raise exception 'Motivo de saída inválido';end if;
 if qty>saldo then raise exception 'Saldo insuficiente: disponível % %',saldo,pr.unidade_referencia;end if;
 val:=case when qty=saldo then total else round(total/saldo*qty,6)end;unit:=val/qty;
 else raise exception 'Tipo de movimento inválido';end if;
 insert into public.estoque_movimentos(produto_id,tipo,quantidade,valor_total,custo_unitario,unidade,data_movimento,motivo,referencia,cadastro_original,usuario_id)values(pid,tipo,qty,val,round(unit,8),pr.unidade_referencia,dt,motivo,ref,jsonb_build_object('id',pr.id,'codigo',pr.codigo_axe,'descricao',pr.descricao_referencia,'unidade',pr.unidade_referencia),p_usuario)returning id into rid;
 res:=jsonb_build_object('movimento_id',rid,'produto_id',pid,'quantidade',qty,'valor_total',val,'custo_unitario',round(unit,8));
 else
 -- Estornos geram contrapartidas; nunca apagam ou editam o lançamento original.
 if a='stock_estornar_importacao'then eid:=(p_dados->>'embarque_id')::uuid;if not exists(select 1 from public.estoque_lotes_importacao l join public.estoque_movimentos m on m.lote_importacao_id=l.id where l.embarque_id=eid and not exists(select 1 from public.estoque_movimentos es where es.estorno_de=m.id))then raise exception 'Nenhum lote ativo para estornar';end if;end if;
 for old in select m.* from public.estoque_movimentos m left join public.estoque_lotes_importacao l on l.id=m.lote_importacao_id where(a='stock_estornar'and m.id=(p_dados->>'movimento_id')::uuid or a='stock_estornar_importacao'and l.embarque_id=eid)and m.estorno_de is null order by m.ordem loop
 if exists(select 1 from public.estoque_movimentos es where es.estorno_de=old.id)then if a='stock_estornar'then raise exception 'Movimento já estornado';else continue;end if;end if;
 if old.lote_importacao_id is not null and a='stock_estornar'then raise exception 'Estorne o lote completo na aba Importações';end if;
 select quantidade,valor_estoque into saldo,total from public.estoque_saldos where produto_id=old.produto_id;
 if old.tipo='ENTRADA'and(saldo<old.quantidade or total<old.valor_total)then raise exception 'Não é possível estornar uma entrada já consumida; regularize as saídas antes';end if;
 if old.tipo='ENTRADA'and saldo=old.quantidade and total<>old.valor_total then raise exception 'Estorno deixaria custo residual sem quantidade. Regularize os movimentos posteriores';end if;
 ref:=btrim(p_dados->>'referencia');if length(coalesce(ref,''))not between 3 and 240 then raise exception 'Informe o motivo do estorno';end if;
 insert into public.estoque_movimentos(produto_id,tipo,quantidade,valor_total,custo_unitario,unidade,data_movimento,motivo,referencia,estorno_de,cadastro_original,usuario_id)values(old.produto_id,case old.tipo when 'ENTRADA'then 'SAIDA'else 'ENTRADA'end,old.quantidade,old.valor_total,old.custo_unitario,old.unidade,(clock_timestamp()at time zone 'America/Sao_Paulo')::date,'ESTORNO',ref,old.id,old.cadastro_original,p_usuario)returning id into rid;items:=items||to_jsonb(rid);
 end loop;
 if jsonb_array_length(items)=0 then raise exception 'Movimento não encontrado ou não pode ser estornado';end if;res:=jsonb_build_object('estornos',items);
 end if;
 insert into public.estoque_requisicoes(id,usuario_id,dados,resultado)values(req,p_usuario,p_dados,res);return res;
end $$;
-- As novas FKs são transferidas pela mesclagem existente. Saldo deriva do livro,
-- sem tabela de posição que pudesse gerar colisão ou soma duplicada.
revoke all on function public.axe_estoque(jsonb,uuid),public.axe_estoque_importacao_previa(uuid),public.axe_estoque_importacao_integrar(uuid,uuid),public.axe_estoque_importacao_hook(),public.axe_estoque_proteger_importacao(),public.axe_estoque_movimento_guard(),public.axe_estoque_unidade_guard(),public.axe_estoque_mesclagem_previa(bigint,bigint)from public,anon,authenticated;
grant execute on function public.axe_estoque(jsonb,uuid),public.axe_estoque_importacao_previa(uuid),public.axe_estoque_importacao_integrar(uuid,uuid),public.axe_estoque_importacao_hook(),public.axe_estoque_proteger_importacao(),public.axe_estoque_movimento_guard(),public.axe_estoque_unidade_guard(),public.axe_estoque_mesclagem_previa(bigint,bigint)to service_role;
commit;
