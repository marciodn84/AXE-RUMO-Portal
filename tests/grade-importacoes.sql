begin;
set local role service_role;
do $$declare uid uuid;oid uuid;proc uuid;before_count int;after_count int;result jsonb;begin
 select m.usuario_id into uid from public.gestao_membros m join public.axe_rumo_revisores rv on rv.usuario_id=m.usuario_id and rv.ativo where m.ativo and m.papel in('ADMIN','EDITOR') limit 1;
 result:=public.axe_imp_fluxo('{"acao":"custo_fluxo_grade"}',uid);before_count:=(result->>'total')::int;oid:=(result->'linhas'->0->>'id')::uuid;
 insert into public.imp_importacao_processos(fornecedor_id,moeda,criado_por)select fornecedor_id,moeda,uid from public.imp_pedidos where id=oid returning id into proc;
 insert into public.imp_importacao_pedidos(processo_id,pedido_id,parcial)select proc,oid,coalesce(max(parcial),0)+1 from public.imp_importacao_pedidos where pedido_id=oid;
 result:=public.axe_imp_fluxo('{"acao":"custo_fluxo_grade"}',uid);after_count:=(result->>'total')::int;
 if after_count<>before_count or(select count(*) from jsonb_array_elements(result->'linhas')x where x->>'id'=oid::text)<>1 then raise exception 'Pedido duplicado na grade';end if;
 result:=public.axe_imp_fluxo(jsonb_build_object('acao','custo_fluxo_grade_detalhe','pedido_id',oid),uid);
 if not exists(select 1 from jsonb_array_elements(result->'processos')x where x->>'id'=proc::text)then raise exception 'Processo adicional omitido';end if;
 begin perform public.axe_imp_fluxo('{"acao":"custo_fluxo_grade"}',gen_random_uuid());raise exception 'Acesso indevido';exception when raise_exception then if sqlerrm='Acesso indevido' then raise;end if;end;
end $$;
set constraints all immediate;
rollback;
