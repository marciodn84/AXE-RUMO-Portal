import {createClient} from 'npm:@supabase/supabase-js@2.99.2';
import {parseNFe} from './notas-xml.ts';
import {extrairDI,revisarDI} from './di-documento.ts';
const bucket='axe-importacoes-nomus';
const allowed=['https://erp.axeengenharia.com','https://axe-rumo-portal.marciodnmachado.workers.dev','https://marciodn84.github.io'];
export async function handleNotas(req:Request){
 const origin=req.headers.get('origin')||'',headers:Record<string,string>={'content-type':'application/json','cache-control':'no-store','vary':'Origin','access-control-allow-headers':'authorization,apikey,content-type','access-control-allow-methods':'POST,OPTIONS'};
 if(allowed.includes(origin))headers['access-control-allow-origin']=origin;
 const reply=(v:unknown,s=200)=>new Response(JSON.stringify(v),{status:s,headers});
 if(req.method==='OPTIONS')return reply({});if(req.method!=='POST')return reply({erro:'Método não permitido'},405);
 try{
  const authorization=req.headers.get('authorization')||'';if(!authorization.startsWith('Bearer '))return reply({erro:'Faça login novamente'},401);
  const base=Deno.env.get('SUPABASE_URL')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!,service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const auth=await fetch(base+'/auth/v1/user',{headers:{authorization,apikey:anon},signal:AbortSignal.timeout(15000)});
  if(!auth.ok)return reply({erro:'Sessão inválida'},401);const user=await auth.json();if(typeof user.id!=='string')return reply({erro:'Sessão inválida'},401);
  const reader=req.body?.getReader();if(!reader)return reply({erro:'Dados obrigatórios'},400);
  const chunks:Uint8Array[]=[];let length=0;for(;;){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>12000000){await reader.cancel();return reply({erro:'Arquivo excede o limite de envio'},413);}chunks.push(value);}
  const buf=new Uint8Array(length);let at=0;for(const c of chunks){buf.set(c,at);at+=c.length;}
  const dados=JSON.parse(new TextDecoder().decode(buf));if(!dados||typeof dados!=='object'||Array.isArray(dados))throw Error('Dados inválidos');
  const sb=createClient(base,service,{auth:{persistSession:false,autoRefreshToken:false}});
  async function rpc(p:any){const {data,error}=await sb.rpc('axe_imp_notas',{p_dados:p,p_usuario:user.id});if(error)throw Error(error.code==='P0001'?error.message.slice(0,240):'Revise os vínculos e os campos informados.');return data;}
  if(dados.acao==='nf_venda_tributos_upload'){
   await rpc({acao:'nf_autorizar_upload'});
   if(dados.confirmado!==true||typeof dados.xml!=='string'||new TextEncoder().encode(dados.xml).length>2097152
     ||!Number.isSafeInteger(dados.pedido_id)||dados.pedido_id<1)throw Error('Confira o pedido e selecione um XML de até 2 MB');
   const nota=parseNFe(dados.xml,'1');
   if(!nota.autorizada)throw Error('Selecione o XML da NF-e de venda com protocolo de produção');
   const {data,error}=await sb.rpc('axe_venda_nfe_tributos',{pid:dados.pedido_id,conteudo:dados.xml,uid:user.id});
   if(error)throw Error(error.code==='P0001'?error.message:'Não foi possível vincular os tributos da NF-e');
   return reply(data);
  }
  if(dados.acao==='nf_di_prever'||dados.acao==='nf_di_upload'){
   await rpc({acao:'nf_autorizar_upload'});
   const raw=dados.conteudo;if(typeof raw!=='string'||raw.length>11184812||!raw.length||!/^[A-Za-z0-9+/]*={0,2}$/.test(raw))throw Error('Selecione PDF de até 8 MB');
   let bin:string;try{bin=atob(raw);}catch{throw Error('Arquivo inválido');}const bytes=Uint8Array.from(bin,c=>c.charCodeAt(0));
   if(bytes.length>8388608||new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-')throw Error('Selecione um PDF válido de até 8 MB');
   const extracted=await extrairDI(bytes,dados.paginas);
   if(dados.acao==='nf_di_prever')return reply(extracted.extraido);
   if(dados.confirmado!==true)throw Error('Confirme a revisão dos valores e páginas de origem');
   const revisado=revisarDI(extracted.extraido,dados.revisado,extracted.paginas.length);
   if(!/^[a-f0-9-]{36}$/i.test(dados.requisicao_id||'')||typeof dados.nome!=='string'||!dados.nome.trim())throw Error('Identificação do arquivo inválida');
   const sha256=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(x=>x.toString(16).padStart(2,'0')).join('');
   const reservation=await rpc({acao:'nf_di_reservar',requisicao_id:dados.requisicao_id,declaracao_id:dados.declaracao_id,nome:dados.nome,tamanho:bytes.length,sha256,...extracted,revisado});
   const info=await sb.storage.getBucket(bucket);
   if(info.error){const created=await sb.storage.createBucket(bucket,{public:false,fileSizeLimit:8388608,allowedMimeTypes:['application/pdf','application/xml']});if(created.error){const check=await sb.storage.getBucket(bucket);if(check.error||check.data.public)throw Error('Armazenamento privado indisponível');}}else if(info.data.public)throw Error('Armazenamento deve ser privado');
   const up=await sb.storage.from(bucket).upload(reservation.caminho,bytes,{upsert:false,contentType:'application/pdf'});
   if(up.error){const prior=await sb.storage.from(bucket).download(reservation.caminho);if(prior.error)throw Error('Envio incompleto. Repita o mesmo arquivo.');const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await prior.data.arrayBuffer()))).map(x=>x.toString(16).padStart(2,'0')).join('');if(digest!==sha256)throw Error('Arquivo existente diverge do envio');}
   return reply(await rpc({acao:'nf_di_confirmar_arquivo',leitura_id:reservation.id}));
  }
  if(dados.acao==='nf_upload'||dados.acao==='nf_ler_xml'){
   await rpc({acao:'nf_autorizar_upload'});
   const tipo=dados.tipo,raw=dados.conteudo;
   if(!['XML','PDF'].includes(tipo)||typeof raw!=='string'||raw.length>(tipo==='XML'?2796204:11184812)||!raw.length||!/^[A-Za-z0-9+/]*={0,2}$/.test(raw))throw Error('Arquivo inválido ou acima do limite');
   let bin:string;try{bin=atob(raw);}catch{throw Error('Não foi possível ler o arquivo');}const bytes=Uint8Array.from(bin,c=>c.charCodeAt(0));
   if(bytes.length>(tipo==='XML'?2097152:8388608))throw Error('Arquivo acima do limite: XML 2 MB; PDF 8 MB');
   if(tipo==='PDF'&&new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-')throw Error('Selecione um arquivo PDF válido');
   let xml:any;
   if(tipo==='XML'){
    // Preserve original bytes in Storage. Decode supported XML encodings explicitly.
    const prefix=new TextDecoder('latin1').decode(bytes.slice(0,200));const enc=prefix.match(/encoding\s*=\s*["']([^"']+)/i)?.[1]?.toLowerCase()||'utf-8';
    if(!['utf-8','utf8','iso-8859-1','windows-1252'].includes(enc))throw Error('Use XML em UTF-8 ou ISO-8859-1');
    const textoXml=new TextDecoder(enc,{fatal:true}).decode(bytes);
    xml=parseNFe(textoXml);
    const {data:tributos,error}=await sb.rpc('axe_nfe_tributos',{conteudo:textoXml});
    if(error)throw Error('Não foi possível ler o detalhamento tributário do XML');
    xml.tributos=tributos;
   }
   let pdfChave:string|null=null;
   if(tipo==='PDF'){const nt=await rpc({acao:'nf_detalhe',id:dados.id});const read=await extrairDI(bytes,dados.paginas);const digits=read.paginas.map((p:any)=>p.texto).join('\n').replace(/\D/g,'');if(!nt.chave||!digits.includes(nt.chave))throw Error('Conflito: a chave do PDF não corresponde ao XML desta nota ou não pôde ser lida. Selecione o PDF correto ou complemente a leitura.');pdfChave=nt.chave;}
   if(dados.acao==='nf_upload'&&tipo==='XML'&&!xml.autorizada)throw Error('Anexe o XML emitido com protocolo de autorização; o espelho só pode ser consultado.');
   if(dados.acao==='nf_ler_xml'){if(tipo!=='XML')throw Error('Selecione o XML');return reply(xml);}
   if(typeof dados.nome!=='string'||!dados.nome.trim()||!String(dados.requisicao_id||'').match(/^[a-f0-9-]{36}$/i))throw Error('Identificação do arquivo inválida');
   const sha256=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(x=>x.toString(16).padStart(2,'0')).join('');
   const reserva=await rpc({acao:'nf_reservar',requisicao_id:dados.requisicao_id,id:dados.id||null,versao:dados.versao||null,tipo,nome:dados.nome,sha256,tamanho:bytes.length,...(xml?{xml}:{})});
   if(!reserva.pronto){
    const info=await sb.storage.getBucket(bucket);
    if(info.error){
     // A failed lookup alone must never be treated as a successful private bucket check.
     const created=await sb.storage.createBucket(bucket,{public:false,fileSizeLimit:8388608,allowedMimeTypes:['application/pdf','application/xml']});
     if(created.error){const check=await sb.storage.getBucket(bucket);if(check.error||check.data.public)throw Error('Armazenamento privado indisponível');}
    }else if(info.data.public)throw Error('Armazenamento deve ser privado');
    const up=await sb.storage.from(bucket).upload(reserva.caminho,bytes,{upsert:false,contentType:tipo==='XML'?'application/xml':'application/pdf'});
    if(up.error){
     // A lost response/retry can find the immutable object already present. Verify its bytes.
     const prior=await sb.storage.from(bucket).download(reserva.caminho);if(prior.error)throw Error('Envio incompleto. Tente o mesmo arquivo novamente.');
     const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await prior.data.arrayBuffer()))).map(x=>x.toString(16).padStart(2,'0')).join('');
     if(digest!==sha256)throw Error('Arquivo existente diverge do envio');
    }
    await rpc({acao:'nf_confirmar_arquivo',arquivo_id:reserva.arquivo_id});
   }
   if(tipo==='PDF')await rpc({acao:'nf_pdf_oficial_conferido',id:reserva.id,arquivo_id:reserva.arquivo_id,sha256,chave:pdfChave});
   return reply({id:reserva.id,arquivo_id:reserva.arquivo_id});
  }
  if(length>500000)throw Error('Dados excedem o limite');
  if(dados.acao==='nf_baixar'||dados.acao==='nf_di_baixar'){
   const file=await rpc(dados.acao==='nf_di_baixar'?{acao:'nf_di_arquivo',leitura_id:dados.leitura_id}:{acao:'nf_arquivo',id:dados.id,arquivo_id:dados.arquivo_id});
   const signed=await sb.storage.from(bucket).createSignedUrl(file.caminho,60,{download:file.nome});if(signed.error)throw Error('Não foi possível abrir o anexo');
   return reply({url:signed.data.signedUrl});
  }
  if(!['nf_opcoes','nf_listar','nf_produtos','nf_detalhe','nf_historico','nf_prever','nf_salvar','nf_reabrir','nf_di_listar','nf_di_detalhe'].includes(dados.acao))throw Error('Ação não permitida');
  return reply(await rpc(dados));
 }catch(e){return reply({erro:e instanceof Error?e.message.slice(0,240):'Não foi possível concluir. Tente novamente.'},400);}
}
Deno.serve(handleNotas);

