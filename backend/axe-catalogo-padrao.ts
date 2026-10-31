import {consultarEmpresa,validarCNPJ} from './cnpj-ws.mjs';
const baseHeaders={"content-type":"application/json","access-control-allow-origin":"https://marciodn84.github.io","access-control-allow-headers":"authorization,apikey,content-type","access-control-allow-methods":"POST,OPTIONS","cache-control":"no-store"};
async function bodyJson(req:Request){
 const reader=req.body?.getReader();if(!reader)throw Error('BODY');let size=0;const chunks=[];
 for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>64000){await reader.cancel();throw Error('LIMIT');}chunks.push(value);}
 const bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}return JSON.parse(new TextDecoder().decode(bytes));
}
const positive=(x:unknown)=>Number.isSafeInteger(x)&&Number(x)>0;
Deno.serve(async(req:Request)=>{
 const origin=req.headers.get('origin')||'';
 const allowedOrigins=['https://marciodn84.github.io','https://axe-rumo-portal.marciodnmachado.workers.dev','https://erp.axeengenharia.com'];
 const headers:Record<string,string>={...baseHeaders,'vary':'Origin'};
 if(allowedOrigins.includes(origin))headers['access-control-allow-origin']=origin;
 else delete headers['access-control-allow-origin'];
 const reply=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers});

 if(req.method==='OPTIONS')return reply({});if(req.method!=='POST')return reply({erro:'Método não permitido'},405);
 try{
  const authorization=req.headers.get('authorization')||'';if(!authorization.startsWith('Bearer '))return reply({erro:'Faça login novamente'},401);
  const base=Deno.env.get('SUPABASE_URL')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const auth=await fetch(base+'/auth/v1/user',{headers:{apikey:anon,authorization}});if(!auth.ok)return reply({erro:'Sessão inválida ou expirada'},401);
  const user=await auth.json();if(typeof user.id!=='string')return reply({erro:'Sessão inválida'},401);
  const backend={apikey:key,authorization:'Bearer '+key,'content-type':'application/json'};
  const access=await fetch(base+'/rest/v1/axe_rumo_revisores?select=usuario_id&ativo=eq.true&usuario_id=eq.'+encodeURIComponent(user.id),{headers:backend});
  if(!access.ok)return reply({erro:'Não foi possível verificar seu acesso'},503);
  const reviewers=await access.json();if(!Array.isArray(reviewers)||reviewers.length!==1)return reply({erro:'Usuário sem autorização'},403);
  const b=await bodyJson(req);
  if(b.pagina!==undefined&&(!Number.isSafeInteger(b.pagina)||b.pagina<0||b.pagina>10000))return reply({erro:'Página inválida'},400);
  async function query(table:string,params:Record<string,string>){
   const res=await fetch(base+'/rest/v1/'+table+'?'+new URLSearchParams(params),{headers:{...backend,Prefer:'count=exact'}});
   if(!res.ok)throw Error('QUERY');const rows=await res.json();const range=res.headers.get('content-range')||'';const total=Number(range.split('/')[1]);
   return {linhas:rows,total:Number.isFinite(total)?total:rows.length};
  }
  async function rpc(name:string,data:unknown){
   const res=await fetch(base+'/rest/v1/rpc/'+name,{method:'POST',headers:backend,body:JSON.stringify(data)});const result=await res.json();
   if(!res.ok){const messages:Record<string,string>={'23505':'Esse registro já existe. Atualize a lista antes de tentar novamente.','23503':'Um dos cadastros relacionados não foi encontrado.','23514':'Revise formatos, vigência, alíquotas e campos obrigatórios.','22P02':'Revise os números e os identificadores informados.','22007':'Revise as datas informadas.'};return reply({erro:messages[result.code]||(result.code==='P0001'?String(result.message).slice(0,240):'Não foi possível salvar. Atualize a tela e confira os dados.')},409);}return reply({ok:true,resultado:result});
  }

  const tables:Record<string,string>={produto:'produtos_conciliacao',cliente:'clientes',fornecedor:'fornecedores',referencia_cliente:'produtos_clientes_referencias',opcao_cliente:'produtos_clientes_opcoes',produto_fornecedor:'produtos_fornecedores',similar:'produtos_similares',documento:'produtos_documentos'};
  const table=tables[b.tipo];
  if(!table)return reply({erro:'Cadastro inválido'},400);
  if(b.acao==='consultar_cnpj'){
   if(!['cliente','fornecedor'].includes(b.tipo))return reply({erro:'Consulta disponível para clientes e fornecedores.'},400);
   try{
    const cnpj=validarCNPJ(b.cnpj);
    async function cache(acao:string,dados?:unknown){const res=await fetch(base+'/rest/v1/rpc/axe_cnpj_consulta',{method:'POST',headers:backend,body:JSON.stringify({p_acao:acao,p_cnpj:cnpj,p_usuario:user.id,...(dados?{p_dados:dados}:{})})});const data=await res.json();if(!res.ok)throw Error(data.code==='P0001'?String(data.message).slice(0,240):'Não foi possível consultar o CNPJ.');return data;}
    async function comFaturamento(result:any){
     if(b.tipo==='cliente'){
      const clients=await query('clientes',{select:'id',cnpj:'eq.'+cnpj,legado_grupo:'eq.false',limit:'1'});
      if(clients.linhas[0]){const locais=await query('clientes_locais',{select:'id,dados',cliente_id:'eq.'+clients.linhas[0].id,finalidade:'eq.FATURAMENTO',order:'id.desc',limit:'1'});const l=locais.linhas[0];if(l)result.faturamento_atual={id:l.id,endereco:l.dados?.endereco||null,bloco_original:l.dados?.bloco_original||''};}
     }return result;
    }
    const cached=await cache('consultar');if(cached.cache)return reply(await comFaturamento(cached));
    const empresa=await consultarEmpresa(cnpj);return reply(await comFaturamento(await cache('salvar',empresa)));
   }catch(e){return reply({erro:e instanceof Error&&e.name!=='TimeoutError'?e.message.slice(0,240):'A consulta demorou para responder. Tente novamente ou preencha manualmente.'},400);}
  }
  if(b.acao==='cadastro_bloqueio'){
   if(!['produto','fornecedor'].includes(b.tipo)||!positive(b.id)||typeof b.bloquear!=='boolean'||typeof b.atualizado_em!=='string')return reply({erro:'Dados de bloqueio inválidos'},400);
   return await rpc('axe_cadastro_bloqueio',{p_tipo:b.tipo,p_id:b.id,p_bloquear:b.bloquear,p_motivo:String(b.motivo||'').slice(0,1000),p_usuario:user.id,p_versao:b.atualizado_em});
  }
  if(b.acao==='cadastro_historico'){
   if(!['produto','fornecedor'].includes(b.tipo)||!positive(b.id))return reply({erro:'Cadastro inválido'},400);
   return reply({ok:true,...await query('cadastros_decisoes',{select:'id,acao,anterior,atual,usuario_id,criado_em',entidade:'eq.'+b.tipo.toUpperCase()+'_COMERCIAL',referencia:'eq.'+b.id,order:'id.desc',limit:'50',offset:String((Number(b.pagina)||0)*50)})});
  }
  if(b.acao==='salvar'){
   if(b.consulta_cnpj)return await rpc('axe_catalogo_salvar_cnpj',{p_tipo:b.tipo,p_dados:b.dados,p_usuario:user.id,p_cnpj:validarCNPJ(b.consulta_cnpj)});
   return await rpc('axe_catalogo_salvar',{p_tipo:b.tipo,p_dados:b.dados,p_usuario:user.id});
  }
  if(b.acao==='detalhe'){
   if(!positive(b.id))return reply({erro:'Registro inválido'},400);
   const result=await query(table,{select:'*',id:'eq.'+b.id,limit:'1'});
   return result.linhas[0]?reply(result.linhas[0]):reply({erro:'Registro não encontrado'},404);
  }
  if(b.acao==='listar'){
   const p:Record<string,string>={select:'*',order:'id.asc',limit:'50',offset:String((b.pagina??0)*50)};
   if(b.tipo==='cliente')p.legado_grupo='eq.false';
   const q=String(b.busca||'').slice(0,100).replace(/[%*(),]/g,'');
   if(q){const fields:Record<string,string[]>={produto:['codigo_axe','codigo_anterior','descricao_referencia','part_number'],cliente:['nome','cnpj','codigo_externo'],fornecedor:['razao_social','cnpj','nome_fantasia'],referencia_cliente:['codigo_cliente','descricao_cliente'],produto_fornecedor:['codigo_fornecedor','descricao_fornecedor']};if(fields[b.tipo])p.or='('+(b.tipo==='cliente'&&/^\d{1,15}$/.test(q)?'id.eq.'+q+',':'')+fields[b.tipo].map(f=>f+'.ilike.*'+q+'*').join(',')+')';}
   for(const key of ['produto_id','fornecedor_id','cliente_id','referencia_cliente_id'])if(b[key]!==undefined){
    const allowed:Record<string,string[]>={produto_fornecedor:['produto_id','fornecedor_id'],referencia_cliente:['cliente_id'],opcao_cliente:['referencia_cliente_id','produto_id'],similar:['produto_id'],documento:['produto_id']};
    if(!positive(b[key])||!allowed[b.tipo]?.includes(key))return reply({erro:'Filtro inválido'},400);
    if(b.tipo==='similar'&&key==='produto_id')p.or='(produto_id.eq.'+b[key]+',similar_id.eq.'+b[key]+')';else p[key]='eq.'+b[key];
   }
   return reply(await query(table,p));
  }
  return reply({erro:'Operação não permitida'},400);
 }catch(e){return reply({erro:'Não foi possível concluir a consulta. Atualize a tela e confira os dados.'},400);}
});


