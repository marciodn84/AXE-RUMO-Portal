// Files stay on this device during text extraction and OCR. CDN requests download code/models only.
export async function lerPDFImportacao(file,progress,signal){
 if(!file||file.size>8388608||file.size===0)throw Error('Selecione um PDF de até 8 MB.');
 const bytes=new Uint8Array(await file.arrayBuffer());if(new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-')throw Error('Arquivo não é PDF.');
 progress('Carregando leitor de PDF…');
 const {getDocumentProxy}=await import('https://esm.sh/unpdf@1.9.1');
 const pdf=await getDocumentProxy(bytes,{isEvalSupported:false,maxImageSize:16777216,useSystemFonts:true});let worker=null,ocrPage=0;
 const pages=[];const stop=()=>{if(worker)worker.terminate().catch(()=>{});};signal?.addEventListener('abort',stop,{once:true});
 try{
  if(pdf.numPages>20)throw Error('Divida o documento: limite de 20 páginas por leitura.');
  for(let i=1;i<=pdf.numPages;i++){
   if(signal?.aborted)throw Error('Leitura cancelada.');
   ocrPage=i;progress('Lendo página '+i+' de '+pdf.numPages+'…');const page=await pdf.getPage(i),content=await page.getTextContent();
   const lines=[];let lastY=null,line=[];
   for(const t of content.items){if(!('str' in t))continue;const y=Math.round(t.transform[5]*2)/2;if(lastY!==null&&Math.abs(y-lastY)>3){lines.push(line.join(' '));line=[];}line.push(t.str);lastY=y;if(t.hasEOL){lines.push(line.join(' '));line=[];lastY=null;}}if(line.length)lines.push(line.join(' '));
   let texto=lines.join('\n'),metodo='PDF',confianca=null;
   if(texto.trim().length<80){
    if(!worker){progress('Preparando OCR em português. O primeiro uso baixa o modelo…');const {default:Tesseract}=await import('https://cdn.jsdelivr.net/npm/tesseract.js@7.0.0/dist/tesseract.esm.min.js');const {createWorker}=Tesseract;
     worker=await createWorker('por',1,{workerPath:'https://cdn.jsdelivr.net/npm/tesseract.js@7.0.0/dist/worker.min.js',corePath:'https://cdn.jsdelivr.net/npm/tesseract.js-core@7.0.0',langPath:'https://cdn.jsdelivr.net/npm/@tesseract.js-data/por@1.0.0/4.0.0_best_int',logger:m=>{if(m.status==='recognizing text')progress('OCR da página '+ocrPage+' de '+pdf.numPages+': '+Math.round(m.progress*100)+'%');}});
    }
    const initial=page.getViewport({scale:1}),scale=Math.min(2,Math.sqrt(12000000/(initial.width*initial.height))),vp=page.getViewport({scale}),canvas=document.createElement('canvas');canvas.width=Math.ceil(vp.width);canvas.height=Math.ceil(vp.height);
    try{await page.render({canvasContext:canvas.getContext('2d'),viewport:vp}).promise;const r=await worker.recognize(canvas);texto=r.data.text;confianca=r.data.confidence;metodo='OCR';}finally{canvas.width=canvas.height=0;}
   }
   if(texto.length>80000)throw Error('Texto da página excede o limite.');pages.push({pagina:i,texto,metodo,confianca});page.cleanup();
  }
  if(pages.every(p=>!p.texto.trim()))throw Error('Não foi possível reconhecer o texto. Envie um PDF legível.');
  return pages;
 }finally{signal?.removeEventListener('abort',stop);if(worker)await worker.terminate().catch(()=>{});await pdf.loadingTask.destroy();}
}

