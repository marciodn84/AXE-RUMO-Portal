do $$
declare
 definicao text:=pg_get_functiondef('public.axe_documentos_entrada(jsonb,uuid)'::regprocedure);
 ponto constant text:='where pr.substituida_por is null and (coalesce(p_dados->>''estado'',''Pendente'')';
 filtro constant text:='where pr.substituida_por is null
  and (p_dados->>''escopo'' = ''geral'' or pr.tipo in (
   ''ACK'',''PEDIDO_IMPORTACAO'',''PARCELA_IMPORTACAO'',''EMBARQUE'',
   ''CONTRATO_CAMBIO'',''SWIFT'',''DI_DUIMP'',''NOTA_FISCAL'',''FECHAMENTO'',
   ''CUSTO_IMPORTACAO'',''FATURA_TRANSPORTADORA''
  )) and (coalesce(p_dados->>''estado'',''Pendente'')';
begin
 if strpos(definicao,ponto)=0 then raise exception 'Listagem de pré-cadastros incompatível';end if;
 execute replace(definicao,ponto,filtro);
end $$;
