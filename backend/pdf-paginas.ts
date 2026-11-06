import {getDocumentProxy} from 'npm:unpdf@1.9.1';
export async function extrairPaginasPDF(bytes:Uint8Array,ocr?:any[]){
 const pdf=await getDocumentProxy(bytes.slice(),{isEvalSupported:false,maxImageSize:16777216});
 const pages:any[]=[];
 try{
  if(pdf.numPages>20)throw Error('Documento excede 20 páginas.');
  if(ocr===undefined)ocr=Array.from({length:pdf.numPages},(_,i)=>({pagina:i+1,metodo:'SEM_OCR'}));
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
 return pages;
}
