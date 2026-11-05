import {getDocumentProxy} from 'npm:unpdf@1.9.1';
import {parseDI,CAMPOS_DI} from './di-parser.ts';
export async function extrairDI(bytes:Uint8Array,ocr:any[]){
 const pdf=await getDocumentProxy(bytes.slice(),{isEvalSupported:false,maxImageSize:16777216});
 const pages:any[]=[];
 try{
  if(pdf.numPages>20)throw Error('Documento excede 20 páginas.');
  if(!Array.isArray(ocr)||ocr.length!==pdf.numPages)throw Error('Envie a leitura de todas as páginas do PDF.');
  for(let i=1;i<=pdf.numPages;i++){
   const p=await pdf.getPage(i),text=await p.getTextContent();const lines:string[]=[];let line:string[]=[],lastY:number|null=null;
   for(const t of text.items){if(!('str' in t))continue;const y=Math.round(t.transform[5]*2)/2;if(lastY!==null&&Math.abs(y-lastY)>3){lines.push(line.join(' '));line=[];}line.push(t.str);lastY=y;if(t.hasEOL){lines.push(line.join(' '));line=[];lastY=null;}}if(line.length)lines.push(line.join(' '));
   const native=lines.join('\n');
   if(native.trim().length>=80)pages.push({pagina:i,texto:native,metodo:'PDF',confianca:null});
   else{const x=ocr[i-1];if(x?.pagina!==i||x.metodo!=='OCR'||typeof x.texto!=='string'||x.texto.length>80000)throw Error('OCR ausente ou inválido na página '+i);pages.push({pagina:i,texto:x.texto,metodo:'OCR',confianca:typeof x.confianca==='number'&&x.confianca>=0&&x.confianca<=100?x.confianca:null});}
   p.cleanup();
  }
 }finally{await pdf.loadingTask.destroy();}
 return {paginas:pages,extraido:parseDI(pages)};
}
export function revisarDI(original:any,d:any,numPages:number){
 if(!d||typeof d!=='object'||!Array.isArray(d.itens)||d.itens.length<1||d.itens.length>500)throw Error('Revise os itens da declaração.');
 if(!/^\d{2}BR\d{11}$|^\d{10}$/.test(d.numero||'')||!/^\d{14}$/.test(d.cnpj||''))throw Error('Confira o número da DI/DUIMP e o CNPJ.');
 const changes:any[]=[],motivo=String(d.motivo||'').trim().slice(0,2000);
 function change(path:string,old:any,value:any){if((old??null)!==(value??null)){if(!motivo)throw Error('Informe a justificativa e a referência documental das correções.');changes.push({campo:path,anterior:old??null,novo:value??null,motivo});}}
 change('numero',original.numero,d.numero);change('cnpj',original.cnpj,d.cnpj);
 const used=new Set();
 const itens=d.itens.map((item:any)=>{
  const rawId=String(item.id||''),id=String(Number(rawId));if(!/^\d{1,5}$/.test(rawId)||used.has(id))throw Error('Item/adição ausente ou duplicado.');used.add(id);
  const old=original.itens.find((x:any)=>x.id===id),ncm=item.ncm||null,unidade=item.unidade?String(item.unidade).trim().toUpperCase():null;
  if(ncm!==null&&!/^\d{8}$/.test(ncm))throw Error('NCM deve conter 8 dígitos.');if(unidade&&unidade.length>20)throw Error('Unidade inválida.');
  change('itens.'+id+'.ncm',old?.ncm,ncm);change('itens.'+id+'.unidade',old?.unidade,unidade);
  function field(k:string,src:any,prev:any,scale:number,positive=false){
   const valor=src?.valor==null||src.valor===''?null:String(src.valor),pagina=src?.pagina==null||src.pagina===''?null:Number(src.pagina);
   if(valor!==null&&(!new RegExp('^\\d{1,12}(?:\\.\\d{1,'+scale+'})?$').test(valor)||(positive&&Number(valor)<=0)))throw Error('Valor inválido no item '+id+': '+k);
   if(valor!==null&&(!Number.isInteger(pagina)||pagina!<1||pagina!>numPages))throw Error('Informe a página de origem de '+k+' no item '+id);
   change('itens.'+id+'.'+k,prev?.valor,valor);if(valor!==null&&prev?.pagina!==pagina)change('itens.'+id+'.'+k+'.pagina',prev?.pagina,pagina);
   return {valor,pagina:valor===null?null:pagina,trecho:prev?.trecho||'',origem:prev?.valor===valor&&prev?.pagina===pagina?'Extraído':'Confirmado manualmente'};
  }
  return {id,ncm,unidade,descricao:String(item.descricao||old?.descricao||'').slice(0,1000),quantidade:field('quantidade',item.quantidade,old?.quantidade,6,true),campos:Object.fromEntries(CAMPOS_DI.map(k=>[k,field(k,item.campos?.[k],old?.campos?.[k],2)]))};
 });
 // Omitting a previously detected item is a material correction too.
 for(const item of original.itens)if(!used.has(item.id))change('itens.'+item.id,item,null);
 return {numero:d.numero,cnpj:d.cnpj,especie:original.especie,itens,motivo,correcoes:changes};
}

