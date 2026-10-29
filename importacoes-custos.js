const el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
const money=v=>v==null?'Pendente':new Intl.NumberFormat('pt-BR',{style:'currency',currency:'BRL'}).format(Number(v));
export function csvCustos(r){
 const cell=v=>{let s=String(v??'');if(/^[=+@\-\t\r]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';};
 const headers=['Pedido','Linha','Descrição','Quantidade','FOB moeda','FOB pago BRL','FOB estimado BRL','Frete BRL','Outras despesas BRL','Multas BRL','Tributos BRL','Créditos BRL','Custo total BRL','Custo unitário BRL'];
 const num=(x,n=2)=>x==null?'PENDENTE':Number(x).toFixed(n).replace('.',',');
 return '\ufeff'+[headers,...r.itens.map(x=>[x.pedido,x.linha,x.descricao,num(x.quantidade,6),num(x.fob_me),num(x.fob_brl),num(x.fob_estimado),num(x.frete),num(x.demais),num(x.multa),num(x.tributos),num(x.credito),num(x.custo_total),num(x.custo_unitario,8)])].map(row=>row.map(cell).join(';')).join('\r\n');
}
export function initCustosImportacao(api,parent){
 const root=el('section',undefined,'imp-internacional imp-custos');root.hidden=true;parent.append(root);
 const msg=el('p','','status'),body=el('div');msg.setAttribute('role','status');root.append(el('h2','Custo real da importação'),el('p','Mercadoria pelo câmbio efetivamente pago, tributos aduaneiros por item e despesas rateadas. A comprovação cambial não interfere neste cálculo.','intro'),msg,body);
 let epoch=0,seq=0,page=0,search='',dirty=false,busy=false,pending=null,opts={editar:false},current=null,calc=null,previewValid=false;
 const dialogs=new Set(),valid=g=>g===epoch&&!root.hidden;
 const guard=()=>root.hidden||!busy&&(!dirty||confirm('Há custos não salvos. Deseja descartá-los?'));
 const change=()=>{dirty=true;pending=null;previewValid=false;};
 function btn(text,fn){const b=el('button',text);b.type='button';b.onclick=async()=>{if(busy)return;b.disabled=true;try{await fn();}catch(e){msg.textContent=e.message;msg.className='status error';}finally{if(b.isConnected)b.disabled=false;}};return b;}
 function field(p,k,label,v='',type='text',choices){
  const l=el('label',label),e=el(choices?'select':type==='textarea'?'textarea':'input');e.name=k;e.setAttribute('aria-label',label);
  if(choices)for(const x of choices){const [v,t]=Array.isArray(x)?x:[x,x];e.append(new Option(t,v));}else if(type!=='textarea')e.type=type;
  e.value=v??'';if(type==='number'){e.min=0;e.step='any';}l.append(e);p.append(l);return e;
 }
 const fields=(p,defs,d={})=>Object.fromEntries(defs.map(([k,l,t,c])=>[k,field(p,k,l,d[k],t||'text',c)]));
 const read=f=>Object.fromEntries(Object.entries(f).map(([k,e])=>[k,e.value.trim()]));
 function grid(form,title){const f=el('fieldset');f.append(el('legend',title));const g=el('div',undefined,'import-mapping');f.append(g);form.append(f);return g;}
 function closeDialogs(){for(const d of dialogs){d.close();d.remove();}dialogs.clear();}
 async function list(){
  const g=epoch,s=++seq;body.replaceChildren();msg.textContent='Consultando embarques…';
  const toolbar=el('div',undefined,'cadastro-toolbar'),q=field(toolbar,'busca','Buscar embarque',search,'search');toolbar.append(btn('Buscar',async()=>{page=0;search=q.value;await list();}));body.append(toolbar);
  const r=await api({acao:'custo_listar',pagina:page,busca:search});if(!valid(g)||s!==seq)return;const table=el('table'),head=el('tr');['Embarque','Fornecedor','Recebimento','Custo','Total BRL','Ação'].forEach(x=>head.append(el('th',x)));table.append(head);
  for(const x of r.linhas){const tr=el('tr');[x.referencia,x.fornecedor,x.status,x.estado||'Ainda não apurado',money(x.custo_total)].forEach(v=>tr.append(el('td',v)));const td=el('td');td.append(btn('Abrir custo',()=>open(x.id)));tr.append(td);table.append(tr);}
  const wrap=el('div',undefined,'scroll');wrap.append(table);body.append(wrap);if(!r.total)body.append(el('p','Cadastre um embarque com itens para iniciar a apuração do custo.'));
  const prev=btn('Anterior',async()=>{page--;await list();}),next=btn('Próxima',async()=>{page++;await list();});prev.disabled=page===0;next.disabled=(page+1)*30>=r.total;body.append(prev,el('span',' Página '+(page+1)+' · '+r.total+' embarque(s) '),next);msg.textContent='';
 }
 async function open(id){if(!guard())return;const g=epoch,s=++seq;const r=await api({acao:'custo_detalhe',embarque_id:id});if(!valid(g)||s!==seq)return;current=r;dirty=false;pending=null;calc=r.custo?.resultado||null;previewValid=false;render(!!opts.editar&&!r.custo);}
 async function pickContract(done){
  const g=epoch,dialog=el('dialog',undefined,'imp-picker'),out=el('div',undefined,'scroll'),status=el('p'),toolbar=el('div',undefined,'cadastro-toolbar'),q=el('input');q.type='search';q.setAttribute('aria-label','Buscar contrato para custo');let pagina=0;
  const close=()=>{dialog.close();dialog.remove();dialogs.delete(dialog);};dialogs.add(dialog);root.append(dialog);
  const prev=btn('Anterior',async()=>{pagina--;await load();}),next=btn('Próxima',async()=>{pagina++;await load();});toolbar.append(q,btn('Buscar',async()=>{pagina=0;await load();}),btn('Fechar',close));
  dialog.append(el('h3','Selecionar contrato efetivamente pago'),toolbar,status,out,prev,next);dialog.addEventListener('cancel',close);dialog.showModal();
  async function load(){try{const r=await api({acao:'fx_listar',tipo:'contratos',pagina,busca:q.value});if(!valid(g)||!dialog.open)return;out.replaceChildren();
   for(const x of r.linhas){const row=el('p');row.append(el('span',x.referencia+' · '+x.fornecedor+' · '+x.moeda+' '+x.valor+' '),btn('Selecionar',async()=>{try{if(x.status!=='Ativo'||String(x.fornecedor_id)!==String(current.embarque.fornecedor_id)||x.moeda!==current.embarque.moeda)throw Error('Use contrato ativo do mesmo fornecedor e moeda.');done(x);close();}catch(e){status.textContent=e.message;}}));out.append(row);}
   prev.disabled=pagina===0;next.disabled=(pagina+1)*30>=r.total;status.textContent=r.total+' contrato(s) · página '+(pagina+1);
  }catch(e){status.textContent=e.message;}}await load();
 }
 function result(r,out,estado){
  out.replaceChildren(el('h3',(estado==='Final'?'Custo final':'Custo calculado — provisório')+': '+money(r.custo_total)));
  if(r.pendencias.length){const ul=el('ul');r.pendencias.forEach(x=>ul.append(el('li',x)));out.append(el('p','Pendências para finalizar:'),ul);}else out.append(el('p','Conferências completas. Revise a memória antes de finalizar.'));
  const table=el('table'),head=el('tr');['Pedido / linha','Produto','Qtde','FOB pago BRL','FOB estimado','Frete','Demais','Multas','Tributos','Créditos considerados','Custo total','Custo unitário'].forEach(x=>head.append(el('th',x)));table.append(head);
  for(const x of r.itens){const tr=el('tr');[x.pedido+' / '+x.linha,x.descricao,x.quantidade,money(x.fob_brl),money(x.fob_estimado),money(x.frete),money(x.demais),money(x.multa),money(x.tributos),money(x.credito),money(x.custo_total),x.custo_unitario==null?'Pendente':Number(x.custo_unitario).toLocaleString('pt-BR',{minimumFractionDigits:2,maximumFractionDigits:8})].forEach(v=>tr.append(el('td',v)));table.append(tr);}
  const scroll=el('div',undefined,'scroll');scroll.append(table);out.append(scroll);
  out.append(el('p','Créditos pendentes, quando informados, participam apenas da projeção provisória. O custo unitário usa até 8 casas decimais; o total de cada item é preservado em centavos.'));
  const memory=el('details');memory.append(el('summary','Memória de rateio por despesa'));
  for(const x of r.rateios){const b=el('div');b.append(el('strong',x.referencia+' · '+x.criterio+' · '+money(x.valor_brl)));const ul=el('ul');for(const [id,v] of Object.entries(x.valores)){const it=r.itens.find(z=>z.pedido_item_id===id);ul.append(el('li',(it?it.pedido+' / '+it.linha:id)+': '+money(v)));}b.append(ul);memory.append(b);}out.append(memory);
  out.append(btn('Exportar custos para ajuste manual no Nomus',()=>{
   const url=URL.createObjectURL(new Blob([csvCustos(r)],{type:'text/csv;charset=utf-8'})),a=el('a');a.href=url;a.download=(estado==='Final'?'custo-final-':'custo-provisorio-')+current.embarque.referencia.replace(/[^a-zA-Z0-9_-]/g,'_')+'.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
  }));
 }
 function render(editing){
  const g=epoch,e=current.embarque,saved=current.custo,d=saved?.dados||{pagamentos:[],despesas:[],tributos:[]};body.replaceChildren();msg.textContent='';
  const toolbar=el('div',undefined,'cadastro-toolbar');toolbar.append(btn('Voltar aos embarques',async()=>{if(!guard())return;dirty=false;pending=null;current=null;await list();}));
  if(opts.editar&&!editing&&saved?.estado!=='Final')toolbar.append(btn('Editar apuração',()=>render(true)));
  if(opts.editar&&saved?.estado==='Final')toolbar.append(btn('Reabrir custo com justificativa',async()=>{
   const motivo=prompt('Qual o motivo da revisão deste custo final?');if(!motivo?.trim())return;await api({acao:'custo_reabrir',embarque_id:e.id,versao:saved.versao,motivo,requisicao_id:crypto.randomUUID()});await open(e.id);
  }));
  body.append(toolbar,el('h3',e.referencia+' · '+e.fornecedor),el('p','Moeda FOB: '+e.moeda+' · Embarque: '+e.status+' · Apuração: '+(saved?.estado||'Nova')));
  if(saved&&saved.resultado.embarque_fonte?.versao!==e.versao)body.append(el('p','O embarque foi alterado após esta apuração. Recalcule a prévia antes de finalizar.','status error'));
  const form=el('form');form.onsubmit=ev=>ev.preventDefault();form.addEventListener('input',change);form.addEventListener('change',change);body.append(form);
  const header=fields(grid(form,'Referências e projeção'),[['referencia','Referência do fechamento / documentos'],['cambio_estimado','Câmbio estimado para FOB ainda não pago (opcional)','number'],['observacoes','Observações','textarea']],d);
  form.append(el('p','O câmbio estimado só projeta valores ainda não pagos; a finalização exige os pagamentos e o câmbio efetivo completos. A taxa aduaneira não converte o custo FOB: informe os tributos já apurados em reais.'));
  const items=[['','Selecionar item'],...e.itens.map(x=>[x.pedido_item_id,x.pedido+' / '+x.linha+' · '+x.descricao])],groups={};
  function collection(key,title,defs,defaults,extra){
   const box=el('fieldset');box.append(el('legend',title));const cards=el('div');box.append(cards);groups[key]=[];
   function add(x={}){
    const card=el('article',undefined,'imp-line'),f=fields(card,defs,{...defaults,...x}),row={id:x.id||crypto.randomUUID(),f,contrato_id:x.contrato_id||null};
    if(extra)extra(card,row,x);groups[key].push(row);cards.append(card);
    if(editing)card.append(btn('Remover registro',()=>{groups[key]=groups[key].filter(z=>z!==row);card.remove();change();}));return f;
   }(d[key]||[]).forEach(add);
   if(editing)box.append(btn('Adicionar '+title.toLowerCase(),()=>{if(groups[key].length>=100)throw Error('Até 100 registros por seção.');const f=add();change();Object.values(f)[0].focus();}));form.append(box);
  }
  collection('pagamentos','Pagamentos FOB',[
   ['pedido_item_id','Item pago','text',items],['valor_me','Valor atribuído em '+e.moeda,'number'],['valor_brl','Valor efetivamente pago em BRL (manual)','number'],['referencia','Referência do pagamento / contrato'],['data_pagamento','Data do pagamento manual','date']
  ],{},(card,row,x)=>{
   const note=el('p');card.append(note);
   function update(){row.f.valor_brl.disabled=!editing||!!row.contrato_id;row.f.data_pagamento.disabled=!editing||!!row.contrato_id;note.textContent=row.contrato_id?'Contrato vinculado: '+row.f.referencia.value+'. O servidor calcula o BRL proporcional ao débito efetivo, sem usar o saldo de comprovação.':'Pagamento manual: informe o valor real em BRL, a referência e a data. Cada valor deve ser atribuído uma única vez.';}
   if(editing){card.append(btn('Selecionar contrato cadastrado',()=>pickContract(c=>{row.contrato_id=c.id;row.f.referencia.value=c.referencia;row.f.valor_brl.value='';row.f.data_pagamento.value='';update();change();})),btn('Usar comprovante manual',()=>{row.contrato_id=null;update();change();}));}update();
  });
  collection('despesas','Despesas',[
   ['referencia','Referência da despesa / comprovante'],['categoria','Categoria','text',['Frete','Seguro','Taxas','Despachante','Despesas aduaneiras','Taxas bancárias','Outras','Multa']],['valor','Valor da despesa','number'],['moeda','Moeda da despesa','text',['BRL','USD','EUR','GBP','CAD','CNY','JPY','CHF']],['cambio','Taxa efetiva da despesa para BRL','number'],['situacao','Confirmação da despesa','text',['Prevista','Confirmada']],['data','Data da despesa','date'],['pedido_item_id','Produto penalizado (obrigatório para multa)','text',items]
  ],{moeda:'BRL',situacao:'Prevista',categoria:'Frete'});
  collection('tributos','Tributos e créditos',[
   ['pedido_item_id','Item tributado','text',items],['tributo','Tributo','text',['II','IPI','ICMS','PIS','COFINS','IBS','CBS','Outros']],['valor','Valor aduaneiro do tributo em BRL','number'],['credito','Crédito informado em BRL','number'],['tratamento','Tratamento do crédito','text',['Pendente','Sem crédito','Crédito validado']],['referencia','Documento / referência do tributo'],['regra_contabilidade','Regra aprovada pela contabilidade / referência']
  ],{credito:0,tratamento:'Pendente'});
  const confirms=grid(form,'Conferências para finalizar'),checks={};
  for(const [k,label] of [['despesas_conferidas','Todas as despesas foram conferidas, sem duplicar adiantamentos ou devoluções'],['tributos_conferidos','Tributos conferidos com os documentos aduaneiros'],['creditos_conferidos','Tratamento dos créditos conferido conforme regras aprovadas com a contabilidade']]){
   const l=el('label'),c=el('input');c.type='checkbox';c.checked=d[k]===true;c.setAttribute('aria-label',label);l.append(c,el('span',label));confirms.append(l);checks[k]=c;
  }
  form.append(el('p','Este módulo não movimenta estoque nem atualiza o Nomus. Os tributos e créditos são informados conforme os documentos e a régua da contabilidade; não há cálculo automático de incidência tributária.'));
  const out=el('section',undefined,'imp-custo-resultado');body.append(out);
  if(calc)result(calc,out,saved?.estado);
  const collect=()=>({...read(header),...Object.fromEntries(Object.entries(groups).map(([k,rows])=>[k,rows.map(r=>({id:r.id,...read(r.f),...(k==='pagamentos'?{contrato_id:r.contrato_id}:{} )}))])),...Object.fromEntries(Object.entries(checks).map(([k,c])=>[k,c.checked]))});
  async function preview(){
   if(!form.reportValidity())return null;
   const payload=collect(),s=++seq;busy=true;const controls=[...root.querySelectorAll('input,select,textarea,button')],states=controls.map(x=>x.disabled);controls.forEach(x=>x.disabled=true);let r;try{r=await api({acao:'custo_prever',embarque_id:e.id,dados:payload});}finally{busy=false;if(valid(g))controls.forEach((x,i)=>x.disabled=states[i]);}
   if(!valid(g)||s!==seq)return null;calc=r;previewValid=true;result(r,out,'Provisório');msg.textContent='Prévia calculada. Nenhuma alteração foi gravada.';return r;
  }
  if(editing){
   form.append(btn('Calcular prévia e rateios',preview));
   async function save(finalizar){
    if(!form.reportValidity())return;
    if(finalizar){const r=await preview();if(!r)return;if(!r.apto_finalizar)throw Error('Resolva as pendências da prévia antes de finalizar.');
     if(!confirm('Finalizar custo de '+money(r.custo_total)+' para '+e.referencia+'? Alterações posteriores exigirão reabertura com justificativa.'))return;
    }
    const payload={acao:'custo_salvar',embarque_id:e.id,versao:saved?.versao||null,finalizar,dados:collect()};
    if(!pending||pending.finalizar!==finalizar)pending={...payload,requisicao_id:crypto.randomUUID()};
    busy=true;const controls=[...root.querySelectorAll('input,select,textarea,button')],states=controls.map(x=>x.disabled);controls.forEach(x=>x.disabled=true);
    try{await api(pending);}finally{busy=false;if(valid(g))controls.forEach((x,i)=>x.disabled=states[i]);}
    if(!valid(g))return;dirty=false;pending=null;await open(e.id);msg.textContent=finalizar?'Custo finalizado. Memória e histórico preservados.':'Apuração provisória salva. Saldos de pagamentos reservados.';msg.className='status';
   }
   form.append(btn('Salvar apuração provisória',()=>save(false)),btn('Finalizar custo',()=>save(true)));
  }else for(const x of form.querySelectorAll('input,select,textarea'))x.disabled=true;
  if(saved){
   const history=el('details');history.append(el('summary','Histórico do custo'));const container=el('div');history.append(btn('Consultar histórico do custo',async()=>{const r=await api({acao:'custo_historico',embarque_id:e.id});if(!valid(g)||current?.embarque.id!==e.id)return;container.replaceChildren();for(const x of r.linhas){const d=el('details');d.append(el('summary',new Date(x.criado_em).toLocaleString('pt-BR')+' · '+x.atual.estado),el('pre',JSON.stringify(x,null,2)));container.append(d);}}),container);body.append(history);
  }
 }
 window.addEventListener('beforeunload',e=>{if(!root.hidden&&(dirty||busy)){e.preventDefault();e.returnValue='';}});
 return {canLeave:guard,async show(v,id){epoch++;seq++;closeDialogs();root.hidden=!v;dirty=false;pending=null;current=null;calc=null;if(!v)return;const g=epoch;try{opts=await api({acao:'custo_opcoes'});if(valid(g)){if(id)await open(id);else await list();}}catch(e){if(valid(g))msg.textContent=e.message;}},reset(){epoch++;seq++;closeDialogs();root.hidden=true;dirty=false;pending=null;current=null;calc=null;opts={editar:false};body.replaceChildren();}};
}
