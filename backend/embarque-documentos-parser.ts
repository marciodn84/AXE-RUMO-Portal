import {getDocumentProxy} from 'npm:unpdf@1.9.1';
const norm=(s:string)=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase();
export function numeroDocumento(raw:string){let s=raw.replace(/\s/g,'');if(!/^\d[\d.,]*$/.test(s))return null;if(s.includes(',')&&s.includes('.'))s=s.lastIndexOf(',')>s.lastIndexOf('.')?s.replace(/\./g,'').replace(',','.'):s.replace(/,/g,'');else if(s.includes(','))s=s.replace(',','.');return /^\d+(?:\.\d+)?$/.test(s)?s:null;}
const unique=(v:any[])=>{const a=[...new Set(v.filter(x=>x!==null&&x!==''))];return a.length===1?a[0]:null;};
function date(raw:string,us:boolean){const m=raw.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);if(!m)return null;const d=us?m[2]:m[1],mo=us?m[1]:m[2],s=m[3]+'-'+mo+'-'+d;return !isNaN(Date.parse(s))&&new Date(s+'T12:00:00Z').toISOString().slice(0,10)===s?s:null;}
export function parseInvoice(paginas:any[]){
 const text=paginas.map(p=>p.texto).join('\n'),avisos:string[]=[];
 const numero=unique([...text.matchAll(/Invoice\s*(?:No\.?|N[º°]|Number)\s*(?:Date)?\s*[:#]?\s*([A-Z0-9-]+)\s+(\d{2}\/\d{2}\/\d{4})/gi)].map(m=>m[1]));
 const dates=[...text.matchAll(/Invoice\s*(?:No\.?|N[º°]|Number)\s*(?:Date)?\s*[:#]?\s*[A-Z0-9-]+\s+(\d{2}\/\d{2}\/\d{4})/gi)].map(m=>date(m[1],true));
 const pedidos=[...new Set([...text.matchAll(/\bPO\s*\d{3,20}\b/gi)].map(m=>m[0].replace(/\s/g,'').toUpperCase()))];
 const moeda=unique([...text.matchAll(/Currency\s*:\s*([A-Z]{3})/gi)].map(m=>m[1].toUpperCase()));
 const valor=unique([...text.matchAll(/Invoice Total\s*:\s*([\d.,]+)/gi)].map(m=>numeroDocumento(m[1])));
 const itens:any[]=[];
 for(const p of paginas){for(const m of p.texto.matchAll(/^\s*(\d{1,6})\s+NYK\s*:\s*([A-Z0-9-]+)\s*\/\s*([A-Z0-9-]+)\s+([A-Z]{1,5})\s+([\d.,]+)\s+([\d.,]+)\s+([\d.,]+)/gm)){
  itens.push({linha:m[1],codigo_fornecedor:m[2],part_number:m[3],unidade:m[4],quantidade:numeroDocumento(m[5]),valor_unitario:numeroDocumento(m[6]),subtotal:numeroDocumento(m[7]),pagina:p.pagina,trecho:m[0].trim()});
 }}
 if(!/invoice/i.test(text))throw Error('O PDF não foi identificado como invoice.');
 if(!numero)avisos.push('Número da invoice não identificado com segurança.');if(!moeda)avisos.push('Moeda não identificada com segurança.');if(!valor)avisos.push('Total da invoice não identificado com segurança.');if(!itens.length)avisos.push('Leiaute dos itens não reconhecido: selecione e preencha os itens manualmente.');
 const total_itens=itens.length?Math.round(itens.reduce((s,i)=>s+Number(i.subtotal||0),0)*100)/100:null;
 if(valor&&total_itens!==null&&Math.abs(Number(valor)-total_itens)>0.01)avisos.push('Total da invoice difere da soma dos itens. Confira frete, encargos e os valores antes de aprovar.');
 return {numero,data:unique(dates),moeda,valor,pedidos,itens,total_itens,condicao:unique([...text.matchAll(/Payment Terms\s*:\s*([^\n]+)/gi)].map(m=>m[1].trim())),avisos};
}
export async function parsePacking(bytes:Uint8Array,paginas:any[]){
 const text=paginas.map(p=>p.texto).join('\n'),itens:any[]=[];
 const pedidos=[...new Set([...text.matchAll(/\bPO\s*\d{3,20}\b/gi)].map(m=>m[0].replace(/\s/g,'').toUpperCase()))];
 const pdf=await getDocumentProxy(bytes.slice(),{isEvalSupported:false,maxImageSize:16777216});
 try{for(let pg=1;pg<=pdf.numPages;pg++){
  const p=await pdf.getPage(pg),tc=await p.getTextContent(),ts=tc.items.filter((t:any)=>'str'in t&&t.str.trim()).map((t:any)=>({s:t.str.trim(),x:t.transform[4],y:t.transform[5]}));
  const hdr=ts.filter((t:any)=>/^Shipped$/i.test(t.s));
  const codes=ts.filter((t:any)=>/^NYK\s*:?/i.test(t.s)).map((t:any)=>{if(/^NYK\s*:/i.test(t.s))return t;const rest=ts.filter((v:any)=>Math.abs(v.y-t.y)<4&&v.x>t.x&&v.x<t.x+40&&/^\s*:/.test(v.s));return rest.length===1?{...t,s:t.s+rest[0].s}:t;});
  for(const code of codes){const h=hdr.find((h:any)=>h.y>code.y&&h.x>code.x);const vals=h?ts.filter((t:any)=>Math.abs(t.y-code.y)<4&&t.x>=h.x&&t.x<h.x+38&&/^\d+(?:[.,]\d+)?$/.test(t.s)):[];const line=ts.filter((t:any)=>Math.abs(t.y-code.y)<4&&t.x<code.x&&/^\d{1,6}$/.test(t.s));
   const c=code.s.match(/NYK\s*:\s*([A-Z0-9-]+)/i);if(c)itens.push({linha:unique(line.map((x:any)=>x.s)),codigo_fornecedor:c[1],quantidade:unique(vals.map((x:any)=>numeroDocumento(x.s))),pagina:pg});
  }p.cleanup();
 }}finally{await pdf.loadingTask.destroy();}
 const kg=unique([...text.matchAll(/Gross Weight\s+Lbs\s+Kgs\s+([\d.,]+)\s+([\d.,]+)/gi)].map(m=>numeroDocumento(m[2])));
 const lbs=unique([...text.matchAll(/Gross\s+weight\s+([\d.,]+)\s*(?:lbs|lb)\b/gi)].map(m=>numeroDocumento(m[1])));
 return {pedidos,itens,peso_bruto_kg:kg?Number(kg):lbs?Number(lbs)*0.45359237:null,avisos:!itens.length?['Itens do packing list não reconhecidos; faça a conferência manual.']:[]};
}
export function parsePesos(paginas:any[]){
 const text=paginas.map(p=>p.texto).join('\n'),itens:any[]=[];
 for(const m of text.matchAll(/(?:^|\n)\s*([\d-]{10,20})\s*\n\s*QTY\s*:\s*([\d.,]+)([\s\S]*?)(?=\n\s*[\d-]{10,20}\s*\n\s*QTY|$)/gi)){
  const w=m[3].match(/Gross\s+weight\s+([\d.,]+)\s*(lbs?|kgs?)\.?\s*ea\.,\s*([\d.,]+)\s*lbs?\.?\s*total/i);if(w)itens.push({codigo_fornecedor:m[1],quantidade:numeroDocumento(m[2]),peso_bruto_kg:Number(numeroDocumento(w[3]))*0.45359237,trecho:w[0]});
 }return {itens};
}
export function combinarLiberacao(invoice:any,packing:any,pesos:any,pedido:any){
 const key=(s:any)=>String(s||'').replace(/[^A-Z0-9]/gi,'').toUpperCase(),avisos=[...invoice.avisos,...packing.avisos];
 const itens=invoice.itens.map((x:any)=>{const candidates=pedido.itens.filter((p:any)=>Number(p.linha)===Number(x.linha)&&[p.codigo_fornecedor,p.codigo_axe].some((c:any)=>c&&[x.codigo_fornecedor,x.part_number].some((d:any)=>key(c)===key(d))));
  const p=candidates.length===1?candidates[0]:null,pl=packing.itens.filter((r:any)=>key(r.codigo_fornecedor)===key(x.codigo_fornecedor)||Number(r.linha)===Number(x.linha)),w=pesos?.itens.filter((r:any)=>[x.codigo_fornecedor,x.part_number].some((d:any)=>key(r.codigo_fornecedor)===key(d)))||[];
  if(pl.length===1&&key(pl[0].codigo_fornecedor)!==key(x.codigo_fornecedor))avisos.push('Linha '+x.linha+': código do packing '+pl[0].codigo_fornecedor+' difere da invoice '+x.codigo_fornecedor+'. Confira o original antes de importar.');
  if(pl.length!==1||pl[0].quantidade===null)avisos.push('Linha '+x.linha+': quantidade do packing list não confirmada automaticamente.');else if(Number(pl[0].quantidade)!==Number(x.quantidade))avisos.push('Linha '+x.linha+': quantidade da invoice difere do packing list.');
  if(!p)avisos.push('Linha '+x.linha+': selecione o produto do pedido.');else if(Number(p.valor_unitario)!==Number(x.valor_unitario))avisos.push('Linha '+x.linha+': preço da invoice '+x.valor_unitario+'; preço do pedido '+p.valor_unitario+'. Corrija a divergência antes de aprovar.');
  return {...x,pedido_item_id:p?.id||'',packing_quantidade:pl.length===1?pl[0].quantidade:null,peso_bruto:w.length===1&&Number(w[0].quantidade)===Number(x.quantidade)?w[0].peso_bruto_kg:null};
 });
 if(!invoice.pedidos.includes(pedido.referencia.toUpperCase())||!packing.pedidos.includes(pedido.referencia.toUpperCase()))avisos.push('Confira o número do pedido nos dois documentos; uma correção exige justificativa.');
 return {invoice,packing,pesos,itens,avisos};
}
