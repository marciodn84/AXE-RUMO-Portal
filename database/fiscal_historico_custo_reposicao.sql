create function public.axe_fiscal_cenario_reposicao(
 entrada jsonb, resultado jsonb, usuario uuid
) returns jsonb language plpgsql set search_path='' as $$
declare
 dados jsonb:=entrada->'reposicao';
 base jsonb;
 compra jsonb;
 taxa numeric;
 outros_unitarios numeric;
 estoque numeric;
 reposicao numeric;
 quantidade numeric:=(resultado#>>'{comercial,quantidade}')::numeric;
 outros_venda numeric:=coalesce((resultado#>>'{totais,custos_adicionais}')::numeric,0);
 receita numeric:=(resultado#>>'{totais,receita_apos_tributos}')::numeric;
 cobrado numeric:=(resultado#>>'{totais,total_cobrado}')::numeric;
 calculada boolean:=resultado->>'estado'='CALCULADA';
 margens jsonb;
begin
 if jsonb_typeof(dados) is distinct from 'object' then raise exception 'Cenário de reposição inválido';end if;
 if nullif(dados->>'taxa','') is not null then
  if dados->>'taxa' !~ '^[0-9]{1,8}(\.[0-9]{1,10})?$' then raise exception 'Informe uma taxa de câmbio válida';end if;
  taxa:=(dados->>'taxa')::numeric;
  if taxa<=0 then raise exception 'A taxa de câmbio deve ser positiva';end if;
 end if;
 if nullif(dados->>'outros_custos_unitarios','') is not null then
  if dados->>'outros_custos_unitarios' !~ '^-?[0-9]{1,12}(\.[0-9]{1,8})?$' then raise exception 'Informe os demais custos em reais por unidade';end if;
  outros_unitarios:=(dados->>'outros_custos_unitarios')::numeric;
 end if;
 base:=public.axe_imp_estrutura(jsonb_build_object('acao','v2_produto_custo_reposicao','produto_id',entrada#>>'{contexto,produto_id}'),usuario);
 if base->>'importado' is distinct from 'true' then raise exception 'O cenário exige um produto importado';end if;
 compra:=base->'compra';
 estoque:=(base#>>'{saldo,custo_medio}')::numeric;
 if taxa is not null then
  if compra->>'valor_unitario' is null then raise exception 'Produto sem compra confirmada para conversão';end if;
  if dados->>'moeda' is distinct from compra->>'moeda' then raise exception 'A moeda de compra mudou. Selecione o produto novamente';end if;
  reposicao:=round((compra->>'valor_unitario')::numeric*taxa+coalesce(outros_unitarios,0),8);
  if reposicao<0 then raise exception 'O custo de reposição não pode ser negativo';end if;
 end if;
 select jsonb_object_agg(b.nome,case when b.custo is not null then jsonb_build_object('custo',b.custo,
  'custo_total',round(b.custo*quantidade,2)+outros_venda,
  'margem',m.valor,'percentual',case when cobrado>0 then round(m.valor/cobrado*100,4) end) end)
 into margens
 from (values ('estoque',estoque),('reposicao',reposicao)) b(nome,custo)
 cross join lateral (select case when calculada then receita-round(b.custo*quantidade,2)-outros_venda end valor) m;
 return jsonb_build_object('compra',compra,'taxa',taxa,'outros_custos_unitarios',outros_unitarios,
  'quantidade',quantidade,'outros_custos_da_venda',outros_venda,'margens',margens);
end $$;
revoke all on function public.axe_fiscal_cenario_reposicao(jsonb,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_fiscal_cenario_reposicao(jsonb,jsonb,uuid) to service_role;

do $$
declare
 definicao text:=pg_get_functiondef('public.axe_fiscal_simular(jsonb,uuid)'::regprocedure);
 ponto constant text:=' insert into public.fiscal_simulacoes(usuario_id,requisicao_id,hash_entrada,entrada,resultado)';
begin
 if strpos(definicao,ponto)=0 then raise exception 'Rotina de simulação incompatível';end if;
 execute replace(definicao,ponto,
 ' if p_entrada ? ''reposicao'' then
    resultado:=resultado||jsonb_build_object(''cenario_reposicao'',public.axe_fiscal_cenario_reposicao(p_entrada,resultado,p_usuario));
   end if;
 '||ponto);
end $$;
