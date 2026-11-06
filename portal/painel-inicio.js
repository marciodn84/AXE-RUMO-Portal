const brl=(valor,moeda)=>new Intl.NumberFormat('pt-BR',{style:'currency',currency:moeda,currencyDisplay:moeda==='BRL'?'symbol':'code'}).format(Number(valor));
const inteiro=valor=>Number(valor).toLocaleString('pt-BR');
const dia=valor=>valor?valor.split('-').reverse().join('/'):'—';
const mes=valor=>new Intl.DateTimeFormat('pt-BR',{month:'short',year:'2-digit',timeZone:'UTC'}).format(new Date(valor+'T12:00:00Z'));
function el(tag,texto,classe){
  const n=document.createElement(tag);
  if(texto!=null)n.textContent=texto;
  if(classe)n.className=classe;
  return n;
}
function button(texto,fn,classe){
  const b=el('button',texto,classe);
  b.type='button';b.onclick=fn;
  return b;
}
export function initPainelInicio(api,navigate){
  const root=el('section',null,'painel-inicio');
  const status=el('p',null,'status');status.setAttribute('role','status');
  const conteudo=el('div'),dias=el('select'),filtro=el('label','Período da agenda ');
  for(const n of [7,30])dias.append(new Option(n+' dias',n));
  filtro.append(dias);
  const topo=el('div',null,'painel-inicio-topo');
  const atualizar=button('Atualizar painel',()=>show());
  topo.append(el('h2','Acompanhamento diário'),filtro,atualizar);
  root.append(topo,status,conteudo);
  let epoch=0;
  dias.onchange=()=>show();

  function card(titulo,linhas,vazio,atalho){
    const b=button(null,atalho,'stat-card painel-indicador');
    b.append(el('span',titulo));
    for(const linha of linhas)b.append(el('strong',linha));
    if(!linhas.length)b.append(el('strong',vazio));
    return b;
  }
  function serie(pai,dados,grupos,formato){
    const limite=Math.max(1,...dados.flatMap(x=>grupos.map(g=>g.valor(x))));
    const tabela=el('table',null,'painel-series'),h=tabela.createTHead().insertRow();
    for(const nome of ['Mês',...grupos.map(g=>g.nome)]){const th=el('th',nome);th.scope='col';h.append(th);}
    const body=tabela.createTBody();
    for(const item of dados){
      const row=body.insertRow();const th=el('th',mes(item.mes));th.scope='row';row.append(th);
      for(const g of grupos){
        const v=g.valor(item),td=row.insertCell(),bar=el('span',null,'painel-barra '+g.classe),track=el('span',null,'painel-trilho');
        bar.style.width=(v/limite*100)+'%';track.setAttribute('aria-hidden','true');track.append(bar);
        td.append(el('span',formato(v)),track);
      }
    }
    pai.replaceChildren(tabela);
  }
  function render(d){
    const cards=el('div',null,'erp-stats painel-indicadores');
    const valores=lista=>lista.map(x=>brl(x.valor,x.moeda));
    const financeiro=()=>navigate('pagar');
    cards.append(card('A pagar hoje',valores(d.a_pagar_hoje),'Nenhum vencimento hoje',financeiro),
      card('Vencidos',valores(d.vencidos),'Nenhum vencido',financeiro),
      card('Pago no mês',valores(d.pago_mes),'Sem pagamentos no mês',()=>navigate('caixa')),
      card('Entregas previstas · '+d.dias+' dias',[inteiro(d.entregas)],'',()=>agenda.scrollIntoView({block:'start'})));
    const graficos=el('div',null,'painel-graficos');
    const compras=el('section',null,'source-card'),pagamentos=el('section',null,'source-card'),pedidos=el('div'),graficoPago=el('div');
    compras.append(el('h3','Pedidos registrados · últimos 6 meses'),pedidos,
      button('Abrir pedidos de compra',()=>navigate('pedidos-compra'),'text-button'),
      button('Abrir pedidos comerciais',()=>navigate('pedidos-comerciais'),'text-button'));
    serie(pedidos,d.meses,[{nome:'Compras',classe:'compras',valor:x=>Number(x.compras)},{nome:'Vendas',classe:'vendas',valor:x=>Number(x.vendas)}],inteiro);
    const moeda=el('select'),rotulo=el('label','Moeda ');
    const moedas=new Set(['BRL',...d.meses.flatMap(x=>Object.keys(x.pagamentos))]);
    for(const c of moedas)moeda.append(new Option(c,c));
    rotulo.append(moeda);
    pagamentos.append(el('h3','Pagamentos registrados · últimos 6 meses'),rotulo,graficoPago,
      el('small','Inclui parcelas, fretes pagos e envios de numerário. Parcelas sem histórico detalhado usam a última data de pagamento registrada.'));
    const renderPago=()=>serie(graficoPago,d.meses,[{nome:'Pago em '+moeda.value,classe:'pagamentos',valor:x=>Number(x.pagamentos[moeda.value]||0)}],v=>brl(v,moeda.value));
    moeda.onchange=renderPago;renderPago();
    graficos.append(compras,pagamentos);

    const agenda=el('section',null,'source-card painel-agenda');
    agenda.append(el('h3','Agenda operacional'),el('p','Tarefas, pagamentos e entregas dos próximos '+d.dias+' dias.'));
    if(!d.agenda.length)agenda.append(el('p','Nenhum registro neste período.'));
    else{
      const scroll=el('div',null,'scroll'),table=el('table'),h=table.createTHead().insertRow(),b=table.createTBody();
      for(const t of ['Data','Tipo','Registro','Valor','Ação']){const th=el('th',t);th.scope='col';h.append(th);}
      for(const a of d.agenda){
        const r=b.insertRow();
        r.append(el('td',dia(a.data)),el('td',a.tipo),el('td',[a.titulo,a.descricao].filter(Boolean).join(' · ')),
          el('td',a.moeda?brl(a.valor,a.moeda):'—'));
        const abrir=()=>{
          if(a.tarefa_id)navigate('tarefas',{registroId:a.tarefa_id});
          else if(a.embarque_id&&a.pedido_id)navigate('importacoes-internacionais',{pedidoId:a.pedido_id,faturaEmbarqueId:a.embarque_id});
          else if(a.pedido_id)navigate('pedidos-compra',{pedidoId:a.pedido_id});
          else navigate('pagar');
        };
        const atalho=button('Abrir',abrir,'text-button');atalho.setAttribute('aria-label','Abrir '+a.titulo);
        r.insertCell().append(atalho);
      }
      scroll.append(table);agenda.append(scroll);
      if(d.agenda_total>d.agenda.length)agenda.append(el('p','Exibindo '+d.agenda.length+' de '+d.agenda_total+' registros.'));
    }
    conteudo.replaceChildren(cards,graficos,agenda);
  }
  async function show(){
    const run=++epoch;atualizar.disabled=true;status.textContent='Atualizando acompanhamento…';
    try{
      const r=await api({acao:'v2_painel_inicio',dias:Number(dias.value)});
      if(run!==epoch)return;
      render(r);
      status.textContent='Posição de '+dia(r.hoje)+' · Horário de Brasília';
    }catch(e){if(run===epoch){conteudo.replaceChildren();status.textContent=e.message;}}
    finally{if(run===epoch)atualizar.disabled=false;}
  }
  return {root,show,reset(){epoch++;conteudo.replaceChildren();status.textContent='';dias.value='7';atualizar.disabled=false;}};
}
