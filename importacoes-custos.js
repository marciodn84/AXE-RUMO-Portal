import {validarCampos} from './validacao-campos.js?v=20261029-aceite2';
import {initFechamentoDespachante} from './importacoes-fechamento.js?v=20261028-fech1';
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
 const fechamento=initFechamentoDespachante(api,v=>busy=v);
 const guard=()=>root.hidden||fechamento.canLeave()&&!busy&&(!dirty||confirm('Há custos não salvos. Deseja descartá-los?'));
 const change=()=>{dirty=true;pending=null;previewValid=false;};
 function btn(text,fn){const b=el('button',text);b.type='button';b.onclick=async()=>{if(busy)return;b.disabled=true;try{await fn();}catch(e){msg.textContent=e.message;msg.className='status error';}finally{if(b.isConnected)b.disabled=false;}};return b;}
 function field(p,k,label,v='',type='text',choices){
  const l=el('label',label),e=el(choices?'select':type==='textarea'?'textarea':'input');e.name=k;e.setAttribute('aria-label',label);
  if(choices)for(const x of choices){const [v,t]=Array.isArray(x)?x:[x,x];e.append(new Option(t,v));}else if(type!=='textarea')e.type=type;
  e.value=v??'';e.required=['valor','valor_me','categoria','moeda','tributo','tratamento'].includes(k);if(type==='number'){e.min=0;e.step='any';}l.append(e);p.append(l);return e;
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
  if(r.transporte_fonte){const t=r.transporte_fonte;out.append(el('p','Frete documental: '+t.valor+' USD × taxa DUIMP '+(t.cambio||'pendente')+' = '+money(t.valor_brl)+' · DUIMP '+(t.duimp_numero||'pendente')+' · registro '+(t.data_registro_duimp||'pendente')+' · '+(t.fonte_taxa||'Taxa ainda não confirmada')+'.'));}
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
  const g=epoch,e=current.embarque,saved=current.custo,base=saved?.dados||{pagamentos:[],despesas:[],tributos:[]},frete=current.transporte,d={...base,despesas:[...(base.despesas||[]).filter(x=>!x.origem_transporte),...(frete?[frete]:[])]};body.replaceChildren();msg.textContent='';
  const toolbar=el('div',undefined,'cadastro-toolbar');toolbar.append(btn('Voltar aos embarques',async()=>{if(!guard())return;dirty=false;pending=null;current=null;await list();}));
  if(opts.editar&&!editing&&saved?.estado!=='Final')toolbar.append(btn('Editar apuração',()=>render(true)));
  if(opts.editar&&saved?.estado==='Final')toolbar.append(btn('Reabrir custo com justificativa',async()=>{
   const motivo=prompt('Qual o motivo da revisão deste custo final?');if(!motivo?.trim())return;await api({acao:'custo_reabrir',embarque_id:e.id,versao:saved.versao,motivo,requisicao_id:crypto.randomUUID()});await open(e.id);
  }));
  toolbar.append(btn('Fechamentos do despachante',async()=>{if(dirty)throw Error('Salve a apuração provisória antes de anexar ou importar um fechamento.');await fechamento.open(e,saved,!!opts.editar&&saved?.estado!=='Final',async()=>{dirty=false;pending=null;await open(e.id);msg.textContent='Fechamento importado no custo provisório. Revise a memória e o tratamento dos créditos antes de finalizar.';});}));
  body.append(toolbar,el('h3',e.referencia+' · '+e.fornecedor),el('p','Moeda FOB: '+e.moeda+' · Embarque: '+e.status+' · Apuração: '+(saved?.estado||'Nova')));
  if(saved&&saved.resultado.embarque_fonte?.versao!==e.versao)body.append(el('p','O embarque foi alterado após esta apuração. Recalcule a prévia antes de finalizar.','status error'));
  if(frete)body.append(el('p','Frete documental: '+Number(frete.valor).toLocaleString('pt-BR')+' USD · '+money(frete.valor_brl)+' · taxa DUIMP '+(frete.cambio||'pendente')+'. Rateio pelo peso real bruto dos itens. Alterações devem ser feitas em Documentos de transporte, no embarque.'));
  if(current.financeiro){const fin=current.financeiro,pend=Math.max(0,Number(fin.fob)-Number(fin.pago_vinculado));body.append(el('p','Pagamento vinculado a este embarque: '+Number(fin.pago_vinculado).toLocaleString('pt-BR')+' '+e.moeda+' · FOB sem vínculo de pagamento aprovado: '+pend.toLocaleString('pt-BR')+' '+e.moeda+'. Este saldo de vínculo não significa uma nova cobrança.'));}
  const form=el('form');form.onsubmit=ev=>ev.preventDefault();form.addEventListener('input',change);form.addEventListener('change',change);body.append(form);
  const header=fields(grid(form,'Referências e projeção'),[['referencia','Referência do fechamento / documentos'],['cambio_estimado','Câmbio estimado para FOB ainda não pago (opcional)','number'],['observacoes','Observações','textarea']],d);
  form.append(el('p','O câmbio estimado só projeta valores ainda não pagos; a finalização exige os pagamentos e o câmbio efetivo completos. A taxa aduaneira não converte o custo FOB: informe os tributos já apurados em reais.'));
  const adders={};
  const items=[['','Selecionar item'],...e.itens.map(x=>[x.pedido_item_id,x.pedido+' / '+x.linha+' · '+x.descricao])],groups={};
  function collection(key,title,defs,defaults,extra){
   const box=el('fieldset');box.append(el('legend',title));const cards=el('div');box.append(cards);groups[key]=[];
   function add(x={}){
    const card=el('article',undefined,'imp-line'),f=fields(card,defs,{...defaults,...x}),row={id:x.id||crypto.randomUUID(),f,contrato_id:x.contrato_id||null,remessa_id:x.remessa_id||null,parcela_id:x.parcela_id||null,remessa_referencia:x.remessa_referencia||'',parcela_referencia:x.parcela_referencia||'',origem_fechamento:x.origem_fechamento||null,origem_transporte:x.origem_transporte||null};
    f.referencia.required=true;if(key!=='despesas')f.pedido_item_id.required=true;if(key==='pagamentos'){f.valor_me.min='0.01';f.valor_brl.min='0.01';}if(extra)extra(card,row,x);groups[key].push(row);cards.append(card);
    if(row.origem_transporte){for(const input of Object.values(f))input.disabled=true;card.append(el('p','Frete dos documentos de transporte; câmbio USD/BRL exclusivo da DUIMP '+(x.duimp_numero||'(pendente)')+'.'));}
    if(editing&&!row.origem_transporte)card.append(btn('Remover registro',()=>{groups[key]=groups[key].filter(z=>z!==row);card.remove();change();}));return f;
   }adders[key]=add;(d[key]||[]).forEach(add);
   if(editing)box.append(btn('Adicionar '+title.toLowerCase(),()=>{if(groups[key].length>=100)throw Error('Até 100 registros por seção.');const f=add();change();Object.values(f)[0].focus();}));form.append(box);
  }
  collection('pagamentos','Pagamentos FOB',[
   ['pedido_item_id','Item pago','text',items],['valor_me','Valor atribuído em '+e.moeda,'number'],['valor_brl','Valor efetivamente pago em BRL (manual)','number'],['referencia','Referência do pagamento / contrato'],['data_pagamento','Data do pagamento manual','date']
  ],{},(card,row,x)=>{
   const note=el('p');card.append(note);
   function update(){row.f.valor_brl.required=!row.contrato_id;row.f.data_pagamento.required=!row.contrato_id;row.f.valor_brl.disabled=!editing||!!row.contrato_id;row.f.data_pagamento.disabled=!editing||!!row.contrato_id;note.textContent=row.contrato_id?'Contrato vinculado: '+row.f.referencia.value+'. O servidor calcula o BRL proporcional ao débito efetivo, sem usar o saldo de comprovação.':'Pagamento manual: informe o valor real em BRL, a referência e a data. Cada valor deve ser atribuído uma única vez.';}
   if(row.remessa_id)card.append(el('p','SWIFT/remessa: '+(row.remessa_referencia||row.remessa_id)+' · Parcela: '+(row.parcela_referencia||row.parcela_id)+' · Liquidação da remessa: '+(x.data_pagamento||'não informada')+'. O saldo não liquidado do contrato não bloqueia este pagamento.'));
   if(editing){card.append(btn('Selecionar contrato cadastrado',()=>pickContract(c=>{row.remessa_id=null;row.parcela_id=null;row.contrato_id=c.id;row.f.referencia.value=c.referencia;row.f.valor_brl.value='';row.f.data_pagamento.value='';update();change();})),btn('Usar comprovante manual',()=>{row.remessa_id=null;row.parcela_id=null;row.contrato_id=null;update();change();}));}update();
  });
  if(editing)form.append(btn('Sugerir pagamentos já registrados',async()=>{
   const signature=rows=>JSON.stringify(rows.map(p=>[p.id,p.pedido_item_id,p.contrato_id||null,Number(p.valor_me)]).sort((a,b)=>String(a[0]).localeCompare(String(b[0]))));
   const before=groups.pagamentos.map(r=>({id:r.id,...read(r.f),contrato_id:r.contrato_id}));
   const fresh=await api({acao:'custo_detalhe',embarque_id:e.id});if(!valid(g))return;
   const stored=fresh.custo?.dados?.pagamentos||[];if(signature(before)!==signature(stored))throw Error('Salve ou descarte as alterações de pagamentos antes de complementar os vínculos.');
   const suggestion=fresh.sugestao_pagamentos;if(!suggestion)throw Error('Sugestão de pagamentos indisponível.');
   const additions=suggestion.pagamentos.filter(p=>!before.some(x=>x.id===p.id));
   if(!additions.length)throw Error(suggestion.avisos.join(' ')||'Nenhum pagamento disponível para sugerir.');
   const dialog=el('dialog',undefined,'imp-picker'),table=el('table'),head=el('tr');
   ['Item','Contrato','Parcela','Remessa / SWIFT','Data da remessa','Valor em '+e.moeda].forEach(t=>head.append(el('th',t)));table.append(head);
   for(const p of additions){const row=el('tr'),it=e.itens.find(x=>x.pedido_item_id===p.pedido_item_id);[it?it.pedido+' / '+it.linha:p.pedido_item_id,p.referencia,p.parcela_referencia||'—',p.remessa_referencia||'—',p.data_pagamento||'—',Number(p.valor_me).toFixed(2)].forEach(t=>row.append(el('td',t)));table.append(row);}
   const close=()=>{dialog.close();dialog.remove();dialogs.delete(dialog);};dialogs.add(dialog);root.append(dialog);
   dialog.append(el('h3','Conferir pagamentos sugeridos'),el('p',suggestion.criterio||''),el('p','Distribuição limitada ao saldo de cada remessa e parcela. Nenhum novo pagamento será criado. Ao salvar, os vínculos serão registrados na parcial, no embarque e no custo, sem consumir o mesmo saldo duas vezes.'),table);
   for(const a of suggestion.avisos)dialog.append(el('p',a));
   dialog.append(btn('Cancelar',close),btn('Aprovar vínculos na apuração',()=>{if(signature(groups.pagamentos.map(r=>({id:r.id,...read(r.f),contrato_id:r.contrato_id})))!==signature(before))throw Error('A apuração mudou. Refaça a sugestão.');additions.forEach(p=>adders.pagamentos(p));change();close();msg.textContent='Vínculos aprovados no formulário. Calcule a prévia e salve a apuração para registrar. Nenhum pagamento foi criado.';}));dialog.addEventListener('cancel',ev=>{ev.preventDefault();close();});dialog.showModal();
  }));
  collection('despesas','Despesas',[
   ['referencia','Referência da despesa / comprovante'],['categoria','Categoria','text',['Frete','Seguro','Taxas','Despachante','Despesas aduaneiras','Taxas bancárias','Outras','Multa']],['valor','Valor da despesa','number'],['moeda','Moeda da despesa','text',['BRL','USD','EUR','GBP','CAD','CNY','JPY','CHF']],['cambio','Taxa efetiva da despesa para BRL','number'],['situacao','Confirmação da despesa','text',['Prevista','Confirmada']],['data','Data da despesa','date'],['pedido_item_id','Produto penalizado (obrigatório para multa)','text',items]
  ],{moeda:'BRL',situacao:'Prevista',categoria:'Frete'},(card,row,x)=>{
   if(frete&&!row.origem_transporte){const label=el('label'),check=el('input');check.type='checkbox';check.checked=x.frete_adicional===true;check.setAttribute('aria-label','Este frete é adicional e não duplica o documento de transporte');label.append(check,el('span','Este frete é adicional e não duplica o documento de transporte'));card.append(label);row.adicional=check;row.f.justificativa_frete=field(card,'justificativa_frete','Justificativa e documento do frete adicional',x.justificativa_frete||'');const sync=()=>{const active=row.f.categoria.value==='Frete';label.hidden=!active;check.required=active;check.disabled=!editing||!active;row.f.justificativa_frete.closest('label').hidden=!active;row.f.justificativa_frete.required=active;};row.f.categoria.addEventListener('change',sync);sync();}
  });
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
  const collect=()=>({...read(header),...Object.fromEntries(Object.entries(groups).map(([k,rows])=>[k,rows.map(r=>({id:r.id,...read(r.f),...(k==='pagamentos'?{contrato_id:r.contrato_id,remessa_id:r.remessa_id,parcela_id:r.parcela_id,remessa_referencia:r.remessa_referencia,parcela_referencia:r.parcela_referencia}:{} ),...(r.origem_fechamento?{origem_fechamento:r.origem_fechamento}:{}),...(r.origem_transporte?{origem_transporte:r.origem_transporte}:{}),...(r.adicional?{frete_adicional:r.adicional.checked}:{})}))])),...Object.fromEntries(Object.entries(checks).map(([k,c])=>[k,c.checked]))});
  function syncRequired(finalizar=false){for(const row of groups.despesas){row.f.pedido_item_id.required=row.f.categoria.value==='Multa';row.f.data.required=finalizar&&row.f.situacao.value==='Confirmada';}for(const c of Object.values(checks))c.required=finalizar;}
  async function preview(){
   syncRequired();if(!validarCampos(form))return null;
   const payload=collect(),s=++seq;busy=true;const controls=[...root.querySelectorAll('input,select,textarea,button')],states=controls.map(x=>x.disabled);controls.forEach(x=>x.disabled=true);let r;try{r=await api({acao:'custo_prever',embarque_id:e.id,dados:payload});}finally{busy=false;if(valid(g))controls.forEach((x,i)=>x.disabled=states[i]);}
   if(!valid(g)||s!==seq)return null;calc=r;previewValid=true;result(r,out,'Provisório');msg.textContent='Prévia calculada. Nenhuma alteração foi gravada.';return r;
  }
  if(editing){
   form.append(btn('Calcular prévia e rateios',preview));
   async function save(finalizar){
    syncRequired(finalizar);if(!validarCampos(form))return;
    if(finalizar){const r=await preview();if(!r)return;if(!r.apto_finalizar)throw Error('Resolva as pendências da prévia antes de finalizar.');
     if(!confirm('Finalizar custo de '+money(r.custo_total)+' para '+e.referencia+'? Alterações posteriores exigirão reabertura com justificativa.'))return;
    }
    const payload={acao:'custo_salvar',embarque_id:e.id,versao:saved?.versao||null,finalizar,dados:collect()};
    if(!pending||pending.finalizar!==finalizar)pending={...payload,requisicao_id:crypto.randomUUID()};
    busy=true;const controls=[...root.querySelectorAll('input,select,textarea,button')],states=controls.map(x=>x.disabled);controls.forEach(x=>x.disabled=true);
    try{await api(pending);}finally{busy=false;if(valid(g))controls.forEach((x,i)=>x.disabled=states[i]);}
    if(!valid(g))return;dirty=false;pending=null;await open(e.id);msg.textContent=finalizar?'Custo finalizado. Memória e histórico preservados.':'Apuração provisória salva. Pagamentos conectados à parcial e ao embarque; saldos reservados sem duplicação.';msg.className='status';
   }
   form.append(btn('Salvar apuração provisória',()=>save(false)),btn('Finalizar custo',()=>save(true)));
  }else for(const x of form.querySelectorAll('input,select,textarea'))x.disabled=true;
  if(saved){
   const history=el('details');history.append(el('summary','Histórico do custo'));const container=el('div');history.append(btn('Consultar histórico do custo',async()=>{const r=await api({acao:'custo_historico',embarque_id:e.id});if(!valid(g)||current?.embarque.id!==e.id)return;container.replaceChildren();for(const x of r.linhas){const d=el('details');d.append(el('summary',new Date(x.criado_em).toLocaleString('pt-BR')+' · '+x.atual.estado),el('pre',JSON.stringify(x,null,2)));container.append(d);}}),container);body.append(history);
  }
 }
 window.addEventListener('beforeunload',e=>{if(!root.hidden&&(dirty||busy)){e.preventDefault();e.returnValue='';}});
 return {canLeave:guard,async show(v,id){epoch++;seq++;closeDialogs();root.hidden=!v;dirty=false;pending=null;current=null;calc=null;if(!v)return;const g=epoch;try{opts=await api({acao:'custo_opcoes'});if(valid(g)){if(id)await open(id);else await list();}}catch(e){if(valid(g))msg.textContent=e.message;}},reset(){fechamento.reset();epoch++;seq++;closeDialogs();root.hidden=true;dirty=false;pending=null;current=null;calc=null;opts={editar:false};body.replaceChildren();}};
}

