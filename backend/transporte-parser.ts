import {identificarTransportador} from './transportador-identidade.ts';
import {getDocumentProxy} from 'npm:unpdf@1.9.1';
import {numeroDocumento} from './embarque-documentos-parser.ts';
const norm=(s:string)=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase().replace(/\s+/g,' ').trim();
const only=(a:any[])=>{const v=[...new Set(a.filter(x=>x!==null&&x!==''))];return v.length===1?v[0]:null;};
function weight(s:string){const m=s.match(/([\d.,]+)\s*(LBS?|KGS?|KG)\b/i);const n=m?numeroDocumento(m[1]):null;return n===null?null:{valor:n,unidade:/^LB/i.test(m![2])?'lb':'kg',kg:Number(n)*(/^LB/i.test(m![2])?0.45359237:1)};}
export async function parseTransporte(bytes:Uint8Array,paginas:any[],categoria:string){
 const text=paginas.map(p=>p.texto).join('\n'),dados:any={},origens:any[]=[],avisos:string[]=[],conflitos=new Set<string>();
 const pdf=await getDocumentProxy(bytes.slice(),{isEvalSupported:false,maxImageSize:16777216});
 const patterns:any={awb:/^NUMERO DE AWB:?$/,servico:/^TIPO DE SERVICO:?$/,volumes:/^NUMERO DE PECAS:?$/,peso_real:/^PESO TOTAL:?$/,peso_cubado:/^VOLUMETRICO:?$/,peso_faturavel:/^FATURAVEL:?$/,frete_usd:/^(?:FATOR DE FATURACAO|VALOR DO FRETE|FRETE TOTAL):?$/,data_documento:/^DATA DE ENVIO:?$/,previsao_chegada:/^DATA EST\. ENTREGA:?$/};
 try{for(let pg=1;pg<=pdf.numPages;pg++){const p=await pdf.getPage(pg),tc=await p.getTextContent(),ts=tc.items.filter((t:any)=>'str'in t&&t.str.trim()).map((t:any)=>({s:t.str.trim(),x:t.transform[4],y:t.transform[5]}));
  for(const [k,re]of Object.entries(patterns)){for(const label of ts.filter((t:any)=>(re as RegExp).test(norm(t.s)))){const vals=ts.filter((t:any)=>Math.abs(t.y-label.y)<2&&t.x>label.x+35).sort((a:any,b:any)=>a.x-b.x);if(!vals.length)continue;const raw=vals[0].s;let value:any=null;
   if(k==='awb')value=/^\d{10}$/.test(raw.replace(/\s/g,''))?raw.replace(/\s/g,''):null;
   else if(k.startsWith('peso_'))value=weight(raw);
   else if(k==='volumes')value=/^\d+$/.test(raw)?Number(raw):null;
   else if(k==='frete_usd'){const m=raw.match(/^([\d.,]+)\s*USD$/i);value=m?numeroDocumento(m[1]):null;}
   else if(k==='data_documento')value=/^\d{4}-\d{2}-\d{2}$/.test(raw)?raw:null;
   else if(k==='previsao_chegada'){const m=raw.match(/(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec),?\s+(\d{4})/i);if(m){const month=['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'].indexOf(m[2].toLowerCase())+1;value=m[3]+'-'+String(month).padStart(2,'0')+'-'+m[1].padStart(2,'0');}}
   else value=raw;
   if(value!==null){if(dados[k]!==undefined&&JSON.stringify(dados[k])!==JSON.stringify(value)){delete dados[k];conflitos.add(k);avisos.push('Valores conflitantes para '+k+' no documento.');}else if(!conflitos.has(k))dados[k]=value;origens.push({campo:k,valor:value,pagina:pg,trecho:label.s+' '+raw});}
  }}p.cleanup();
 }}finally{await pdf.loadingTask.destroy();}
 if(!dados.awb){const v=only([...text.matchAll(/WAYBILL\s+((?:\d[ -]*){10})(?!\d)|Waybill Tracking Number\s*(\d{10})/gi)].map(m=>(m[1]||m[2]).replace(/\D/g,'')));if(v)dados.awb=v;}
 if(!dados.awb){const refs=[...text.matchAll(/^(?:AWB|AIR WAYBILL|WAYBILL TRACKING NUMBER|TRACKING NUMBER|NUMERO DE AWB)[ \t]*:?[ \t]*(?:\r?\n[ \t]*)?([A-Z0-9][A-Z0-9 -]{4,39})[ \t]*$/gmi)].map(m=>m[1].trim()).filter(v=>/\d/.test(v));const v=only(refs);if(v)dados.awb=v;}
 if(!dados.servico&&/EXPRESS WORLDWIDE/i.test(text))dados.servico='EXPRESS WORLDWIDE';
 if(!dados.peso_real){const m=text.match(/Total Weight:\s*([\d.,]+\s*(?:LBS?|KGS?))/i);if(m)dados.peso_real=weight(m[1]);}
 if(!dados.peso_cubado){const m=text.match(/Dimensional Weight:\s*([\d.,]+\s*(?:LBS?|KGS?))/i);if(m)dados.peso_cubado=weight(m[1]);}
 if(!dados.peso_faturavel){const m=text.match(/Chargeable Weight:\s*([\d.,]+\s*(?:LBS?|KGS?))/i);if(m)dados.peso_faturavel=weight(m[1]);}
 if(!dados.volumes){const m=text.match(/Number of Packages:\s*(\d+)/i);if(m)dados.volumes=Number(m[1]);}
 const carrier=identificarTransportador(text);if(carrier.nome){dados.transportador=carrier.nome;if(carrier.documento)dados.transportador_documento=carrier.documento;origens.push({campo:'transportador',valor:carrier.nome,pagina:paginas.find(p=>norm(p.texto).includes(norm(carrier.nome!)))?.pagina||null,trecho:carrier.trecho,criterio:carrier.criterio});}else avisos.push(carrier.conflito?'Transportadoras conflitantes no documento: selecione o cadastro correto.':'Transportadora não identificada com segurança.');if(carrier.conflito)dados.transportador_conflito=true;
 if(!dados.awb)avisos.push('AWB não identificado: complete pela evidência.');
 if(categoria!=='ETIQUETA'&&!dados.frete_usd)avisos.push('Frete em USD não identificado: complete pelo recibo.');
 if(paginas.some(p=>p.metodo==='OCR'))avisos.push('Documento com OCR: revise os campos não reconhecidos nas coordenadas.');
 return{categoria,dados,origens,avisos};
}
export function combinarTransporte(documentos:any[],anterior?:any){
 const ordered=[...documentos].sort((a,b)=>({ETIQUETA:0,RECIBO:1,AJUSTE:2}[a.categoria as 'RECIBO']||0)-({ETIQUETA:0,RECIBO:1,AJUSTE:2}[b.categoria as 'RECIBO']||0));
 const dados:any={...(anterior?.dados||{})},avisos:string[]=[],origens:any[]=[];
 for(const doc of ordered){avisos.push(...doc.avisos);origens.push(...doc.origens.map((o:any)=>({...o,categoria:doc.categoria,documento:doc.arquivo_nome||doc.categoria,sha256:doc.sha256||null})));for(const [k,v]of Object.entries(doc.dados)){if(dados[k]!==undefined&&JSON.stringify(dados[k])!==JSON.stringify(v)&&['awb','peso_real','peso_cubado','peso_faturavel','frete_usd'].includes(k))avisos.push('Documentos informam '+k+' diferente. O recibo/ajuste foi priorizado para sua conferência.');dados[k]=v;}}
 dados.transportador_conflito=documentos.some(d=>d.dados.transportador_conflito===true);const carriers=[...new Set(documentos.map(d=>d.dados.transportador).filter(Boolean).map(norm))];if(carriers.length>1){dados.transportador_conflito=true;avisos.push('Transportadoras conflitantes entre os documentos: selecione o cadastro correto.');}
 return {dados,avisos:[...new Set(avisos)],origens,documentos};
}
