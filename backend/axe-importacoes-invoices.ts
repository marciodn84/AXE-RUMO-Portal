import {classificarEmbarque} from './embarques-abrangencia.js';
import {createClient} from 'npm:@supabase/supabase-js@2.99.2';
import {extrairPaginasPDF} from './pdf-paginas.ts';
import {parseInvoice,parsePacking,parsePesos,combinarLiberacao} from './embarque-documentos-parser.ts';
const origins=['https://erp.axeengenharia.com','https://axe-rumo-portal.marciodnmachado.workers.dev','https://marciodn84.github.io'];
const hash=async(bytes:Uint8Array)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(x=>x.toString(16).padStart(2,'0')).join('');
export async function handleInvoices(req:Request){
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
  if(!['lib_lote_ler','lib_lote_aprovar'].includes(d.acao))throw Error('Ação inválida');
  async function guardarPrivado(bucketName:string,path:string,bytes:Uint8Array){
   const info=await sb.storage.getBucket(bucketName);if(info.error){const made=await sb.storage.createBucket(bucketName,{public:false,fileSizeLimit:8388608,allowedMimeTypes:['application/pdf']});if(made.error){const check=await sb.storage.getBucket(bucketName);if(check.error||check.data.public)throw Error('Armazenamento privado indisponível');}}else if(info.data.public)throw Error('Armazenamento deve ser privado');
   const up=await sb.storage.from(bucketName).upload(path,bytes,{upsert:false,contentType:'application/pdf'});if(up.error){const old=await sb.storage.from(bucketName).download(path);if(old.error||await hash(new Uint8Array(await old.data.arrayBuffer()))!==await hash(bytes))throw Error('Envio incompleto ou arquivo alterado. Repita o mesmo envio.');}
  }
   async function libRPC(data:any){const r=await sb.rpc('axe_liberacao_documental',{p_dados:data,p_usuario:user.id});if(r.error)throw Error(r.error.code==='P0001'?r.error.message:'Confira os documentos, os itens e os saldos da parcial.');return r.data;}
   const libBucket='axe-importacoes-parciais';
   const ctx=await libRPC({acao:'lib_contexto',pedido_id:d.pedido_id});if(!ctx.editar)throw Error('Sem permissão para preparar a parcial');
   if(!Array.isArray(d.arquivos)||d.arquivos.length<3||d.arquivos.length>14||d.arquivos.filter((x:any)=>x.categoria==='PACKING').length!==1||d.arquivos.filter((x:any)=>x.categoria==='PESOS').length>1||d.arquivos.filter((x:any)=>x.categoria==='INVOICE').length>12||d.arquivos.filter((x:any)=>x.categoria==='INVOICE').length<2||!d.arquivos.some((x:any)=>x.categoria==='PACKING'))throw Error('Selecione pelo menos duas invoices e uma packing list; pesos e dimensões são opcionais');
   const files:any[]=[];let totalBytes=0;
   for(const f of d.arquivos){
    if(!['INVOICE','PACKING','PESOS'].includes(f.categoria)||typeof f.nome!=='string'||!f.nome.trim()||f.nome.length>250||typeof f.conteudo!=='string'||f.conteudo.length>11184812||!/^[A-Za-z0-9+/]+={0,2}$/.test(f.conteudo))throw Error('Arquivo PDF inválido');
    const bytes=Uint8Array.from(atob(f.conteudo),c=>c.charCodeAt(0));totalBytes+=bytes.length;if(totalBytes>8388608||new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-')throw Error('Envie PDFs com até 8 MB no total');
    const paginas=await extrairPaginasPDF(bytes,f.paginas);files.push({...f,bytes,paginas,sha256:await hash(bytes)});
   }
   const pack=files.find(f=>f.categoria==='PACKING'),pesos=files.find(f=>f.categoria==='PESOS');
   if(!/pack(?:ing|ina)\s*list/i.test(pack.paginas.map((p:any)=>p.texto).join(' ')))throw Error('O documento selecionado como packing list não foi reconhecido');
   const invoices=files.filter(f=>f.categoria==='INVOICE');
    if(new Set(invoices.map(f=>f.sha256)).size!==invoices.length)throw Error('O mesmo PDF de invoice foi selecionado mais de uma vez');
    const packing=await parsePacking(pack.bytes,pack.paginas);
    const pesosData=pesos?parsePesos(pesos.paginas):null;
    const docs=[];
    for(const file of invoices){
     const invoice=parseInvoice(file.paginas);
     if(invoice.pedidos.length!==1)throw Error(file.nome+': a invoice deve identificar um único pedido de compra');
     const routed=await sb.rpc('axe_imp_pedido_da_invoice',{p_referencia:invoice.pedidos[0],p_usuario:user.id});
     if(routed.error||routed.data.id!==ctx.pedido.id)throw Error(file.nome+': a invoice não corresponde ao pedido selecionado');
     const parsed=combinarLiberacao(invoice,packing,null,ctx.pedido);
     parsed.avisos=parsed.avisos.filter((a:string)=>!/quantidade.*packing/i.test(a));
     docs.push({...parsed,arquivo:file.nome});
    }
    const grouped=new Map<string,any>();
    for(const doc of docs)for(const item of doc.invoice.itens){
     const key=String(item.linha)+'|'+String(item.codigo_fornecedor||item.part_number).replace(/[^a-z0-9]/gi,'').toUpperCase();
     const old=grouped.get(key);
     grouped.set(key,{...item,quantidade:Number(item.quantidade||0)+Number(old?.quantidade||0)});
    }
    const conjunto=combinarLiberacao({...docs[0].invoice,itens:[...grouped.values()]},packing,pesosData,ctx.pedido);
    const avisos=[...new Set([...conjunto.avisos,...docs.flatMap(doc=>doc.avisos)])];
    if(files.some(f=>f.paginas.some((p:any)=>p.metodo==='OCR')))avisos.push('Há páginas com OCR. Confira os campos e as quantidades reconhecidas.');
    const extraido={invoices:docs,packing,pesos:pesosData,avisos};
    if(d.acao==='lib_lote_ler')return reply({...ctx,extraido});
    if(d.confirmado!==true)throw Error('Confirme a conferência de todas as invoices e da packing list');
    if(!/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(d.requisicao_id||''))throw Error('Identificador obrigatório');
    const v=d.dados;
    if(!Array.isArray(v?.invoices)||v.invoices.length!==docs.length)throw Error('Confira todas as invoices');
    const editado=v.invoices.some((x:any,i:number)=>{
     const o=docs[i];
     return x.invoice!==String(o.invoice.numero||'')||x.data_invoice!==String(o.invoice.data||'')||
      x.moeda!==String(o.invoice.moeda||'')||Number(x.valor)!==Number(o.invoice.valor)||
      !Array.isArray(x.itens)||x.itens.length!==o.itens.length||x.itens.some((item:any,j:number)=>{
       const original=o.itens[j];
       return item.pedido_item_id!==original.pedido_item_id||Number(item.quantidade)!==Number(original.quantidade)||
        Number(item.valor_unitario)!==Number(original.valor_unitario);
      });
    });
    if((editado||avisos.length)&&!String(v.motivo||'').trim())throw Error('Informe a justificativa das correções ou divergências documentais');
    const totals=new Map<string,number>();
    for(const x of v.invoices)for(const item of x.itens||[])totals.set(item.pedido_item_id,(totals.get(item.pedido_item_id)||0)+Number(item.quantidade));
    v.abrangencia=classificarEmbarque(ctx.pedido.itens,[...totals].map(([pedido_item_id,quantidade])=>({pedido_item_id,quantidade})));
    let posicao=0;
    const metadata=[];
    for(const file of files){
     const ordem=file.categoria==='INVOICE'?++posicao:null;
     const path='entrada/'+user.id+'/'+d.requisicao_id+'/'+file.categoria+(ordem?'-'+ordem:'')+'.pdf';
     await guardarPrivado(libBucket,path,file.bytes);
     metadata.push({categoria:file.categoria,nome:file.nome,sha256:file.sha256,tamanho:file.bytes.length,caminho:path,posicao:ordem});
    }
    return reply(await libRPC({acao:'lib_aprovar',pedido_id:d.pedido_id,versao:d.versao,requisicao_id:d.requisicao_id,
     confirmado:true,conferiu_parcelas:d.conferiu_parcelas===true,dados:v,extraido,arquivos:metadata}));
 }catch(error){
  return reply({erro:error instanceof Error?error.message:'Não foi possível processar as invoices'},400);
 }
}
Deno.serve(handleInvoices);

