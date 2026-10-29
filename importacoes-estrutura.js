import {initConciliacaoCambio} from './importacoes-cambio.js?v=20261028-cambio1';
const node=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
const moedas=['BRL','USD','EUR','GBP','CAD','CNY','JPY','CHF'];
const etapasPedido=['Rascunho','Emitido','ACK recebido','Cancelado'];
const etapasEmbarque=['Planejamento','Aguardando consolidação','Aguardando coleta','Em trânsito','Em desembaraço','Recebido','Cancelado'];
const money=(v,c)=>new Intl.NumberFormat('pt-BR',{style:'currency',currency:c||'USD'}).format(Number(v||0));
const dt=v=>v?String(v).slice(0,10).split('-').reverse().join('/'):'Sem data';
export function vencimentoParcela(data,dias){if(!data)return '';const d=new Date(data+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+Number(dias||0));return d.toISOString().slice(0,10);}
export function initEstruturaImportacao(api,legacy){
 const root=node('section',undefined,'cadastro-screen imp-internacional imp-estrutura');root.hidden=true;
 document.getElementById('cadastrosRoot').append(root);
 let tipo='pedidos',page=0,epoch=0,seq=0,dirty=false,pending=null,current=null,opts={editar:false,fornecedores:[]},busy=false;
 const dialogs=new Set(),nav=node('div',undefined,'catalog-tabs'),body=node('div'),msg=node('p','','status');
 msg.setAttribute('role','status');
 const guard=()=>!busy&&fx.canLeave()&&(!dirty||confirm('Há alterações não salvas. Deseja descartá-las?'));
 const changed=()=>{dirty=true;pending=null;};
 const check=g=>g===epoch&&!root.hidden;
 function button(text,fn){const b=node('button',text);b.type='button';b.onclick=async()=>{if(busy)return;b.disabled=true;try{await fn();}catch(e){msg.textContent=e.message;msg.className='status error';}finally{if(b.isConnected)b.disabled=false;}};return b;}
 function field(parent,key,label,value='',type='text',choices){
  const l=node('label',label),e=node(choices?'select':type==='textarea'?'textarea':'input');
  if(choices){for(const x of choices){const [v,t]=Array.isArray(x)?x:[x,x];e.append(new Option(t,v));}}else if(type!=='textarea')e.type=type;
  e.value=value??'';e.name=key;e.setAttribute('aria-label',label);
  if(type==='number'){e.step='any';e.min='0';}
  l.append(e);parent.append(l);return e;
 }
 const suppliers=()=>[['','Selecionar fornecedor'],...opts.fornecedores.map(x=>[String(x.id),x.nome])];
 const fields=(parent,defs,data={})=>Object.fromEntries(defs.map(([k,l,t,c])=>[k,field(parent,k,l,data[k],t||'text',c)]));
 const read=inputs=>Object.fromEntries(Object.entries(inputs).map(([k,e])=>[k,e.value.trim()]));
 function grid(parent,title){const box=node('fieldset');box.append(node('legend',title));const g=node('div',undefined,'import-mapping');box.append(g);parent.append(box);return g;}
 function renderNav(){nav.replaceChildren();for(const [key,label] of [['pedidos','Pedidos de compra'],['parcelas','Parcelas'],['embarques','Embarques'],['cambio','Conciliação cambial'],['anteriores','Registros anteriores']]){
  const b=button(label,async()=>{if(!guard()||!legacy.canLeave())return;dirty=false;pending=null;current=null;closeDialogs();await legacy.show(false);await fx.show(false);tipo=key;page=0;epoch++;renderNav();if(key==='cambio'){body.replaceChildren();msg.textContent='';await fx.show(true);}else if(key==='anteriores'){body.replaceChildren(node('p','Registros da primeira versão, preservados com seu histórico. Eles não reservam quantidades na nova estrutura.'));await legacy.show(true);}else await list();});b.setAttribute('aria-pressed',String(tipo===key));nav.append(b);
 }}
 root.append(node('p','Pedidos, condições de pagamento e embarques parciais ou consolidados.','intro'),nav,msg,body);
 const fx=initConciliacaoCambio(api,root);
 let searchValue='';
 async function list(){
  const g=epoch,s=++seq;body.replaceChildren();msg.textContent='Consultando…';
  const tools=node('div',undefined,'cadastro-toolbar'),search=field(tools,'busca','Buscar por referência',searchValue,'search');
  tools.append(button('Buscar',async()=>{searchValue=search.value;page=0;await list();}));
  if(opts.editar)tools.append(button(tipo==='pedidos'?'Novo pedido':tipo==='parcelas'?'Nova parcela':'Novo embarque',async()=>{
   if(tipo==='parcelas')await pickOrder(p=>edit(null,p));else edit(null);
  }));
  const rows=node('div',undefined,'scroll'),pagination=node('div',undefined,'cadastro-toolbar');body.append(tools,rows,pagination);
  const r=await api({acao:'v2_listar',tipo,pagina:page,busca:searchValue});
  if(!check(g)||s!==seq)return;
  const table=node('table'),head=node('tr');
  const titles=tipo==='pedidos'?['Pedido','Fornecedor','Situação','FOB','Programado / pago','Ação']:tipo==='parcelas'?['Parcela / pedido','Vencimento','Valor','Pago / saldo','Situação','Ação']:['Embarque','Fornecedor','Situação','FOB','Coleta prevista','Ação'];
  titles.forEach(t=>head.append(node('th',t)));table.append(head);
  for(const x of r.linhas){
   let vals;if(tipo==='pedidos')vals=[x.referencia,x.fornecedor,x.status,money(x.total,x.moeda),money(x.parcelado,x.moeda)+' / '+money(x.pago,x.moeda)];
   else if(tipo==='parcelas')vals=[x.referencia+' · '+x.pedido,dt(x.vencimento),money(x.valor,x.moeda),money(x.valor_pago,x.moeda)+' / '+money(Number(x.valor)-Number(x.valor_pago),x.moeda),situacaoParcela(x)];
   else vals=[x.referencia,x.fornecedor,x.status,money(x.total,x.moeda),dt(x.dados.previsao_coleta)];
   const tr=node('tr');vals.forEach(v=>tr.append(node('td',v)));const action=node('td');action.append(button('Abrir',()=>open(x.id)));tr.append(action);table.append(tr);
  }
  rows.append(table);if(!r.total)rows.append(node('p','Nenhum registro encontrado.'));
  const prev=button('Anterior',async()=>{page--;await list();}),next=button('Próxima',async()=>{page++;await list();});prev.disabled=page===0;next.disabled=(page+1)*30>=r.total;
  pagination.append(prev,node('span','Página '+(page+1)+' · '+r.total+' registro(s)'),next);msg.textContent='';
 }
 function situacaoParcela(x){if(x.status==='Cancelada')return 'Cancelada';if(Number(x.valor_pago)>=Number(x.valor))return 'Paga';if(Number(x.valor_pago)>0)return 'Paga parcialmente';if(!x.vencimento)return 'Aguardando data-base';return x.vencimento<new Date().toLocaleDateString('en-CA',{timeZone:'America/Sao_Paulo'})?'Vencida':'A pagar';}
 async function open(id){if(!guard())return;const g=epoch,s=++seq;const d=await api({acao:'v2_detalhe',tipo,id});if(!check(g)||s!==seq)return;current=d;dirty=false;pending=null;edit(d,null,false);}
 function closeDialogs(){for(const d of dialogs){d.close();d.remove();}dialogs.clear();}
 async function picker(title,loader,columns,onPick){
  const dialog=node('dialog',undefined,'imp-picker'),heading=node('h2',title),status=node('p'),q=node('input');q.type='search';q.placeholder='Buscar';q.setAttribute('aria-label','Buscar no seletor');
  const rows=node('div',undefined,'scroll'),bar=node('div',undefined,'cadastro-toolbar');let pagina=0,request=0;const g=epoch;
  const close=()=>{dialog.close();dialog.remove();dialogs.delete(dialog);};
  dialog.addEventListener('cancel',close);dialogs.add(dialog);root.append(dialog);
  const previous=button('Anterior',async()=>{pagina--;await load();}),next=button('Próxima',async()=>{pagina++;await load();});
  bar.append(q,button('Buscar',async()=>{pagina=0;await load();}),button('Fechar',close));dialog.append(heading,bar,status,rows,previous,next);dialog.showModal();
  async function load(){const s=++request;status.textContent='Consultando…';try{
   const r=await loader(pagina,q.value);if(!check(g)||!dialog.open||s!==request)return;rows.replaceChildren();
   const table=node('table');for(const x of r.linhas){const tr=node('tr');columns(x).forEach(v=>tr.append(node('td',v)));const td=node('td');td.append(button('Selecionar',async()=>{try{await onPick(x);close();}catch(e){status.textContent=e.message;}}));tr.append(td);table.append(tr);}
   rows.append(table);status.textContent=r.total+' registro(s) · página '+(pagina+1);previous.disabled=pagina===0;next.disabled=(pagina+1)*30>=r.total;
  }catch(e){status.textContent=e.message;}}
  await load();
 }
 async function pickOrder(done){const g=epoch;await picker('Selecionar pedido', (pagina,busca)=>api({acao:'v2_listar',tipo:'pedidos',pagina,busca}),x=>[x.referencia,x.fornecedor,money(x.total,x.moeda),x.status],async x=>{
  if(x.status==='Cancelado')throw Error('Selecione um pedido ativo.');
  const p=await api({acao:'v2_detalhe',tipo:'pedidos',id:x.id});if(check(g))done(p);
 });}
 function edit(item,order=null,editing=true){
  current=item;body.replaceChildren();msg.textContent='';const g=epoch,t=tipo;
  const top=node('div',undefined,'cadastro-toolbar');top.append(button('Voltar à lista',async()=>{if(!guard())return;dirty=false;pending=null;current=null;await list();}));
  if(!editing&&opts.editar)top.append(button('Editar',()=>edit(item,order,true)));
  body.append(top,node('h2',(item?item.referencia:tipo==='pedidos'?'Novo pedido':tipo==='parcelas'?'Nova parcela':'Novo embarque')));
  const form=node('form');form.onsubmit=e=>e.preventDefault();form.addEventListener('input',changed);form.addEventListener('change',changed);body.append(form);
  let collect,summary=()=>{};
  const info=node('div',undefined,'planned-card');
  if(tipo==='pedidos'){
   const general=fields(grid(form,'Pedido e confirmação do fornecedor'),[
    ['referencia','Número do pedido'],['fornecedor_id','Fornecedor','text',suppliers()],['moeda','Moeda','text',moedas],['status','Situação','text',etapasPedido],
    ['data_pedido','Data do pedido','date'],['ack_numero','Número do ACK'],['ack_data','Data do ACK','date'],['observacoes','Observações','textarea']
   ],item||{status:'Rascunho',moeda:'USD'});
   const section=node('fieldset');section.append(node('legend','Itens do pedido'));const cards=node('div');section.append(cards);form.append(section);
   let lines=[];
   function add(x={}){
    const card=node('article',undefined,'imp-line');card.append(node('h3','Linha do pedido'));
    const inputs=fields(card,[
     ['linha','Linha'],['codigo_axe','Código AXE'],['codigo_fornecedor','Código do fornecedor / part number'],['descricao','Descrição técnica'],['unidade','Unidade'],
     ['quantidade','Quantidade pedida','number'],['valor_unitario','Preço unitário FOB','number'],['peso_bruto_unitario','Peso bruto unitário (kg)','number'],
     ['disponibilizada','Quantidade disponibilizada acumulada','number'],['data_disponibilidade','Data da disponibilidade','date']
    ],{linha:'',quantidade:1,valor_unitario:0,disponibilizada:0,...x});
    const line={id:x.id||crypto.randomUUID(),inputs,card};lines.push(line);
    if(x.reservada!==undefined)card.append(node('p','Reservada em embarques: '+x.reservada+' · Recebida: '+x.recebida));
    if(editing)card.append(button('Remover item',()=>{lines=lines.filter(l=>l!==line);card.remove();changed();summary();}));
    cards.append(card);return inputs;
   }
   (item?.itens||[]).forEach(add);
   if(editing)section.append(button('Adicionar item',()=>{if(lines.length>=100)throw Error('Até 100 itens por pedido.');const f=add();changed();f.linha.focus();}));
   collect=()=>({...read(general),itens:lines.map(l=>({id:l.id,...read(l.inputs)}))});
   summary=()=>{const d=collect(),total=d.itens.reduce((s,x)=>s+Number(x.quantidade||0)*Number(x.valor_unitario||0),0),parcelado=(item?.parcelas||[]).filter(p=>p.status!=='Cancelada').reduce((s,x)=>s+Number(x.valor),0);
    info.replaceChildren(node('h3','FOB do pedido: '+money(total,d.moeda)),node('p','Parcelas programadas: '+money(parcelado,d.moeda)+' · Valor ainda sem programação: '+money(total-parcelado,d.moeda)),node('p','Parcelas por percentual mantêm o valor confirmado ao salvar; revise a programação após alterar o pedido. Disponibilidade acumulada inclui as quantidades já liberadas para embarques anteriores. Pesos em kg; nenhum prazo é preenchido automaticamente.'));
   };
   if(item&&!editing){
    const box=node('section');box.append(node('h3','Parcelas deste pedido'));
    for(const p of item.parcelas||[]){box.append(node('p',p.referencia+' · '+money(p.valor,item.moeda)+' · '+dt(p.vencimento)+' · '+situacaoParcela(p)),button('Abrir parcela',()=>{tipo='parcelas';renderNav();return open(p.id);}));}
    if(opts.editar)box.append(button('Adicionar parcela deste pedido',()=>{tipo='parcelas';renderNav();dirty=false;pending=null;edit(null,item);}));body.append(box);
   }
  }else if(tipo==='parcelas'){
   const p=order||item;
   form.append(node('p','Pedido: '+(p?.pedido||p?.referencia||'')+' · Moeda: '+p?.moeda));
   const f=fields(grid(form,'Condição da parcela'),[
    ['referencia','Identificação da parcela'],['modo','Definição do valor','text',['Valor','Percentual']],['valor','Valor da parcela','number'],['percentual','Percentual do pedido','number'],
    ['marco','Marco para vencimento','text',['Pedido','Disponibilização / invoice','Coleta','Manual']],['proforma','Proforma / invoice de pagamento'],
    ['data_base','Data-base informada','date'],['dias','Dias corridos após a data-base','number'],['vencimento','Vencimento manual','date'],['status','Situação','text',['Prevista','Cancelada']]
   ],item||{modo:'Valor',marco:'Disponibilização / invoice',dias:0,status:'Prevista'});
   f.dias.step='1';f.dias.max='3650';
   const pay=fields(grid(form,'Registro manual do pagamento'),[
    ['valor_pago','Valor pago acumulado na moeda do pedido','number'],['data_pagamento','Data do pagamento mais recente','date'],['cambio','Taxa efetiva para BRL','number'],['contrato_cambio','Referência do contrato de câmbio'],['observacoes','Observações','textarea']
   ],item||{valor_pago:0});
   collect=()=>({...read(f),...read(pay),pedido_id:item?.pedido_id||order?.id});
   summary=()=>{const d=collect(),date=d.marco==='Manual'?d.vencimento:vencimentoParcela(d.data_base,d.dias);f.vencimento.disabled=!editing||d.marco!=='Manual';f.valor.disabled=!editing||d.modo==='Percentual';f.percentual.disabled=!editing||d.modo!=='Percentual';
    info.replaceChildren(node('h3','Vencimento: '+dt(date)),node('p','30 DUE: selecione Disponibilização / invoice, informe a data da invoice e 30 dias corridos.'));
    if(d.modo==='Percentual')info.append(node('p',order?'Valor calculado: '+money(Number(order.total)*Number(d.percentual||0)/100,order.moeda):'O percentual será recalculado sobre o total atual do pedido ao salvar.'));
    info.append(node('p','Este formulário registra pagamentos já realizados. Não executa pagamentos. O contrato de câmbio é uma referência; a conciliação com DI/DUIMP será implementada separadamente.'));
   };
  }else{
   const f=fields(grid(form,'Lote de embarque'),[
    ['referencia','Referência do embarque'],['fornecedor_id','Fornecedor','text',suppliers()],['moeda','Moeda FOB e cotação do frete','text',moedas],['status','Situação','text',etapasEmbarque]
   ],item||{moeda:'USD',status:'Planejamento'});
   const meta=fields(grid(form,'Transporte e acompanhamento'),[
    ['servico','Serviço','text',['','DHL','Agente de cargas']],['transportador','Transportador / agente escolhido'],['despachante','Despachante aduaneiro'],['data_envio_despachante','Data de envio ao despachante','date'],
    ['rastreio','AWB / BL / rastreamento'],['etiqueta','Referência da etiqueta'],['previsao_coleta','Coleta prevista','date'],['data_coleta','Coleta realizada','date'],['previsao_chegada','Chegada prevista','date'],
    ['frete_cotado','Frete cotado na moeda selecionada','number'],['urgente','Urgente','text',['Não','Sim']],['motivo','Motivo de urgência / cancelamento'],['observacoes','Observações','textarea']
   ],item?.dados||{urgente:'Não'});
   const section=node('fieldset');section.append(node('legend','Itens selecionados de pedidos'));const cards=node('div');section.append(cards);form.append(section);let lines=[];
   function add(x){
    if(lines.some(l=>l.pedido_item_id===(x.pedido_item_id||x.id)))throw Error('Este item já está selecionado. Edite sua quantidade.');
    const card=node('article',undefined,'imp-line');card.append(node('h3',x.pedido+' · linha '+x.linha),node('p',x.descricao+' · '+x.unidade));
    if(x.reservada!==undefined)card.append(node('p','Saldo para planejar: '+(Number(x.quantidade)-Number(x.reservada))+' · Disponibilizada: '+x.disponibilizada+' · Reservada em outros embarques: '+x.reservada));
    const inputs=fields(card,[
     ['quantidade','Quantidade neste embarque','number'],['peso_bruto','Peso bruto total do item (kg)','number'],['invoice','Invoice deste envio'],['invoice_data','Emissão da invoice','date'],
     ['recebida','Quantidade recebida','number'],['data_recebimento','Data do recebimento','date']
    ],x.pedido_item_id?x:{quantidade:'',peso_bruto:'',recebida:0});
    const l={pedido_item_id:x.pedido_item_id||x.id,valor_unitario:x.valor_unitario,inputs};lines.push(l);cards.append(card);
    if(editing)card.append(button('Retirar do embarque',()=>{lines=lines.filter(z=>z!==l);card.remove();changed();summary();}));
    f.fornecedor_id.disabled=true;f.moeda.disabled=true;return inputs;
   }
   (item?.itens||[]).forEach(add);
   if(editing)section.append(button('Selecionar item de pedido',async()=>{
    if(!f.fornecedor_id.value)throw Error('Selecione o fornecedor primeiro.');if(lines.length>=100)throw Error('Até 100 itens por embarque.');
    await picker('Selecionar mercadoria', (pagina,busca)=>api({acao:'v2_catalogo',tipo:'pedidos',fornecedor_id:f.fornecedor_id.value,embarque_id:item?.id||null,pagina,busca}),
     x=>[x.pedido+' / '+x.linha,x.descricao,x.moeda,'Saldo: '+(Number(x.quantidade)-Number(x.reservada)),'Disponível: '+x.disponibilizada],x=>{
      if(x.moeda!==f.moeda.value)throw Error('Selecione a mesma moeda do pedido.');const inputs=add(x);changed();summary();setTimeout(()=>inputs.quantidade.focus(),0);
     });
   }));
   collect=()=>({...read(f),dados:read(meta),itens:lines.map(l=>({pedido_item_id:l.pedido_item_id,...read(l.inputs)}))});
   summary=()=>{const d=collect(),total=lines.reduce((s,l)=>s+Number(l.inputs.quantidade.value||0)*Number(l.valor_unitario),0),frete=Number(d.dados.frete_cotado||0);
    const pendentePeso=lines.some(l=>!Number(l.inputs.peso_bruto.value));
    info.replaceChildren(node('h3','FOB selecionado: '+money(total,d.moeda)),node('p','Peso bruto informado: '+lines.reduce((s,l)=>s+Number(l.inputs.peso_bruto.value||0),0).toLocaleString('pt-BR')+' kg'+(pendentePeso?' · Há itens sem peso informado.':'')),
    node('p',d.dados.urgente==='Sim'?'Embarque urgente: registre o motivo da coleta isolada.':!frete?'Informe o frete cotado para avaliar a consolidação.':total>frete?'FOB maior que o frete: condição de valor para consolidação atendida.':'FOB ainda não supera o frete cotado. Avalie aguardar consolidação.'),
    node('p','Planejamento reserva saldo do pedido. Para liberar a coleta, confirme no pedido a quantidade disponibilizada. Etiqueta emitida não confirma coleta. Recebimento não movimenta automaticamente o estoque.'));
   };
  }
  form.append(info);form.addEventListener('input',summary);form.addEventListener('change',summary);
  if(!editing)for(const e of form.querySelectorAll('input,select,textarea'))e.disabled=true;
  summary();
  if(editing){
   const save=button('Salvar '+(tipo==='pedidos'?'pedido':tipo==='parcelas'?'parcela':'embarque'),async()=>{
    if(!form.reportValidity())return;
    const dados=collect();
    if(!pending)pending={acao:'v2_salvar',tipo:t,id:item?.id||null,versao:item?.versao||null,requisicao_id:crypto.randomUUID(),dados};
    busy=true;const controls=[...root.querySelectorAll('input,select,textarea,button')];controls.forEach(e=>e.disabled=true);
    let r;try{r=await api(pending);}finally{busy=false;if(check(g)){controls.forEach(e=>e.disabled=false);summary();}}
    if(!check(g))return;dirty=false;pending=null;await open(r.id);msg.textContent='Registro salvo. Histórico preservado.';msg.className='status';
   });form.append(save);
  }else if(item){
   const history=node('details');history.append(node('summary','Histórico de alterações'));const out=node('div');
   history.append(button('Consultar histórico',async()=>{const r=await api({acao:'v2_historico',tipo:t,id:item.id});if(!check(g)||current?.id!==item.id)return;out.replaceChildren();for(const e of r.linhas){const entry=node('details');entry.append(node('summary',new Date(e.criado_em).toLocaleString('pt-BR')+' · '+(e.anterior?'Alteração':'Criação')),node('pre',JSON.stringify(e,null,2)));out.append(entry);}}),out);body.append(history);
  }
 }
 window.addEventListener('beforeunload',e=>{if((dirty||busy)&&!root.hidden){e.preventDefault();e.returnValue='';}});
 return {
  canLeave:()=>root.hidden||(guard()&&legacy.canLeave()),
  async show(visible){
   epoch++;seq++;closeDialogs();fx.show(false);if(!visible){root.hidden=true;legacy.show(false);return;}
   root.hidden=false;dirty=false;pending=null;current=null;tipo='pedidos';page=0;searchValue='';renderNav();const g=epoch;
   try{opts=await api({acao:'v2_opcoes'});if(check(g))await list();}catch(e){if(check(g))msg.textContent=e.message;}
  },
  reset(){fx.reset();epoch++;seq++;closeDialogs();root.hidden=true;body.replaceChildren();dirty=false;pending=null;current=null;opts={editar:false,fornecedores:[]};legacy.reset();}
 };
}
