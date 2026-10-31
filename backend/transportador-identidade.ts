const norm=(s:string)=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/\s+/g,' ').trim().toUpperCase();
export function identificarTransportador(text:string){
 const labeled=[...text.matchAll(/^(?:TRANSPORTADORA|TRANSPORTADOR|CARRIER|ISSUING CARRIER|AIRLINE)\s*:\s*([^\r\n]{2,100})$/gim)].map(m=>({nome:m[1].trim(),trecho:m[0].trim()}));
 const labels=[...new Map(labeled.map(x=>[norm(x.nome),x])).values()];
 const tax=[...new Set([...text.matchAll(/(?:CNPJ\s+(?:DA\s+TRANSPORTADORA|DO\s+TRANSPORTADOR)|CARRIER\s+TAX\s+ID)\s*[:#]\s*(\d{2}\.?\d{3}\.?\d{3}\/?\d{4}-?\d{2})/gi)].map(m=>m[1].replace(/\D/g,'')))];
 const brands=[['DHL',/\bDHL\b|MYDHL\+/i],['FEDEX',/\bFEDEX\b/i],['UPS',/\bUPS\b/i]].filter(([,re])=>(re as RegExp).test(text)).map(([name])=>name as string);
 const conflito=labels.length>1||tax.length>1||(!labels.length&&brands.length>1);
 return{nome:conflito?null:labels.length===1?labels[0].nome:brands.length===1?brands[0]:null,documento:tax.length===1?tax[0]:null,conflito,criterio:labels.length?'Nome identificado no campo da transportadora':'Marca única identificada no documento',trecho:labels.length===1?labels[0].trecho:brands.join(', ')};
}
