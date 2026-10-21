const groups = [
 ['Visão geral',[['inicio','Visão geral','home']]],
 ['Comercial',[['oportunidades','Oportunidades','planned'],['propostas','Propostas comerciais','planned'],['pedidos','Pedidos de venda','live'],['precos','Histórico de preços','live']]],
 ['Operação',[['operacao','Conciliação RUMO','live'],['resolver','Central de pendências','live'],['compras','Compras e importações','planned'],['estoque','Estoque e movimentações','planned'],['producao','Produção','planned'],['logistica','Expedição e entregas','planned']]],
 ['Financeiro',[['receber','Contas a receber','planned'],['pagar','Contas a pagar','planned'],['caixa','Fluxo de caixa','planned'],['conciliacao','Conciliação bancária','planned']]],
 ['Cadastros',[['clientes','Clientes e endereços','live'],['produtos','Produtos e identificadores','live'],['fornecedores','Fornecedores','planned'],['equivalencias','Produtos por empresa','planned'],['regras','Regras fiscais','live']]],
 ['Gestão',[['indicadores','Indicadores e metas','planned'],['aprovacoes','Alçadas de aprovação','planned'],['relatorios','Relatórios gerenciais','planned'],['auditoria','Histórico de alterações','planned']]],
 ['Administração',[['usuarios','Usuários e permissões','planned'],['integracoes','Integrações','planned']]]
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
 integracoes:['Acompanhamento das integrações','Histórico de execução e falhas','Configuração por serviço']
};
const make=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
export function initERP(cadastros,api){
 const panel=document.getElementById('panel'), oldNav=panel.querySelector('.portal-nav'),originalExit=document.getElementById('logout');
 oldNav.remove();panel.querySelector('.portal-toolbar').remove();
 const sidebar=make('aside',undefined,'erp-sidebar');
 const brand=make('div',undefined,'erp-brand');brand.append(make('span','A','brand-mark'),make('div','AXE','brand-name'));
 brand.lastChild.append(make('small','ENGENHARIA'));sidebar.append(brand,make('p','SISTEMA DE GESTÃO','sidebar-caption'));
 const filter=make('input');filter.type='search';filter.placeholder='Encontrar menu';filter.setAttribute('aria-label','Filtrar menus');sidebar.append(filter);
 const nav=make('nav');nav.setAttribute('aria-label','Menu principal');
 const routes=new Map(),buttons=new Map();
 for(const [group,items] of groups){
  const section=make('details',undefined,'menu-group');section.open=true;section.append(make('summary',group));
  for(const [key,title,type] of items){
   routes.set(key,{group,title,type});const b=make('button');b.type='button';b.dataset.route=key;
   b.append(make('span',title));if(type==='planned')b.append(make('span','Em breve','menu-status'));
   b.onclick=()=>navigate(key);buttons.set(key,b);section.append(b);
  }nav.append(section);
 }sidebar.append(nav,make('div','AXE Engenharia · ERP','sidebar-footer'));
 const workspace=make('div',undefined,'erp-workspace'),top=make('div',undefined,'erp-topbar');
 const toggle=make('button','☰','menu-toggle');toggle.type='button';toggle.setAttribute('aria-label','Abrir ou fechar menu');toggle.setAttribute('aria-expanded','false');
 toggle.onclick=()=>{const open=panel.classList.toggle('menu-open');toggle.setAttribute('aria-expanded',String(open));};
 const breadcrumb=make('span','Gestão / Visão geral','breadcrumb');
 const exit=originalExit;exit.id='logout';
 // Preserve the original sign-out handler even after moving its button.
 top.append(toggle,breadcrumb,make('span','Ambiente AXE','environment'),exit);
 const heading=make('div',undefined,'erp-heading'),eyebrow=make('p','VISÃO GERAL','eyebrow'),title=make('h1','Visão geral'),subtitle=make('p','');
 heading.append(eyebrow,title,subtitle);
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
 ['Comercial','Do relacionamento com o cliente ao pedido de venda.','pedidos',['Clientes e pedidos','Preços e condições','Propostas e oportunidades · em breve']],
 ['Operação','Produtos, compras, produção e entrega conectados.','operacao',['Conciliação RUMO','Pendências de cadastro','Estoque, compras e produção · em breve']],
 ['Financeiro','Compromissos, recebimentos e previsibilidade de caixa.','receber',['Contas a pagar e receber · em breve','Fluxo de caixa · em breve','Conciliação bancária · em breve']],
 ['Gestão','Decisões apoiadas em indicadores e rastreabilidade.','indicadores',['Indicadores e metas · em breve','Alçadas e relatórios · em breve','Consulta de auditoria · em breve']]
 ]){
  const card=make('article',undefined,'module-card');card.append(make('h3',name),make('p',desc));const list=make('ul');items.forEach(i=>list.append(make('li',i)));const b=make('button','Explorar '+name,'text-button');b.onclick=()=>navigate(target);card.append(list,b);moduleGrid.append(card);
 }home.append(make('h2','Áreas de gestão','section-title'),moduleGrid);
 const roadmap=make('div',undefined,'roadmap-note');roadmap.append(make('strong','Evolução por etapas'),make('p','Os controles atuais continuam disponíveis. Menus com “Em breve” apresentam o escopo previsto e ainda não executam operações.'));home.append(roadmap);
 const operation=document.getElementById('operacao'),root=document.getElementById('cadastrosRoot');
 content.append(home,future,operation,root);workspace.append(top,heading,content);panel.replaceChildren(sidebar,workspace);
 filter.oninput=()=>{const q=filter.value.trim().toLocaleLowerCase('pt-BR');for(const section of nav.children){const groupMatch=section.querySelector('summary').textContent.toLocaleLowerCase('pt-BR').includes(q);let visible=0;for(const b of section.querySelectorAll('button')){b.hidden=!groupMatch&&!b.textContent.toLocaleLowerCase('pt-BR').includes(q);if(!b.hidden)visible++;}section.hidden=visible===0;if(q&&visible)section.open=true;}};
 let current='inicio',epoch=0;
 async function refreshStats(){
  const run=++epoch;refresh.disabled=true;status.textContent='Atualizando indicadores…';
  const keys=Object.keys(values);const result=await Promise.allSettled(keys.map(secao=>api({acao:'listar',secao,pagina:0})));
  if(run!==epoch)return;let errors=0;
  result.forEach((r,i)=>{const total=r.status==='fulfilled'?r.value.total:null;values[keys[i]].textContent=Number.isFinite(total)?total.toLocaleString('pt-BR'):'Indisponível';if(!Number.isFinite(total))errors++;});
  status.textContent=errors?'Alguns indicadores não puderam ser consultados. Tente atualizar.':'Atualizado em '+new Date().toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'});
  refresh.disabled=false;
 }
 function navigate(key){
  const route=routes.get(key);if(!route)return;current=key;
  cadastros.show(null);home.hidden=true;future.hidden=true;
  for(const [k,b] of buttons){b.setAttribute('aria-current',k===key?'page':'false');if(k===key)b.closest('details').open=true;}
  breadcrumb.textContent=route.group+' / '+route.title;eyebrow.textContent=route.group.toLocaleUpperCase('pt-BR');title.textContent=route.title;
  subtitle.textContent=route.type==='planned'?'Estrutura prevista para a evolução do ERP.':'Controles da AXE Engenharia';
  if(key==='inicio')home.hidden=false;
  else if(route.type==='live')cadastros.show(key);
  else{
   future.hidden=false;future.replaceChildren();const card=make('div',undefined,'planned-card');
   card.append(make('span','Em breve','planned-badge'),make('h2',route.title),make('p','Este módulo está planejado. As operações estarão disponíveis após a implementação e validação.'));
   const list=make('ul');(plans[key]||[]).forEach(item=>list.append(make('li',item)));card.append(list);
   const back=make('button','Voltar à visão geral','secondary');back.onclick=()=>navigate('inicio');card.append(back);future.append(card);
  }
  panel.classList.remove('menu-open');toggle.setAttribute('aria-expanded','false');
 }
 const observer=new MutationObserver(()=>{if(!panel.hidden){navigate('inicio');refreshStats();}else{epoch++;Object.values(values).forEach(v=>v.textContent='—');refresh.disabled=false;status.textContent='Os indicadores serão consultados ao entrar.';filter.value='';filter.oninput();}});
 observer.observe(panel,{attributes:true,attributeFilter:['hidden']});
 navigate('inicio');
 return {navigate};
}
