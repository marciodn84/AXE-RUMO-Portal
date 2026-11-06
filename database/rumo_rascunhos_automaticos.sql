create extension if not exists pg_cron;

create or replace function public.axe_importar_rascunhos_rumo() returns jsonb
language plpgsql
set search_path = ''
set lock_timeout = '3s'
as $$
declare
  responsavel uuid;
  pedido record;
  resultado jsonb;
  criados jsonb := '[]';
  falhas jsonb := '[]';
begin
  -- Compartilha a trava da criação manual para evitar concorrência com o botão do ERP.
  if not pg_try_advisory_xact_lock(hashtextextended('axe_venda_rumo', 0)) then
    return jsonb_build_object('adiado', true);
  end if;

  select m.usuario_id into responsavel
  from public.gestao_membros m
  join public.axe_rumo_revisores r using (usuario_id)
  where m.ativo and r.ativo and m.papel = 'ADMIN'
  order by m.usuario_id
  limit 1;

  if responsavel is null then
    raise exception 'Importação RUMO sem administrador habilitado';
  end if;

  for pedido in
    select p.id, p.numero_pedido
    from public.pedidos p
    join public.clientes c on c.id = p.cliente_id
    where c.grupo_comercial = 'RUMO' and c.ativo and not c.legado_grupo
      and not exists (select 1 from public.comercial_pedidos v where v.pedido_rumo_id = p.id)
      and exists (
        select 1 from public.pedido_itens i where i.pedido_id = p.id and i.fase_status_sap = 'ACEITO'
      )
      and not exists (
        select 1 from public.pedido_itens i
        where i.pedido_id = p.id and coalesce(i.fase_status_sap, '') not in ('ACEITO', 'ENTREGUE')
      )
    order by p.id
  loop
    begin
      resultado := public.axe_venda_rumo(
        jsonb_build_object('acao', 'rumo_criar', 'pedido_rumo_id', pedido.id), responsavel
      );
      if not coalesce((resultado->>'existente')::boolean, false) then
        insert into public.comercial_eventos (tipo, registro_id, acao, usuario_id, evidencia)
        values ('pedido', (resultado->>'id')::bigint, 'rumo_importacao_automatica', responsavel,
          'Rascunho importado automaticamente após aceite no portal RUMO');
        criados := criados || jsonb_build_array(jsonb_build_object('rumo', pedido.numero_pedido, 'id', resultado->'id'));
      end if;
    exception when others then
      raise warning 'Importação automática RUMO % [%]: %', pedido.numero_pedido, sqlstate, sqlerrm;
      falhas := falhas || jsonb_build_array(jsonb_build_object('rumo', pedido.numero_pedido, 'motivo', sqlerrm));
    end;
  end loop;

  return jsonb_build_object('criados', criados, 'falhas', falhas);
end;
$$;

revoke all on function public.axe_importar_rascunhos_rumo() from public, anon, authenticated, service_role;

select cron.schedule(
  'axe-importar-rascunhos-rumo', '*/5 * * * *',
  'select public.axe_importar_rascunhos_rumo()'
);
