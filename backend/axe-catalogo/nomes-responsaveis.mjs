const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function nomeResponsavel(user){
 const m=user?.user_metadata||{};
 for(const value of [m.full_name,m.nome,m.name,user?.email])if(typeof value==='string'&&value.trim())return value.trim().slice(0,200);
 return 'Usuário não identificado';
}
export async function identificarResponsaveis(resultado,atual,consultar){
 if(!Array.isArray(resultado?.linhas))return resultado;
 const cache=new Map();
 const resolver=id=>{
  if(!uuid.test(id))return Promise.resolve(null);
  if(!cache.has(id))cache.set(id,Promise.resolve().then(()=>id===atual.id?atual:consultar(id)).then(nomeResponsavel).catch(()=>'Usuário não identificado'));
  return cache.get(id);
 };
 resultado.linhas=await Promise.all(resultado.linhas.map(async row=>{
  const id=String(row.responsavel||'');
  if(!uuid.test(id))return row;
  return {...row,responsavel_id:id,responsavel:await resolver(id)};
 }));
 return resultado;
}
