import {padronizarImportacao} from './importacoes-layout.js?v=20261030-email36';
import {initCadastrosImportacao} from './importacoes-cadastros.js?v=20261029-docauto17';
import {aceiteDocumentoOficial,temConflitoDocumental} from './importacoes-documento-oficial.js?v=20261029-docauto17';
import {initVisaoImportacao} from './importacoes-fluxo.js?v=20261030-email36';
import {initTransporteDocumental} from './importacoes-transporte.js?v=20261030-email36';
import {initPagamentoDocumental} from './importacoes-pagamento-documental.js?v=20261030-email36';
import {initLiberacaoDocumental} from './importacoes-liberacao.js?v=20261030-email36';
import {initParcelasSugeridas} from './importacoes-parcelas-sugeridas.js?v=20261030-email36';
import {validarCampos} from './validacao-campos.js?v=20261030-email36';
import {initEntradaEmail} from './importacoes-entrada-email.js?v=20261030-email36';
import {initACKImportacao} from './importacoes-ack.js?v=20261030-email36';
import {lerPDFImportacao} from './importacoes-di-leitura.js?v=20261028-di1';
import {initNotasImportacao} from './importacoes-notas.js?v=20261030-email36';
import {initCustosImportacao} from './importacoes-custos.js?v=20261030-email36';
import {initConciliacaoCambio} from './importacoes-cambio.js?v=20261030-email36';
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
 padronizarImportacao(root);
 let voltarFluxo=null;
 let tipo='visao',page=0,epoch=0,seq=0,dirty=false,pending=null,current=null,opts={editar:false,fornecedores:[]},busy=false;
 const dialogs=new Set(),nav=node('div',undefined,'catalog-tabs'),body=node('div'),msg=node('p','','status');
 msg.setAttribute('role','status');
 const guard=()=>!busy&&cadastros.canLeave()&&visao.canLeave()&&transporte.canLeave()&&pagamento.canLeave()&&liberacao.canLeave()&&planos.canLeave()&&entrada.canLeave()&&ack.canLeave()&&fx.canLeave()&&custos.canLeave()&&notas.canLeave()&&(!dirty||confirm('Há alterações não salvas. Deseja descartá-las?'));
 const changed=()=>{dirty=true;pending=null;};
 const check=g=>g===epoch&&!root.hidden;
 function button(text,fn){const b=node('button',text);b.type='button';b.onclick=async()=>{if(busy)return;b.disabled=true;try{await fn();}catch(e){msg.textContent=e.message;msg.className='status error';}finally{if(b.isConnected)b.disabled=false;}};return b;}
 function field(parent,key,label,value='',type='text',choices){
  const l=node('label',label),e=node(choices?'select':type==='textarea'?'textarea':'input');
  if(choices){for(const x of choices){const [v,t]=Array.isArray(x)?x:[x,x];e.append(new Option(t,v));}}else if(type!=='textarea')e.type=type;
  e.value=value??'';e.name=key;e.required=['referencia','fornecedor_id','moeda','status','linha','descricao','unidade','quantidade','valor_unitario','modo','marco'].includes(key);e.setAttribute('aria-label',label);
  if(type==='number'){e.step='any';e.min=key==='quantidade'?'0.000001':'0';}
  l.append(e);parent.append(l);return e;
 }
 const suppliers=()=>[['','Selecionar fornecedor'],...opts.fornecedores.map(x=>[String(x.id),x.nome])];
 const fields=(parent,defs,data={})=>Object.fromEntries(defs.map(([k,l,t,c])=>[k,field(parent,k,l,data[k],t||'text',c)]));
 const read=inputs=>Object.fromEntries(Object.entries(inputs).map(([k,e])=>[k,e.value.trim()]));
 function grid(parent,title){const box=node('fieldset');box.append(node('legend',title));const g=node('div',undefined,'import-mapping');box.append(g);parent.append(box);return g;}
 function renderNav(){nav.replaceChildren();for(const [key,label] of [['visao','Visão única'],['pedidos','Pedidos de compra'],['entrada','Pré-cadastros de e-mail'],['parcelas','Parcelas'],['embarques','Embarques'],['cambio','Conciliação cambial'],['custos','Custo real'],['notas','Notas Nomus'],['anteriores','Registros anteriores']]){
  const b=button(label,async()=>{if(!guard()||!legacy.canLeave())return;dirty=false;pending=null;current=null;closeDialogs();await visao.show(false);await legacy.show(false);await entrada.show(false);await fx.show(false);await custos.show(false);await notas.show(false);tipo=key;voltarFluxo=null;page=0;epoch++;renderNav();if(key==='visao'){body.replaceChildren();msg.textContent='';await visao.show(true);}else if(key==='entrada'){body.replaceChildren();msg.textContent='';await entrada.show(true,opts.editar);}else if(key==='notas'){body.replaceChildren();msg.textContent='';await notas.show(true);}else if(key==='custos'){body.replaceChildren();msg.textContent='';await custos.show(true);}else if(key==='cambio'){body.replaceChildren();msg.textContent='';await fx.show(true);}else if(key==='anteriores'){body.replaceChildren(node('p','Registros da primeira versão, preservados com seu histórico. Eles não reservam quantidades na nova estrutura.'));await legacy.show(true);}else await list();});b.setAttribute('aria-pressed',String(tipo===key));nav.append(b);
 }}
 root.append(node('p','Pedidos, condições de pagamento e embarques parciais ou consolidados.','intro'),nav,msg,body);
 const cadastros=initCadastrosImportacao(api,root);
 const entrada=initEntradaEmail(api,root);
 const transporte=initTransporteDocumental(api,root,async id=>{await open(id);});
 const pagamento=initPagamentoDocumental(api,root,async r=>{await open(tipo==='parcelas'?r.id:r.pedido_id);});
 const liberacao=initLiberacaoDocumental(api,root,async id=>{await open(id);});
 const planos=initParcelasSugeridas(api,root,async id=>{await open(id);});
 const ack=initACKImportacao(api,root,async id=>{await open(id);msg.textContent='ACK anexado e recebimento confirmado. Histórico preservado.';});
 const fx=initConciliacaoCambio(api,root);
 const custos=initCustosImportacao(api,root);
 const notas=initNotasImportacao(api,root);
 const visao=initVisaoImportacao(api,root,async(t,id,pedidoId)=>{
  if(!guard())return;await visao.show(false);voltarFluxo=pedidoId||'novo';tipo=t;body.replaceChildren();
  if(id){const d=await api({acao:'v2_detalhe',tipo:t,id});current=d;edit(d,null,true);}else edit(null);
 });

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
 async function open(id){if(!guard())return;if(voltarFluxo){const pid=voltarFluxo==='novo'?id:voltarFluxo;voltarFluxo=null;tipo='visao';body.replaceChildren();renderNav();await visao.show(true,pid);return;}const g=epoch,s=++seq;const d=await api({acao:'v2_detalhe',tipo,id});if(!check(g)||s!==seq)return;current=d;dirty=false;pending=null;edit(d,null,false);}
 function closeDialogs(){transporte.reset();pagamento.reset();liberacao.reset();ack.reset();for(const d of dialogs){d.close();d.remove();}dialogs.clear();}
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
  const top=node('div',undefined,'cadastro-toolbar');top.append(button('Voltar à lista',async()=>{if(!guard())return;dirty=false;pending=null;current=null;if(voltarFluxo){const pid=voltarFluxo;voltarFluxo=null;tipo='visao';body.replaceChildren();renderNav();await visao.show(true,pid==='novo'?undefined:pid);return;}await list();}));
  if(!editing&&opts.editar)top.append(button('Editar',()=>edit(item,order,true)));
  if(!editing&&item&&tipo==='pedidos')top.append(button('ACK do fornecedor',()=>ack.show(item,opts.editar)));
  if(!editing&&item&&opts.editar&&tipo==='pedidos')top.append(pagamento.button(item.id));
  if(!editing&&item&&opts.editar&&tipo==='parcelas')top.append(pagamento.button(item.pedido_id,item.id)); 
  body.append(top,node('h2',(item?item.referencia:tipo==='pedidos'?'Novo pedido':tipo==='parcelas'?'Nova parcela':'Novo embarque')));
  const form=node('form');form.onsubmit=e=>e.preventDefault();form.addEventListener('input',changed);form.addEventListener('change',changed);body.append(form);
  let collect,summary=()=>{};const participantes={};
  const info=node('div',undefined,'planned-card');
  if(tipo==='pedidos'){
   const general=fields(grid(form,'Pedido e confirmação do fornecedor'),[
    ['referencia','Número do pedido'],['fornecedor_id','Fornecedor','text',suppliers()],['moeda','Moeda','text',moedas],['status','Situação','text',etapasPedido],
    ['data_pedido','Data do pedido','date'],['condicao_pagamento','Condição de pagamento','textarea'],['ack_numero','Número do ACK'],['ack_data','Data do ACK','date'],['observacoes','Observações','textarea']
   ],item||{status:'Rascunho',moeda:'USD'});
   if(editing)form.append(button('Buscar ou cadastrar fornecedor',()=>cadastros.escolher('participante',{},pr=>{if(![...general.fornecedor_id.options].some(o=>o.value===String(pr.id)))general.fornecedor_id.append(new Option(pr.razao_social,pr.id));general.fornecedor_id.value=String(pr.id);changed();})));
   const section=node('fieldset');section.append(node('legend','Itens do pedido'));const cards=node('div');section.append(cards);form.append(section);
   let lines=[];
   function add(x={}){
    const card=node('article',undefined,'imp-line');card.append(node('h3','Linha do pedido'));
    const inputs=fields(card,[
     ['linha','Linha'],['codigo_axe','Código AXE'],['codigo_fornecedor','Código do fornecedor / part number'],['descricao','Descrição técnica'],['unidade','Unidade'],
     ['quantidade','Quantidade pedida','number'],['valor_unitario','Preço unitário FOB','number'],['peso_bruto_unitario','Peso bruto unitário (kg)','number'],
     ['disponibilizada','Quantidade disponibilizada acumulada','number'],['data_disponibilidade','Data da disponibilidade','date']
    ],{linha:'',quantidade:1,valor_unitario:0,disponibilizada:0,...x});
    const line={id:x.id||crypto.randomUUID(),produto_id:x.produto_id||null,inputs,card};lines.push(line);
    if(!line.produto_id&&x.codigo_axe)void api({acao:'custo_cadastro_buscar',tipo:'produto',busca:x.codigo_axe}).then(r=>{if(!card.isConnected)return;const exact=r.linhas.filter(p=>[p.codigo_axe,p.codigo_anterior].includes(x.codigo_axe));if(exact.length===1){line.produto_id=exact[0].id;produtoLabel.textContent=(exact[0].codigo_axe||'#'+exact[0].id)+' · '+exact[0].descricao_referencia;}}).catch(()=>{});

    const produtoLabel=node('p',line.produto_id?'Produto do cadastro AXE #'+line.produto_id:'Produto do cadastro ainda não vinculado');card.prepend(produtoLabel);
    if(editing)card.append(button('Selecionar produto do cadastro',()=>cadastros.escolher('produto',{codigo_anterior:inputs.codigo_axe.value,part_number:inputs.codigo_fornecedor.value,descricao_referencia:inputs.descricao.value,unidade_referencia:inputs.unidade.value},pr=>{line.produto_id=pr.id;produtoLabel.textContent=(pr.codigo_axe||'#'+pr.id)+' · '+pr.descricao_referencia;if(!inputs.descricao.value)inputs.descricao.value=pr.descricao_referencia||'';if(!inputs.unidade.value)inputs.unidade.value=pr.unidade_referencia||'';changed();})));
    if(x.reservada!==undefined)card.append(node('p','Reservada em embarques: '+x.reservada+' · Recebida: '+x.recebida));
    if(editing)card.append(button('Remover item',()=>{lines=lines.filter(l=>l!==line);card.remove();changed();summary();}));
    cards.append(card);return inputs;
   }
   (item?.itens||[]).forEach(add);
   if(editing)section.append(button('Adicionar item',()=>{if(lines.length>=100)throw Error('Até 100 itens por pedido.');const f=add();changed();f.linha.focus();}));
   if(!item&&editing){
    const box=node('fieldset'),status=node('p','','status'),preview=node('div');box.append(node('legend','Cadastrar pelo PDF do Nomus'),node('p','Leia o PDF do pedido de compra e confira os dados antes de preencher o formulário. O arquivo é usado para leitura; o pedido só será gravado em Salvar pedido.'));
    const file=field(box,'pdf_nomus','PDF do pedido Nomus (até 8 MB / 20 páginas)','','file');file.accept='.pdf,application/pdf';let parsed=null,arquivo=null;
    file.onchange=()=>{parsed=null;arquivo=null;preview.replaceChildren();status.textContent='';};
    box.append(button('Ler PDF do Nomus',async()=>{
     const selected=file.files[0];if(!selected)throw Error('Selecione o PDF do pedido.');
     busy=true;const controls=[...root.querySelectorAll('input,select,textarea,button')],states=controls.map(c=>c.disabled);controls.forEach(c=>c.disabled=true);
     try{
      const paginas=await lerPDFImportacao(selected,t=>status.textContent=t);
      const conteudo=await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(String(r.result).split(',')[1]);r.onerror=()=>reject(Error('Não foi possível ler o arquivo'));r.readAsDataURL(selected);});
      const r=await api({acao:'pedido_pdf_ler',conteudo,paginas});if(!check(g))return;
      const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await selected.arrayBuffer()))).map(x=>x.toString(16).padStart(2,'0')).join('');parsed=r;arquivo={nome:selected.name,hash};
      preview.replaceChildren(node('p','Pedido: '+(r.referencia||'Não identificado')+' · Fornecedor no PDF: '+(r.fornecedor||'Não identificado')+' · '+r.itens.length+' item(ns)'),node('p','Data: '+dt(r.data_pedido)+' · Moeda: '+(r.moeda||'Confirmar')+' · Total do PDF: '+(r.total_documento?money(r.total_documento,r.moeda):'Não identificado')));
      for(const warning of r.avisos)preview.append(node('p',warning,'status error'));
      const scroll=node('div',undefined,'scroll'),table=node('table'),head=node('tr');['Linha','Código Nomus','Descrição','Unidade','Quantidade','Preço unitário','Subtotal PDF'].forEach(t=>head.append(node('th',t)));table.append(head);
      for(const x of r.itens){const tr=node('tr');[x.linha,x.codigo_axe,x.descricao,x.unidade,x.quantidade??'Confirmar',x.valor_unitario??'Confirmar',x.subtotal_documento??'Não informado'].forEach(t=>tr.append(node('td',t)));table.append(tr);}scroll.append(table);preview.append(scroll);
      const l=node('label'),c=node('input');c.type='checkbox';c.setAttribute('aria-label','Conferi os dados extraídos do pedido Nomus');l.append(c,document.createTextNode(' Conferi os dados extraídos e vou revisar o fornecedor, os códigos e os valores no formulário.'));preview.append(l);aceiteDocumentoOficial(c,temConflitoDocumental(r.avisos));
      const apply=button('Usar dados do documento',()=>{
       if(!c.checked)throw Error('Confirme a conferência dos dados extraídos.');if(!parsed?.itens.length)throw Error('Nenhum item foi reconhecido. Use o cadastro manual.');
       if((lines.length||general.referencia.value)&&!confirm('Substituir os dados e itens ainda não salvos deste novo pedido pelos dados lidos do PDF?'))return;
       cards.replaceChildren();lines=[];
       general.referencia.value=parsed.referencia||'';general.data_pedido.value=parsed.data_pedido||'';general.moeda.value=parsed.moeda||'';
       const normalize=v=>String(v||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^A-Za-z0-9]/g,'').toUpperCase();
       const match=opts.fornecedores.filter(f=>normalize(f.nome)===normalize(parsed.fornecedor));if(match.length===1&&parsed.fornecedor)general.fornecedor_id.value=String(match[0].id);else general.fornecedor_id.value='';
       for(const x of parsed.itens)add({...x,quantidade:x.quantidade??'',valor_unitario:x.valor_unitario??'',peso_bruto_unitario:'',disponibilizada:0,data_disponibilidade:''});
       general.condicao_pagamento.value=(parsed.condicoes_comerciais||[]).filter(x=>/^(Payment|Pagamento)\s*:/i.test(x)).map(x=>x.replace(/^[^:]+:\s*/, '')).join('; ');
       const entrega=parsed.itens.filter(x=>x.entrega_documento).map(x=>'Linha '+x.linha+': entrega prevista no PDF '+x.entrega_documento).join('\n');
       general.observacoes.value=[general.observacoes.value,'Origem: PDF Nomus '+arquivo.nome+' · SHA-256 '+arquivo.hash,'Fornecedor no PDF: '+(parsed.fornecedor||'Não identificado'),entrega,...(parsed.condicoes_comerciais||[]),...parsed.avisos].filter(Boolean).join('\n');
       changed();summary();status.textContent='Formulário preenchido. Confirme o fornecedor e os códigos do cadastro AXE; depois clique em Salvar pedido. Nenhum registro foi criado pela leitura.';
      });preview.append(apply);status.textContent='Leitura concluída. Revise os dados extraídos.';
     }finally{busy=false;if(check(g))controls.forEach((c,i)=>{if(c.isConnected)c.disabled=states[i];});}
    }),status,preview);form.prepend(box);
   }
   collect=()=>({...read(general),itens:lines.map(l=>({id:l.id,produto_id:l.produto_id,...read(l.inputs)}))});
   summary=()=>{general.ack_numero.required=general.status.value==='ACK recebido';general.ack_data.required=general.status.value==='ACK recebido';const d=collect(),total=d.itens.reduce((s,x)=>s+Number(x.quantidade||0)*Number(x.valor_unitario||0),0),parcelado=(item?.parcelas||[]).filter(p=>p.status!=='Cancelada').reduce((s,x)=>s+Number(x.valor),0);
    info.replaceChildren(node('h3','FOB do pedido: '+money(total,d.moeda)),node('p','Pagamentos confirmados: '+money((item?.parcelas||[]).reduce((s,p)=>s+Number(p.valor_pago||0),0),d.moeda)+' · Saldo devedor: '+money(total-(item?.parcelas||[]).reduce((s,p)=>s+Number(p.valor_pago||0),0),d.moeda)),node('p','Parcelas programadas: '+money(parcelado,d.moeda)+' · Valor ainda sem programação: '+money(total-parcelado,d.moeda)),node('p','Parcelas por percentual mantêm o valor confirmado ao salvar; revise a programação após alterar o pedido. Disponibilidade acumulada inclui as quantidades já liberadas para embarques anteriores. Pesos em kg; nenhum prazo é preenchido automaticamente.'));
   };
   if(item&&!editing){
    const documentos=node('section');body.append(documentos);void liberacao.render(item,documentos,opts.editar);
    const sugestoes=node('section');body.append(sugestoes);void planos.render(item,sugestoes,opts.editar);
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
   f.valor.required=true;f.valor.min='0.01';f.percentual.required=true;f.percentual.min='0.000001';f.percentual.max='100';f.dias.step='1';f.dias.max='3650';
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
    ['servico','Serviço','text',['','DHL','Agente de cargas']],['data_envio_despachante','Data de envio ao despachante','date'],
    ['rastreio','AWB / BL / rastreamento'],['etiqueta','Referência da etiqueta'],['previsao_coleta','Coleta prevista','date'],['data_coleta','Coleta realizada','date'],['previsao_chegada','Chegada prevista','date'],
    ['frete_cotado','Frete cotado na moeda selecionada','number'],['urgente','Urgente','text',['Não','Sim']],['motivo','Motivo de urgência / cancelamento'],['observacoes','Observações','textarea']
   ],item?.dados||{urgente:'Não'});
   const pessoas=grid(form,'Participantes do embarque');
   for(const role of ['transportador','despachante']){const old=(item?.participantes||[]).find(p=>p.papel===role),select=field(pessoas,role,role==='transportador'?'Transportador':'Despachante',old?.id||'','text',[['','Selecionar cadastro'],...(old?[[String(old.id),old.nome]]:[])]);if(old)participantes[role]=old.id;select.addEventListener('change',()=>{participantes[role]=select.value||null;changed();});if(editing)pessoas.append(button('Buscar ou cadastrar '+role,()=>cadastros.escolher('participante',{razao_social:item?.dados?.[role]||''},pr=>{if(![...select.options].some(o=>o.value===String(pr.id)))select.append(new Option(pr.razao_social,pr.id));select.value=String(pr.id);participantes[role]=pr.id;changed();})));}
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
   collect=()=>({...read(f),dados:{...(item?.dados||{}),...read(meta)},itens:lines.map(l=>({pedido_item_id:l.pedido_item_id,...read(l.inputs)}))});
   summary=()=>{meta.data_coleta.required=['Em trânsito','Em desembaraço','Recebido'].includes(f.status.value);meta.motivo.required=meta.urgente.value==='Sim'||f.status.value==='Cancelado';const d=collect(),total=lines.reduce((s,l)=>s+Number(l.inputs.quantidade.value||0)*Number(l.valor_unitario),0),frete=Number(d.dados.frete_cotado||0);
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
    summary();if(!validarCampos(form))return;
    const dados=collect();
    if(!pending)pending={acao:'v2_salvar',tipo:t,id:item?.id||null,versao:item?.versao||null,requisicao_id:crypto.randomUUID(),dados};
    busy=true;const controls=[...root.querySelectorAll('input,select,textarea,button')];controls.forEach(e=>e.disabled=true);
    let r;try{r=await api(pending);}finally{busy=false;if(check(g)){controls.forEach(e=>e.disabled=false);summary();}}
    if(!check(g))return;if(t==='embarques')for(const [role,id]of Object.entries(participantes))if(id)await api({acao:'custo_cadastro_vincular',tipo:role,embarque_id:r.id,cadastro_id:id});dirty=false;pending=null;if(voltarFluxo){await open(r.id);}else{current=null;await list();}msg.textContent='Registro salvo. Histórico preservado.';msg.className='status';
   });const actions=node('div',undefined,'form-actions');actions.append(button('Cancelar',async()=>{if(!guard())return;dirty=false;pending=null;current=null;if(voltarFluxo){const pid=voltarFluxo;voltarFluxo=null;tipo='visao';body.replaceChildren();renderNav();await visao.show(true,pid==='novo'?undefined:pid);}else await list();}),save);form.append(actions);
  }else if(item){
   if(tipo==='embarques'){const documentos=node('section');body.append(documentos);void transporte.render(item,documentos,opts.editar);}
   if(tipo==='embarques'){
    const financeiro=node('section'),estado=node('p','Consultando pagamentos vinculados…');financeiro.append(node('h3','Pagamento da parcial e do embarque'),estado);body.append(financeiro);
    void api({acao:'custo_detalhe',embarque_id:item.id}).then(r=>{if(!financeiro.isConnected)return;const fin=r.financeiro;if(!fin){estado.textContent='Consulte os pagamentos na apuração de custo.';return;}estado.textContent='FOB: '+money(fin.fob,item.moeda)+' · Pagamento vinculado: '+money(fin.pago_vinculado,item.moeda)+' · Sem vínculo aprovado: '+money(Math.max(0,Number(fin.fob)-Number(fin.pago_vinculado)),item.moeda)+'. Pagamentos registrados no pedido podem ser vinculados na apuração; isso não cria uma nova cobrança.';for(const p of fin.parcelas||[])financeiro.append(node('p',p.referencia+' · Contrato '+p.contrato+' · Remessa em '+dt(p.data_pagamento)+' · '+money(p.valor_no_embarque,item.moeda)));}).catch(e=>{if(financeiro.isConnected)estado.textContent=e.message;});
   }

   if(tipo==='embarques')body.append(button('Apurar custo deste embarque',async()=>{if(!guard())return;tipo='custos';renderNav();body.replaceChildren();msg.textContent='';await custos.show(true,item.id);}));
   const history=node('details');history.append(node('summary','Histórico de alterações'));const out=node('div');
   history.append(button('Consultar histórico',async()=>{const r=await api({acao:'v2_historico',tipo:t,id:item.id});if(!check(g)||current?.id!==item.id)return;out.replaceChildren();for(const e of r.linhas){const entry=node('details');entry.append(node('summary',new Date(e.criado_em).toLocaleString('pt-BR')+' · '+(e.anterior?'Alteração':'Criação')),node('pre',JSON.stringify(e,null,2)));out.append(entry);}}),out);body.append(history);
  }
 }
 window.addEventListener('beforeunload',e=>{if((dirty||busy)&&!root.hidden){e.preventDefault();e.returnValue='';}});
 return {
  canLeave:()=>root.hidden||(guard()&&legacy.canLeave()),
  async show(visible){
   epoch++;seq++;closeDialogs();entrada.show(false);fx.show(false);custos.show(false);notas.show(false);visao.show(false);if(!visible){root.hidden=true;legacy.show(false);return;}
   root.hidden=false;dirty=false;pending=null;current=null;tipo='visao';voltarFluxo=null;page=0;searchValue='';renderNav();const g=epoch;
   try{opts=await api({acao:'v2_opcoes'});if(check(g))await visao.show(true);}catch(e){if(check(g))msg.textContent=e.message;}
  },
  reset(){cadastros.reset();visao.reset();voltarFluxo=null;transporte.reset();pagamento.reset();liberacao.reset();planos.reset();entrada.reset();ack.reset();notas.reset();custos.reset();fx.reset();epoch++;seq++;closeDialogs();root.hidden=true;body.replaceChildren();dirty=false;pending=null;current=null;opts={editar:false,fornecedores:[]};legacy.reset();}
 };
}

