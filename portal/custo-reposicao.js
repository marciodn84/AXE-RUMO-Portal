export function custoEmMoeda(valor, moeda) {
  return new Intl.NumberFormat('pt-BR',{
    style:'currency',currency:moeda,currencyDisplay:'code',maximumFractionDigits:8
  }).format(Number(valor));
}
export function referenciaCompra(compra) {
  if(!compra)return 'Ainda não há compra importada confirmada na unidade AXE.';
  const data=compra.data?.split('-').reverse().join('/');
  return [custoEmMoeda(compra.valor_unitario,compra.moeda)+' / '+compra.unidade,
    compra.origem==='Invoice'?'Invoice conferida':'Entrada de importação',
    compra.fornecedor,compra.pedido,compra.linha&&'linha '+compra.linha,data].filter(Boolean).join(' · ');
}
export function margensPorCusto(resultado, quantidade, outrosCustos, custoEstoque, custoReposicao) {
  if(resultado.estado!=='CALCULADA'||resultado.totais.receita_apos_tributos==null)return null;
  const receita=Number(resultado.totais.receita_apos_tributos);
  const faturado=Number(resultado.totais.total_cobrado);
  const centavos=n=>Math.round(n*100)/100;
  const calcular=custo=>{
    if(custo==null||!Number.isFinite(custo)||custo<0)return null;
    const margem=centavos(receita-centavos(custo*quantidade+outrosCustos));
    return {custo,margem,percentual:faturado>0?margem/faturado*100:null};
  };
  return {estoque:calcular(custoEstoque),reposicao:calcular(custoReposicao)};
}
