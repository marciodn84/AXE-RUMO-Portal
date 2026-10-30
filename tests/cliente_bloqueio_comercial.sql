begin; do $$
declare c public.clientes;u uuid;blocked boolean;v bigint;prop bigint;propnum bigint;beforeevents bigint;
begin
 select * into c from public.clientes where id=12184;select usuario_id into u from public.axe_rumo_revisores where ativo limit 1;
 select count(*) into beforeevents from public.cadastros_decisoes where entidade='CLIENTE_COMERCIAL' and referencia=c.id::text;
 insert into public.comercial_propostas(cliente_id,titulo,entrada,documento,total,pendencias,criado_por) values(c.id,'TESTE ROLLBACK','{}','{}',0,'[]',u) returning id,numero into prop,propnum;
 blocked:=false;begin perform public.axe_cliente_bloqueio(c.id,true,'',u,c.atualizado_em);exception when raise_exception then blocked:=true;end;if not blocked then raise exception 'Motivo vazio aceito';end if;
 perform public.axe_cliente_bloqueio(c.id,true,'Teste transacional — não persistir',u,c.atualizado_em);
 blocked:=false;begin insert into public.comercial_oportunidades(cliente_id,titulo,etapa,responsavel) values(c.id,'TESTE','NOVA',u);exception when raise_exception then if sqlerrm like 'Cliente bloqueado comercialmente:%' then blocked:=true;else raise;end if;end;if not blocked then raise exception 'Oportunidade liberada';end if;
 blocked:=false;begin insert into public.comercial_propostas(cliente_id,titulo,entrada,documento,total,pendencias,criado_por) values(c.id,'TESTE','{}','{}',0,'[]',u);exception when raise_exception then if sqlerrm like 'Cliente bloqueado comercialmente:%' then blocked:=true;else raise;end if;end;if not blocked then raise exception 'Proposta liberada';end if;
 blocked:=false;begin update public.comercial_propostas set estado='ENVIADA' where id=prop;exception when raise_exception then if sqlerrm like 'Cliente bloqueado comercialmente:%' then blocked:=true;else raise;end if;end;if not blocked then raise exception 'Envio liberado';end if;
 blocked:=false;begin insert into public.comercial_pedidos(proposta_id,numero_proposta,pedido_cliente,documento,criado_por) values(prop,propnum,'TESTE','{}',u);exception when raise_exception then if sqlerrm like 'Cliente bloqueado comercialmente:%' then blocked:=true;else raise;end if;end;if not blocked then raise exception 'Venda liberada';end if;
 blocked:=false;begin insert into public.pedidos(cliente_id,numero_pedido) values(c.id,'TESTE-BLOQUEIO');exception when raise_exception then if sqlerrm like 'Cliente bloqueado comercialmente:%' then blocked:=true;else raise;end if;end;if not blocked then raise exception 'Pedido liberado';end if;
 select * into c from public.clientes where id=c.id;perform public.axe_cliente_bloqueio(c.id,false,null,u,c.atualizado_em);
 insert into public.comercial_oportunidades(cliente_id,titulo,etapa,responsavel) values(c.id,'TESTE','NOVA',u) returning id into v;
 if (select count(*) from public.cadastros_decisoes where entidade='CLIENTE_COMERCIAL' and referencia=c.id::text)<>beforeevents+2 then raise exception 'Histórico incompleto';end if;
end $$;rollback;
