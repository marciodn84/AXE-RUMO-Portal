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

  if(['rumo_criar','rumo_detalhe','rumo_salvar','rumo_aprovar','rumo_recarregar'].includes(b.acao)){
   if((b.acao==='rumo_criar'&&!positive(b.pedido_rumo_id))||(b.acao!=='rumo_criar'&&!positive(b.id)))return reply({erro:'Pedido inválido'},400);
   return await rpc('axe_venda_rumo',{p_dados:b,p_usuario:user.id});
  }
  const tables:Record<string,string>={oportunidades:'comercial_oportunidades',propostas:'comercial_propostas',pedidos:'comercial_pedidos',eventos:'comercial_eventos',clientes:'clientes',enderecos:'clientes_locais',referencias:'produtos_clientes_referencias',opcoes:'produtos_clientes_opcoes',produtos:'produtos_conciliacao'};
  if(b.acao==='salvar'){
   if(!['oportunidade','proposta','revisar','situacao','pedido'].includes(b.operacao)||!b.dados||typeof b.dados!=='object'||Array.isArray(b.dados))return reply({erro:'Operação inválida'},400);
   return await rpc('axe_comercial_salvar',{p_acao:b.operacao,p_dados:b.dados,p_usuario:user.id});
  }
  const table=tables[b.secao];if(!table)return reply({erro:'Consulta inválida'},400);
  const p:Record<string,string>={select:'*',order:'id.desc',limit:'50',offset:String((b.pagina??0)*50)};
  if(b.acao==='detalhe'){
   if(!positive(b.id))return reply({erro:'Registro inválido'},400);
   const result=await query(table,{select:'*',id:'eq.'+b.id,limit:'1'});return result.linhas[0]?reply(result.linhas[0]):reply({erro:'Registro não encontrado'},404);
  }
  if(b.acao!=='listar')return reply({erro:'Ação não permitida'},400);
  if(b.secao==='clientes'){p.legado_grupo='eq.false';p.ativo='eq.true';}
  if(['referencias','produtos'].includes(b.secao))p.ativo='eq.true';if(b.secao==='produtos'&&b.somente_axe===true){p.codigo_axe='not.is.null';p.mesclado_em_id='is.null';p.bloqueado_comercial='eq.false';}
  if(b.secao==='enderecos')p.finalidade='in.(ENTREGA,FATURAMENTO)';
  const q=String(b.busca||'').slice(0,100).replace(/[%*(),]/g,'');
  const fields:Record<string,string[]>={pedidos:['pedido_cliente'],oportunidades:['titulo'],propostas:['titulo'],clientes:['nome','cnpj'],referencias:['codigo_cliente','descricao_cliente'],produtos:['codigo_axe','codigo_anterior','descricao_referencia']};
  if(q&&fields[b.secao])p.or='('+fields[b.secao].map(f=>f+'.ilike.*'+q+'*').join(',')+')';
  for(const key of ['cliente_id','referencia_cliente_id','registro_id'])if(b[key]!==undefined){
   const allowed:Record<string,string[]>={enderecos:['cliente_id'],referencias:['cliente_id'],opcoes:['referencia_cliente_id'],eventos:['registro_id'],propostas:['cliente_id'],oportunidades:['cliente_id']};
   if(!positive(b[key])||!allowed[b.secao]?.includes(key))return reply({erro:'Filtro inválido'},400);p[key]='eq.'+b[key];
  }
  if(b.secao==='eventos'){if(!['proposta','oportunidade','pedido'].includes(b.tipo))return reply({erro:'Histórico inválido'},400);p.tipo='eq.'+b.tipo;p.order='id.asc';}
  return reply(await query(table,p));
 }catch(e){return reply({erro:'Não foi possível concluir a consulta. Atualize a tela e confira os dados.'},400);}
});
