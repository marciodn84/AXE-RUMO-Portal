alter function public.axe_imp_estrutura(jsonb,uuid) rename to axe_imp_estrutura_sem_pedido_pdf;
create function public.axe_imp_estrutura(p_dados jsonb,p_usuario uuid) returns jsonb
language plpgsql set search_path='' as $$
declare
 pedido jsonb;
 fornecedor jsonb;
 tributos jsonb;
 pid uuid;
begin
 if p_dados->>'acao' is distinct from 'v2_pedido_pdf' then
  return public.axe_imp_estrutura_sem_pedido_pdf(p_dados,p_usuario);
 end if;
 pid:=(p_dados->>'pedido_id')::uuid;
 pedido:=public.axe_imp_estrutura_sem_pedido_pdf(jsonb_build_object('acao','v2_detalhe','tipo','pedidos','id',pid),p_usuario);
 if pedido->>'id' is null then raise exception 'Pedido não encontrado';end if;
 pedido:=jsonb_set(pedido,'{itens}',(
  select coalesce(jsonb_agg(x||jsonb_build_object('subtotal',round((x->>'quantidade')::numeric*(x->>'valor_unitario')::numeric,2)) order by pos),'[]')
  from jsonb_array_elements(pedido->'itens') with ordinality t(x,pos)
 ));
 select jsonb_build_object('nome',f.razao_social,'pais',f.pais,'documento',coalesce(nullif(f.cnpj,''),f.documento_fiscal),
  'inscricao',f.inscricao_estadual,'contato',f.contato,'email',f.email,'telefone',f.telefone,'endereco',f.endereco)
 into fornecedor from public.fornecedores f where f.id=(pedido->>'fornecedor_id')::bigint;
 select jsonb_build_object('linhas',t.linhas,'total_documento',t.total_documento,'subtotal_documento',t.subtotal_documento)
 into tributos from public.tributos_registros t where t.origem='compra' and t.registro=pid::text;
 return jsonb_build_object('pedido',pedido,'fornecedor',fornecedor,'tributos',coalesce(tributos,'{"linhas":[]}'::jsonb));
end $$;
revoke all on function public.axe_imp_estrutura(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_imp_estrutura(jsonb,uuid) to service_role;
