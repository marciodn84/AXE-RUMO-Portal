import {parseNumerario} from './numerario-parser.ts';
import {createClient} from 'npm:@supabase/supabase-js@2.99.2';
import {extrairPaginasPDF} from './di-documento.ts';
import {lerPedidoPDF} from './pedido-pdf.ts';
import {parseFechamento,revisarFechamento} from './fechamento-parser.ts';
const bucket='axe-importacoes-fechamentos';
const origins=['https://erp.axeengenharia.com','https://axe-rumo-portal.marciodnmachado.workers.dev','https://marciodn84.github.io'];
export async function handleFechamento(req:Request){
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
  async function rpc(data:any){const r=await sb.rpc('axe_imp_fechamentos',{p_dados:data,p_usuario:user.id});if(r.error)throw Error(r.error.code==='P0001'?r.error.message.slice(0,240):'Revise os campos, valores e vínculos do fechamento.');return r.data;}
  if(typeof d.acao==='string'&&d.acao.startsWith('num_')){
   const nrpc=async(data:any)=>{const r=await sb.rpc('axe_imp_numerario',{p_dados:data,p_usuario:user.id});if(r.error)throw Error(r.error.code==='P0001'?r.error.message:'Não foi possível gravar o numerário. Confira os dados.');return r.data;};
   if(d.acao==='num_ler'||d.acao==='num_upload'){
    await nrpc({acao:'num_autorizar',processo_id:d.processo_id});
    if(typeof d.conteudo!=='string'||d.conteudo.length>11184812||!/^[A-Za-z0-9+/]+={0,2}$/.test(d.conteudo))throw Error('Selecione PDF de até 8 MB');
    const bytes=Uint8Array.from(atob(d.conteudo),c=>c.charCodeAt(0));if(bytes.length>8388608||new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-')throw Error('PDF inválido');
    const pages=await extrairPaginasPDF(bytes,d.paginas),parsed=parseNumerario(pages,d.categoria);
    if(d.acao==='num_ler')return reply(parsed);
    let dados=parsed;
    if(d.categoria!=='Fechamento'){
     dados={...parsed,valor:d.dados?.valor||null,data:d.dados?.data||null};
     if(dados.valor!==null&&!/^\d{1,15}(?:\.\d{1,2})?$/.test(dados.valor))throw Error('Valor inválido');
     if(dados.data!==null&&!/^\d{4}-\d{2}-\d{2}$/.test(dados.data))throw Error('Data inválida');
     if(((parsed.valor&&parsed.valor!==dados.valor)||(parsed.data&&parsed.data!==dados.data))&&d.corrigir!==true)throw Error('Confirme a correção dos dados divergentes do documento');
    }
    const sha=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(x=>x.toString(16).padStart(2,'0')).join('');
    const rr=await nrpc({acao:'num_reservar',processo_id:d.processo_id,requisicao_id:d.requisicao_id,categoria:d.categoria,nome:d.nome,sha256:sha,dados});
    if(!rr.pronto){const up=await sb.storage.from(bucket).upload(rr.caminho,bytes,{upsert:false,contentType:'application/pdf'});if(up.error){const prev=await sb.storage.from(bucket).download(rr.caminho);if(prev.error)throw Error('Envio incompleto. Repita o mesmo arquivo.');const h=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await prev.data.arrayBuffer()))).map(x=>x.toString(16).padStart(2,'0')).join('');if(h!==sha)throw Error('Arquivo existente diverge');}}
    return reply(await nrpc({acao:'num_confirmar',processo_id:d.processo_id,id:rr.id,substituir:d.substituir}));
   }
   if(d.acao==='num_baixar'){const f=await nrpc({...d,acao:'num_arquivo'});const r=await sb.storage.from(bucket).createSignedUrl(f.caminho,60,{download:f.nome});if(r.error)throw Error('Arquivo indisponível');return reply({url:r.data.signedUrl});}
   if(length>500000)throw Error('Dados excedem o limite');
   if(!['num_movimento','num_contexto','num_despachante','num_vincular','num_estornar','num_conciliar','num_financeiro'].includes(d.acao))throw Error('Ação não permitida');
   return reply(await nrpc(d));
  }
  if(d.acao==='fech_ler'||d.acao==='fech_upload'||d.acao==='pedido_pdf_ler'){
   await rpc({acao:'fech_autorizar'});if(typeof d.conteudo!=='string'||!d.conteudo.length||d.conteudo.length>11184812||!/^[A-Za-z0-9+/]*={0,2}$/.test(d.conteudo))throw Error('Selecione PDF de até 8 MB');
   const bytes=Uint8Array.from(atob(d.conteudo),c=>c.charCodeAt(0));if(bytes.length>8388608||new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-')throw Error('PDF inválido ou acima de 8 MB');
   if(d.acao==='pedido_pdf_ler')return reply(await lerPedidoPDF(bytes,d.paginas));
   const paginas=await extrairPaginasPDF(bytes,d.paginas),extraido=parseFechamento(paginas);if(d.acao==='fech_ler')return reply(extraido);
   if(d.confirmado!==true||d.escopo_confirmado!==true)throw Error('Confirme a revisão e o escopo do fechamento');
   const revisado=revisarFechamento(extraido,d.revisado,paginas.length);
   if(typeof d.nome!=='string'||!d.nome.trim()||!/^[a-f0-9-]{36}$/i.test(d.requisicao_id||''))throw Error('Identificação do arquivo inválida');
   const sha256=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(x=>x.toString(16).padStart(2,'0')).join('');
   const reserve=await rpc({acao:'fech_reservar',requisicao_id:d.requisicao_id,embarque_id:d.embarque_id,declaracao_id:d.declaracao_id,nome:d.nome,tamanho:bytes.length,sha256,paginas,extraido,revisado,escopo_confirmado:true});
   if(!reserve.pronto){
    const info=await sb.storage.getBucket(bucket);if(info.error){const r=await sb.storage.createBucket(bucket,{public:false,fileSizeLimit:8388608,allowedMimeTypes:['application/pdf']});if(r.error){const check=await sb.storage.getBucket(bucket);if(check.error||check.data.public)throw Error('Armazenamento privado indisponível');}}else if(info.data.public)throw Error('Armazenamento deve ser privado');
    const up=await sb.storage.from(bucket).upload(reserve.caminho,bytes,{upsert:false,contentType:'application/pdf'});
    if(up.error){const prev=await sb.storage.from(bucket).download(reserve.caminho);if(prev.error)throw Error('Envio incompleto. Repita o mesmo arquivo.');const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await prev.data.arrayBuffer()))).map(x=>x.toString(16).padStart(2,'0')).join('');if(hash!==sha256)throw Error('Arquivo existente diverge do envio');}
    await rpc({acao:'fech_confirmar_arquivo',id:reserve.id});
   }return reply({id:reserve.id});
  }
  if(length>500000)throw Error('Dados excedem o limite');
  if(d.acao==='fech_baixar'){const f=await rpc({acao:'fech_arquivo',id:d.id});const r=await sb.storage.from(bucket).createSignedUrl(f.caminho,60,{download:f.nome});if(r.error)throw Error('Não foi possível abrir o anexo');return reply({url:r.data.signedUrl});}
  if(!['fech_listar','fech_detalhe','fech_plano','fech_aplicar'].includes(d.acao))throw Error('Ação não permitida');return reply(await rpc(d));
 }catch(e){return reply({erro:e instanceof Error?e.message.slice(0,240):'Não foi possível concluir. Tente novamente.'},400);}
}
Deno.serve(handleFechamento);

