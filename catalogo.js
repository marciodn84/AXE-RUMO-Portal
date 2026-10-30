import {montarConsultaCNPJ} from './consulta-cnpj.js?v=20261029-cnpj26';
import {botoesPlanilha} from './planilha-cadastros.js?v=20261029-cliente25';
const node=(tag,text,cls)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
const labels={produto:'Produto',cliente:'Cliente',fornecedor:'Fornecedor',referencia_cliente:'Referência do cliente',opcao_cliente:'Produto aceito pelo cliente',produto_fornecedor:'Produto do fornecedor',similar:'Similar técnico',documento:'Documento do produto'};
const situations=[['EM_AVALIACAO','Em avaliação'],['APROVADO','Aprovado'],['BLOQUEADO','Bloqueado'],['INATIVO','Inativo']];
const bool=[['true','Sim'],['false','Não']];
const origins=[['0','0 · Nacional'],['1','1 · Importação direta'],['2','2 · Estrangeira adquirida no Brasil'],['3','3 · Nacional, conteúdo importado >40% a 70%'],['4','4 · Nacional, PPB'],['5','5 · Nacional, conteúdo importado até 40%'],['6','6 · Importação direta sem similar nacional'],['7','7 · Estrangeira adquirida no Brasil sem similar nacional'],['8','8 · Nacional, conteúdo importado >70%']];
const schemas={
 produto:['Identificação',['descricao_referencia','Descrição AXE','textarea',true],['codigo_anterior','Código anterior'],['forma_obtencao','Forma de obtenção','select',false,[['IMP','Importado diretamente'],['TER','Adquirido de terceiro'],['FAB','Fabricado pela AXE']]],['tipo_item','Tipo de item'],['unidade_referencia','Unidade de estoque / venda','text',true],['ativo','Ativo','bool',true],
 'Características técnicas',['descricao_tecnica','Descrição técnica','textarea'],['marca','Marca'],['fabricante','Fabricante'],['part_number','Part number'],['modelo','Modelo'],['composicao','Composição','textarea'],['aplicacao','Aplicação','textarea'],
 'Classificação fiscal',['ncm_referencia','NCM (8 números)'],['ex_tipi','Ex-TIPI'],['cest','CEST (7 números)'],['gtin','GTIN / código de barras'],['origem_fiscal_padrao','Origem fiscal','select',false,origins],['pais_origem','País de origem (duas letras)'],
 'Estoque e medidas',['controla_estoque','Controla estoque','bool'],['controle_lote','Controla lote','bool'],['controle_serie','Controla número de série','bool'],['estoque_minimo','Estoque mínimo','number'],['peso_liquido_kg','Peso líquido (kg)','number'],['peso_bruto_kg','Peso bruto (kg)','number'],['comprimento_mm','Comprimento (mm)','number'],['largura_mm','Largura (mm)','number'],['altura_mm','Altura (mm)','number'],['observacoes','Observações','textarea']],
 cliente:['Identificação',['cnpj','CNPJ (14 números)','text',true],['nome','Razão social','text',true],['nome_fantasia','Nome fantasia'],['inscricao_estadual','Inscrição estadual'],['grupo_comercial','Grupo comercial'],['ativo','Ativo','bool',true],
 'Contato',['contato','Responsável'],['email','E-mail','email'],['telefone','Telefone'],['observacoes','Observações','textarea']],
 fornecedor:['Identificação',['razao_social','Razão social / nome','text',true],['nome_fantasia','Nome fantasia'],['pais','País (BR, US, CN…)','text',true],['cnpj','CNPJ do fornecedor nacional'],['documento_fiscal','Identificação fiscal estrangeira'],['inscricao_estadual','Inscrição estadual'],['ativo','Ativo','bool',true],
 'Contato e endereço',['contato','Responsável'],['email','E-mail','email'],['telefone','Telefone'],['endereco','Endereço completo','textarea'],['observacoes','Observações','textarea']],
 referencia_cliente:['Empresa e código',['cliente_id','Cliente por CNPJ','lookup:cliente',true],['codigo_cliente','Código utilizado pelo cliente','text',true],['descricao_cliente','Descrição utilizada nos pedidos do cliente','textarea',true],['unidade_cliente','Unidade do cliente','text',true],['ativo','Ativa','bool',true],
 'Requisitos do cliente',['referencia_tecnica','Referência técnica'],['desenho','Desenho'],['revisao','Revisão do desenho'],['embalagem_exigida','Embalagem exigida'],['identificacao_exigida','Identificação exigida'],['certificados_exigidos','Certificados exigidos'],['observacoes','Observações','textarea']],
 opcao_cliente:['Produto e vínculo',['referencia_cliente_id','Referência do cliente','lookup:referencia_cliente',true],['produto_id','Produto AXE','lookup:produto',true],['tipo_vinculo','Tipo de vínculo','select',true,[['REFERENCIA','Referência principal'],['SIMILAR','Similar'],['PARALELO','Paralelo']]],['situacao','Situação','select',true,situations],
 'Unidades e condições',['fator_conversao','Unidades AXE por unidade do cliente','positive',true],['quantidade_minima','Quantidade mínima','number'],['multiplo_venda','Múltiplo de venda','positive'],['prazo_dias','Prazo (dias)','integer'],['valido_desde','Válido desde','date'],['valido_ate','Válido até','date'],
 'Aceite do cliente',['aprovado_por','Responsável pelo aceite do cliente'],['evidencia_aceite','Evidência do aceite (pedido, e-mail ou documento)','textarea'],['restricoes','Restrições de fornecimento','textarea']],
 produto_fornecedor:['Empresa e código',['produto_id','Produto AXE','lookup:produto',true],['fornecedor_id','Fornecedor','lookup:fornecedor',true],['codigo_fornecedor','Código utilizado pelo fornecedor','text',true],['descricao_fornecedor','Descrição utilizada pelo fornecedor','textarea',true],['fabricante','Fabricante'],['part_number','Part number do fornecedor'],['situacao','Situação','select',true,situations],['preferencial','Fornecedor preferencial deste produto','bool',true],
 'Compra e conversão',['unidade_compra','Unidade de compra','text',true],['fator_conversao','Unidades AXE por unidade de compra','positive',true],['quantidade_minima','Quantidade mínima de compra','number'],['multiplo_compra','Múltiplo de compra','positive'],['prazo_dias','Prazo (dias)','integer'],['moeda','Moeda (BRL, USD, EUR…)'],['valido_desde','Válido desde','date'],['valido_ate','Válido até','date'],
 'Informação fiscal do fornecedor',['ncm_informado','NCM informado na compra'],['origem_fiscal','Origem fiscal informada','select',false,origins],['pais_origem','País de origem'],['observacoes','Observações','textarea']],
 similar:['Relação técnica',['produto_id','Produto AXE','lookup:produto',true],['similar_id','Produto similar','lookup:produto',true],['justificativa','Justificativa técnica','textarea',true]],
 documento:['Referência documental',['produto_id','Produto AXE','lookup:produto',true],['tipo','Tipo de documento','text',true],['titulo','Título','text',true],['referencia_arquivo','Referência do arquivo ou endereço HTTPS','text',true],['revisao','Revisão'],['valido_desde','Válido desde','date'],['valido_ate','Válido até','date']]
};
const nameOf=(type,r)=>type==='produto'?[r.codigo_axe||r.codigo_anterior||'#'+r.id,r.descricao_referencia].join(' · '):type==='cliente'?['ID '+r.id,r.nome,r.cnpj].filter(Boolean).join(' · '):type==='fornecedor'?[r.razao_social,r.cnpj||r.documento_fiscal].filter(Boolean).join(' · '):['Cliente #'+r.cliente_id,r.codigo_cliente,r.descricao_cliente].join(' · ');
export function initCatalogo(api){
 const root=document.getElementById('cadastrosRoot');const screen=node('section',undefined,'cadastro-screen');screen.hidden=true;root.append(screen);
 let epoch=0,request=0,active=null,type='fornecedor',page=0,query='',productFilter=null,referenceFilter=null,dialog=null;
 const cache=new Map();
 const btn=(text,fn)=>{const b=node('button',text);b.type='button';b.onclick=async()=>{b.disabled=true;try{await fn();}catch(e){status.textContent=e.message;status.className='status error';}finally{b.disabled=false;}};return b;};
 const heading=node('h2'),intro=node('p',undefined,'intro'),tabs=node('div',undefined,'catalog-tabs'),tools=node('form',undefined,'searchbar'),search=node('input');search.type='search';search.placeholder='Buscar por nome, código ou descrição';search.setAttribute('aria-label','Buscar no catálogo');
 const status=node('p','','status');status.setAttribute('role','status');const tableWrap=node('div',undefined,'scroll'),table=node('table');tableWrap.append(table);
 const count=node('span'),previous=btn('Anterior',()=>{page--;return load();}),next=btn('Próxima',()=>{page++;return load();});const paging=node('div',undefined,'paging');paging.append(previous,count,next);
 tools.append(search,btn('Buscar',()=>{query=search.value.trim();page=0;return load();}),btn('Novo cadastro',()=>edit(type,null,productFilter?{produto_id:productFilter}:{})));
 const excelTools=botoesPlanilha('fornecedor',api,{ativo:()=>active==='fornecedores'&&!screen.hidden,versao:()=>epoch,status:(text,error)=>{status.textContent=text;status.className=error?'status error':'status';}});excelTools.hidden=true;tools.append(excelTools);
 tools.onsubmit=e=>{e.preventDefault();query=search.value.trim();page=0;load();};screen.append(heading,intro,tabs,tools,status,tableWrap,paging);
 async function lookupRecord(kind,id){if(!id)return null;const key=kind+':'+id;if(!cache.has(key))cache.set(key,api({acao:'detalhe',tipo:kind,id:Number(id)}).catch(e=>{cache.delete(key);throw e;}));return cache.get(key);}
 async function display(kind,id){const r=await lookupRecord(kind,id);return r?nameOf(kind,r):'Não informado';}
 function selectTab(kind){type=kind;page=0;query='';search.value='';referenceFilter=null;for(const b of tabs.querySelectorAll('button'))b.setAttribute('aria-pressed',String(b.dataset.kind===kind));return load();}
 async function show(key,produtoId){epoch++;screen.hidden=true;active=key;if(!key)return;screen.hidden=false;productFilter=produtoId||null;referenceFilter=null;cache.clear();tabs.replaceChildren();
  excelTools.hidden=key!=='fornecedores';
  heading.textContent=key==='fornecedores'?'Fornecedores':'Produtos por cliente e fornecedor';
  intro.textContent=key==='fornecedores'?'Cadastre fornecedores nacionais e estrangeiros e seus contatos.':'Cada código do cliente pode aceitar vários produtos AXE. Os produtos mantêm códigos, estoques e custos separados. A relação técnica não substitui o aceite do cliente.';
  const kinds=key==='fornecedores'?['fornecedor']:['referencia_cliente','opcao_cliente','produto_fornecedor','similar','documento'];
  for(const kind of kinds){const b=btn(labels[kind],()=>selectTab(kind));b.dataset.kind=kind;tabs.append(b);}
  if(productFilter){intro.append(node('span',' Filtro: produto AXE #'+productFilter+'.'));tabs.append(btn('Mostrar todos os produtos',()=>show(key)));}
  return selectTab(kinds[0]);
 }
 async function load(){const run=++request,gen=epoch,kind=type;status.className='status';status.textContent='Carregando…';previous.disabled=next.disabled=true;
  try{const filters={};if(productFilter&&['opcao_cliente','produto_fornecedor','similar','documento'].includes(kind))filters.produto_id=productFilter;if(referenceFilter&&kind==='opcao_cliente')filters.referencia_cliente_id=referenceFilter;
   const result=await api({acao:'listar',tipo:kind,pagina:page,busca:query,...filters});
   const rows=await Promise.all(result.linhas.map(async r=>{
    let cells;
    if(kind==='fornecedor')cells=[r.razao_social,r.cnpj||r.documento_fiscal||'Não informado',r.pais||'País pendente',[r.contato,r.email,r.telefone].filter(Boolean).join(' · '),r.ativo?'Ativo':'Inativo'];
    if(kind==='referencia_cliente')cells=[await display('cliente',r.cliente_id),r.codigo_cliente,r.descricao_cliente,r.unidade_cliente||'Unidade pendente',r.ativo?'Ativa':'Inativa'];
    if(kind==='opcao_cliente')cells=[await display('referencia_cliente',r.referencia_cliente_id),await display('produto',r.produto_id),r.tipo_vinculo,r.situacao,'Conversão: '+(r.fator_conversao??'pendente'),r.evidencia_aceite||'Sem evidência'];
    if(kind==='produto_fornecedor')cells=[await display('produto',r.produto_id),await display('fornecedor',r.fornecedor_id),r.codigo_fornecedor,r.descricao_fornecedor,(r.unidade_compra||'Unidade pendente')+' · fator '+(r.fator_conversao??'pendente'),r.situacao+(r.preferencial?' · Preferencial':'')];
    if(kind==='similar')cells=[await display('produto',r.produto_id),await display('produto',r.similar_id),r.justificativa];
    if(kind==='documento')cells=[await display('produto',r.produto_id),r.tipo,r.titulo,r.referencia_arquivo,r.revisao||'Sem revisão'];return {r,cells};
   }));if(gen!==epoch||run!==request)return;
   table.replaceChildren();const heads={fornecedor:['Fornecedor','Documento','País','Contato','Situação'],referencia_cliente:['Cliente','Código do cliente','Descrição do cliente','Unidade','Situação'],opcao_cliente:['Referência do cliente','Produto AXE','Vínculo','Situação','Unidades AXE / unidade cliente','Evidência'],produto_fornecedor:['Produto AXE','Fornecedor','Código do fornecedor','Descrição do fornecedor','Unidade / conversão','Situação'],similar:['Produto AXE','Similar técnico','Justificativa'],documento:['Produto','Tipo','Título','Referência','Revisão']};
   const h=node('tr');for(const title of [...heads[kind],'Ações'])h.append(node('th',title));const th=node('thead');th.append(h);table.append(th);const body=node('tbody');
   for(const {r,cells} of rows){const tr=node('tr');for(const value of cells)tr.append(node('td',value??'—'));const actions=node('td');actions.append(btn('Editar',()=>edit(kind,r.id)));
    if(kind==='referencia_cliente')actions.append(btn('Produtos aceitos',()=>{type='opcao_cliente';page=0;query='';search.value='';referenceFilter=r.id;return load();}),btn('Vincular produto AXE',()=>edit('opcao_cliente',null,{referencia_cliente_id:r.id})));
    if(kind==='fornecedor')actions.append(btn('Vincular produto',()=>edit('produto_fornecedor',null,{fornecedor_id:r.id})));
    tr.append(actions);body.append(tr);
   }table.append(body);count.textContent=result.total?`${page*50+1}–${page*50+rows.length} de ${result.total}`:'Nenhum registro';previous.disabled=page===0;next.disabled=(page+1)*50>=result.total;status.textContent=rows.length?'Consulta atualizada.':'Nenhum cadastro nesta consulta. Use “Novo cadastro” para começar.';
  }catch(e){if(gen===epoch&&run===request){status.textContent=e.message;status.className='status error';previous.disabled=page===0;}}
 }
 async function edit(kind,id,defaults={}){
  const gen=epoch;let record;try{record=id?await api({acao:'detalhe',tipo:kind,id:Number(id)}):{ativo:true,pais:kind==='fornecedor'?'BR':undefined,situacao:'EM_AVALIACAO',tipo_vinculo:'REFERENCIA',preferencial:false,...defaults};}catch(e){status.textContent=e.message;return;}if(gen!==epoch)return;
  if(dialog)dialog.remove();const dlg=node('dialog',undefined,'edit-dialog catalog-dialog');dialog=dlg;const form=node('form');form.append(node('h2',(id?'Editar: ':'Novo cadastro: ')+labels[kind]));
  if(kind==='produto')form.append(node('p','Código AXE: '+(record.codigo_axe||'gerado ao definir a forma de obtenção')+'. O código permanece igual se o NCM mudar. Alterações de descrição, unidade ou NCM voltam à conferência. Impostos e alíquotas são definidos nas regras fiscais.','intro'));
  if(kind==='cliente'){const identity=node('label','ID ERP'),value=node('input');value.type='text';value.readOnly=true;value.value=record.id??'';value.placeholder='Gerado automaticamente ao salvar';value.setAttribute('aria-label','ID ERP');identity.append(value);form.append(identity);}
  if(kind==='opcao_cliente'||kind==='produto_fornecedor')form.append(node('p','Conversão: quantidade de unidades AXE contida em uma unidade do cliente ou fornecedor. Ex.: uma caixa com 10 unidades AXE → fator 10.','intro'));
  const inputs={};let group;
  for(const field of schemas[kind]){
   if(typeof field==='string'){group=node('fieldset');group.append(node('legend',field));form.append(group);continue;}
   const [key,title,inputType='text',required=false,choices]=field;const label=node('label',title);let input;
   if(inputType==='textarea')input=node('textarea');else if(inputType==='select'||inputType==='bool'||inputType.startsWith('lookup:'))input=node('select');else{input=node('input');input.type=['positive','integer'].includes(inputType)?'number':inputType;}
   input.name=key;input.setAttribute('aria-label',title);input.required=required;
   if(input.tagName==='SELECT'){input.append(new Option('Selecione',''));for(const [value,text] of inputType==='bool'?bool:choices||[])input.append(new Option(text,value));}
   if(['number','positive','integer'].includes(inputType)){input.min=inputType==='positive'?'0.000001':'0';input.step=inputType==='integer'?'1':'0.000001';}
   if(input.tagName==='INPUT')input.maxLength=key==='cnpj'?14:1000;if(input.tagName==='TEXTAREA')input.maxLength=5000;
   if(key==='cnpj'){input.pattern='[0-9]{14}';input.inputMode='numeric';if(kind==='cliente'&&id)input.readOnly=true;}
   if(['ncm_referencia','ncm_informado'].includes(key))input.pattern='[0-9]{8}';if(key==='cest')input.pattern='[0-9]{7}';if(key==='gtin')input.pattern='([0-9]{8}|[0-9]{12}|[0-9]{13}|[0-9]{14})';
   if(['pais','pais_origem'].includes(key)){input.pattern='[A-Za-z]{2}';input.maxLength=2;}if(key==='moeda'){input.pattern='[A-Za-z]{3}';input.maxLength=3;}
   if(inputType.startsWith('lookup:')){
    const entity=inputType.split(':')[1],lookup=node('div',undefined,'catalog-lookup'),filter=node('input'),info=node('small','Busque por nome ou código.');filter.type='search';filter.placeholder='Localizar '+title.toLowerCase();filter.setAttribute('aria-label','Localizar '+title.toLowerCase());let sequence=0,lookupPage=0;
    async function find(reset=true){if(reset)lookupPage=0;const n=++sequence;info.textContent='Buscando…';try{const results=await api({acao:'listar',tipo:entity,pagina:lookupPage,busca:filter.value.trim()});if(n!==sequence||!dlg.isConnected)return;const selected=input.value,old=[...input.options].find(o=>o.value===selected);input.replaceChildren(new Option('Selecione',''));for(const r of results.linhas)input.append(new Option(nameOf(entity,r),r.id));if(old&&selected&&![...input.options].some(o=>o.value===selected))input.append(old);input.value=selected;info.textContent=results.total+' registros; página '+(lookupPage+1);more.disabled=(lookupPage+1)*50>=results.total;back.disabled=lookupPage===0;}catch(e){info.textContent=e.message;}}
    const locate=btn('Localizar',()=>find()),back=btn('Anteriores',()=>{lookupPage--;return find(false);}),more=btn('Mais opções',()=>{lookupPage++;return find(false);});back.disabled=true;more.disabled=true;
    filter.onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();find();}};lookup.append(filter,locate,back,more,info);label.append(lookup);
    if(record[key]){const selected=await lookupRecord(entity,record[key]);if(gen!==epoch)return;input.append(new Option(nameOf(entity,selected),record[key]));}
   }
   input.value=record[key]===null||record[key]===undefined?'':String(record[key]);
   if(key==='forma_obtencao'&&record.codigo_axe)input.disabled=true;
   label.append(input);group.append(label);inputs[key]={input,inputType};
   if(key==='ncm_referencia'){const hint=node('small');const update=()=>{const code=input.value.trim();hint.textContent=/^[0-9]{8}$/.test(code)?'Classificação pelo NCM: capítulo '+code.slice(0,2)+' · posição '+code.slice(0,4)+' · subposição '+code.slice(0,6):'Informe o NCM para identificar capítulo, posição e subposição.';};input.addEventListener('input',update);update();label.append(hint);}
  }
  const consultaCNPJ=montarConsultaCNPJ(form,inputs,api,kind,{valido:()=>gen===epoch&&dialog===dlg});
  const error=node('p','','status error');error.setAttribute('role','alert');const actions=node('div',undefined,'form-actions'),save=node('button','Salvar');save.type='submit';actions.append(btn('Cancelar',()=>dlg.close()),save);form.append(error,actions);dlg.append(form);document.body.append(dlg);dlg.showModal();
  let fingerprint='',req='';form.onsubmit=async e=>{e.preventDefault();if(consultaCNPJ?.pendente()){error.textContent='Aguarde a consulta do CNPJ terminar.';return;}if(!form.reportValidity())return;const data={};
   for(const [key,{input,inputType}] of Object.entries(inputs)){
    const value=input.value.trim();if(input.disabled)continue;
    if(inputType==='bool')data[key]=value===''?null:value==='true';else if(inputType.startsWith('lookup:')||['number','positive','integer'].includes(inputType))data[key]=value===''?null:Number(value);else data[key]=value||null;
   }
   if(kind==='fornecedor'&&data.pais?.toUpperCase()==='BR'&&!data.cnpj){error.textContent='Informe o CNPJ do fornecedor nacional.';return;}
   if(kind==='fornecedor'&&data.pais?.toUpperCase()!=='BR'&&!data.documento_fiscal){error.textContent='Informe a identificação fiscal estrangeira.';return;}
   if(kind==='opcao_cliente'&&data.situacao==='APROVADO'&&(!data.aprovado_por||!data.evidencia_aceite)){error.textContent='Informe o responsável e a evidência do aceite do cliente.';return;}
   if(data.valido_desde&&data.valido_ate&&data.valido_ate<data.valido_desde){error.textContent='A validade final deve ser igual ou posterior à inicial.';return;}
   if(id){data.id=Number(id);data.atualizado_em=record.atualizado_em;}
   const fp=JSON.stringify(data);if(fp!==fingerprint){req=crypto.randomUUID();fingerprint=fp;}data.requisicao_id=req;save.disabled=true;error.textContent='Salvando…';
   try{await api({acao:'salvar',tipo:kind,dados:data,...(consultaCNPJ?.cnpj()?{consulta_cnpj:consultaCNPJ.cnpj()}:{})});if(gen!==epoch)return;cache.clear();dlg.close();document.dispatchEvent(new CustomEvent('axe-catalogo-salvo'));if(active)await load();}catch(e){error.textContent=e.message;}finally{save.disabled=false;}
  };
 }
 document.addEventListener('axe-editar-catalogo',e=>edit(e.detail.tipo,e.detail.id));
 return {show,edit,reset(){epoch++;request++;active=null;screen.hidden=true;table.replaceChildren();cache.clear();if(dialog)dialog.remove();dialog=null;}};
}


