import {gerarPlanilha} from './planilha-cadastros.js?v=20261103-excel66';
import {prazoEntrega} from './prazo-entrega.js?v=20261103-prazo61';
const statuses={AGUARDANDO_ACEITE:'Aguardando aceite',ACEITO:'Aceito',CORRECAO_SOLICITADA:'Correção solicitada',CANCELADO:'Cancelado',RECUSADO:'Recusado',ENTREGUE:'Entregue','Sem resposta':'Aguardando aceite','Aceito Fornecedor':'Aceito','Devolucao Portal':'Correção solicitada',STATUS_AUSENTE:'Não informado',CANCELADO_PDF_SEM_PRODUTOS:'Cancelado',ITEM_EXCLUIDO_PDF:'Cancelado'};
const data=x=>typeof x==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(x)?x.split('-').reverse().join('/'):'';
export async function exportarPedidosExcel(api,consulta,{valido=()=>true,progresso=()=>{}}={}){
 const filtro={...consulta,acao:'listar',secao:'pedidos'},rows=[],ids=new Set();let expected=null;
 for(let pagina=0;;pagina++){
  if(!valido())return null;progresso(rows.length);
  const r=await api({...filtro,pagina});if(!valido())return null;
  if(!Number.isSafeInteger(r.total)||r.total<0||!Array.isArray(r.linhas))throw Error('Resposta incompleta da pesquisa.');
  if(expected===null)expected=r.total;
  if(r.total!==expected)throw Error('Os resultados mudaram durante a exportação. Atualize e tente novamente.');
  if(expected>100000)throw Error('Refine os filtros: a exportação permite até 100 mil itens.');
  if(!r.linhas.length&&rows.length<expected)throw Error('A pesquisa retornou dados incompletos.');
  for(const row of r.linhas){if(row.id==null||ids.has(String(row.id)))throw Error('Os resultados mudaram durante a exportação. Atualize e tente novamente.');ids.add(String(row.id));rows.push(row);}
  if(rows.length>expected)throw Error('A quantidade exportada diverge da pesquisa.');
  if(rows.length===expected)break;
 }
 if(!valido())return null;
 const numeric=['quantidade_original','quantidade_pendente','valor_unitario','icms_aliquota','ipi_aliquota'];
 const records=rows.map(r=>{const v={...r,numero_pedido:String(r.numero_pedido??''),numero_item:String(r.numero_item??''),cnpj_faturamento:String(r.cnpj_faturamento??''),codigo_material:String(r.codigo_material??''),numero_nf:String(r.numero_nf??''),data_pedido:data(r.data_pedido),data_remessa:data(r.data_remessa),status:statuses[r.fase_status_sap||r.status_texto]||r.fase_status_sap||r.status_texto||'Não informado',prazo:prazoEntrega(r).texto};for(const key of numeric)v[key]=r[key]!==null&&r[key]!==undefined&&r[key]!==''&&Number.isFinite(Number(r[key]))?Number(r[key]):'';return v;});
 return{blob:gerarPlanilha('pedido',records),total:records.length};
}
