const groups = [
 ['Visão geral',[['inicio','Visão geral','home']]],
 ['Comercial',[['simulador','Simulador fiscal e comercial','fiscal'],['oportunidades','Oportunidades','comercial'],['propostas','Propostas comerciais','comercial'],['pedidos-comerciais','Pedidos comerciais internos','comercial'],['pedidos','Pedidos do portal RUMO','live'],['precos','Histórico de preços','live']]],
 ['Operação',[['compras','Compras','planned'],['importacoes-internacionais','Importações internacionais','importacoes-internacionais'],['estoque','Estoque e movimentações','planned'],['producao','Produção','planned'],['logistica','Expedição e entregas','planned']]],
 ['Financeiro',[['receber','Contas a receber','planned'],['pagar','Contas a pagar','planned'],['caixa','Fluxo de caixa','planned'],['conciliacao','Conciliação bancária','planned']]],
 ['Cadastros',[['clientes','Cadastro de Clientes','live'],['produtos','Produtos e identificadores','live'],['resolver','Pendências de produtos','live'],['fornecedores','Fornecedores','catalogo'],['equivalencias','Produtos por empresa','catalogo'],['estabelecimento','Estabelecimento AXE','fiscal','Fiscal'],['fiscal','Regras tributárias','fiscal','Fiscal'],['naturezas','Tipos de operação','fiscal','Fiscal'],['formulas','Fórmulas de cálculo','fiscal','Fiscal'],['perfis','Perfis de produtos','fiscal','Fiscal'],['destinatarios','Perfis de clientes','fiscal','Fiscal'],['clientes_fiscais','Vincular clientes a perfis','fiscal','Fiscal'],['tributacao-produtos','Tributação por produto','fiscal','Fiscal'],['regras','Conferência fiscal RUMO','live','Fiscal']]],
 ['Gestão',[['tarefas','Tarefas e atividades','gestao'],['projetos','Projetos','gestao'],['paginas','Conhecimento e controles','gestao'],['pedidos-gestao','Acompanhamento de pedidos','gestao'],['organizacoes','Organizações e contatos','gestao'],['documentos','Documentos e decisões','gestao'],['registros','Registros operacionais','gestao'],['indicadores','Indicadores e metas','planned'],['aprovacoes','Alçadas de aprovação','planned'],['relatorios','Relatórios gerenciais','planned'],['auditoria','Histórico de alterações','planned']]],
 ['Integrações',[['importacao','Importar e conciliar cadastros','importacao'],['integracoes','Portais de clientes','hub'],['operacao','Pedidos e conciliação','live','RUMO Logística'],['novo-portal','Outros portais de clientes','planned']]],
 ['Administração',[['usuarios','Usuários e permissões','planned']]]
];
const plans = {
 oportunidades:['Funil de oportunidades','Responsável, etapa e próxima ação','Previsão de fechamento'],
 propostas:['Propostas com código e descrição do cliente','Seleção de similares aceitos','Revisões e aprovação comercial'],
 compras:['Pedidos com código e descrição do fornecedor','Prazos e recebimentos parciais','Custos e documentos de importação'],
 estoque:['Saldo por produto e local','Reservas e disponibilidade','Entradas, saídas e inventário'],
 producao:['Ordens de produção','Estrutura de materiais','Consumo, apontamento e custo'],
 logistica:['Programação das entregas','Separação e expedição','Comprovantes e rastreabilidade'],
 receber:['Títulos e vencimentos','Recebimentos parciais','Cobrança e inadimplência'],
 pagar:['Compromissos e vencimentos','Aprovação de pagamentos','Baixas e comprovantes'],
 caixa:['Previsão de entradas e saídas','Saldo por conta','Realizado e previsto'],
 conciliacao:['Importação de extratos','Correspondência com títulos','Tratamento de diferenças'],
 fornecedores:['Empresas nacionais e estrangeiras','Contatos e condições comerciais','Homologação de fornecedores'],
 equivalencias:['Código e descrição por cliente e fornecedor','Part numbers e unidades de conversão','Similares aprovados por cliente'],
 indicadores:['Indicadores por área','Metas e períodos de comparação','Resultados e desvios'],
 aprovacoes:['Alçadas por tipo e valor','Responsáveis e substitutos','Registro das decisões'],
 relatorios:['Vendas, compras e margens','Posição financeira','Exportação e filtros por período'],
 auditoria:['Responsável e data da alteração','Valores anteriores e atuais','Consulta por registro'],
 usuarios:['Perfis por função','Permissões por módulo','Controle de acesso'],
 'novo-portal':['Conector específico para cada portal de cliente','Vínculo com os CNPJs de faturamento e suas permissões','Mapeamento de pedidos, documentos e situações','Histórico de sincronização e tratamento de falhas']
};
const make=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
export function initERP(cadastros,api,fiscal,catalogo,importacao,comercial,gestao,importacoesInternacionais){
 const panel=document.getElementById('panel'), oldNav=panel.querySelector('.portal-nav'),originalExit=document.getElementById('logout');
 oldNav.remove();panel.querySelector('.portal-toolbar').remove();
 const sidebar=make('aside',undefined,'erp-sidebar');sidebar.id='erp-menu';sidebar.setAttribute('aria-label','Navegação principal');
 const brand=make('div',undefined,'erp-brand');brand.append(make('span','A','brand-mark'),make('div','AXE','brand-name'));
 brand.lastChild.append(make('small','ENGENHARIA'));sidebar.append(brand,make('p','SISTEMA DE GESTÃO','sidebar-caption'));
 const reveal=make('button','☰','sidebar-reveal');reveal.type='button';reveal.setAttribute('aria-label','Expandir ou recolher menu');reveal.setAttribute('aria-controls',sidebar.id);reveal.title='Menu';sidebar.append(reveal);
 const filter=make('input');filter.type='search';filter.placeholder='Encontrar menu';filter.setAttribute('aria-label','Filtrar menus');sidebar.append(filter);
 const nav=make('nav');nav.setAttribute('aria-label','Menu principal');
 const routes=new Map(),buttons=new Map();
 for(const [group,items] of groups){
  const section=make('details',undefined,'menu-group');section.open=false;section.append(make('summary',group));
  const subgroups=new Map();
  for(const [key,title,type,subgroup] of items){
   let target=section;
   if(subgroup){if(!subgroups.has(subgroup)){const nested=make('details',undefined,'connector-submenu');nested.open=false;nested.append(make('summary',subgroup));section.append(nested);subgroups.set(subgroup,nested);}target=subgroups.get(subgroup);}
   routes.set(key,{group,title,type,subgroup});const b=make('button');b.type='button';b.dataset.route=key;
   b.append(make('span',title));if(type==='planned')b.append(make('span','Em breve','menu-status'));
   b.onclick=event=>{navigate(key);if(event.detail>0&&current===key)heading.querySelector('h1').focus({preventScroll:true});};buttons.set(key,b);target.append(b);
  }nav.append(section);
 }sidebar.append(nav,make('div','AXE Engenharia · ERP','sidebar-footer'));
 const workspace=make('div',undefined,'erp-workspace'),top=make('div',undefined,'erp-topbar');
 const toggle=make('button','☰','menu-toggle');toggle.type='button';toggle.setAttribute('aria-label','Abrir ou fechar menu');toggle.setAttribute('aria-expanded','false');
 toggle.setAttribute('aria-controls',sidebar.id);
 const desktop=window.matchMedia('(min-width:761px)');
 function syncMenu(){const expanded=panel.classList.contains('menu-open')||(desktop.matches&&(sidebar.classList.contains('menu-hover')||sidebar.contains(document.activeElement)));for(const b of [toggle,reveal])b.setAttribute('aria-expanded',String(expanded));}
 const toggleMenu=()=>{panel.classList.toggle('menu-open');syncMenu();};toggle.onclick=reveal.onclick=toggleMenu;
 sidebar.addEventListener('pointerenter',event=>{if(desktop.matches&&event.pointerType==='mouse'){sidebar.classList.add('menu-hover');syncMenu();}});
 sidebar.addEventListener('pointerleave',()=>{sidebar.classList.remove('menu-hover');syncMenu();});
 sidebar.addEventListener('focusin',syncMenu);sidebar.addEventListener('focusout',()=>queueMicrotask(syncMenu));
 panel.addEventListener('keydown',event=>{if(event.key==='Escape'&&(panel.classList.contains('menu-open')||sidebar.contains(document.activeElement))){panel.classList.remove('menu-open');sidebar.classList.remove('menu-hover');toggle.focus();syncMenu();event.preventDefault();}});
 desktop.addEventListener('change',()=>{panel.classList.remove('menu-open');sidebar.classList.remove('menu-hover');syncMenu();});syncMenu();
 const breadcrumb=make('span','Gestão / Visão geral','breadcrumb');
 const exit=originalExit;exit.id='logout';
 // Preserve the original sign-out handler even after moving its button.
 top.append(toggle,breadcrumb,make('span','Ambiente AXE','environment'),exit);
 const heading=make('div',undefined,'erp-heading'),eyebrow=make('p','VISÃO GERAL','eyebrow'),title=make('h1','Visão geral'),subtitle=make('p','');
 title.tabIndex=-1;heading.append(eyebrow,title,subtitle);
 const content=make('div',undefined,'erp-content'),home=make('section',undefined,'erp-home'),future=make('section',undefined,'erp-future');
 const hero=make('div',undefined,'welcome-card');hero.append(make('p','AXE ENGENHARIA','eyebrow'),make('h2','Toda a operação, uma visão.'),make('p','Acompanhe os controles disponíveis e a evolução do seu sistema de gestão.'));
 const quick=make('button','Abrir central de pendências','primary');quick.onclick=()=>navigate('resolver');hero.append(quick);home.append(hero);
 const stats=make('div',undefined,'erp-stats');const values={};
 for(const [key,label] of [['produtos','Produtos cadastrados'],['pedidos','Itens de pedidos'],['resolver','Pendências de cadastro']]){
  const card=make('button',undefined,'stat-card');card.type='button';card.onclick=()=>navigate(key);const value=make('strong','—');values[key]=value;card.append(make('span',label),value,make('small','Consultar registros →'));stats.append(card);
 }home.append(stats);const status=make('p','Os indicadores serão consultados ao entrar.','status');home.append(status);
 const refresh=make('button','Atualizar indicadores','secondary');refresh.onclick=()=>refreshStats();home.append(refresh);
 const moduleGrid=make('div',undefined,'module-grid');
 for(const [name,desc,target,items] of [
 ['Comercial','Do relacionamento com o cliente ao pedido de venda.','propostas',['Oportunidades e próximas ações','Propostas, revisões e aprovação','Pedidos comerciais internos']],
 ['Operação','Compras, estoque, produção e entrega conectados.','importacoes-internacionais',['Importações internacionais','Estoque e produção · em breve','Expedição e entregas · em breve']],
 ['Integrações','Conectores para os portais de cada cliente.','integracoes',['RUMO Logística · pedidos e conciliação','Empresas identificadas por CNPJ','Estrutura para novos portais de clientes']],
 ['Financeiro','Compromissos, recebimentos e previsibilidade de caixa.','receber',['Contas a pagar e receber · em breve','Fluxo de caixa · em breve','Conciliação bancária · em breve']],
 ['Gestão','Decisões apoiadas em indicadores e rastreabilidade.','indicadores',['Indicadores e metas · em breve','Alçadas e relatórios · em breve','Consulta de auditoria · em breve']]
 ]){
  const card=make('article',undefined,'module-card');card.append(make('h3',name),make('p',desc));const list=make('ul');items.forEach(i=>list.append(make('li',i)));const b=make('button','Explorar '+name,'text-button');b.onclick=()=>navigate(target);card.append(list,b);moduleGrid.append(card);
 }home.append(make('h2','Áreas de gestão','section-title'),moduleGrid);
 const roadmap=make('div',undefined,'roadmap-note');roadmap.append(make('strong','Evolução por etapas'),make('p','Os controles atuais continuam disponíveis. Menus com “Em breve” apresentam o escopo previsto e ainda não executam operações.'));home.append(roadmap);
 const operation=document.getElementById('operacao'),root=document.getElementById('cadastrosRoot');
 content.append(home,future,operation,root);workspace.append(top,heading,content);panel.replaceChildren(sidebar,workspace);
 filter.oninput=()=>{const q=filter.value.trim().toLocaleLowerCase('pt-BR');for(const section of nav.children){const groupMatch=section.querySelector('summary').textContent.toLocaleLowerCase('pt-BR').includes(q);let visible=0;for(const b of section.querySelectorAll('button')){const route=routes.get(b.dataset.route);b.hidden=!groupMatch&&!(b.textContent+' '+(route.subgroup||'')).toLocaleLowerCase('pt-BR').includes(q);if(!b.hidden)visible++;}for(const nested of section.querySelectorAll('.connector-submenu')){nested.hidden=![...nested.querySelectorAll('button')].some(b=>!b.hidden);if(q&&!nested.hidden)nested.open=true;}section.hidden=visible===0;if(q&&visible)section.open=true;}};
 let current='inicio',epoch=0;
 async function refreshStats(){
  const run=++epoch;refresh.disabled=true;status.textContent='Atualizando indicadores…';
  const keys=Object.keys(values);const result=await Promise.allSettled(keys.map(secao=>api({acao:'listar',secao,pagina:0})));
  if(run!==epoch)return;let errors=0;
  result.forEach((r,i)=>{const total=r.status==='fulfilled'?r.value.total:null;values[keys[i]].textContent=Number.isFinite(total)?total.toLocaleString('pt-BR'):'Indisponível';if(!Number.isFinite(total))errors++;});
  status.textContent=errors?'Alguns indicadores não puderam ser consultados. Tente atualizar.':'Atualizado em '+new Date().toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'});
  refresh.disabled=false;
 }
 function navigate(key,produtoId,expandirMenu=true){
  const route=routes.get(key);if(!route)return;if(importacoesInternacionais&&!importacoesInternacionais.canLeave())return;current=key;if(!panel.hidden){try{sessionStorage.setItem('axe:erp:ultima-tela',key);}catch{}}
  cadastros.show(null);if(fiscal)fiscal.show(null);if(catalogo)catalogo.show(null);if(importacao)importacao.show(false);if(comercial)comercial.show(null);if(gestao)gestao.show(null);if(importacoesInternacionais)importacoesInternacionais.show(false);home.hidden=true;future.hidden=true;
  for(const [k,b] of buttons){b.setAttribute('aria-current',k===key?'page':'false');if(k===key&&expandirMenu){let parent=b.parentElement;while(parent&&parent!==nav){if(parent.tagName==='DETAILS')parent.open=true;parent=parent.parentElement;}}}
  breadcrumb.textContent=[route.group,route.subgroup,route.title].filter(Boolean).join(' / ');eyebrow.textContent=(route.subgroup||route.group).toLocaleUpperCase('pt-BR');title.textContent=route.title;
  eyebrow.hidden=key==='clientes';subtitle.hidden=key==='clientes';
  subtitle.textContent=route.type==='planned'?'Estrutura prevista para a evolução do ERP.':'Controles da AXE Engenharia';
  if(key==='inicio')home.hidden=false;
  else if(route.type==='gestao')gestao.show(key==='pedidos-gestao'?'pedidos':key);
  else if(route.type==='comercial')comercial.show(key);
  else if(key==='importacoes-internacionais')importacoesInternacionais.show(true);
  else if(key==='importacao')importacao.show(true);
  else if(key==='fornecedores'||key==='equivalencias')catalogo.show(key,produtoId);
  else if(route.type==='live')cadastros.show(key);
  else if(route.type==='fiscal'){if(key==='simulador'&&typeof produtoId==='object')fiscal.openSimulation(produtoId);else if(produtoId)fiscal.openProduct(produtoId);else fiscal.show(key==='tributacao-produtos'?'produtos':key);}
  else if(route.type==='hub'){
   future.hidden=false;future.replaceChildren();const card=make('div',undefined,'planned-card');
   card.append(make('span','Conector disponível','badge'),make('h2','RUMO Logística'),make('p','Acesse os pedidos, a conciliação e as conferências do portal RUMO. Cada CNPJ de faturamento continua identificado separadamente nos cadastros e pedidos.'));
   const open=make('button','Abrir RUMO Logística','primary');open.onclick=()=>navigate('operacao');card.append(open);future.append(card);
   const next=make('div',undefined,'planned-card');next.append(make('h2','Outros portais de clientes'),make('p','Cada novo portal terá seu próprio conector e vínculo com as empresas atendidas. A configuração e os controles de sincronização serão implementados conforme cada integração.'));
   const scope=make('button','Ver estrutura prevista','secondary');scope.onclick=()=>navigate('novo-portal');next.append(scope);future.append(next);
  }
  else{
   future.hidden=false;future.replaceChildren();const card=make('div',undefined,'planned-card');
   card.append(make('span','Em breve','planned-badge'),make('h2',route.title),make('p','Este módulo está planejado. As operações estarão disponíveis após a implementação e validação.'));
   const list=make('ul');(plans[key]||[]).forEach(item=>list.append(make('li',item)));card.append(list);
   const back=make('button','Voltar à visão geral','secondary');back.onclick=()=>navigate('inicio');card.append(back);future.append(card);
  }
  panel.classList.remove('menu-open');syncMenu();
 }
 const observer=new MutationObserver(()=>{if(!panel.hidden){let saved='inicio';try{const key=sessionStorage.getItem('axe:erp:ultima-tela');if(routes.has(key))saved=key;}catch{}for(const group of nav.querySelectorAll('details'))group.open=false;navigate(saved,undefined,false);refreshStats();}else{epoch++;Object.values(values).forEach(v=>v.textContent='—');refresh.disabled=false;status.textContent='Os indicadores serão consultados ao entrar.';filter.value='';filter.oninput();}});
 observer.observe(panel,{attributes:true,attributeFilter:['hidden']});
 navigate('inicio',undefined,false);
 return {navigate};
}



