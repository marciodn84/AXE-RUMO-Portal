import {validarCampos} from './validacao-campos.js?v=20261030-imp34';
const el=(t,s)=>{const n=document.createElement(t);if(s!==undefined)n.textContent=s;return n;};
const money=(v,m)=>v==null?'Valor pendente':new Intl.NumberFormat('pt-BR',{style:'currency',currency:m}).format(v);
export function initParcelasSugeridas(api,root,onSaved){
 let dialog=null,busy=false,dirty=false;
 const guard=()=>!busy&&(!dirty||confirm('Há uma parcela em conferência. Deseja descartar esta revisão?'));
 const close=()=>{dialog?.close();dialog?.remove();dialog=null;dirty=false;};
 function button(text,fn){const b=el('button',text);b.type='button';b.onclick=async()=>{if(busy)return;b.disabled=true;try{await fn();}catch(e){const s=dialog?.querySelector('[role=status]');if(s)s.textContent=e.message;}finally{if(b.isConnected)b.disabled=false;}};return b;}
 function field(parent,label,type,value,choices){const l=el('label',label),i=el(choices?'select':'input');if(choices)for(const c of choices)i.append(new Option(c,c));else i.type=type;i.value=value??'';i.setAttribute('aria-label',label);l.append(i);parent.append(l);return i;}
 async function review(pedido,plano,index,existing){
  if(!guard())return;close();dialog=el('dialog');dialog.className='imp-picker';dialog.setAttribute('aria-label','Conferência da parcela sugerida');const local=dialog,base=plano.sugestao.linhas[index],status=el('p');status.setAttribute('role','status');
  dialog.append(el('h2','Conferir parcela — '+pedido.referencia),el('p','Origem: '+plano.contexto.fonte+' · '+plano.contexto.condicao),el('p','Trecho identificado: '+base.trecho),button('Fechar',()=>{if(guard())close();}),status);
  const form=el('form');form.onsubmit=e=>e.preventDefault();dialog.append(form);const grid=el('div');grid.className='import-mapping';form.append(grid);
  const ref=field(grid,'Identificação da parcela sugerida','text',base.referencia),modo=field(grid,'Definição do valor sugerido','text',base.modo,['Valor','Percentual']),valor=field(grid,'Valor da parcela sugerida','number',base.valor),pct=field(grid,'Percentual da parcela sugerida','number',base.percentual),marco=field(grid,'Marco da parcela sugerida','text',base.marco,['Pedido','Disponibilização / invoice','Coleta','Manual']),date=field(grid,'Data-base confirmada','date',base.data_base),dias=field(grid,'Dias após a data-base','number',base.dias),due=field(grid,'Vencimento manual confirmado','date',base.vencimento),invoice=field(grid,'Invoice vinculada à parcela','text','');
  ref.required=true;modo.required=true;marco.required=true;valor.required=true;valor.min='0.01';valor.step='0.01';pct.required=true;pct.min='0.000001';pct.max='100';pct.step='any';dias.required=true;dias.min='0';dias.max='3650';dias.step='1';const resumo=el('p');form.append(resumo);
  const aceite=field(form,'Conferi a origem, o valor e as datas pendentes desta parcela','checkbox','');aceite.checked=false;aceite.required=true;Object.assign(aceite.style,{width:'18px',minHeight:'0',height:'18px'});
  let checkExisting=null;if(existing.length){const box=el('section');box.append(el('h3','Parcelas já cadastradas'));for(const p of existing)box.append(el('p',p.referencia+' · '+money(p.valor,pedido.moeda)+' · '+(p.vencimento||'Sem data')+' · '+p.status));form.append(box);checkExisting=field(form,'Conferi as parcelas existentes e esta parcela não é duplicada','checkbox','');checkExisting.checked=false;checkExisting.required=true;Object.assign(checkExisting.style,{width:'18px',minHeight:'0',height:'18px'});}
  let pending=null;
  function refresh(){valor.disabled=modo.value==='Percentual';pct.disabled=modo.value!=='Percentual';due.disabled=marco.value!=='Manual';date.disabled=marco.value==='Manual';dias.disabled=marco.value==='Manual';let v=marco.value==='Manual'?due.value:date.value;if(v&&marco.value!=='Manual'){const d=new Date(v+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+Number(dias.value||0));v=d.toISOString().slice(0,10);}const amount=modo.value==='Percentual'?Math.round(Number(plano.contexto.total)*Number(pct.value||0))/100:Number(valor.value||0);resumo.textContent='Valor: '+money(amount,pedido.moeda)+' · Vencimento: '+(v||'Pendente — será necessário informar a data-base depois')+'. Nenhum pagamento será registrado.';}
  form.addEventListener('input',()=>{dirty=true;pending=null;refresh();});form.addEventListener('change',()=>{dirty=true;pending=null;refresh();});refresh();
  form.append(button('Aprovar e criar parcela',async()=>{
   refresh();if(!validarCampos(form))return;
   if(!pending)pending={acao:'plano_aprovar',id:plano.id,linha:index,requisicao_id:crypto.randomUUID(),confirmado:aceite.checked,conferiu_existentes:checkExisting?.checked||false,dados:{pedido_id:pedido.id,referencia:ref.value.trim(),modo:modo.value,valor:valor.value,percentual:pct.value,marco:marco.value,data_base:date.disabled?'':date.value,dias:dias.disabled?0:dias.value,vencimento:due.disabled?'':due.value,proforma:invoice.value.trim(),status:'Prevista',valor_pago:0}};
   busy=true;const controls=[...form.querySelectorAll('button,input,select')],states=controls.map(c=>c.disabled);controls.forEach(c=>c.disabled=true);try{await api(pending);if(dialog!==local)return;dirty=false;close();busy=false;await onSaved(pedido.id);}finally{busy=false;controls.forEach((c,i)=>{if(c.isConnected)c.disabled=states[i];});}
  }));dialog.addEventListener('cancel',e=>{e.preventDefault();if(guard())close();});root.append(dialog);dialog.showModal();
 }
 return {canLeave:guard,reset:close,async render(pedido,where,editar){
  where.replaceChildren(el('h3','Parcelas sugeridas para aprovação'));const status=el('p');status.setAttribute('role','status');where.append(status);status.textContent='Analisando condição de pagamento…';
  try{const r=await api({acao:editar?'plano_sugerir':'plano_contexto',pedido_id:pedido.id});if(!where.isConnected)return;status.textContent='';
   if(!r.contexto.condicao){status.textContent='Informe a condição de pagamento no pedido ou anexe e confirme um ACK com essa informação.';return;}
   where.append(el('p','Fonte: '+r.contexto.fonte+' · '+r.contexto.condicao));if(r.contexto.fonte==='ACK'&&r.contexto.condicao_pedido&&r.contexto.condicao_pedido.trim().toUpperCase()!==r.contexto.condicao.trim().toUpperCase())where.append(el('p','A condição do ACK difere da registrada no pedido. Confira a divergência antes de aprovar.'));
   const plano=r.plano||r.planos.find(p=>JSON.stringify(p.contexto)===JSON.stringify(r.contexto));if(!plano){status.textContent='Nenhuma sugestão preparada.';return;}
   for(const w of plano.sugestao.avisos)where.append(el('p',w));const table=el('table'),head=el('tr');['Parcela','Valor','Marco / dias','Pendências','Situação'].forEach(x=>head.append(el('th',x)));table.append(head);
   plano.sugestao.linhas.forEach((l,i)=>{const ac=plano.aceites.find(x=>x.linha===i),tr=el('tr');[l.referencia,money(l.valor,pedido.moeda),l.marco+' / '+l.dias+' dias',l.pendencias.join(' '),ac?'Aprovada':'Pendente de aprovação'].forEach(x=>tr.append(el('td',x)));const td=el('td');if(editar&&!ac)td.append(button('Conferir parcela '+(i+1),()=>review(pedido,plano,i,r.parcelas.filter(p=>p.status!=='Cancelada'))));tr.append(td);table.append(tr);});const scroll=el('div');scroll.className='scroll';scroll.append(table);where.append(scroll);
   if(r.planos.some(p=>p.id!==plano.id&&p.aceites.length))where.append(el('p','Há parcelas aprovadas em outra revisão. Elas foram preservadas; confira os registros antes de alterar a programação.'));
  }catch(e){if(where.isConnected)status.textContent=e.message;}
 }};
}
