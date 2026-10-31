const origins=['https://erp.axeengenharia.com','https://axe-rumo-portal.marciodnmachado.workers.dev','https://marciodn84.github.io'];
export async function estoqueHandler(req:Request){
 const origin=req.headers.get('origin')||'',headers:Record<string,string>={'content-type':'application/json','cache-control':'no-store','vary':'Origin','access-control-allow-headers':'authorization,apikey,content-type','access-control-allow-methods':'POST,OPTIONS'};if(origins.includes(origin))headers['access-control-allow-origin']=origin;
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 if(req.method==='OPTIONS')return reply({});if(req.method!=='POST')return reply({erro:'Método não permitido'},405);
 try{
 const authorization=req.headers.get('authorization')||'';if(!authorization.startsWith('Bearer '))return reply({erro:'Faça login novamente'},401);
 const base=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!;
 const userRes=await fetch(base+'/auth/v1/user',{headers:{apikey:anon,authorization}});if(!userRes.ok)return reply({erro:'Sessão inválida ou expirada'},401);const user=await userRes.json();if(typeof user.id!=='string')return reply({erro:'Sessão inválida'},401);
 const reader=req.body?.getReader();if(!reader)return reply({erro:'Dados ausentes'},400);let size=0;const chunks=[];for(;;){const r=await reader.read();if(r.done)break;size+=r.value.length;if(size>32768){await reader.cancel();return reply({erro:'Dados excedem o limite'},413);}chunks.push(r.value);}const bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}const d=JSON.parse(new TextDecoder().decode(bytes));
 if(!['stock_listar','stock_detalhe','stock_movimentos','stock_importacoes','stock_importacao_previa','stock_importar','stock_movimentar','stock_estornar','stock_estornar_importacao'].includes(d.acao))return reply({erro:'Operação inválida'},400);
 const res=await fetch(base+'/rest/v1/rpc/axe_estoque',{method:'POST',headers:{apikey:key,authorization:'Bearer '+key,'content-type':'application/json'},body:JSON.stringify({p_dados:d,p_usuario:user.id})});const body=await res.json();if(!res.ok)return reply({erro:body.code==='P0001'?String(body.message).slice(0,700):body.code==='55P03'?'Outra operação está usando estes registros. Aguarde e atualize a consulta.':['22P02','22007','22008','23514','22003'].includes(body.code)?'Confira os números, datas, quantidades e campos obrigatórios.':'Não foi possível registrar. Atualize a consulta antes de tentar novamente.'},409);return reply(body);
 }catch{return reply({erro:'Não foi possível concluir a operação. Confira os dados e tente novamente.'},400);}
}
Deno.serve(estoqueHandler);
