const fs=require('fs'),http=require('http'),path=require('path'),assert=require('assert/strict');
const{chromium}=require('/Users/marciomachado/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fixture={pedido:{id:1,referencia:'PO TESTE',fornecedor:'Fornecedor teste',moeda:'BRL'},embarques:[]};
const html=`<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="style.css"><link rel="stylesheet" href="importacoes-internacionais.css"><div id="cadastrosRoot"></div><script type="module">import{initEstruturaImportacao}from'./importacoes-estrutura.js';window.fixture=${JSON.stringify(fixture)};window.calls=[];const api=async d=>{calls.push(d);if(d.acao==='v2_opcoes')return{editar:true,fornecedores:[{id:7,nome:fixture.pedido.fornecedor}]};if(d.acao==='custo_fluxo_listar')return{total:1,linhas:[{...fixture.pedido,pago:37054.56,embarques:1}]};if(d.acao==='custo_fluxo_detalhe')return fixture;if(d.acao==='custo_opcoes')return{editar:true};if(d.acao==='custo_detalhe'){const x=fixture.embarques[0];return{embarque:x.embarque,custo:x.custo,financeiro:x.financeiro,sugestao_pagamentos:{pagamentos:[],avisos:[]},transporte:null};}if(d.acao==='custo_cadastro_buscar')return{linhas:[]};if(d.acao==='custo_cadastro_criar')return{id:900};if(d.acao==='v2_detalhe')return {...fixture.pedido,fornecedor_pais:window.country,fornecedor_id:7,status:'Recebido',itens:[],parcelas:[]};if(d.acao==='lib_contexto')return{liberacoes:[]};if(d.acao==='plano_sugerir')return{contexto:{condicao:''}};if(d.acao==='v2_listar')return{total:1,linhas:[{...fixture.pedido,total:100,parcelado:0,pago:0,status:'Recebido'}]};throw Error('Ação inesperada '+d.acao);};window.country=new URLSearchParams(location.search).get('pais')||'BR';const tela=initEstruturaImportacao(api,{canLeave:()=>true,show:async()=>{},reset(){}});tela.setNavigate((...args)=>window.navegacao=args);await tela.show(true,{area:'compras'});</script>`;
const server=http.createServer((req,res)=>{const p=new URL(req.url,'http://x').pathname;res.setHeader('content-type',p.endsWith('.css')?'text/css':p==='/'?'text/html':'text/javascript');if(p==='/favicon.ico'){res.statusCode=204;return res.end();}if(p==='/importacoes-fechamento.js')return res.end('export const initFechamentoDespachante=()=>({canLeave:()=>true,reset(){},open:async()=>{}});');if(p==='/importacoes-di.js')return res.end('export const initLeituraDI=()=>({canLeave:()=>true,reset(){},open:async()=>{}});');try{res.end(p==='/'?html:fs.readFileSync(path.join(__dirname,'../portal',p)));}catch{res.statusCode=404;res.end('');}});
(async()=>{
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const browser=await chromium.launch({executablePath:'/Users/marciomachado/Library/Caches/ms-playwright/chromium-1248/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  const url='http://127.0.0.1:'+server.address().port;
  await page.goto(url);
  await page.getByRole('button',{name:'Mais ações do pedido PO TESTE'}).click();
  const menu=page.getByRole('menu');
  await menu.getByRole('menuitem',{name:/Notas fiscais de entrada/}).waitFor();
  assert.equal(await page.locator('.purchase-order-header').count(),0);
  assert.equal(await menu.getByRole('menuitem',{name:/processo de importação/}).count(),0);
  const paths=await menu.locator('button svg').evaluateAll(icons=>icons.map(svg=>svg.innerHTML));
  assert.equal(new Set(paths).size,paths.length);
  await page.keyboard.press('Escape');
  await page.getByRole('button',{name:'Visualizar pedido PO TESTE'}).click();
  await page.locator('.purchase-order-header').waitFor();
  assert.equal(await page.getByRole('button',{name:/Notas fiscais de entrada|Exportar pedido|ACK do fornecedor/}).count(),0);
  await page.goto(url+'/?pais=DE');
  await page.getByRole('button',{name:'Mais ações do pedido PO TESTE'}).click();
  await menu.getByRole('menuitem',{name:'Abrir processo de importação'}).waitFor();
  assert.equal(await menu.getByRole('menuitem',{name:/Notas fiscais de entrada/}).count(),0);
  await menu.getByRole('menuitem',{name:'Editar pedido'}).click();
  await page.locator('.purchase-order-header').waitFor();
  assert.equal(await page.getByRole('button',{name:'Salvar pedido'}).count(),1);
  assert.deepEqual(errors,[]);
  console.log('Pedido de compra: menu na lista, símbolos distintos, detalhe para visualizar ou editar.');
 }finally{await browser.close();server.close();}
})().catch(e=>{console.error(e);server.close();process.exitCode=1;});
