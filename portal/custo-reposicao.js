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
