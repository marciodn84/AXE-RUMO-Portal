import {botaoTributos} from './tributos-registros.js?v=20261106-perfis17';
const el=(t,s,c)=>{const n=document.createElement(t);if(s!=null)n.textContent=s;if(c)n.className=c;return n;};
const etapasServico={PLANEJAMENTO:'Planejamento',EM_EXECUCAO:'Em execução',CONCLUIDO:'Concluído'};
const money=(v,c='BRL')=>v==null?'Pendente':Number(v).toLocaleString('pt-BR',{style:'currency',currency:c||'BRL'});
export function initVendaRumo(api,{box,say,back,tributosApi}){
 let epoch=0,current=null,dirty=false;
 const rpc=async d=>(await api(d)).resultado;
 const btn=(text,fn)=>{const b=el('button',text);b.type='button';b.onclick=async()=>{const e=epoch;b.disabled=true;try{await fn();}catch(x){if(e===epoch)say(x.message);}finally{if(b.isConnected)b.disabled=false;}};return b;};
 async function abrir(id,editar=true){
  const e=++epoch;say('Carregando pedido de venda…');current=await rpc({acao:'rumo_detalhe',id});if(e!==epoch)return;
  const p=current,rascunho=editar&&p.estado==='RASCUNHO';dirty=false;box.replaceChildren(btn('Voltar à lista',back),el('h2','Pedido de venda AXE PC-'+String(p.id).padStart(6,'0')),el('p','Origem: RUMO '+p.pedido_cliente+' · '+p.documento.cliente.nome+' · CNPJ '+p.documento.cliente.cnpj),el('p','Situação: '+(p.estado==='APROVADO'?'Aprovado — execução interna iniciada':'Rascunho — aguardando vínculo e aprovação'),'badge'));
  if(editar&&tributosApi)box.append(botaoTributos(tributosApi,'venda',p.id));
  if(p.fonte_alterada)box.append(el('p','O pedido RUMO foi atualizado. Recarregue e confira os dados antes de aprovar.','error'));
  box.append(el('p','Pagamento: '+(p.documento.condicao_pagamento||'Não informado no cadastro de origem')+' · Data do pedido: '+(p.documento.data_pedido||'Não informada')));
  const tipo=el('select'),tipoLabel=el('label','Tipo de atendimento');
  tipo.append(new Option('Produto','PRODUTO'),new Option('Serviço','SERVICO'));
  tipo.value=p.tipo_atendimento||'PRODUTO';tipo.disabled=!rascunho;
  tipoLabel.append(tipo);box.append(tipoLabel);
  const servico=()=>tipo.value==='SERVICO';
  const actions=el('div',undefined,'com-tools'),form=el('form',undefined,'com-form'),itemsBox=el('div',undefined,'venda-rumo-items');box.append(actions,form);form.append(itemsBox);const fields=[];
  for(const item of p.itens){
   const card=el('fieldset',undefined,'com-item');card.append(el('legend','Item '+item.numero_item+' · SAP '+(item.codigo_cliente||'não informado na origem')),el('h3',item.nome_cliente));
   card.append(el('p',String(item.quantidade??'Pendente')+' '+(item.unidade_cliente||'unidade pendente')+' · '+money(item.preco_unitario,item.moeda)+' / un. · Remessa: '+(item.data_remessa||'Sem data')));
   card.append(el('p','ICMS: '+(item.dados_fonte?.icms_aliquota??'não informado')+'% · IPI: '+(item.dados_fonte?.ipi_aliquota??'não informado')+'%'));
   if(item.descricao_detalhada){const details=el('details');details.append(el('summary','Descrição detalhada do cliente — consulta técnica'),el('p',item.descricao_detalhada));card.append(details);}
   const vinculo=el('div');vinculo.hidden=servico();card.append(vinculo);
   const product=el('select');product.setAttribute('aria-label','Produto AXE do item '+item.numero_item);product.append(new Option('Selecione o produto AXE',''));
   const map=new Map();const add=x=>{if(!x)return;map.set(String(x.id),x);if(![...product.options].some(o=>o.value===String(x.id)))product.append(new Option(x.codigo_axe+' · '+x.descricao_referencia,x.id));};
   add(item.produto_axe);product.value=item.produto_id||'';product.disabled=!rascunho;const lab=el('label','Produto AXE');lab.append(product);vinculo.append(lab);
   const search=el('input');search.type='search';search.setAttribute('aria-label','Buscar produto AXE para item '+item.numero_item);search.placeholder='Código AXE ou nome do produto';let page=0,seq=0;const info=el('small');
   const next=btn('Mais produtos',async()=>{page++;await buscar();});
   const searchBtn=btn('Buscar produto',async()=>{page=0;await buscar();});
   async function buscar(){
    const n=++seq;info.textContent='Buscando…';const r=await api({acao:'listar',secao:'produtos',somente_axe:true,pagina:page,busca:search.value.trim()});if(e!==epoch||n!==seq)return;
    const selected=product.value,keep=map.get(selected);map.clear();product.replaceChildren(new Option('Selecione o produto AXE',''));add(keep);for(const x of r.linhas)add(x);product.value=selected;info.textContent=r.total+' produto(s) · página '+(page+1);next.disabled=(page+1)*50>=r.total;
   }
   if(rascunho){const tools=el('div',undefined,'com-tools');tools.append(search,searchBtn,next,btn('Cadastrar produto AXE',()=>document.dispatchEvent(new CustomEvent('axe-editar-catalogo',{detail:{tipo:'produto'}}))),info);vinculo.append(tools);search.onkeydown=x=>{if(x.key==='Enter'){x.preventDefault();searchBtn.click();}};}
   const factor=el('input');factor.type='number';factor.min='0.000001';factor.step='0.000001';factor.value=item.fator_conversao??'';factor.setAttribute('aria-label','Conversão de unidade do item '+item.numero_item);
   const flab=el('label','Unidades AXE por unidade do cliente');flab.append(factor);vinculo.append(flab);
   const change=()=>{const x=map.get(product.value),same=x?.unidade_referencia&&item.unidade_cliente&&x.unidade_referencia.trim().toUpperCase()===item.unidade_cliente.trim().toUpperCase();factor.readOnly=!!same||!rascunho;if(same)factor.value='1';flab.hidden=!!same;info.textContent=x?'Unidade AXE: '+(x.unidade_referencia||'não cadastrada')+' · Unidade cliente: '+item.unidade_cliente:'Vincule um produto AXE antes de aprovar.';};
   product.onchange=()=>{factor.value='';change();dirty=true;};factor.oninput=()=>dirty=true;change();
   if(item.execucao&&servico()){
    const etapa=el('select'),rotulo=el('label','Etapa do serviço');
    for(const [valor,nome] of Object.entries(etapasServico))etapa.append(new Option(nome,valor));
    etapa.value=item.execucao.etapa;etapa.disabled=!editar;
    rotulo.append(etapa);
    card.append(el('p','Quantidade em acompanhamento: '+item.execucao.quantidade+' '+item.unidade_cliente),rotulo);
    if(editar)card.append(btn('Salvar etapa',async()=>{
     await rpc({acao:'rumo_salvar',id:p.id,versao:p.versao,execucao_servico:{item_id:item.id,etapa:etapa.value}});
     await abrir(p.id);say('Etapa do serviço atualizada.');
    }));
   }else if(item.execucao)card.append(el('p','Execução: '+item.execucao.quantidade+' unidades AXE · '+item.execucao.etapa));
   fields.push({id:item.id,product,factor,vinculo});itemsBox.append(card);
  }
  tipo.onchange=()=>{for(const f of fields)f.vinculo.hidden=servico();dirty=true;};
  const read=()=>fields.map(x=>({id:x.id,produto_id:x.product.value?Number(x.product.value):null,fator_conversao:x.factor.value||null}));
  async function salvar(){const r=await rpc({acao:'rumo_salvar',id:p.id,versao:p.versao,tipo_atendimento:tipo.value,itens:servico()?[]:read()});dirty=false;return r;}
  if(rascunho){
   actions.append(btn('Salvar rascunho',async()=>{await salvar();await abrir(p.id);say('Rascunho salvo.');}));
   actions.append(btn('Aprovar e iniciar fluxo interno',async()=>{
    if(!servico()&&fields.some(x=>!x.product.value)){say('Vincule o produto AXE em todos os itens antes de aprovar.');fields.find(x=>!x.product.value)?.product.focus();return;}
    const saved=await salvar();try{await rpc({acao:'rumo_aprovar',id:p.id,versao:saved.versao});await abrir(p.id);say(servico()?'Serviço aprovado e disponível para acompanhamento.':'Pedido aprovado. Vínculos salvos e demandas internas criadas.');}catch(error){await abrir(p.id);say(error.message);}}));
   if(p.fonte_alterada)actions.append(btn('Recarregar dados RUMO',async()=>{await rpc({acao:'rumo_recarregar',id:p.id,versao:p.versao});await abrir(p.id);}));
  }
  form.onsubmit=x=>x.preventDefault();
  box.append(el('h3','Total dos itens: '+money(p.total,p.itens[0]?.moeda)));
  if(p.estado==='APROVADO')box.append(el('p',servico()?'Acompanhe a execução do serviço por item.':'As demandas estão em planejamento para atendimento por estoque, compras ou produção. A operação fiscal continua no Nomus.','intro'));
  const hist=el('details');hist.append(el('summary','Histórico do pedido'));const hb=btn('Carregar histórico',async()=>{const r=await api({acao:'listar',secao:'eventos',tipo:'pedido',registro_id:p.id,pagina:0});if(e!==epoch)return;for(const x of r.linhas)hist.append(el('p',new Date(x.criado_em).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'})+' · '+x.acao));hb.remove();});hist.append(hb);if(editar)box.append(hist);
  say('');
 }
 return{abrir,reset(){epoch++;dirty=false;current=null;},canLeave(){return!dirty||confirm('Há vínculos ainda não salvos. Sair deste pedido?');}};
}
