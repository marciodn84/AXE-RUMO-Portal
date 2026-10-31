import {classificarEmbarque} from './embarques-abrangencia.js';
import {createClient} from 'npm:@supabase/supabase-js@2.99.2';
import {extrairPaginasPDF} from './di-documento.ts';
import {parseTransporte,combinarTransporte} from './transporte-parser.ts';
import {parseSwift} from './swift-parser.ts';
import {parseInvoice,parsePacking,parsePesos,combinarLiberacao} from './embarque-documentos-parser.ts';
import {sugerirParcelas} from './parcelas-parser.ts';
import {parseCambio} from './cambio-parser.ts';
import {parseACK,revisarACK} from './ack-parser.ts';
const bucket='axe-importacoes-acks';
const origins=['https://erp.axeengenharia.com','https://axe-rumo-portal.marciodnmachado.workers.dev','https://marciodn84.github.io'];
const hash=async(bytes:Uint8Array)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(x=>x.toString(16).padStart(2,'0')).join('');
export async function handleEntrada(req:Request){
 const origin=req.headers.get('origin')||'',headers:Record<string,string>={'content-type':'application/json','cache-control':'no-store','vary':'Origin','access-control-allow-headers':'authorization,apikey,content-type','access-control-allow-methods':'POST,OPTIONS'};
 if(origins.includes(origin))headers['access-control-allow-origin']=origin;
 const reply=(v:unknown,status=200)=>new Response(JSON.stringify(v),{status,headers});
 if(req.method==='OPTIONS')return reply({});if(req.method!=='POST')return reply({erro:'Método não permitido'},405);
 try{
  const authorization=req.headers.get('authorization')||'';if(!authorization.startsWith('Bearer '))return reply({erro:'Faça login novamente'},401);
  const base=Deno.env.get('SUPABASE_URL')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!,service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const auth=await fetch(base+'/auth/v1/user',{headers:{authorization,apikey:anon},signal:AbortSignal.timeout(15000)});if(!auth.ok)return reply({erro:'Sessão inválida'},401);const user=await auth.json();if(typeof user.id!=='string')return reply({erro:'Sessão inválida'},401);
  const reader=req.body?.getReader();if(!reader)throw Error('Dados obrigatórios');const chunks:Uint8Array[]=[];let length=0;
  for(;;){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>12000000){await reader.cancel();return reply({erro:'Arquivo acima do limite'},413);}chunks.push(value);}
  const all=new Uint8Array(length);let at=0;for(const c of chunks){all.set(c,at);at+=c.length;}const d=JSON.parse(new TextDecoder().decode(all));if(!d||typeof d!=='object'||Array.isArray(d))throw Error('Dados inválidos');
  const sb=createClient(base,service,{auth:{persistSession:false,autoRefreshToken:false}});
  async function rpc(data:any){const r=await sb.rpc('axe_documentos_entrada',{p_dados:data,p_usuario:user.id});if(r.error)throw Error(r.error.code==='P0001'?r.error.message.slice(0,240):'Revise os dados e vínculos do documento.');return r.data;}
  async function download(f:any,bucketName:string){
   if(f.conteudo_base64){
    const bytes=Uint8Array.from(atob(f.conteudo_base64),c=>c.charCodeAt(0));if(await hash(bytes)!==f.sha256)throw Error('Integridade do anexo não confirmada');
    const info=await sb.storage.getBucket(bucketName);if(info.error){const made=await sb.storage.createBucket(bucketName,{public:false,fileSizeLimit:8388608});if(made.error){const check=await sb.storage.getBucket(bucketName);if(check.error||check.data.public)throw Error('Armazenamento privado indisponível');}}else if(info.data.public)throw Error('Armazenamento deve ser privado');
    const up=await sb.storage.from(bucketName).upload(f.caminho,bytes,{upsert:false,contentType:f.tipo_mime||'application/pdf'});if(up.error){const old=await sb.storage.from(bucketName).download(f.caminho);if(old.error||await hash(new Uint8Array(await old.data.arrayBuffer()))!==f.sha256)throw Error('Não foi possível confirmar o anexo para download');}
   }
   const r=await sb.storage.from(bucketName).createSignedUrl(f.caminho,60,{download:f.nome});if(r.error)throw Error('Não foi possível abrir o anexo');return reply({url:r.data.signedUrl});
  }
  async function guardarPrivado(bucketName:string,path:string,bytes:Uint8Array){
   const info=await sb.storage.getBucket(bucketName);if(info.error){const made=await sb.storage.createBucket(bucketName,{public:false,fileSizeLimit:8388608,allowedMimeTypes:['application/pdf']});if(made.error){const check=await sb.storage.getBucket(bucketName);if(check.error||check.data.public)throw Error('Armazenamento privado indisponível');}}else if(info.data.public)throw Error('Armazenamento deve ser privado');
   const up=await sb.storage.from(bucketName).upload(path,bytes,{upsert:false,contentType:'application/pdf'});if(up.error){const old=await sb.storage.from(bucketName).download(path);if(old.error||await hash(new Uint8Array(await old.data.arrayBuffer()))!==await hash(bytes))throw Error('Envio incompleto ou arquivo alterado. Repita o mesmo envio.');}
  }
  if(['transp_contexto','transp_ler','transp_salvar','transp_baixar'].includes(d.acao)){
   async function trpc(data:any){const r=await sb.rpc('axe_transporte_documental',{p_dados:data,p_usuario:user.id});if(r.error)throw Error(r.error.code==='P0001'?r.error.message:'Confira os documentos, a DUIMP e os valores do transporte.');return r.data;}
   const bucketName='axe-importacoes-transporte';if(d.acao==='transp_baixar')return await download(await trpc({acao:'transp_arquivo',id:d.id}),bucketName);
   const ctx=await trpc({acao:'transp_contexto',embarque_id:d.embarque_id});if(d.acao==='transp_contexto')return reply(ctx);if(!ctx.editar)throw Error('Sem permissão para anexar transporte');if(ctx.custo_final)throw Error('Reabra o custo final com justificativa antes de alterar o transporte');
   if(!Array.isArray(d.arquivos)||d.arquivos.length>3||new Set(d.arquivos.map((f:any)=>f.categoria)).size!==d.arquivos.length||(!d.arquivos.length&&!ctx.atual))throw Error('Selecione os documentos de transporte');
   const files:any[]=[],parsed:any[]=[];let total=0;
   for(const f of d.arquivos){if(!['RECIBO','ETIQUETA','AJUSTE'].includes(f.categoria)||typeof f.nome!=='string'||!f.nome.trim()||f.nome.length>250||typeof f.conteudo!=='string'||f.conteudo.length>11184812||!/^[A-Za-z0-9+/]+={0,2}$/.test(f.conteudo))throw Error('Arquivo PDF inválido');const bytes=Uint8Array.from(atob(f.conteudo),c=>c.charCodeAt(0));total+=bytes.length;if(total>8388608||new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-')throw Error('Até 8 MB no total dos PDFs');const paginas=await extrairPaginasPDF(bytes,f.paginas);files.push({...f,bytes,sha256:await hash(bytes)});parsed.push({...await parseTransporte(bytes,paginas,f.categoria),arquivo_nome:f.nome,sha256:files.at(-1).sha256});}
   const extraido=parsed.length?combinarTransporte(parsed,ctx.atual?.extraido):ctx.atual.extraido;
   if(d.acao==='transp_ler')return reply({...ctx,extraido});
   if(d.confirmado!==true)throw Error('Confirme os dados e os documentos antes de gravar');if(!/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(d.requisicao_id||''))throw Error('Identificador obrigatório');
   const reviewed=d.dados;if(!reviewed)throw Error('Confira os dados do transporte');
   const changed=String(reviewed.awb||'')!==String(extraido.dados.awb||'')||Number(reviewed.frete_usd)!==Number(extraido.dados.frete_usd)||['real','cubado','faturavel'].some(k=>extraido.dados['peso_'+k]?.kg==null||Math.abs(Number(reviewed['peso_'+k+'_kg'])-Number(extraido.dados['peso_'+k]?.kg))>0.00001);
   if(changed&&!String(reviewed.motivo||'').trim())throw Error('Justifique as correções dos campos reconhecidos no documento');
   const metadata=[];for(const f of files){const path='entrada/'+user.id+'/'+d.requisicao_id+'/'+f.categoria+'.pdf';await guardarPrivado(bucketName,path,f.bytes);metadata.push({categoria:f.categoria,nome:f.nome,sha256:f.sha256,tamanho:f.bytes.length,caminho:path});}
   return reply(await trpc({acao:'transp_salvar',embarque_id:d.embarque_id,versao_embarque:d.versao_embarque,base_revisao_id:d.base_revisao_id||null,requisicao_id:d.requisicao_id,confirmado:true,conferiu_duimp:d.conferiu_duimp===true,dados:reviewed,extraido,arquivos:metadata}));
  }
  if(['pagdoc_contexto','pagdoc_ler','pagdoc_aprovar'].includes(d.acao)){
   async function payRPC(data:any){const r=await sb.rpc(data.acao==='pagdoc_aprovar'?'axe_pagamento_processos':'axe_pagamento_documental',{p_dados:data,p_usuario:user.id});if(r.error)throw Error(r.error.code==='P0001'?r.error.message:'Confira o comprovante, os vínculos e os saldos.');return r.data;}
   const ctx=await payRPC({acao:'pagdoc_contexto',pedido_id:d.pedido_id});if(d.acao==='pagdoc_contexto')return reply(ctx);if(!ctx.editar)throw Error('Sem permissão para registrar pagamento');
   const contract=d.contrato_id?ctx.contratos.find((c:any)=>c.id===d.contrato_id):null;if(d.contrato_id&&!contract)throw Error('Selecione contrato do mesmo fornecedor e moeda');
   let uploadedBytes=0;
   async function readFile(f:any,storedId?:string){
    if(storedId){const meta=await payRPC({acao:'pagdoc_arquivo',id:storedId});if(!contract||meta.contrato_id!==contract.id)throw Error('Anexo pertence a outro contrato');let bytes:Uint8Array;if(meta.conteudo_base64){bytes=Uint8Array.from(atob(meta.conteudo_base64),c=>c.charCodeAt(0));}else{const r=await sb.storage.from('axe-cambio-arquivos').download(meta.caminho);if(r.error)throw Error('Não foi possível recuperar o arquivo salvo');bytes=new Uint8Array(await r.data.arrayBuffer());}if(bytes.length!==meta.tamanho||await hash(bytes)!==meta.sha256)throw Error('Integridade do anexo não confirmada');return {...meta,bytes,paginas:await extrairPaginasPDF(bytes,undefined)};}
    if(!f||typeof f.nome!=='string'||!f.nome.trim()||f.nome.length>250||typeof f.conteudo!=='string'||f.conteudo.length>11184812||!/^[A-Za-z0-9+/]+={0,2}$/.test(f.conteudo))throw Error('Selecione o PDF do documento');const bytes=Uint8Array.from(atob(f.conteudo),c=>c.charCodeAt(0));uploadedBytes+=bytes.length;if(uploadedBytes>8388608||new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-')throw Error('Até 8 MB no total dos PDFs');return {...f,bytes,sha256:await hash(bytes),tamanho:bytes.length,paginas:await extrairPaginasPDF(bytes,f.paginas)};
   }
   const contractFile=contract?null:await readFile(d.contrato_arquivo),contractParsed=contractFile?parseCambio(contractFile.paginas):null;
   const swiftFile=await readFile(d.swift_arquivo,d.swift_arquivo_id),swiftParsed=parseSwift(swiftFile.paginas);
   const previous=ctx.remessas.find((r:any)=>r.sha256===swiftFile.sha256||(swiftParsed.uetr&&r.uetr===swiftParsed.uetr)),used=Number(previous?.utilizado||0);
   if(d.acao==='pagdoc_ler'){const saldo=await sb.rpc('axe_imp_pagamento_saldo_processos',{arquivo_sha:swiftFile.sha256,p_usuario:user.id});if(saldo.error)throw Error('Não foi possível conferir o saldo por processo');return reply({...ctx,saldo_processos:saldo.data?.saldo??null,contrato:contract,contrato_extraido:contractParsed,swift:swiftParsed,comprovante_utilizado:used,comprovante_disponivel:swiftParsed.valor?Number(swiftParsed.valor)-used:null});}
   if(d.confirmado!==true||d.nao_duplicado!==true)throw Error('Confirme a conferência do pagamento e a ausência de duplicidade');
   if(!/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(d.requisicao_id||''))throw Error('Identificador obrigatório');
   const proof=d.swift_revisado;if(!proof||!/^\d+(?:\.\d{1,2})?$/.test(String(proof.valor||''))||Number(proof.valor)<=0||!/^\d{4}-\d{2}-\d{2}$/.test(proof.data||'')||new Date(proof.data+'T12:00:00Z').toISOString().slice(0,10)!==proof.data||!['USD','EUR','GBP','CAD','CNY','JPY','CHF','BRL'].includes(proof.moeda))throw Error('Confira valor, moeda e data do comprovante');
   const altered=['valor','moeda','data','uetr','referencia'].some(k=>String(proof[k]||'')!==String(swiftParsed[k]||''));if(altered&&!String(d.dados?.motivo||'').trim())throw Error('Justifique as correções dos dados lidos do SWIFT');
   let newContract=null;
   if(!contract){
    if(!/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(d.contrato_requisicao_id||''))throw Error('Identificador do novo contrato obrigatório');const reviewed=d.contrato_revisado;if(!reviewed)throw Error('Confira os dados do contrato');
    await guardarPrivado('axe-cambio-arquivos','entrada/'+user.id+'/'+d.contrato_requisicao_id+'.pdf',contractFile.bytes);
    newContract={requisicao_id:d.contrato_requisicao_id,nome:contractFile.nome,sha256:contractFile.sha256,tamanho:contractFile.tamanho,extraido:contractParsed,dados:{...reviewed,fornecedor_id:ctx.pedido.fornecedor_id,status:'Ativo',pedidos:d.dados?.processos?.length?[]:[{pedido_id:ctx.pedido.id,valor:d.dados.valor}]}};
   }
   const path='entrada/'+user.id+'/'+d.requisicao_id+'/SWIFT.pdf';if(!d.swift_arquivo_id)await guardarPrivado('axe-cambio-arquivos',path,swiftFile.bytes);
   return reply(await payRPC({acao:'pagdoc_aprovar',pedido_id:d.pedido_id,versao_pedido:d.versao_pedido,contrato_id:d.contrato_id||null,versao_contrato:d.versao_contrato,novo_contrato:newContract,swift_arquivo_id:d.swift_arquivo_id||null,arquivo:{nome:swiftFile.nome,sha256:swiftFile.sha256,tamanho:swiftFile.tamanho,caminho:d.swift_arquivo_id?swiftFile.caminho:path},swift:proof,extraido:{contrato:contractParsed,swift:swiftParsed},dados:d.dados,requisicao_id:d.requisicao_id,confirmado:true,nao_duplicado:true}));
  }
  if(['lib_contexto','lib_ler','lib_aprovar','lib_baixar'].includes(d.acao)){
   async function libRPC(data:any){const r=await sb.rpc('axe_liberacao_documental',{p_dados:data,p_usuario:user.id});if(r.error)throw Error(r.error.code==='P0001'?r.error.message:'Confira os documentos, os itens e os saldos da parcial.');return r.data;}
   const libBucket='axe-importacoes-parciais';
   if(d.acao==='lib_baixar')return await download(await libRPC({acao:'lib_arquivo',id:d.id}),libBucket);
   let ctx=await libRPC({acao:'lib_contexto',pedido_id:d.pedido_id});if(d.acao==='lib_contexto')return reply(ctx);if(!ctx.editar)throw Error('Sem permissão para preparar a parcial');
   if(!Array.isArray(d.arquivos)||d.arquivos.length<2||d.arquivos.length>3||new Set(d.arquivos.map((x:any)=>x.categoria)).size!==d.arquivos.length||!d.arquivos.some((x:any)=>x.categoria==='INVOICE')||!d.arquivos.some((x:any)=>x.categoria==='PACKING'))throw Error('Selecione a invoice e o packing list; pesos e dimensões são opcionais');
   const files:any[]=[];let totalBytes=0;
   for(const f of d.arquivos){
    if(!['INVOICE','PACKING','PESOS'].includes(f.categoria)||typeof f.nome!=='string'||!f.nome.trim()||f.nome.length>250||typeof f.conteudo!=='string'||f.conteudo.length>11184812||!/^[A-Za-z0-9+/]+={0,2}$/.test(f.conteudo))throw Error('Arquivo PDF inválido');
    const bytes=Uint8Array.from(atob(f.conteudo),c=>c.charCodeAt(0));totalBytes+=bytes.length;if(totalBytes>8388608||new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-')throw Error('Envie PDFs com até 8 MB no total');
    const paginas=await extrairPaginasPDF(bytes,f.paginas);files.push({...f,bytes,paginas,sha256:await hash(bytes)});
   }
   const inv=files.find(f=>f.categoria==='INVOICE'),pack=files.find(f=>f.categoria==='PACKING'),pesos=files.find(f=>f.categoria==='PESOS');
   if(!/pack(?:ing|ina)\s*list/i.test(pack.paginas.map((p:any)=>p.texto).join(' ')))throw Error('O documento selecionado como packing list não foi reconhecido');
   const invoiceData=parseInvoice(inv.paginas);if(invoiceData.pedidos.length!==1)throw Error('Cada invoice deve identificar um único PO. Confira o documento.');const routed=await sb.rpc('axe_imp_pedido_da_invoice',{p_referencia:invoiceData.pedidos[0],p_usuario:user.id});if(routed.error)throw Error(routed.error.code==='P0001'?routed.error.message:'Confira o PO da invoice');if(routed.data.id!==ctx.pedido.id){if(d.acao!=='lib_ler')throw Error('O PO identificado mudou. Releia os documentos.');ctx=await libRPC({acao:'lib_contexto',pedido_id:routed.data.id});}const parsed=combinarLiberacao(invoiceData,await parsePacking(pack.bytes,pack.paginas),pesos?parsePesos(pesos.paginas):null,ctx.pedido);
   if(files.some(f=>f.paginas.some((p:any)=>p.metodo==='OCR')))parsed.avisos.push('Há páginas com OCR. Confira todos os campos e os itens reconhecidos.');
   if(d.acao==='lib_ler')return reply({...ctx,extraido:parsed});
   if(d.confirmado!==true)throw Error('Confirme os documentos, a disponibilidade da mercadoria e os vínculos de parcelas');
   if(!/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(d.requisicao_id||''))throw Error('Identificador obrigatório');
   const v=d.dados;if(!v||!Array.isArray(v.itens))throw Error('Confira os itens da parcial');
   const edited=String(v.invoice||'')!==String(parsed.invoice.numero||'')||String(v.data_invoice||'')!==String(parsed.invoice.data||'')||String(v.moeda||'')!==String(parsed.invoice.moeda||'')||Number(v.valor)!==Number(parsed.invoice.valor)||v.itens.length!==parsed.itens.length||v.itens.some((x:any)=>{const o=parsed.itens.find((i:any)=>i.pedido_item_id&&i.pedido_item_id===x.pedido_item_id);return !o||Number(o.quantidade)!==Number(x.quantidade)||Number(o.valor_unitario)!==Number(x.valor_unitario);})||parsed.avisos.some((a:string)=>/difere|não confirmada|número do pedido/i.test(a));
   if(edited&&!String(v.motivo||'').trim())throw Error('Informe a justificativa das correções ou divergências documentais');
   v.abrangencia=classificarEmbarque(ctx.pedido.itens,v.itens);
   const metadata=[];for(const f of files){const path='entrada/'+user.id+'/'+d.requisicao_id+'/'+f.categoria+'.pdf';await guardarPrivado(libBucket,path,f.bytes);metadata.push({categoria:f.categoria,nome:f.nome,sha256:f.sha256,tamanho:f.bytes.length,caminho:path});}
   return reply(await libRPC({acao:'lib_aprovar',pedido_id:d.pedido_id,versao:d.versao,requisicao_id:d.requisicao_id,confirmado:true,conferiu_parcelas:d.conferiu_parcelas===true,dados:v,extraido:parsed,arquivos:metadata}));
  }
  if(['plano_contexto','plano_sugerir','plano_aprovar'].includes(d.acao)){
   async function planoRPC(data:any){const r=await sb.rpc('axe_parcelas_planejamento',{p_dados:data,p_usuario:user.id});if(r.error)throw Error(r.error.code==='P0001'?r.error.message:'Confira a programação de parcelas.');return r.data;}
   if(d.acao!=='plano_sugerir')return reply(await planoRPC(d));
   const r=await planoRPC({acao:'plano_contexto',pedido_id:d.pedido_id});if(!r.editar)throw Error('Sem permissão para preparar parcelas');
   if(!r.contexto.condicao)return reply({...r,plano:null});
   const sugestao=sugerirParcelas(r.contexto.condicao,Number(r.contexto.total),r.contexto.data_pedido),assinatura=await hash(new TextEncoder().encode(JSON.stringify({contexto:r.contexto,sugestao,versao:'parcelas_v1'})));
   const plano=await planoRPC({acao:'plano_preparar',pedido_id:d.pedido_id,contexto:r.contexto,sugestao,assinatura});return reply({...r,plano});
  }
  if(['fxdoc_ler','fxdoc_criar'].includes(d.acao)){
   const permission=await sb.rpc('axe_imp_financeiro',{p_dados:{acao:'fx_opcoes'},p_usuario:user.id});if(permission.error||!permission.data?.editar)throw Error('Sem permissão para cadastrar contrato');
   if(typeof d.conteudo!=='string'||d.conteudo.length>11184812||!/^[A-Za-z0-9+/]+={0,2}$/.test(d.conteudo))throw Error('Selecione PDF de até 8 MB');
   const bytes=Uint8Array.from(atob(d.conteudo),c=>c.charCodeAt(0));if(bytes.length>8388608||new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-')throw Error('PDF inválido ou acima de 8 MB');
   const paginas=await extrairPaginasPDF(bytes,d.paginas),extraido=parseCambio(paginas);
   if(d.acao==='fxdoc_ler')return reply(extraido);
   if(d.confirmado!==true)throw Error('Confirme a conferência dos dados e do arquivo');
   if(!/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(d.requisicao_id||'')||typeof d.nome!=='string'||!d.nome.trim()||d.nome.length>250)throw Error('Identificação do documento inválida');
   const sha256=await hash(bytes),fxBucket='axe-cambio-arquivos',path='entrada/'+user.id+'/'+d.requisicao_id+'.pdf';
   const info=await sb.storage.getBucket(fxBucket);if(info.error){const made=await sb.storage.createBucket(fxBucket,{public:false,fileSizeLimit:8388608,allowedMimeTypes:['application/pdf']});if(made.error){const check=await sb.storage.getBucket(fxBucket);if(check.error||check.data.public)throw Error('Armazenamento privado indisponível');}}else if(info.data.public)throw Error('Armazenamento deve ser privado');
   const up=await sb.storage.from(fxBucket).upload(path,bytes,{upsert:false,contentType:'application/pdf'});if(up.error){const old=await sb.storage.from(fxBucket).download(path);if(old.error||await hash(new Uint8Array(await old.data.arrayBuffer()))!==sha256)throw Error('Envio incompleto ou alterado. Repita o mesmo arquivo.');}
   const result=await sb.rpc('axe_cambio_criar_com_arquivo',{p_dados:{requisicao_id:d.requisicao_id,nome:d.nome,sha256,tamanho:bytes.length,extraido,dados:d.dados},p_usuario:user.id});if(result.error)throw Error(result.error.code==='P0001'?result.error.message:'Confira os dados e os vínculos antes de salvar.');return reply(result.data);
  }
  if(['fxdoc_upload','fxdoc_listar','fxdoc_baixar'].includes(d.acao)){
   async function fxrpc(data:any){const r=await sb.rpc('axe_cambio_arquivos',{p_dados:data,p_usuario:user.id});if(r.error)throw Error(r.error.code==='P0001'?r.error.message:'Revise o contrato e os dados do anexo.');return r.data;}
   const fxBucket='axe-cambio-arquivos';
   if(d.acao==='fxdoc_listar')return reply(await fxrpc({acao:d.acao,contrato_id:d.contrato_id}));
   if(d.acao==='fxdoc_baixar')return await download(await fxrpc({acao:'fxdoc_arquivo',id:d.id}),fxBucket);
   if(d.confirmado!==true)throw Error('Confirme o contrato e o tipo de documento antes de anexar');
   if(typeof d.conteudo!=='string'||d.conteudo.length>11184812||!/^[A-Za-z0-9+/]+={0,2}$/.test(d.conteudo))throw Error('Selecione PDF de até 8 MB');
   const bytes=Uint8Array.from(atob(d.conteudo),c=>c.charCodeAt(0));
   if(bytes.length>8388608||new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-')throw Error('PDF inválido ou acima de 8 MB');
   if(!['CONTRATO','SWIFT'].includes(d.categoria)||typeof d.nome!=='string'||!d.nome.trim()||d.nome.length>250)throw Error('Informe o tipo e o nome do documento');
   const sha256=await hash(bytes),f=await fxrpc({acao:'fxdoc_reservar',contrato_id:d.contrato_id,categoria:d.categoria,nome:d.nome,sha256,tamanho:bytes.length,requisicao_id:d.requisicao_id});
   if(!f.pronto){
    const info=await sb.storage.getBucket(fxBucket);if(info.error){const made=await sb.storage.createBucket(fxBucket,{public:false,fileSizeLimit:8388608,allowedMimeTypes:['application/pdf']});if(made.error){const check=await sb.storage.getBucket(fxBucket);if(check.error||check.data.public)throw Error('Armazenamento privado indisponível');}}else if(info.data.public)throw Error('Armazenamento deve ser privado');
    const up=await sb.storage.from(fxBucket).upload(f.caminho,bytes,{upsert:false,contentType:'application/pdf'});
    if(up.error){const old=await sb.storage.from(fxBucket).download(f.caminho);if(old.error||await hash(new Uint8Array(await old.data.arrayBuffer()))!==sha256)throw Error('Envio incompleto. Repita o mesmo arquivo.');}
    await fxrpc({acao:'fxdoc_confirmar',id:f.id});
   }
   let automatico:any=null;
   if(d.categoria==='SWIFT'){
    const swift=parseSwift(await extrairPaginasPDF(bytes,d.paginas));
    const processed=await sb.rpc('axe_imp_swift_arquivo_processar',{p_dados:{arquivo_id:f.id,swift},p_usuario:user.id});
    if(processed.error)throw Error(processed.error.code==='P0001'?processed.error.message:'Não foi possível conferir o SWIFT com a invoice');
    automatico=processed.data;
   }
   return reply({id:f.id,...(automatico?{pagamento_automatico:automatico}:{})});
  }
  if(d.acao==='ack_ler'||d.acao==='ack_upload'||d.acao==='ack_pre_cadastrar'){
   await rpc({acao:'ack_autorizar'});if(typeof d.conteudo!=='string'||!d.conteudo.length||d.conteudo.length>11184812||!/^[A-Za-z0-9+/]*={0,2}$/.test(d.conteudo))throw Error('Selecione PDF de até 8 MB');
   const bytes=Uint8Array.from(atob(d.conteudo),c=>c.charCodeAt(0));if(bytes.length>8388608||new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-')throw Error('PDF inválido ou acima de 8 MB');
   const paginas=await extrairPaginasPDF(bytes,d.paginas),extraido=parseACK(paginas);if(d.acao==='ack_ler')return reply(extraido);
   const automatico=d.acao==='ack_pre_cadastrar';
   if(!automatico&&d.confirmado!==true)throw Error('Confirme a revisão do ACK');
   if(automatico&&(!d.email_id||!d.anexo_id))throw Error('Pré-cadastro automático exige a mensagem e o anexo da coleta compartilhada');
   const alvo=automatico?await rpc({acao:'ack_localizar',referencia:extraido.pedido,requisicao_id:d.requisicao_id}):null;
   const revisado=revisarACK(extraido,automatico?extraido:d.revisado);
   if(typeof d.nome!=='string'||!d.nome.trim()||!/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(d.requisicao_id||''))throw Error('Identificação do arquivo inválida');
   const sha256=await hash(bytes);
   const reserve=await rpc({acao:'ack_reservar',requisicao_id:d.requisicao_id,pedido_id:automatico?alvo.id:d.pedido_id,nome:d.nome,tamanho:bytes.length,sha256,paginas,extraido,revisado,email_id:d.email_id||null,anexo_id:d.anexo_id||null});
   if(!reserve.pronto){
    const info=await sb.storage.getBucket(bucket);if(info.error){const r=await sb.storage.createBucket(bucket,{public:false,fileSizeLimit:8388608,allowedMimeTypes:['application/pdf']});if(r.error){const check=await sb.storage.getBucket(bucket);if(check.error||check.data.public)throw Error('Armazenamento privado indisponível');}}else if(info.data.public)throw Error('Armazenamento deve ser privado');
    const up=await sb.storage.from(bucket).upload(reserve.caminho,bytes,{upsert:false,contentType:'application/pdf'});
    if(up.error){const prev=await sb.storage.from(bucket).download(reserve.caminho);if(prev.error)throw Error('Envio incompleto. Repita o mesmo arquivo.');if(await hash(new Uint8Array(await prev.data.arrayBuffer()))!==sha256)throw Error('Arquivo existente diverge do envio');}
    await rpc({acao:'ack_confirmar_arquivo',id:reserve.id});
   }
   if(automatico){if(alvo.proposta){if(alvo.proposta.tipo!=='ACK'||alvo.proposta.mensagem_id!==d.email_id)throw Error('Identificador de pré-cadastro já utilizado');return reply({id:reserve.id,proposta_id:alvo.proposta.id,estado:alvo.proposta.estado});}const proposta=await rpc({acao:'email_propor',requisicao_id:d.requisicao_id,mensagem_id:d.email_id,agente:'importacoes.ack',chave_processo:'ack:'+reserve.id,tipo:'ACK',resumo:'Confirmar ACK '+revisado.ack_numero+' do pedido '+revisado.pedido,pendencias:[],aplicacao:{acao:'ack_aplicar',id:reserve.id,versao:alvo.versao,alteracoes:{pedido:alvo.referencia,situacao:{anterior:alvo.status,novo:'Aceito -ACK'},numero_ack:{anterior:alvo.ack_numero,novo:revisado.ack_numero},data_ack:{anterior:alvo.ack_data,novo:revisado.ack_data}},avisos:extraido.avisos,itens_documento:extraido.itens,condicoes:extraido.condicoes}});return reply({id:reserve.id,proposta_id:proposta.id,estado:'Pendente'});}
   return reply({id:reserve.id,aplicado_em:reserve.aplicado_em});
  }
  if(d.acao==='email_anexar')return reply(await rpc(d));
  if(length>1500000)throw Error('Dados excedem o limite');
  if(d.acao==='ack_baixar')return await download(await rpc({acao:'ack_arquivo',id:d.id}),bucket);
  if(d.acao==='email_baixar')return await download(await rpc({acao:'email_arquivo',arquivo_id:d.arquivo_id}),'axe-email-anexos');
  if(!['ack_listar','ack_aplicar','email_registrar','email_listar','email_detalhe','email_resultado','email_propor','email_propostas_listar','email_proposta_detalhe','email_decidir','email_ack_propor'].includes(d.acao))throw Error('Ação não permitida');return reply(await rpc(d));
 }catch(e){return reply({erro:e instanceof Error?e.message.slice(0,240):'Não foi possível concluir. Tente novamente.'},400);}
}
Deno.serve(handleEntrada);

