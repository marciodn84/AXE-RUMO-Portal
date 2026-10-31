const el=(t,text,cls)=>{const n=document.createElement(t);if(text!=null)n.textContent=text;if(cls)n.className=cls;return n;};
const btn=(text,fn)=>{const b=el('button',text);b.type='button';b.onclick=fn;return b;};
export function indicadorSituacao(value){
 const names={APROVADO:'Aprovado',VALIDADO:'Validado',ATIVA:'Ativa',ATIVO:'Ativo',INATIVO:'Inativo',INATIVA:'Inativa',BLOQUEADO:'Bloqueado',PENDENTE:'Pendente',EM_AVALIACAO:'Em avaliação',RASCUNHO:'Rascunho',VALIDADA:'Validada',LIBERADO:'Liberado'};
 const key=String(value||'');const color=['APROVADO','VALIDADO','ATIVA','ATIVO','VALIDADA','LIBERADO'].includes(key)?'released':key==='BLOQUEADO'?'blocked':['PENDENTE','EM_AVALIACAO','RASCUNHO'].includes(key)?'pending':'inactive';
 const n=el('span',null,'client-commercial-status '+color),dot=el('span',null,'status-dot');dot.setAttribute('aria-hidden','true');n.append(dot,document.createTextNode(names[key]||key||'Não informado'));return n;
}
export function indicadorCadastro(r){const n=indicadorSituacao(r.bloqueado_comercial?'BLOQUEADO':r.ativo===false?'INATIVO':'LIBERADO');if(r.bloqueado_comercial)n.title=r.motivo_bloqueio||'Bloqueado';return n;}
export function controleCadastro(api,valido=()=>true){
 let modal=null;
 function fechar(){if(modal)modal.remove();modal=null;}
 function abrir(titulo,r){fechar();const d=el('dialog',null,'edit-dialog');modal=d;d.append(el('h2',titulo),el('p',r.razao_social||r.descricao_referencia||r.nome||'#'+r.id));document.body.append(d);return d;}
 async function historico(tipo,r,pg=0){const d=abrir('Histórico de bloqueios',r);d.append(btn('Fechar',fechar));d.showModal();try{const result=await api({acao:'cadastro_historico',tipo,id:r.id,pagina:pg});if(modal!==d||!valido())return;if(!result.linhas.length)d.append(el('p','Nenhum bloqueio ou desbloqueio registrado.'));for(const row of result.linhas){const a=el('article',null,'source-card');a.append(el('h3',row.acao==='BLOQUEAR'?'Bloqueado':'Desbloqueado'),el('p',new Date(row.criado_em).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'})),el('p','Motivo: '+(row.acao==='BLOQUEAR'?row.atual?.motivo_bloqueio:row.anterior?.motivo_bloqueio)),el('small','Usuário: '+row.usuario_id));d.append(a);}if(pg>0)d.append(btn('Anteriores',()=>historico(tipo,r,pg-1)));if((pg+1)*50<result.total)d.append(btn('Próximos',()=>historico(tipo,r,pg+1)));}catch(e){d.append(el('p',e.message,'error'));}}
 function alterar(tipo,r,atualizar){const bloqueado=Boolean(r.bloqueado_comercial),d=abrir((bloqueado?'Desbloquear ':'Bloquear ')+tipo,r),f=el('form');let motivo;
  if(bloqueado)f.append(el('p','Motivo do bloqueio: '+r.motivo_bloqueio));else{const label=el('label','Motivo do bloqueio');motivo=el('textarea');motivo.required=true;motivo.minLength=3;motivo.maxLength=1000;motivo.setAttribute('aria-label','Motivo do bloqueio');label.append(motivo);f.append(label);}
  f.append(el('p',tipo==='produto'?'O bloqueio impede novas compras, propostas e pedidos que incluam este produto.':'O bloqueio impede novos pedidos e processos de compra com este fornecedor.'));if(r.ativo===false)f.append(el('p','O cadastro permanecerá inativo após o desbloqueio.'));
  const error=el('p','','error'),actions=el('div',null,'form-actions'),save=el('button',bloqueado?'Desbloquear':'Bloquear');error.setAttribute('role','alert');save.type='submit';actions.append(btn('Cancelar',fechar),save);f.append(error,actions);d.append(f);d.showModal();
  f.onsubmit=async e=>{e.preventDefault();if(!f.reportValidity())return;const text=motivo?.value.trim()||'';if(!bloqueado&&text.length<3){error.textContent='Informe o motivo do bloqueio.';return;}save.disabled=true;try{await api({acao:'cadastro_bloqueio',tipo,id:r.id,bloquear:!bloqueado,motivo:text,atualizado_em:r.atualizado_em});if(modal!==d||!valido())return;fechar();await atualizar();}catch(e){error.textContent=e.message;}finally{save.disabled=false;}};
 }
 return {alterar,historico,reset:fechar};
}
