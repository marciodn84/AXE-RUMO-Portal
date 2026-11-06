import {padronizarAcoes} from './acoes-icones.js?v=20261104-pedido6';
const el=(t,v)=>{const n=document.createElement(t);if(v!=null)n.textContent=v;return n;},brl=v=>Number(v||0).toLocaleString('pt-BR',{style:'currency',currency:'BRL'}),data=v=>v?String(v).slice(0,10).split('-').reverse().join('/'):'Não informada';
export function initFinanceiroNumerario(api,comprasApi){
 const root=el('section');root.className='cadastro-screen imp-internacional';root.hidden=true;let epoch=0;document.getElementById('panel').append(root);
 function table(parent,heads,rows){const scroll=el('div'),t=el('table'),h=el('tr');scroll.className='scroll';for(const title of heads){const th=el('th',title);th.scope='col';h.append(th);}t.append(h);for(const row of rows){const tr=el('tr');for(const value of row){const td=el('td');if(value instanceof Node)td.append(value);else td.textContent=value??'—';tr.append(td);}t.append(tr);}scroll.append(t);parent.append(scroll);padronizarAcoes(parent);}
 async function national(key,seq){if(!comprasApi||!['pagar','caixa'].includes(key))return;
  const section=el('section'),bar=el('div'),search=el('input'),status=el('p'),rows=el('div'),pages=el('div');bar.className='cadastro-toolbar';search.type='search';search.placeholder='Pedido, fornecedor ou parcela';search.setAttribute('aria-label','Buscar financeiro nacional');section.append(el('h3',key==='pagar'?'Contas a pagar — compras nacionais':'Previsão financeira — compras nacionais'),el('p',key==='pagar'?'Adiantamentos, provisões e títulos consolidados pela NF-e, com saldo a pagar.':'Parcelas por vencimento, saldo previsto e pagamentos acumulados. A data de pagamento indica a última confirmação da parcela.'),bar,status,rows,pages);root.append(section);let page=0,request=0;
  const button=(label,fn)=>{const b=el('button',label);b.type='button';b.onclick=fn;return b;};
  async function load(){const req=++request;status.textContent='Consultando parcelas nacionais…';try{const r=await comprasApi({acao:'v2_listar',tipo:'parcelas',origem:'nacional',somente_abertas:key==='pagar',pagina:page,busca:search.value});if(seq!==epoch||req!==request)return;rows.replaceChildren();pages.replaceChildren();table(rows,['Vencimento','Pedido / fornecedor','Parcela / NF-e','Fase','Meio','Valor','Pago','Saldo a pagar',...(key==='caixa'?['Último pagamento']:[]),'Ação'],r.linhas.map(p=>[data(p.vencimento),p.pedido+' · '+p.fornecedor,p.referencia+(p.notas?' · NF-e '+p.notas:''),p.financeiro?.fase||'Programação manual',({PIX:'PIX',CARTAO:'Cartão',BOLETO:'Boleto',TRANSFERENCIA_BANCARIA:'Transferência bancária'})[p.meio_pagamento]||'A conferir',brl(p.valor),brl(p.valor_pago),brl(Number(p.valor)-Number(p.valor_pago)),...(key==='caixa'?[data(p.data_pagamento)]:[]),button('Abrir',()=>document.dispatchEvent(new CustomEvent('axe-abrir-pedido-compra',{detail:{pedidoId:p.pedido_id}})))]));const previous=button('Anterior',()=>{page--;void load();}),next=button('Próxima',()=>{page++;void load();});previous.disabled=page===0;next.disabled=(page+1)*30>=r.total;pages.append(previous,el('span','Página '+(page+1)+' · '+r.total+' parcela(s)'),next);status.textContent=r.total?'':'Nenhuma parcela nesta situação.';}catch(e){if(seq===epoch&&req===request)status.textContent=e.message;}}
  bar.append(search,button('Buscar',()=>{page=0;void load();}));search.onkeydown=e=>{if(e.key==='Enter'){page=0;void load();}};await load();
 }
 async function faturasFrete(key,seq){
  if(!comprasApi||!['pagar','caixa'].includes(key))return;
  const section=el('section'),rows=el('div'),status=el('p'),prev=el('button','Anterior'),next=el('button','Próxima');
  let pagina=0;
  section.append(el('h3',key==='pagar'?'Faturas de frete a pagar':'Faturas de frete'),status,rows,prev,next);
  root.append(section);
  async function carregar(){
   prev.disabled=next.disabled=true;
   try{
    const r=await comprasApi({acao:'v2_frete_fatura_financeiro',somente_abertas:key==='pagar',pagina});
    if(seq!==epoch)return;
    rows.replaceChildren();
    table(rows,['Vencimento','Pagamento','Transportadora','Embarque','Fatura','Meio','Valor','Situação'],
     r.linhas.map(f=>[data(f.vencimento),data(f.data_pagamento),f.transportadora,f.embarque,f.numero,f.meio_pagamento,brl(f.valor_brl),f.situacao]));
    status.textContent=r.linhas.length?'':'Nenhuma fatura nesta página.';
    prev.disabled=pagina===0;next.disabled=r.linhas.length<30;
   }catch(e){if(seq===epoch)status.textContent=e.message;}
  }
  prev.onclick=()=>{pagina--;void carregar();};
  next.onclick=()=>{pagina++;void carregar();};
  await carregar();
 }
 return{async show(key){document.querySelector('.erp-content')?.append(root);const seq=++epoch;root.hidden=!key;if(!key)return;root.replaceChildren(el('h2',key==='pagar'?'Contas a pagar':key==='caixa'?'Fluxo de caixa':'Contas a receber'));const loading=Promise.all([national(key,seq),faturasFrete(key,seq)]);try{const r=await api({acao:'num_financeiro'});if(seq!==epoch)return;const section=el('section');section.append(el('h3','Numerário das importações'),el('p','Lançamentos originados no numerário. Transferências são comprovadas pelos documentos anexados no processo.'));root.append(section);const rows=key==='caixa'?r.movimentos.map(m=>[m.data,r.processos.find(p=>p.processo_id===m.processo_id)?.referencia||m.processo_id,m.tipo,brl((m.tipo==='Devolução'?1:-1)*Number(m.valor))]):r.processos.filter(p=>Number(p.resumo[key==='pagar'?'a_pagar':'a_receber'])>0).map(p=>[p.referencia,key==='pagar'?(p.resumo.fechamento?'Complemento ao despachante':'Adiantamento previsto'):'Devolução do despachante',brl(p.resumo[key==='pagar'?'a_pagar':'a_receber']),brl(p.resumo.comprovantes_bancarios_pendentes)]);table(section,key==='caixa'?['Data','Processo','Movimento','Valor']:['Processo','Natureza','Valor','Comprovantes bancários pendentes'],rows);if(!rows.length)section.append(el('p','Nenhum lançamento nesta situação.'));}catch(e){if(seq===epoch)root.append(el('p',e.message));}await loading;}};
}
