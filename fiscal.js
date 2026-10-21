const e=(tag,text,cls)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
const btn=(text,fn)=>{const b=e('button',text);b.type='button';b.onclick=fn;return b;};
const taxes=['II','IPI','ICMS','ICMS_ST','FCP','PIS','COFINS','IBS_UF','IBS_MUN','CBS','IS'];
const names={II:'Imposto de Importação',ICMS_ST:'ICMS-ST',IBS_UF:'IBS estadual',IBS_MUN:'IBS municipal',IS:'Imposto Seletivo'};
const ufs='AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO'.split(' ');
const numKeys=['natureza_id','perfil_id','produto_id','cliente_id','fornecedor_id','perfil_destinatario_id'];
export function initFiscal(api){
 const root=e('section',undefined,'cadastro-screen fiscal-screen');root.hidden=true;document.getElementById('cadastrosRoot').append(root);
 let section='regras',page=0,search='',product=null,options=null,epoch=0,modal=null,filter='';
 const title=e('h2','Cadastro fiscal'),intro=e('p','Regras por operação e vigência. A validação registra a aprovação fiscal; não ativa emissão nem cálculo automático de documentos.','intro');
 const tabs=e('nav',undefined,'fiscal-tabs');tabs.setAttribute('aria-label','Cadastros fiscais');
 const tabButtons={};for(const [key,label] of [['estabelecimento','Estabelecimento AXE'],['regras','Regras tributárias'],['naturezas','Tipos de operação'],['perfis','Perfis de produtos'],['destinatarios','Perfis de clientes'],['clientes_fiscais','Vincular clientes'],['produtos','Tributação por produto']]){const b=btn(label,()=>{section=key;page=0;product=null;load();});tabButtons[key]=b;tabs.append(b);}
 const form=e('form',undefined,'searchbar'),input=e('input');input.type='search';input.placeholder='Buscar por título, nome ou produto';input.setAttribute('aria-label','Buscar cadastro fiscal');
 const submit=e('button','Buscar');submit.type='submit';const add=btn('Novo registro',()=>editSimple());
 const situation=e('select');situation.setAttribute('aria-label','Situação da regra');for(const [v,t] of [['','Todas as situações'],['RASCUNHO','Rascunhos'],['VALIDADA','Validadas'],['INATIVA','Inativas']])situation.append(new Option(t,v));situation.onchange=()=>{filter=situation.value;page=0;load();};
 form.append(input,submit,btn('Atualizar',()=>load()),situation,add,btn('Simular seleção',()=>simulate()));form.onsubmit=ev=>{ev.preventDefault();search=input.value.trim();page=0;load();};
 const msg=e('p','','status');msg.setAttribute('role','status');const body=e('div'),paging=e('div',undefined,'paging'),count=e('span');
 const prev=btn('Anterior',()=>{page--;load();}),next=btn('Próxima',()=>{page++;load();});paging.append(prev,count,next);root.append(title,intro,tabs,form,msg,body,paging);
 async function getOptions(){options=await api({acao:'opcoes'});return options;}
 function say(text,error=false){msg.textContent=text;msg.className=error?'status error':'status';}
 async function run(type,data){return api({acao:'salvar',tipo:type,dados:{...data,requisicao_id:crypto.randomUUID()}});}
 function labelFor(type,id){return options?.[type]?.linhas.find(x=>x.id===id)?.nome||'#'+id;}
 function ruleCard(r){
  const card=e('article',undefined,'source-card');card.append(e('span',r.situacao,'badge'),e('h3',r.titulo+' · versão '+r.versao),e('p',labelFor('naturezas',r.natureza_id)+' · '+r.vigencia_inicio+' até '+(r.vigencia_fim||'sem data final')));
  card.append(e('p',[r.produto_id?'Produto #'+r.produto_id:null,r.perfil_id?'Perfil: '+labelFor('perfis',r.perfil_id):null,r.ncm?'NCM '+r.ncm:null].filter(Boolean).join(' · ')));
  const conditions=[r.empresa_cnpj?'Empresa '+r.empresa_cnpj:null,r.regime_tributario,r.perfil_destinatario_id?'Perfil de clientes: '+labelFor('destinatarios',r.perfil_destinatario_id):null,r.consumidor_final!=null?'Consumidor final: '+(r.consumidor_final?'sim':'não'):null,r.finalidade_destinatario,r.sujeito_st!=null?'ST: '+(r.sujeito_st?'sim':'não'):null,r.forma_obtencao,r.perfil_contraparte,r.cliente_id?'Exceção para cliente #'+r.cliente_id:'Todos os clientes compatíveis',r.fornecedor_id?'Fornecedor #'+r.fornecedor_id:null,'AXE: PR',r.ufs_contraparte?.length?'UFs da contraparte: '+r.ufs_contraparte.join(', '):null,r.paises_contraparte?.length?'Países da contraparte: '+r.paises_contraparte.join(', '):null,!r.ufs_contraparte?.length&&!r.paises_contraparte?.length?'Todas as localidades do mercado da operação':null,r.municipio_destino?'Município '+r.municipio_destino:null,r.pais_origem,r.cfop?'CFOP '+r.cfop:null];card.append(e('p',conditions.filter(Boolean).join(' · ')||'Contexto ainda não informado'));
  const details=e('details');details.append(e('summary','Tributos e fundamentação'));
  for(const t of r.tributos||[]){details.append(e('p',(names[t.tributo]||t.tributo)+' · '+t.tratamento+' · Alíquota: '+(t.aliquota??'não informada')+'%'+(t.cst?' · CST '+t.cst:'')+(t.cclass_trib?' · cClassTrib '+t.cclass_trib:'')+' · Base: '+(t.base_calculo||'não informada')));details.append(e('p',[t.reducao_base!=null?'Redução de base: '+t.reducao_base+'%':null,t.reducao_aliquota!=null?'Redução de alíquota: '+t.reducao_aliquota+'%':null,t.diferimento!=null?'Diferimento: '+t.diferimento+'%':null,t.beneficio?'Benefício: '+t.beneficio:null,t.credito?'Créditos: '+t.credito:null].filter(Boolean).join(' · ')));}
  details.append(e('p','Fonte: '+(r.fonte||'não informada')),e('p','Fundamento: '+(r.fundamento_legal||'não informado')),e('p','Consulta: '+(r.data_consulta||'não informada')+' · Tabela: '+(r.versao_tabela||'não informada')));card.append(details);
  if(r.situacao==='RASCUNHO'){card.append(btn('Editar rascunho',()=>editRule(r)),btn('Validar regra',()=>transition('validar',r)));}
  card.append(btn('Criar nova versão',()=>transition('revisar',r)),btn('Simular aplicação',()=>simulate(r)));if(r.situacao!=='INATIVA')card.append(btn('Inativar',()=>transition('inativar',r)));return card;
 }
 async function transition(type,r){
  if(type!=='revisar'&&!confirm(type==='validar'?'Confirmar que esta regra e seus códigos foram conferidos com a orientação fiscal? A versão validada ficará protegida contra edição.':'Inativar esta regra?'))return;
  try{await run(type,{id:r.id,atualizado_em:r.atualizado_em,confirmacao:'CONFIRMAR'});await load();}catch(err){say(err.message,true);}
 }
 async function load(){
  const gen=++epoch;Object.entries(tabButtons).forEach(([k,b])=>b.setAttribute('aria-pressed',String(k===section)));
  add.hidden=['produtos','clientes_fiscais','estabelecimento'].includes(section);add.textContent=section==='regras'?'Nova regra':['perfis','destinatarios'].includes(section)?'Novo perfil':'Novo tipo de operação';situation.hidden=section!=='regras';
  prev.disabled=next.disabled=true;say('Carregando...');body.replaceChildren();
  try{
   await getOptions();if(gen!==epoch)return;
   if(section==='estabelecimento'){renderCompany();count.textContent='';say('Estabelecimento fiscal da AXE.');return;}
   if(product&&section==='produtos')return await loadProduct(product.id,gen);
   const d=await api({acao:'listar',secao:section,pagina:page,busca:search,situacao:section==='regras'?filter:undefined});if(gen!==epoch)return;
   for(const r of d.linhas){
    if(section==='regras')body.append(ruleCard(r));
    else{const card=e('article',undefined,'source-card');card.append(e('h3',section==='produtos'?(r.codigo_axe||r.codigo_anterior||'#'+r.id)+' · '+r.descricao_referencia:r.codigo+' · '+r.nome));
     if(section==='produtos')card.append(e('p','NCM '+(r.ncm_referencia||'pendente')),btn('Abrir tributação',()=>{product=r;page=0;load();}));
     else if(section==='clientes_fiscais'){card.querySelector('h3').textContent=r.nome+' · '+r.cnpj;const select=e('select');select.setAttribute('aria-label','Perfil fiscal de '+r.nome);select.append(new Option('Perfil ainda não definido',''));for(const p of options.destinatarios.linhas)select.append(new Option(p.nome,p.id));select.value=r.perfil_destinatario_id||'';card.append(select,btn('Salvar perfil do cliente',async()=>{try{await run('vinculo_cliente',{cliente_id:r.id,perfil_destinatario_id:select.value,atualizado_em:r.atualizado_em});await load();}catch(err){say(err.message,true);}}));}
     else if(section==='naturezas'){card.append(e('p',r.direcao+' · '+r.mercado+' · '+r.contraparte),e('p','Estoque: '+(r.efeito_estoque||'pendente')+' · Financeiro: '+(r.efeito_financeiro||'pendente')),e('p','CFOP interno: '+(r.cfop_interno||'pendente')+' · Interestadual: '+(r.cfop_interestadual||'pendente')+' · Exterior: '+(r.cfop_exterior||'pendente')),e('p','Cobertura de tributos: '+((r.tributos_esperados||[]).join(', ')||'a definir')),e('p',r.configurada?'Parâmetros cadastrados; movimentações operacionais serão implementadas nas próximas etapas.':'Configuração pendente'),btn('Editar operação',()=>editSimple(r)));}
     else card.append(e('p',r.condicao_icms|| (r.operacao? r.operacao+' · '+r.finalidade+(r.cfop?' · CFOP '+r.cfop:''):(r.descricao||'Sem descrição'))));body.append(card);}
   }
   count.textContent=d.total?(page*50+1)+'–'+(page*50+d.linhas.length)+' de '+d.total:'Nenhum registro';prev.disabled=page===0;next.disabled=(page+1)*50>=d.total;say(d.linhas.length?'Consulta atualizada.':'Nenhum registro nesta consulta.');
  }catch(err){if(gen===epoch)say(err.message,true);}
 }
 async function loadProduct(id,gen){
  const d=await api({acao:'produto',id,pagina:page});if(gen!==epoch)return;product=d.produto;
  const card=e('article',undefined,'source-card');card.append(e('h3',(product.codigo_axe||product.codigo_anterior||'#'+id)+' · '+product.descricao_referencia),e('p','NCM: '+(product.ncm_referencia||'não informado')));
  const select=e('select');select.setAttribute('aria-label','Perfil fiscal padrão do produto');select.append(new Option('Sem perfil fiscal',''));for(const p of options.perfis.linhas.filter(x=>x.ativo))select.append(new Option(p.codigo+' · '+p.nome,p.id));select.value=product.perfil_fiscal_id||'';
  card.append(e('p','Perfil fiscal padrão'),select,btn('Salvar perfil',async()=>{try{await run('vinculo',{produto_id:product.id,perfil_id:select.value,atualizado_em:product.atualizado_em});await load();}catch(err){say(err.message,true);}}),btn('Nova regra exclusiva',()=>editRule({produto_id:product.id,ncm:product.ncm_referencia})),btn('Voltar aos produtos',()=>{product=null;page=0;load();}));body.append(card);
  body.append(e('p','Regras relacionadas por produto, perfil ou NCM. Confira operação, condições e vigência; esta consulta não seleciona nem calcula tributos automaticamente.','intro'));
  for(const r of d.regras.linhas)body.append(ruleCard(r));if(!d.regras.total)body.append(e('p','Nenhuma regra relacionada a este produto.'));
  count.textContent=d.regras.total+' regra(s) relacionada(s)';prev.disabled=page===0;next.disabled=(page+1)*50>=d.regras.total;say('Tributação consultada.');
 }
 function openDialog(titleText){if(modal)modal.remove();modal=e('dialog',undefined,'edit-dialog fiscal-dialog');const f=e('form');f.append(e('h2',titleText));const error=e('p','','error');error.setAttribute('role','alert');modal.append(f);document.body.append(modal);modal.showModal();return {f,error};}
 function field(form,key,label,kind='text',value='',required=false,choices=[]){const l=e('label',label);let n;
  if(kind==='select'){n=e('select');n.append(new Option('Não definido',''));for(const [v,t] of choices)n.append(new Option(t,v));}
  else if(kind==='textarea')n=e('textarea');else{n=e('input');n.type=kind;if(kind==='number'){n.min=0;n.max=100;n.step='any';}}
  n.name=key;n.value=value??'';n.required=required;l.append(n);form.append(l);return n;
 }
 function actions(f,error,save){const row=e('div',undefined,'form-actions');row.append(btn('Cancelar',()=>modal.close()));const b=e('button','Salvar rascunho');b.type='submit';row.append(b);f.append(error,row);let fingerprint='',request='';const gen=epoch;
  f.onsubmit=async ev=>{ev.preventDefault();if(!f.reportValidity())return;b.disabled=true;try{const payload=save();const hash=JSON.stringify(payload);if(hash!==fingerprint){fingerprint=hash;request=crypto.randomUUID();}await api({acao:'salvar',tipo:payload.tipo,dados:{...payload.dados,requisicao_id:request}});if(gen!==epoch)return;modal.close();await load();}catch(err){error.textContent=err.message;}finally{b.disabled=false;}};return b;
 }
 function renderCompany(){
  const emp=options.estabelecimento.linhas[0],card=e('article',undefined,'source-card');
  card.append(e('h3',emp.nome),e('p','CNPJ '+emp.cnpj+' · '+emp.uf+' · Lucro presumido'),e('p','Endereço: '+(emp.endereco||'Ainda não informado')),e('p','Município IBGE: '+(emp.municipio_ibge||'Ainda não informado')),e('p','Origem fixa nas saídas e destino fixo nas entradas.'));
  card.append(btn('Completar endereço fiscal',()=>{const {f,error}=openDialog('Estabelecimento fiscal da AXE');f.append(e('p','CNPJ, UF e regime são os dados confirmados da AXE.'));const municipio=field(f,'municipio_ibge','Código IBGE do município','text',emp.municipio_ibge);municipio.pattern='41[0-9]{5}';const endereco=field(f,'endereco','Endereço fiscal completo','textarea',emp.endereco);actions(f,error,()=>({tipo:'estabelecimento',dados:{municipio_ibge:municipio.value,endereco:endereco.value,atualizado_em:emp.atualizado_em}})).textContent='Salvar endereço';}));body.append(card);
 }
 function editSimple(r={}){if(section==='regras')return editRule({});const type=section==='destinatarios'?'perfil_destinatario':section==='perfis'?'perfil':'natureza';const {f,error}=openDialog(type==='perfil_destinatario'?'Novo perfil de clientes':type==='perfil'?'Novo perfil fiscal':r.id?'Editar tipo de operação':'Novo tipo de operação');const fields={};
  fields.codigo=field(f,'codigo','Código','text',r.codigo,true);fields.codigo.pattern='[A-Za-z0-9_]{2,60}';fields.codigo.readOnly=Boolean(r.id);fields.nome=field(f,'nome','Nome','text',r.nome,true);
  if(type==='perfil_destinatario')fields.condicao_icms=field(f,'condicao_icms','Condição perante o ICMS','select','',true,[['CONTRIBUINTE','Contribuinte'],['ISENTO','Isento de inscrição'],['NAO_CONTRIBUINTE','Não contribuinte']]);
  else if(type==='perfil')fields.descricao=field(f,'descricao','Descrição e critérios','textarea');
  else{
   for(const [key,title,values] of [['operacao','Operação',['COMPRA','IMPORTACAO','VENDA','DEVOLUCAO','REMESSA','RETORNO','TRANSFERENCIA','BONIFICACAO']],['direcao','Direção',['ENTRADA','SAIDA']],['mercado','Mercado da contraparte',['DOMESTICO','EXTERIOR']],['contraparte','Relacionamento',['CLIENTE','FORNECEDOR','OUTRA']],['efeito_estoque','Efeito no estoque',['ENTRADA','SAIDA','NENHUM']],['efeito_financeiro','Efeito financeiro',['PAGAR','RECEBER','NENHUM']]])fields[key]=field(f,key,title,'select',r[key],true,values.map(v=>[v,v]));
   fields.finalidade=field(f,'finalidade','Finalidade','text',r.finalidade);
   for(const [key,title] of [['cfop_interno','CFOP dentro do estado'],['cfop_interestadual','CFOP interestadual'],['cfop_exterior','CFOP exterior']]){fields[key]=field(f,key,title,'text',r[key]);fields[key].pattern='[1-7][0-9]{3}';}
   f.append(e('h3','Tributos que precisam de regra'),e('p','Selecione a cobertura fiscal exigida. Isenção ou não incidência também devem ter regra explícita. Sem esta definição a simulação não considera a cobertura completa.'));
  }
  const expected=[];if(type==='natureza')for(const tax of taxes){const l=e('label',names[tax]||tax),c=e('input');c.type='checkbox';c.checked=(r.tributos_esperados||[]).includes(tax);l.prepend(c);f.append(l);expected.push({tax,c});}
  actions(f,error,()=>({tipo:type,dados:{...Object.fromEntries(Object.entries(fields).map(([k,n])=>[k,n.value.trim()])),...(type==='natureza'?{tributos_esperados:expected.filter(x=>x.c.checked).map(x=>x.tax)}:{}),...(r.id?{id:r.id,atualizado_em:r.atualizado_em}:{})}})).textContent='Salvar';
 }
 function locationFields(f,nodes,r,simulation=false){
  const emp=options.estabelecimento.linhas[0];nodes.empresa_cnpj.value=emp.cnpj;nodes.empresa_cnpj.readOnly=true;nodes.regime_tributario.value=emp.regime_tributario;nodes.regime_tributario.disabled=true;
  const note=e('p','','intro');nodes.natureza_id.closest('label').after(note);
  const geo=e('fieldset');geo.append(e('legend','Localidades da contraparte'));
  const allLabel=e('label','Todos os estados do Brasil'),all=e('input');all.type='checkbox';all.checked=!(r.ufs_contraparte||[]).length;allLabel.prepend(all);geo.append(allLabel);
  const grid=e('div',undefined,'uf-grid'),choices=[];for(const uf of ufs){const l=e('label',uf),check=e('input');check.type='checkbox';check.checked=(r.ufs_contraparte||[]).includes(uf);check.disabled=all.checked;l.prepend(check);grid.append(l);choices.push({uf,check});}geo.append(grid);all.onchange=()=>choices.forEach(x=>x.check.disabled=all.checked);
  const countries=field(geo,'paises_contraparte','Países da contraparte (ISO: CN, US, DE; vazio = todos os países estrangeiros)','text',(r.paises_contraparte||[]).join(', '));
  if(!simulation)nodes.natureza_id.closest('label').after(geo);
  const toggle=()=>{
   const n=options.naturezas.linhas.find(x=>x.id===Number(nodes.natureza_id.value));if(!n)return;
   const entry=n.direcao==='ENTRADA',foreign=n.mercado==='EXTERIOR';note.textContent=entry?'Entrada: destino fixo no estabelecimento AXE, Paraná.':'Saída: origem fixa no estabelecimento AXE, Paraná.';
   const fixed=entry?'uf_destino':'uf_origem',other=entry?'uf_origem':'uf_destino';
   for(const k of ['uf_origem','uf_destino']){nodes[k].readOnly=k===fixed;nodes[k].required=simulation;nodes[k].closest('label').hidden=!simulation&&k===other;}
   nodes[fixed].value=emp.uf;if(nodes[other].readOnly)nodes[other].readOnly=false;
   if(simulation){nodes[other].closest('label').hidden=foreign;nodes[other].required=!foreign;if(foreign)nodes[other].value='EX';else if(nodes[other].value==='EX')nodes[other].value='';}
   allLabel.hidden=grid.hidden=foreign;countries.closest('label').hidden=!foreign;
   if(nodes.pais_origem){nodes.pais_origem.closest('label').hidden=true;nodes.pais_origem.value='';}
   if(nodes.pais_contraparte){nodes.pais_contraparte.closest('label').hidden=!foreign;nodes.pais_contraparte.required=foreign;}
   nodes.municipio_destino.closest('label').hidden=entry;if(entry)nodes.municipio_destino.value=emp.municipio_ibge||'';
   for(const k of ['cliente_id','perfil_destinatario_id'])if(nodes[k]){nodes[k].closest('label').hidden=n.contraparte!=='CLIENTE';if(n.contraparte!=='CLIENTE')nodes[k].value='';}
   nodes.fornecedor_id.closest('label').hidden=n.contraparte!=='FORNECEDOR';if(n.contraparte!=='FORNECEDOR')nodes.fornecedor_id.value='';
   if(simulation){nodes.cliente_id.required=n.contraparte==='CLIENTE';for(const k of ['consumidor_final','finalidade_destinatario','sujeito_st'])nodes[k].required=n.operacao==='VENDA';}
  };nodes.natureza_id.onchange=toggle;toggle();
  return ()=>{const n=options.naturezas.linhas.find(x=>x.id===Number(nodes.natureza_id.value));const selected=all.checked?[]:choices.filter(x=>x.check.checked).map(x=>x.uf);if(n.mercado==='DOMESTICO'&&!all.checked&&!selected.length)throw Error('Selecione ao menos um estado ou marque todos.');const countriesList=countries.value.split(/[;,\s]+/).filter(Boolean).map(x=>x.toUpperCase());return {ufs_contraparte:n.mercado==='DOMESTICO'?selected:[],paises_contraparte:n.mercado==='EXTERIOR'?countriesList:[],uf_origem:n.direcao==='SAIDA'?emp.uf:n.mercado==='EXTERIOR'?'EX':selected.length===1?selected[0]:null,uf_destino:n.direcao==='ENTRADA'?emp.uf:n.mercado==='EXTERIOR'?'EX':selected.length===1?selected[0]:null};};
 }
 function editRule(r){
  const {f,error}=openDialog(r.id?'Editar rascunho':'Nova regra tributária');const nodes={};
  const spec=[['titulo','Título','text',true],['natureza_id','Tipo de operação','select',true,options.naturezas.linhas.map(n=>[n.id,n.nome])],['perfil_id','Perfil fiscal','select',false,options.perfis.linhas.map(n=>[n.id,n.nome])],['produto_id','Produto exclusivo','select',false,r.produto_id?[[r.produto_id,'Produto vinculado']]:[]],['ncm','NCM (8 dígitos)'],['empresa_cnpj','CNPJ da empresa Axe'],['regime_tributario','Regime tributário','select',false,[['SIMPLES','Simples Nacional'],['LUCRO_PRESUMIDO','Lucro presumido'],['LUCRO_REAL','Lucro real'],['OUTRO','Outro']]],['perfil_destinatario_id','Perfil fiscal dos clientes','select',false,(options.destinatarios?.linhas||[]).map(n=>[n.id,n.nome])],['consumidor_final','Consumidor final','select',false,[['true','Sim'],['false','Não']]],['finalidade_destinatario','Finalidade da aquisição','select',false,[['USO_CONSUMO','Uso e consumo'],['ATIVO','Ativo imobilizado'],['REVENDA','Revenda'],['INDUSTRIALIZACAO','Industrialização'],['OUTRA','Outra']]],['sujeito_st','Operação sujeita a ST','select',false,[['true','Sim'],['false','Não']]],['forma_obtencao','Forma de obtenção do produto','select',false,[['FAB','Fabricado'],['IMP','Importado'],['TER','Comprado de terceiro']]],['perfil_contraparte','Observações complementares (não usadas na seleção)'],['cliente_id','Cliente específico (exceção opcional)','select',false,options.clientes.linhas.map(n=>[n.id,n.nome+' · '+n.cnpj])],['fornecedor_id','Fornecedor específico (exceção opcional)','select',false,options.fornecedores.linhas.map(n=>[n.id,n.razao_social])],['uf_origem','UF de origem'],['uf_destino','UF de destino'],['municipio_destino','Código IBGE do município de destino'],['pais_origem','País de origem'],['cfop','CFOP específico (opcional; prevalece sobre a operação)'],['vigencia_inicio','Início da vigência','date',true],['vigencia_fim','Fim da vigência','date'],['fonte','Fonte oficial / referência'],['fundamento_legal','Fundamentação legal','textarea'],['data_consulta','Data da consulta à fonte','date'],['versao_tabela','Versão da tabela oficial (CST / cClassTrib)']];
  f.append(e('p','Vincule ao menos um perfil, produto ou NCM. A seleção combina regras por tributo. Use várias regras quando as localidades ou condições diferirem; o mesmo imposto não pode ter duas regras aplicáveis. Campos vazios de alíquota permanecem não informados.','intro'));
  for(const [k,t,kind,req,choices] of spec){nodes[k]=field(f,k,t,kind||'text',r[k],req,choices);if(['ncm','empresa_cnpj','cfop','uf_origem','uf_destino','municipio_destino'].includes(k))nodes[k].pattern={ncm:'[0-9]{8}',empresa_cnpj:'[0-9]{14}',cfop:'[1-7][0-9]{3}',uf_origem:'[A-Za-z]{2}',uf_destino:'[A-Za-z]{2}',municipio_destino:'[0-9]{7}'}[k];}
  const readLocation=locationFields(f,nodes,r);
  const productSearch=e('input');productSearch.type='search';productSearch.placeholder='Código Axe, código anterior ou descrição';productSearch.setAttribute('aria-label','Buscar produto para a regra');
  const findProduct=btn('Localizar produto',async()=>{findProduct.disabled=true;try{const d=await api({acao:'listar',secao:'produtos',pagina:0,busca:productSearch.value});nodes.produto_id.replaceChildren(new Option('Não definido',''));for(const p of d.linhas)nodes.produto_id.append(new Option((p.codigo_axe||p.codigo_anterior||'Produto')+' · '+p.descricao_referencia,p.id));error.textContent=d.total>50?'Há mais produtos; refine a busca.':d.total+' produto(s) encontrado(s).';}catch(err){error.textContent=err.message;}finally{findProduct.disabled=false;}});
  nodes.produto_id.closest('label').after(productSearch,findProduct);
  if(r.produto_id)api({acao:'produto',id:r.produto_id}).then(d=>{const p=d.produto;if(p&&nodes.produto_id.options.length>1)nodes.produto_id.options[1].text=(p.codigo_axe||p.codigo_anterior||'Produto')+' · '+p.descricao_referencia;}).catch(()=>{});
  f.append(e('h3','Tributos desta regra'));const taxInputs=[];
  for(const tax of taxes){const old=(r.tributos||[]).find(t=>t.tributo===tax);const box=e('details',undefined,'source-card');box.append(e('summary',names[tax]||tax));const label=e('label','Configurar este tributo'),check=e('input');check.type='checkbox';check.checked=Boolean(old);label.prepend(check);box.append(label);const fields=e('fieldset');fields.disabled=!check.checked;check.onchange=()=>fields.disabled=!check.checked;
   const t={};t.tratamento=field(fields,'tratamento','Tratamento','select',old?.tratamento||'',true,['TRIBUTADO','ZERO','ISENTO','SUSPENSO','NAO_INCIDE','DIFERIDO'].map(v=>[v,v]));
   for(const [k,title,kind] of [['base_calculo','Base de cálculo / regra de composição','textarea'],['aliquota','Alíquota (%)','number'],['reducao_base','Redução da base (%)','number'],['reducao_aliquota','Redução da alíquota (%)','number'],['diferimento','Diferimento (%)','number'],['cst','CST / CSOSN','text'],['cclass_trib','cClassTrib (IBS/CBS)','text'],['beneficio','Código / fundamento do benefício','text'],['credito','Tratamento de créditos','textarea']])t[k]=field(fields,k,title,kind,old?.[k]);
   box.append(fields);f.append(box);taxInputs.push({tax,check,t});
  }
  actions(f,error,()=>{const dados={};for(const [k,n] of Object.entries(nodes)){const v=n.value.trim();dados[k]=v?(['consumidor_final','sujeito_st'].includes(k)?v==='true':numKeys.includes(k)?Number(v):k.startsWith('uf_')?v.toUpperCase():v):null;}Object.assign(dados,readLocation());dados.tributos=taxInputs.filter(x=>x.check.checked).map(x=>{const t={tributo:x.tax};for(const [k,n]of Object.entries(x.t))t[k]=n.value.trim()?(n.type==='number'?Number(n.value):n.value.trim()):null;return t;});if(r.id){dados.id=r.id;dados.atualizado_em=r.atualizado_em;}return {tipo:'regra',dados};});
 }
 async function simulate(r={}){
  try{await getOptions();}catch(err){say(err.message,true);return;}
  const {f,error}=openDialog('Simular tributação por operação');f.append(e('p','A seleção usa apenas regras validadas. O perfil vem do cadastro do cliente; finalidade e ST pertencem a esta operação.','intro'));const ns={};
  const specs=[['natureza_id','Tipo de operação','select',true,options.naturezas.linhas.map(n=>[n.id,n.nome])],['produto_id','Produto','select',true,r.produto_id?[[r.produto_id,'Produto da regra']]:[]],['empresa_cnpj','CNPJ da empresa'],['regime_tributario','Regime tributário','select',true,[['SIMPLES','Simples Nacional'],['LUCRO_PRESUMIDO','Lucro presumido'],['LUCRO_REAL','Lucro real'],['OUTRO','Outro']]],['cliente_id','Cliente','select',false,options.clientes.linhas.map(n=>[n.id,n.nome+' · '+n.cnpj])],['fornecedor_id','Fornecedor','select',false,options.fornecedores.linhas.map(n=>[n.id,n.razao_social])],['uf_origem','UF de origem'],['uf_destino','UF de destino'],['municipio_destino','Município destino (código IBGE)'],['pais_contraparte','País da contraparte (ISO de duas letras)'],['data_operacao','Data da operação','date',true],['consumidor_final','Consumidor final','select',false,[['true','Sim'],['false','Não']]],['finalidade_destinatario','Finalidade da aquisição','select',false,[['USO_CONSUMO','Uso e consumo'],['ATIVO','Ativo imobilizado'],['REVENDA','Revenda'],['INDUSTRIALIZACAO','Industrialização'],['OUTRA','Outra']]],['sujeito_st','Sujeito a ST','select',false,[['true','Sim'],['false','Não']]]];
  for(const [k,t,kind,required,choices] of specs)ns[k]=field(f,k,t,kind||'text',r[k],required,choices);
  const searchProduct=e('input');searchProduct.type='search';searchProduct.placeholder='Código ou descrição do produto';searchProduct.setAttribute('aria-label','Localizar produto para simulação');
  ns.produto_id.closest('label').after(searchProduct,btn('Buscar produtos',async()=>{try{const d=await api({acao:'listar',secao:'produtos',pagina:0,busca:searchProduct.value});ns.produto_id.replaceChildren(new Option('Selecione',''));for(const p of d.linhas)ns.produto_id.append(new Option((p.codigo_axe||p.codigo_anterior||'Produto')+' · '+p.descricao_referencia,p.id));}catch(err){error.textContent=err.message;}}));
  locationFields(f,ns,r,true);
  const result=e('div');const go=e('button','Simular operação');go.type='submit';f.append(error,result,btn('Fechar',()=>modal.close()),go);f.onsubmit=async ev=>{ev.preventDefault();if(!f.reportValidity())return;go.disabled=true;error.textContent='';try{const c={};for(const [k,n]of Object.entries(ns)){const v=n.value.trim();c[k]=v?['consumidor_final','sujeito_st'].includes(k)?v==='true':numKeys.includes(k)?Number(v):k.startsWith('uf_')?v.toUpperCase():v:null;}const d=await api({acao:'selecionar',contexto:c});result.replaceChildren(e('h3',{SELECIONADA:'Regras selecionadas e cobertura conferida',SEM_REGRA:'Nenhuma regra validada compatível',CONFLITO:'Seleção bloqueada: regras ou CFOPs conflitantes',DADOS_INCOMPLETOS:'Seleção bloqueada: faltam informações',COBERTURA_PENDENTE:'Defina a cobertura de tributos no tipo de operação',COBERTURA_INCOMPLETA:'Cobertura incompleta: faltam regras para tributos previstos',CFOP_PENDENTE:'Defina o CFOP do tipo de operação ou da regra'}[d.estado]||d.estado));
   if(d.campos)result.append(e('p','Campos a completar: '+d.campos.join(', ')));
   if(d.cfop)result.append(e('p','CFOP selecionado: '+d.cfop));
   for(const t of d.tributos||[]){const card=e('article',undefined,'source-card');card.append(e('h4',(names[t.tributo]||t.tributo)+' · '+({SELECIONADA:'Regra selecionada',CONFLITO:'Conflito',DADOS_INCOMPLETOS:'Faltam dados',SEM_REGRA:'Sem regra'}[t.estado]||t.estado)));if(t.regra)card.append(e('p',t.regra.titulo+' · versão '+t.regra.versao),e('p','Tratamento: '+t.parametros.tratamento+' · Alíquota: '+(t.parametros.aliquota??'não informada')+'%'));if(t.campos)card.append(e('p','Complete: '+t.campos.join(', ')));for(const x of t.candidatos||[])card.append(e('p',x.regra.titulo+' · versão '+x.regra.versao));result.append(card);}
   result.append(e('p','A simulação seleciona parâmetros fiscais; não calcula valores, emite notas nem gera movimentos de estoque ou financeiro.'));
  }catch(err){error.textContent=err.message;}finally{go.disabled=false;}};
 }
 return {show(key){root.hidden=!key;if(key){section=key==='fiscal'?'regras':key;product=null;page=0;load();}},openProduct(id){section='produtos';product={id};page=0;root.hidden=false;load();},reset(){epoch++;options=null;product=null;body.replaceChildren();root.hidden=true;if(modal)modal.remove();}};
}
