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
  const tables:Record<string,string>={clientes:'portal_clientes',produtos:'portal_produtos',pedidos:'portal_pedidos',precos:'portal_precos',regras:'portal_regras',resolver:'portal_pendencias_produtos'};
  if(b.acao==='listar'){
   if(!tables[b.secao]||!Number.isSafeInteger(b.pagina??0)||(b.pagina??0)<0||(b.pagina??0)>10000)return reply({erro:'Consulta inválida'},400);
   const params:Record<string,string>={select:'*',order:b.secao==='precos'?'data_negocio.desc.nullslast,id.desc':'id.asc',limit:'50',offset:String((b.pagina??0)*50)};
   const search=String(b.busca||'').slice(0,100).replace(/[%*]/g,'');if(search)params.termos_busca='ilike.*'+search+'*';
   if(b.cliente_id!==undefined){if(!positive(b.cliente_id)||!['pedidos','precos','regras'].includes(b.secao))return reply({erro:'Filtro inválido'},400);params.cliente_id='eq.'+b.cliente_id;}
   if(b.produto_id!==undefined){if(!positive(b.produto_id)||b.secao!=='produtos')return reply({erro:'Produto inválido'},400);params.id='eq.'+b.produto_id;}
   if(b.secao==='resolver'&&b.historico===true)params.order='registrado_em.desc,id.desc';
   if(b.status&&b.secao==='regras'&&['RASCUNHO','ATIVA','INATIVA'].includes(b.status))params.status='eq.'+b.status;
   if(b.secao==='pedidos'&&b.status!==undefined&&b.status!==''){
    const statuses:Record<string,string[]>={AGUARDANDO_ACEITE:['AGUARDANDO_ACEITE','Sem resposta','Aguardando aceite'],ACEITO:['ACEITO','Aceito Fornecedor','Aceito'],CORRECAO_SOLICITADA:['CORRECAO_SOLICITADA','Devolucao Portal','Correção solicitada'],RECUSADO:['RECUSADO','Recusado'],CANCELADO:['CANCELADO','CANCELADO_PDF_SEM_PRODUTOS','ITEM_EXCLUIDO_PDF','Cancelado'],ENTREGUE:['ENTREGUE','Entregue']};
    if(typeof b.status!=='string'||(!Object.hasOwn(statuses,b.status)&&b.status!=='NAO_INFORMADO'))return reply({erro:'Status inválido'},400);
    if(b.status==='NAO_INFORMADO')params.or='(fase_status_sap.eq.STATUS_AUSENTE,and(or(fase_status_sap.is.null,fase_status_sap.eq.""),or(status_texto.is.null,status_texto.eq."")))';
    else{const values='('+statuses[b.status].map(x=>'"'+x+'"').join(',')+')';params.or='(fase_status_sap.in.'+values+',and(or(fase_status_sap.is.null,fase_status_sap.eq.""),status_texto.in.'+values+'))';}
   }
   if(b.secao==='resolver'&&b.campo){if(!['descricao_referencia','unidade_referencia','ncm_referencia','identificador'].includes(b.campo))return reply({erro:'Campo inválido'},400);params.campo='eq.'+b.campo;}
   const table=b.secao==='resolver'&&b.historico===true?'portal_escolhas_produtos_historico':b.secao==='precos'&&b.incluir_versoes!==true?'portal_precos_atuais':tables[b.secao];
   const result=await query(table,params);return reply({ok:true,...result,pagina:b.pagina??0,tamanho:50});
  }
  if(b.acao==='opcoes'){
   const q=String(b.busca||'').slice(0,80).replace(/[%*]/g,'');const p:Record<string,string>={select:'id,descricao_referencia,status_validacao',order:'id.asc',limit:'200'};if(q)p.descricao_referencia='ilike.*'+q+'*';
   const cp:Record<string,string>={select:'id,nome,codigo_externo,cnpj',order:'nome.asc',limit:'200'};const cq=String(b.cliente_busca||'').slice(0,80).replace(/[%*]/g,'');if(cq)cp.termos_busca='ilike.*'+cq+'*';
   return reply({ok:true,clientes:await query('portal_clientes',cp),produtos:await query('produtos_conciliacao',p)});
  }
  if(b.acao==='detalhes'){
   if(!positive(b.id)||!['cliente','produto'].includes(b.tipo))return reply({erro:'Registro inválido'},400);
   if(b.tipo==='cliente')return reply({ok:true,locais:await query('clientes_locais',{select:'*',cliente_id:'eq.'+b.id,...(b.historico===true?{}:{vigente:'eq.true',excluido_em:'is.null'}),order:'id.desc',limit:'50',offset:String((Number(b.pagina)||0)*50)}),cobrancas:await query('clientes_cobrancas_documentais',{select:'*',cliente_id:'eq.'+b.id,order:'observado_em.desc',limit:'50',offset:String((Number(b.pagina)||0)*50)})});
   return reply({ok:true,identificadores:await query('produtos_identificadores',{select:'*',produto_id:'eq.'+b.id,status_validacao:'neq.INATIVO',order:'id.asc',limit:'50',offset:String((Number(b.pagina)||0)*50)}),observacoes:await query('produtos_observacoes',{select:'id,cliente_id,contexto,codigo,descricao,unidade,ncm,situacao_vinculo,observado_em,extracao_pdf_id,documento_id',produto_id:'eq.'+b.id,order:'observado_em.desc',limit:'50',offset:String((Number(b.pagina)||0)*50)})});
  }
  if(b.acao==='excluir_local'){
   if(!positive(b.id)||!positive(b.cliente_id))return reply({erro:'Endereço inválido'},400);
   return await rpc('axe_portal_excluir_local',{p_id:b.id,p_cliente:b.cliente_id,p_usuario:user.id});
  }
  if(b.acao==='bloqueio_comercial'){
   if(!positive(b.id)||typeof b.bloquear!=='boolean'||typeof b.atualizado_em!=='string')return reply({erro:'Dados de bloqueio inválidos'},400);
   return await rpc('axe_cliente_bloqueio',{p_cliente:b.id,p_bloquear:b.bloquear,p_motivo:String(b.motivo||'').slice(0,1000),p_usuario:user.id,p_versao:b.atualizado_em});
  }
  if(b.acao==='historico_bloqueio'){
   if(!positive(b.id))return reply({erro:'Cliente inválido'},400);
   return reply({ok:true,...await query('cadastros_decisoes',{select:'id,acao,anterior,atual,usuario_id,criado_em',entidade:'eq.CLIENTE_COMERCIAL',referencia:'eq.'+b.id,order:'id.desc',limit:'50',offset:String((Number(b.pagina)||0)*50)})});
  }
  if(b.acao==='salvar'){
   if(!['cliente','local','produto','identificador','regra','inativar_regra'].includes(b.tipo)||!b.dados||typeof b.dados!=='object'||Array.isArray(b.dados))return reply({erro:'Operação inválida'},400);
   if(b.tipo==='inativar_regra'&&b.confirmacao!=='CONFIRMAR')return reply({erro:'Confirme a inativação'},400);
   return await rpc('axe_portal_salvar',{p_acao:b.tipo,p_dados:b.dados,p_usuario:user.id});
  }
  if(b.acao==='validar_identificador'){
   if(!positive(b.id)||b.confirmacao!=='CONFIRMAR'||String(b.justificativa||'').trim().length<5)return reply({erro:'Confirmação e justificativa exigidas'},400);
   return await rpc('axe_validar_identificador_produto',{p_identificador:b.id,p_usuario:user.id,p_justificativa:String(b.justificativa).slice(0,1500)});
  }
  if(b.acao==='ativar_regra'){
   if(!positive(b.id)||b.confirmacao!=='CONFIRMAR'||String(b.fonte||'').trim().length<5)return reply({erro:'Confirmação e fonte fiscal exigidas'},400);
   return await rpc('axe_ativar_regra_fiscal',{p_regra:b.id,p_usuario:user.id,p_fonte:String(b.fonte).slice(0,2000)});
  }
  if(b.acao==='conferir'){
   if(!positive(b.id))return reply({erro:'Condição inválida'},400);return await rpc('axe_conferir_regra_fiscal',{p_condicao:b.id});
  }
  if(b.acao==='escolher_produto'){
   if(typeof b.chave!=='string'||b.chave.length>120||!/^([a-f0-9]{32})$/.test(b.versao||'')||typeof b.opcao!=='string'||b.opcao.length>64||!/^[a-f0-9-]{36}$/i.test(b.requisicao_id||''))return reply({erro:'Escolha inválida'},400);
   return await rpc('axe_portal_escolher_produto',{p_chave:b.chave,p_versao:b.versao,p_opcao:b.opcao,p_requisicao:b.requisicao_id,p_usuario:user.id});
  }
  return reply({erro:'Operação não permitida'},400);
 }catch(e){return reply({erro:e instanceof Error&&e.message==='LIMIT'?'Formulário excede o tamanho permitido':'Não foi possível concluir. Verifique os dados ou tente atualizar a tela.'},400);}
});

