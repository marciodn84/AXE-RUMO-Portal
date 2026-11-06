const {chromium}=require('/Users/marciomachado/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright'),http=require('http'),fs=require('fs'),path=require('path'),assert=require('assert/strict');
const fixture={pedido:{id:'p',referencia:'PO002223',moeda:'USD',itens:[{id:'i',linha:'10',descricao:'Produto',quantidade:2,reservada:0,valor_unitario:38.25}]},creditos:[],extraido:{invoice:{numero:'5610527600',data:'2026-09-30',moeda:'USD',valor:'76.50',pedidos:['PO002223'],condicao:'Cash in Advance'},packing:{pedidos:['PO002223'],peso_bruto_kg:1.36},itens:[{pedido_item_id:'i',linha:'10',codigo_fornecedor:'Z610399470001',quantidade:2,valor_unitario:38.25,peso_bruto:1.36}],avisos:['Linha 10: código do packing 2610399470001 difere da invoice Z610399470001. Confira o original antes de importar.']}};
const lote=process.argv.includes('--lote');
if(lote){
 const extra=fixture.extraido;
 fixture.extraido={packing:extra.packing,avisos:[],invoices:['INV-1','INV-2'].map(numero=>({
  arquivo:numero+'.pdf',invoice:{...extra.invoice,numero,valor:'38.25'},
  itens:[{...extra.itens[0],quantidade:1}]
 }))};
}
const html=`<section id="root"></section><script type="module">import{initLiberacaoDocumental}from'/importacoes-liberacao.js';window.saves=0;const f=${JSON.stringify(fixture)};window.c=initLiberacaoDocumental(async d=>{if(['lib_ler','lib_lote_ler'].includes(d.acao))return f;if(['lib_aprovar','lib_lote_aprovar'].includes(d.acao)){saves++;window.payload=d;}return{}},document.querySelector('#root'),()=>{});await c.show(f.pedido);window.ready=true;</script>`;
(async()=>{const server=http.createServer((req,res)=>{const p=req.url.split('?')[0];res.setHeader('Content-Type',p==='/'?'text/html':'text/javascript');if(p==='/')return res.end(html);if(p==='/importacoes-di-leitura.js')return res.end('export async function lerPDFImportacao(){return [{pagina:1,texto:"test"}]}');try{res.end(fs.readFileSync(path.join(__dirname,'../portal',p)))}catch{res.statusCode=404;res.end()}});await new Promise(r=>server.listen(0,'127.0.0.1',r));const b=await chromium.launch({headless:true,executablePath:'/Users/marciomachado/Library/Caches/ms-playwright/chromium-1248/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'});try{const p=await b.newPage();await p.goto('http://127.0.0.1:'+server.address().port);await p.waitForFunction(()=>window.ready);for(const label of ['Invoices do embarque','Packing list do embarque'])await p.getByLabel(label,{exact:true}).setInputFiles({name:'test.pdf',mimeType:'application/pdf',buffer:Buffer.from('%PDF-test')});if(lote)await p.getByLabel('Invoices do embarque',{exact:true}).setInputFiles(['INV-1','INV-2'].map(name=>({name:name+'.pdf',mimeType:'application/pdf',buffer:Buffer.from('%PDF-'+name)})));await p.getByRole('button',{name:'Ler invoice e packing list',exact:true}).click();
if(lote){
 const qty=p.getByLabel('Quantidade nesta invoice',{exact:true}).first();
 const submit=p.getByRole('button',{name:'Importar documentos e criar embarque',exact:true});
 await qty.waitFor();
 await qty.fill('2');
 await p.getByLabel('Valor FOB da invoice',{exact:true}).first().fill('76.50');
 await p.getByLabel('Justificativa para correções ou divergências',{exact:true}).fill('Conferência da quantidade');
 await p.getByLabel('Conferi as invoices, a packing list e as quantidades por item',{exact:true}).check();
 await submit.click();
 assert.equal(await p.evaluate(()=>saves),0);
 assert(await p.getByText('A soma das invoices ultrapassa o saldo desta linha.').first().isVisible());
 await qty.fill('1');
 await p.getByLabel('Valor FOB da invoice',{exact:true}).first().fill('38.25');
 await submit.click();
 await p.waitForFunction(()=>saves===1);
 const payload=await p.evaluate(()=>window.payload);
 assert.equal(payload.acao,'lib_lote_aprovar');
 assert.equal(payload.arquivos.length,3);
 assert.deepEqual(payload.dados.invoices.map(i=>[i.invoice,i.itens[0].pedido_item_id,i.itens[0].quantidade]),[['INV-1','i','1'],['INV-2','i','1']]);
 console.log('PASS: duas invoices na mesma linha do pedido e bloqueio de saldo excedido');
 return;
}
const reason=p.getByLabel('Justificativa para correções ou divergências',{exact:true});await reason.waitFor({state:'visible'});assert(await reason.getAttribute('required')!==null);assert.equal(await p.evaluate(()=>saves),0);assert(await p.getByText('Embarque: Total — cobre todo o saldo disponível para embarcar do pedido.',{exact:true}).isVisible());await p.getByLabel('Quantidade neste embarque',{exact:true}).fill('1');assert(await p.getByText('Embarque: Parcial — ainda restarão itens ou quantidades para embarcar.',{exact:true}).isVisible());console.log('PASS: motivo de conflito visível e obrigatório; leitura não salva nem cria embarque');}finally{await b.close();server.close()}})().catch(e=>{console.error(e);process.exit(1)});
