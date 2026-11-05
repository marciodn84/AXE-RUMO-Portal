export const CAMPOS_DI=['FOB','Frete','Seguro','II','IPI','ICMS','PIS','COFINS','IBS','CBS'] as const;
type Fonte={valor:string|null,pagina:number|null,trecho:string,conflitos?:string[]};
const empty=():Fonte=>({valor:null,pagina:null,trecho:''});
const norm=(s:string)=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase();
export function numeroBR(v:string,scale=6){
 const s=v.trim();if(!/^(?:\d{1,3}(?:\.\d{3})+|\d+)(?:,\d+)?$/.test(s))return null;
 const n=s.replace(/\./g,'').replace(',','.');if(!new RegExp('^\\d{1,12}(?:\\.\\d{1,'+scale+'})?$').test(n))return null;return n;
}
export function parseDI(paginas:any[]){
 if(!Array.isArray(paginas)||!paginas.length||paginas.length>20)throw Error('Documento deve conter de 1 a 20 páginas');
 if(paginas.some((p,i)=>p.pagina!==i+1||typeof p.texto!=='string'||p.texto.length>80000||!['PDF','OCR'].includes(p.metodo)))throw Error('Páginas de leitura inválidas');
 const totalText=paginas.reduce((s,p)=>s+p.texto.length,0);if(totalText>500000)throw Error('Texto extraído excede o limite');
 const all=paginas.map(p=>norm(p.texto)).join('\n');
 const nums=[...all.matchAll(/(?:DUIMP|DUIMP\s+N[RO.]*|DECLARACAO DE IMPORTACAO)[^\n\d]{0,25}(\d{2}\s*BR\s*\d[\d.\s-]{8,24})/g)].map(m=>m[1].replace(/[^A-Z0-9]/g,''));
 const duimp=[...new Set(nums.filter(n=>/^\d{2}BR\d{11}$/.test(n)))];
 const diNums=[...all.matchAll(/(?:D\.?I\.?\s*(?:N[RO°º.]*)?|DECLARACAO DE IMPORTACAO)\s*[:.\-]?\s*(\d{2}\/\d{7}-\d)/g)].map(m=>m[1].replace(/\D/g,''));
 const ids=[...new Set([...duimp,...diNums])];
 const cnpjs=[...all.matchAll(/CNPJ(?:\s+DO IMPORTADOR)?[^\d]{0,60}(\d{2}\.\d{3}\.\d{3}\/\d{4}-\d{2}|\d{14})/g)].map(m=>m[1].replace(/\D/g,''));
 const cnpj=[...new Set(cnpjs)];
 const out:any={numero:ids.length===1?ids[0]:null,especie:duimp.length?'DUIMP':'DI',cnpj:cnpj.length===1?cnpj[0]:null,parser:'axe-di-1',totais:Object.fromEntries(CAMPOS_DI.map(k=>[k,empty()])),itens:[],avisos:[],paginas:paginas.map(p=>({pagina:p.pagina,metodo:p.metodo,confianca:p.confianca??null}))};
 if(ids.length!==1)out.avisos.push('Número da declaração ausente ou ambíguo. Confira o documento.');
 if(!out.cnpj)out.avisos.push('CNPJ do importador não identificado com segurança.');
 const fields:any={FOB:/(?:^|\b)FOB\s*[.:\s]*R\$\s*([\d.,]+)/,Frete:/\bFRETE\s*[.:\s]*R\$\s*([\d.,]+)/,Seguro:/\bSEGURO\s*[.:\s]*R\$\s*([\d.,]+)/,
  II:/(?:^|[|\n])\s*II\s*[.:\s]*(?:\d[\d.,]*\s*%[^|\n]*?)?R\$\s*([\d.,]+)/,
  IPI:/(?:^|[|\n])\s*IPI\s*[.:\s]*(?:\d[\d.,]*\s*%[^|\n]*?)?R\$\s*([\d.,]+)/,
  ICMS:/(?:^|[|\n])\s*ICMS(?:\s+RECOLHIDO)?\s*[.:\s]*R\$\s*([\d.,]+)/,
  PIS:/(?:^|[|\n])\s*PIS(?:\s*\/\s*PASEP)?\s*[.:\s]*(?:\d[\d.,]*\s*%[^|\n]*?)?R\$\s*([\d.,]+)/,
  COFINS:/(?:^|[|\n])\s*COFINS\s*[.:\s]*(?:\d[\d.,]*\s*%[^|\n]*?)?R\$\s*([\d.,]+)/,
  IBS:/\bIBS\s*(?:TOTAL)?\s*[.:\s]*R\$\s*([\d.,]+)/,CBS:/\bCBS\s*[.:\s]*R\$\s*([\d.,]+)/};
 function set(target:any,key:string,v:string,page:number,trecho:string,scale=2){const n=numeroBR(v,scale);if(n===null)return;const old=target[key];if(old?.valor!==null&&old?.valor!==undefined&&Number(old.valor)!==Number(n)){target[key]={valor:null,pagina:page,trecho:trecho.slice(0,500),conflitos:[...new Set([...(old.conflitos||[]),old.valor,n].filter(Boolean))]};}else if(old?.conflitos?.length){if(!old.conflitos.includes(n))old.conflitos.push(n);}else target[key]={valor:n,pagina:page,trecho:trecho.slice(0,500)};}
 const getItem=(id:string)=>{id=String(Number(id));let item=out.itens.find((x:any)=>x.id===id);if(!item){item={id,ncm:null,descricao:'',unidade:null,quantidade:empty(),campos:Object.fromEntries(CAMPOS_DI.map(k=>[k,empty()]))};out.itens.push(item);}return item;};
 let current:any=null,inDomestic=false;
 for(const page of paginas){
  const lines=norm(page.texto).split('\n').map((x:string)=>x.replace(/\s+/g,' ').trim());
  for(let i=0;i<lines.length;i++){
   const line=lines[i],next=lines[i+1]||'',both=line+' '+next;
   const header=line.match(/(?:EXTRATO[^\n]*[:/]\s*ITEM|ADICAO\s*\/\s*ITEM|ADICAO|ITEM)\s*[:.]?\s*(\d{1,5})(?:\b|\s*-)/);
   if(header){current=getItem(header[1]);inDomestic=false;}
   if(/VALORES.*MOEDA NACIONAL|VALORES EM REAIS|TOTAL IMPOSTOS/.test(line)){inDomestic=true;current=null;}
   if(/VALORES EM MOEDA FOB|VALORES EM MOEDA ESTRANGEIRA/.test(line)){inDomestic=false;}
   const ncm=both.match(/\bNCM\s*[:.]?\s*(\d{4}[. ]?\d{2}[. ]?\d{2}|\d{8})/);if(current&&ncm)current.ncm=ncm[1].replace(/\D/g,'');
   if(current&&/CODIGO DO PRODUTO|DESCRICAO DA MERCADORIA|DETALHAMENTO DO PRODUTO/.test(line)&&!current.descricao)current.descricao=next.slice(0,500);
   if(current&&/QUANTIDADE NA UNIDADE COMERCIALIZADA|QUANTIDADE COMERCIAL|QUANTIDADE NA UNIDADE COMERCIAL/.test(line)){
    const after=line.split(/QUANTIDADE[^:]*:/)[1]?.trim();let val=after?.match(/^([\d.,]+)$/)?.[1];
    if(!val){const numbers=[...next.matchAll(/(?:^|\s)(\d[\d.,]*)(?=\s|$)/g)];val=numbers.at(-1)?.[1];}
    if(val)set(current,'quantidade',val,page.pagina,both,6);
   }
   if(current&&/UNIDADE COMERCIAL(?:IZADA)?\s*:/.test(line)&&!line.includes('QUANTIDADE'))current.unidade=line.split(':').at(-1)?.trim()||next.split(' ')[0];
   for(const k of CAMPOS_DI){
    const re=fields[k];const match=line.match(re)||(/R\$\s*$/.test(line)?both.match(re):null);if(!match)continue;
    // Only a labelled R$ amount qualifies. Foreign amounts, percentages and "outros tributos" do not.
    if(current)set(current.campos,k,match[1],page.pagina,line);else if(inDomestic||['ICMS','II','IPI','PIS','COFINS','IBS','CBS'].includes(k))set(out.totais,k,match[1],page.pagina,line);
   }
  }
 }
 if(out.itens.length===1){const item=out.itens[0];for(const k of CAMPOS_DI){const t=out.totais[k],v=item.campos[k];if(t.valor!==null){if(v.valor===null&&!v.conflitos)item.campos[k]={...t};else if(v.valor!==null&&Number(v.valor)!==Number(t.valor))item.campos[k]={valor:null,pagina:v.pagina,trecho:v.trecho+' | Total: '+t.trecho,conflitos:[v.valor,t.valor]};}}}
 if(!out.itens.length)out.avisos.push('Itens/adições não identificados neste leiaute. A revisão precisa indicar os itens com suas páginas de origem.');
 for(const item of out.itens){if(item.quantidade.valor===null)out.avisos.push('Item '+item.id+': quantidade comercial não identificada.');for(const k of CAMPOS_DI){if(item.campos[k].conflitos?.length)out.avisos.push('Item '+item.id+': valores conflitantes para '+k+'.');}}
 return out;
}

