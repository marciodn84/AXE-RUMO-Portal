CREATE OR REPLACE FUNCTION public.axe_imp_fluxo(p_dados jsonb, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare a text:=p_dados->>'acao';papel text;pr public.imp_importacao_processos;src public.imp_importacao_processos;pid uuid;oid uuid;dest uuid;page integer:=coalesce((p_dados->>'pagina')::integer,0);term text:=left(coalesce(p_dados->>'busca',''),120);r jsonb;rr jsonb;x jsonb;ships jsonb:='[]';members jsonb;
begin
 select m.papel into papel from public.gestao_membros m join public.axe_rumo_revisores rv on rv.usuario_id=m.usuario_id and rv.ativo where m.usuario_id=p_usuario and m.ativo;if papel is null then raise exception 'Sem acesso às importações';end if;

 if a='custo_fluxo_grade' then
  return public.axe_imp_fluxo_base(jsonb_build_object('acao','custo_fluxo_listar','pagina',page,'busca',term),p_usuario)||jsonb_build_object('editar',papel in('ADMIN','EDITOR'));
 end if;
 if a='custo_fluxo_grade_detalhe' then
  oid:=(p_dados->>'pedido_id')::uuid;
  r:=public.axe_imp_fluxo_base(jsonb_build_object('acao','custo_fluxo_detalhe','pedido_id',oid),p_usuario);
  select coalesce(jsonb_agg(to_jsonb(z) order by z.parcial),'[]') into members from(
   select q.*,min(pp.parcial) parcial,papel in('ADMIN','EDITOR') and q.estado='Aberto' editar
   from public.imp_importacao_pedidos pp join public.imp_importacao_processos q on q.id=public.axe_imp_processo_raiz(pp.processo_id)
   where pp.pedido_id=oid group by q.id)z;
  ships:='[]';
  for x in select value from jsonb_array_elements(r->'embarques') loop
   select q.* into pr from public.imp_importacao_embarques pe join public.imp_importacao_processos q on q.id=public.axe_imp_processo_raiz(pe.processo_id) where pe.embarque_id=(x->'embarque'->>'id')::uuid;
   ships:=ships||jsonb_build_array(x||jsonb_build_object('processo',case when pr.id is not null then to_jsonb(pr) else null end,
    'parcial',(select min(pp.parcial) from public.imp_importacao_pedidos pp where pp.pedido_id=oid and public.axe_imp_processo_raiz(pp.processo_id)=pr.id),
    'editar',papel in('ADMIN','EDITOR') and pr.estado='Aberto',
    'abrangencia',(select l.dados->>'abrangencia' from public.imp_liberacoes l where l.pedido_id=oid and l.embarque_id=(x->'embarque'->>'id')::uuid limit 1)));
  end loop;
  return r||jsonb_build_object('processos',members,'embarques',ships,'numerario_arquivos',(select coalesce(jsonb_agg(to_jsonb(nd)-'caminho'-'dados'),'[]') from public.imp_num_documentos nd where nd.pronto and exists(select 1 from jsonb_array_elements(members) mm where mm->>'id'=public.axe_imp_processo_raiz(nd.processo_id)::text)));
 end if;
 if a in('custo_fluxo_listar','custo_fluxo_processos_abertos') then
  if page<0 or page>100000 then raise exception 'Página inválida';end if;
  return jsonb_build_object('editar',papel in('ADMIN','EDITOR'),'total',(select count(*) from public.imp_importacao_processos q where q.estado<>'Consolidado' and (a<>'custo_fluxo_processos_abertos' or q.estado='Aberto' and q.fornecedor_id=(p_dados->>'fornecedor_id')::bigint and q.moeda=p_dados->>'moeda') and exists(select 1 from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=q.id and po.referencia ilike '%'||term||'%')),
  'linhas',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select q.id processo_id,(select pp.pedido_id from public.imp_importacao_pedidos pp where public.axe_imp_processo_raiz(pp.processo_id)=q.id order by pp.parcial,pp.pedido_id limit 1) id,
   (select string_agg(po.referencia,', ' order by po.referencia) from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=q.id) referencia,
   (select string_agg(case when (select count(*) from public.imp_importacao_pedidos p2 where public.axe_imp_processo_raiz(p2.processo_id)=q.id)>1 then po.referencia||': ' else '' end||lpad(pp.parcial::text,2,'0'),', ' order by po.referencia) from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=q.id) parcial,
   (select jsonb_agg(jsonb_build_object('id',po.id,'referencia',po.referencia,'parcial',pp.parcial)) from public.imp_importacao_pedidos pp join public.imp_pedidos po on po.id=pp.pedido_id where public.axe_imp_processo_raiz(pp.processo_id)=q.id) pedidos,
   public.axe_imp_status_parcial(q.id) status_processo,f.razao_social fornecedor,q.fornecedor_id,q.moeda,
   (select coalesce(sum(public.axe_imp_valor_processo_pedido(q.id,pp.pedido_id)),0) from public.imp_importacao_pedidos pp where public.axe_imp_processo_raiz(pp.processo_id)=q.id) total,
   (select coalesce(sum(ap.valor),0) from public.imp_remessa_processos ap where public.axe_imp_processo_raiz(ap.processo_id)=q.id) pago,(select count(*) from public.imp_importacao_embarques pe where public.axe_imp_processo_raiz(pe.processo_id)=q.id) embarques
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
end $function$
;
