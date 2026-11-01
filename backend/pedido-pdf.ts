import {getDocumentProxy} from 'npm:unpdf@1.9.1';
import {extrairPaginasPDF} from './di-documento.ts';
const clean=(s:string)=>s.replace(/\s+/g,' ').trim();
function num(s:string){const n=s.replace(/(?:US\$|R\$|USD|EUR|€)/g,'').trim();if(!/^(?:\d{1,3}(?:\.\d{3})+|\d+),\d{1,6}$/.test(n)&&!/^\d+$/.test(n))return null;return n.replace(/\./g,'').replace(',','.');}
export async function lerPedidoPDF(bytes:Uint8Array,ocr:any[]){
 const paginas=await extrairPaginasPDF(bytes,ocr),text=paginas.map(p=>p.texto).join('\n');
 if(!/PURCHASE\s+ORDER|PEDIDO\s+DE\s+COMPRA|ORDEM\s+DE\s+COMPRA/i.test(text))throw Error('Selecione o PDF do pedido de compra emitido no Nomus.');
 const refs=[...text.matchAll(/(?:PURCHASE\s+ORDER|PEDIDO\s+DE\s+COMPRA|ORDEM\s+DE\s+COMPRA)\s*[:#-]?\s*(PO\s*\d+|\d+)/gi)].map(m=>m[1].replace(/\s/g,''));
 const out:any={referencia:new Set(refs).size===1?refs[0]:null,data_pedido:null,fornecedor:null,moeda:null,itens:[],avisos:[],condicoes_comerciais:[...new Set([...text.matchAll(/(?:^|\n)\s*-\s*(Payment|Freight|Transportation company|Pagamento|Frete|Transportadora)\s*:\s*([^\n]+)/gi)].map(m=>clean(m[1]+': '+m[2])))],total_documento:null,total_pedido_documento:null,tributos_documento:{}};
 const currencies=[...new Set([...text.matchAll(/US\$|\bUSD\b|R\$|\bEUR\b|€/g)].map(m=>m[0]==='US$'?'USD':m[0]==='R$'?'BRL':m[0]==='€'?'EUR':m[0]))];if(currencies.length===1)out.moeda=currencies[0];
 const pdf=await getDocumentProxy(bytes.slice(),{isEvalSupported:false,maxImageSize:16777216});
 try{
  for(let pg=1;pg<=pdf.numPages;pg++){
   const page=await pdf.getPage(pg),tc=await page.getTextContent();const ts=tc.items.filter((t:any)=>typeof t.str==='string'&&t.str.trim()).map((t:any)=>({s:(()=>{const s=clean(t.str),w=s.split(' ');return w.length>2&&w.every(c=>c.length===1)?w.join(''):s;})(),x:t.transform[4],y:t.transform[5],w:t.width}));
   const hdr=(label:string)=>ts.find((t:any)=>new RegExp('^(?:'+label+')$','i').test(t.s));
   const itemH=hdr('Item'),productH=hdr('Product|Produto'),unitH=hdr('Unit|Unidade'),qtyH=hdr('Quantity|Quantidade|Qtde\\.?|Qtd\\.?'),priceH=hdr('Price un\\.|Preço un\\.'),subtotalH=ts.find((t:any)=>/^SubTotal/i.test(t.s)),deliveryH=hdr('Delivery|Entrega|Prazo de entrega');
   if(pg===1){
    const title=ts.find((t:any)=>/PURCHASE ORDER|PEDIDO DE COMPRA/i.test(t.s));
    const dates=ts.filter((t:any)=>/^\d{2}\/\d{2}\/\d{4}$/.test(t.s)&&title&&t.y>title.y-50&&t.y<title.y+10);
    if(dates.length===1){const [dd,mm,yy]=dates[0].s.split('/');const iso=yy+'-'+mm+'-'+dd;if(!isNaN(Date.parse(iso))&&new Date(iso+'T12:00:00Z').toISOString().slice(0,10)===iso)out.data_pedido=iso;}
    const supplier=ts.find((t:any)=>/^Supplier data|Dados do fornecedor/i.test(t.s));if(supplier){const names=ts.filter((t:any)=>t.x<supplier.x+200&&t.y<supplier.y-4&&t.y>supplier.y-28&&!/CNPJ|CPF|Address|Telefone/i.test(t.s)).sort((a:any,b:any)=>b.y-a.y);if(names.length)out.fornecedor=names[0].s;}
    const total=ts.find((t:any)=>/^(?:Product|Produto|Produtos):/i.test(t.s));if(total){const vals=ts.filter((t:any)=>Math.abs(t.y-total.y)<2&&t.x>total.x&&t.x<total.x+120).map((t:any)=>num(t.s)).filter(Boolean);if(vals.length===1)out.total_documento=vals[0];}
    const headerAmount=(label:RegExp)=>{const h=ts.find((t:any)=>label.test(t.s)&&(!itemH||t.y>itemH.y+20));if(!h)return null;const values=ts.filter((t:any)=>Math.abs(t.y-h.y)<2&&t.x>h.x+h.w&&t.x<h.x+100).map((t:any)=>num(t.s)).filter((v:any)=>v!==null);return values.length===1?values[0]:null;};
    out.total_pedido_documento=headerAmount(/^Total:$/i);for(const name of ['ICMS','ICMS ST','IPI','PIS','COFINS','IBPT']){const value=headerAmount(new RegExp('^'+name+':$','i'));if(value!==null)out.tributos_documento[name]=value;}
   }
   if(!itemH||!productH||!unitH||!qtyH||!priceH||!subtotalH){out.avisos.push('Página '+pg+': colunas dos itens não reconhecidas'+(paginas[pg-1].metodo==='OCR'?' no PDF digitalizado':' neste leiaute')+'. Confira se há itens para cadastrar manualmente.');continue;}
   const descX=productH.x+productH.w+3,unitX=unitH.x-10,qtyX=qtyH.x-10,priceX=priceH.x-10,subX=subtotalH.x-10,deliveryX=deliveryH?deliveryH.x-10:Infinity;
   const anchors=ts.filter((t:any)=>/^\d{3,5}$/.test(t.s)&&Math.abs(t.x-itemH.x)<22&&t.y<itemH.y-8).sort((a:any,b:any)=>b.y-a.y);
   for(let n=0;n<anchors.length;n++){
    const a=anchors[n],upper=n===0?itemH.y-8:(anchors[n-1].y+a.y)/2,lower=n===anchors.length-1?a.y-14:(a.y+anchors[n+1].y)/2;
    const row=ts.filter((t:any)=>t.y<upper&&t.y>lower);
    const col=(lo:number,hi:number)=>row.filter((t:any)=>t.x>=lo&&t.x<hi).sort((a:any,b:any)=>b.y-a.y||a.x-b.x).map((t:any)=>t.s).join(' ');
    const descParts=row.filter((t:any)=>t.x>=descX&&t.x<unitX).sort((a:any,b:any)=>b.y-a.y||a.x-b.x);
    const kept=descParts.filter((t:any,i:number)=>!descParts.some((u:any,j:number)=>j!==i&&Math.abs(t.x-u.x)<3&&Math.abs(t.y-u.y)<10&&u.s.length>t.s.length&&u.s.startsWith(t.s)));
    const descricao=clean(kept.map((t:any)=>t.s).join(' '));
    const quantidade=num(col(qtyX,priceX)),unitario=num(col(priceX,subX)),subtotal=num(col(subX,deliveryX));
    const codigo=clean(col(itemH.x+22,descX)).replace(/\s+/g,''),unidade=clean(col(unitX,qtyX)),entrega=clean(col(deliveryX,Infinity));
    if(!descricao||!codigo||!unidade||quantidade===null||unitario===null||Number(quantidade)<=0){out.avisos.push('Página '+pg+', linha '+a.s+': campos incompletos; confira e complete no formulário.');}
    out.itens.push({linha:a.s,codigo_axe:codigo,codigo_fornecedor:descricao.match(/NYK\s*:\s*([A-Za-z0-9-]+)/i)?.[1]||'',descricao,unidade,quantidade,valor_unitario:unitario,subtotal_documento:subtotal,entrega_documento:/^\d{2}\/\d{2}\/\d{4}$/.test(entrega)?entrega:null,pagina:pg});
    if(subtotal!==null&&quantidade!==null&&unitario!==null&&Math.abs(Number(quantidade)*Number(unitario)-Number(subtotal))>0.0000001)out.avisos.push('Linha '+a.s+': quantidade × preço difere do subtotal do PDF. Revise o preço unitário.');
   }page.cleanup();
  }
 }finally{await pdf.loadingTask.destroy();}
 if(out.itens.length>100)throw Error('O pedido possui mais de 100 itens. Divida o cadastro antes de continuar.');
 if(new Set(out.itens.map((x:any)=>x.linha)).size!==out.itens.length)out.avisos.push('Há números de linha repetidos no PDF. Corrija antes de salvar.');
 if(out.total_documento&&out.itens.length&&out.itens.every((x:any)=>x.subtotal_documento!==null)){const total=out.itens.reduce((s:number,x:any)=>s+Number(x.subtotal_documento),0);if(Math.abs(total-Number(out.total_documento))>0.01)out.avisos.push('A soma dos itens difere do total dos produtos no PDF. Confira todas as páginas e os valores antes de aplicar.');}
 if(!out.itens.length)out.avisos.push('Itens não reconhecidos neste leiaute. Use o cadastro manual.');
 if(!out.moeda)out.avisos.push('Moeda não identificada com segurança. Selecione a moeda do pedido.');
 if(!out.data_pedido)out.avisos.push('Data do pedido não identificada com segurança.');
 return out;
}

