import {validarCampos} from './validacao-campos.js?v=20261029-aceite2';
import {lerPDFImportacao} from './importacoes-di-leitura.js?v=20261028-di1';
const el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
const moedas=['USD','EUR','GBP','CAD','CNY','JPY','CHF','BRL'];
const money=(v,c)=>new Intl.NumberFormat('pt-BR',{style:'currency',currency:c||'USD'}).format(Number(v||0));
const date=v=>v?String(v).slice(0,10).split('-').reverse().join('/'):'Sem data';
export function csvBanco(linhas){
 const cell=v=>{let s=String(v??'');if(/^[=+@\-\t\r]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';};
 const cols=['Banco','Contrato','Pedido','DI/DUIMP','Chave de acesso','Moeda','Valor a comprovar','Situação','Data de envio'];
 return '\ufeff'+[cols,...linhas.map(x=>[x.banco,x.contrato,x.pedido,x.declaracao,x.chave_acesso,x.moeda,Number(x.valor).toFixed(2).replace('.',','),x.status,x.data_envio||''])].map(row=>row.map(cell).join(';')).join('\r\n');
}
export function initConciliacaoCambio(api,parent){
 const root=el('section',undefined,'imp-internacional imp-cambio');root.hidden=true;parent.append(root);
 const nav=el('div',undefined,'catalog-tabs'),msg=el('p','','status'),body=el('div');msg.setAttribute('role','status');
 root.append(el('h2','Conciliação cambial'),el('p','Pendência financeira independente do estoque e do custo dos produtos. Os vínculos usam o pedido de compra, mesmo que as invoices tenham números diferentes.','intro'),nav,msg,body);
 let pdfNovo=null,pdfPrecisaLer=false;
 let tipo='contratos',pagina=0,busca='',epoch=0,seq=0,dirty=false,busy=false,pending=null,current=null,opts={editar:false,fornecedores:[]};
 const dialogs=new Set(),valid=g=>g===epoch&&!root.hidden,guard=()=>root.hidden||!busy&&(!dirty||confirm('Há alterações cambiais não salvas. Deseja descartá-las?'));
 const changed=()=>{dirty=true;pending=null;};
 function btn(label,fn){const b=el('button',label);b.type='button';b.onclick=async()=>{if(busy)return;b.disabled=true;try{await fn();}catch(e){msg.textContent=e.message;msg.className='status error';}finally{if(b.isConnected)b.disabled=false;}};return b;}
 function field(parent,k,label,v='',type='text',choices){
  const l=el('label',label),e=el(choices?'select':type==='textarea'?'textarea':'input');e.name=k;e.setAttribute('aria-label',label);
  if(choices)for(const x of choices){const [v,t]=Array.isArray(x)?x:[x,x];e.append(new Option(t,v));}else if(type!=='textarea')e.type=type;
  e.value=v??'';e.required=['referencia','fornecedor_id','moeda','valor','valor_pedido','status','banco'].includes(k);if(type==='number'){e.min=['valor','valor_pedido'].includes(k)?'0.01':'0';e.step='any';}l.append(e);parent.append(l);return e;
 }
 const fields=(p,defs,d={})=>Object.fromEntries(defs.map(([k,l,t,c])=>[k,field(p,k,l,d[k],t||'text',c)]));
 const values=f=>Object.fromEntries(Object.entries(f).map(([k,e])=>[k,e.value.trim()]));
 function grid(form,title){const f=el('fieldset');f.append(el('legend',title));const g=el('div',undefined,'import-mapping');f.append(g);form.append(f);return g;}
 function closeDialogs(){for(const d of dialogs){d.close();d.remove();}dialogs.clear();}
 function tabs(){nav.replaceChildren();for(const [key,label] of [['contratos','Contratos de câmbio'],['declaracoes','DI / DUIMP'],['vinculos','Vínculos e baixas'],['sugestoes','Sugestões por pedido']]){
  const b=btn(label,async()=>{if(!guard())return;dirty=false;pending=null;current=null;tipo=key;pagina=0;busca='';epoch++;closeDialogs();tabs();await list();});b.setAttribute('aria-pressed',String(tipo===key));nav.append(b);
 }}
 async function list(){
  const g=epoch,s=++seq;body.replaceChildren();msg.textContent='Consultando saldos…';
  const toolbar=el('div',undefined,'cadastro-toolbar'),q=field(toolbar,'busca','Buscar contrato, declaração ou pedido',busca,'search');
  toolbar.append(btn('Buscar',async()=>{busca=q.value;pagina=0;await list();}));
  if(opts.editar&&tipo!=='sugestoes')toolbar.append(btn(tipo==='contratos'?'Novo contrato':tipo==='declaracoes'?'Nova DI / DUIMP':'Novo vínculo',()=>{pdfNovo=null;pdfPrecisaLer=false;return tipo==='vinculos'?chooseLink():edit(null);}));
  if(tipo==='vinculos')toolbar.append(btn('Exportar pendentes para banco (CSV)',async()=>{
   const r=await api({acao:'fx_exportar',tipo:'vinculos',busca});if(!valid(g))return;
   if(!r.total)throw Error('Nenhum vínculo preparado ou enviado para exportar.');
   const url=URL.createObjectURL(new Blob([csvBanco(r.linhas)],{type:'text/csv;charset=utf-8'})),a=el('a');a.href=url;a.download='comprovacao-cambial.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
   msg.textContent='Relação exportada. O envio ao banco e a baixa continuam sob seu controle.';
  }));
  body.append(toolbar);
  if(tipo==='sugestoes')body.append(el('p','Cada sugestão usa o saldo do pedido em comum. Revise os documentos e o valor antes de confirmar. Sugestões concorrentes são recalculadas após cada gravação; nenhuma baixa é automática.'));
  const rows=el('div',undefined,'scroll'),foot=el('div',undefined,'cadastro-toolbar');body.append(rows,foot);
  const r=await api({acao:'fx_listar',tipo,pagina,busca});if(!valid(g)||s!==seq)return;
  const table=el('table'),head=el('tr');
  const labels=tipo==='contratos'?['Contrato / banco','Valor original','Disponível para vincular','Preparado / enviado','Baixado pelo banco','A comprovar / prazo','Ação']:tipo==='declaracoes'?['DI/DUIMP','Valor de mercadorias','Disponível','Preparado / enviado','Baixado','Situação','Ação']:tipo==='vinculos'?['Contrato','DI/DUIMP','Pedido','Valor','Situação','Ação']:['Contrato','DI/DUIMP','Pedido em comum','Máximo sugerido','Ação'];
  labels.forEach(t=>head.append(el('th',t)));table.append(head);
  for(const x of r.linhas){const tr=el('tr');let v;
   if(tipo==='contratos')v=[x.referencia+' · '+x.dados.banco,money(x.valor,x.moeda),money(x.disponivel,x.moeda),money(x.preparado,x.moeda)+' / '+money(x.enviado,x.moeda),money(x.baixado,x.moeda),money(x.a_comprovar,x.moeda)+' · '+date(x.dados.prazo_comprovacao)+(x.status==='Cancelado'?' · Cancelado':'')];
   else if(tipo==='declaracoes')v=[x.referencia,money(x.valor,x.moeda),money(x.disponivel,x.moeda),money(x.preparado,x.moeda)+' / '+money(x.enviado,x.moeda),money(x.baixado,x.moeda),x.status];
   else if(tipo==='vinculos')v=[x.contrato,x.declaracao,x.pedido,money(x.valor,x.moeda),x.status];
   else v=[x.contrato,x.declaracao,x.pedido,money(x.valor,x.moeda)];
   v.forEach(t=>tr.append(el('td',t)));const action=el('td');
   if(tipo!=='sugestoes')action.append(btn('Abrir',()=>open(x.id)));
   else if(opts.editar)action.append(btn('Revisar sugestão',()=>fromSuggestion(x)));
   tr.append(action);table.append(tr);
  }rows.append(table);if(!r.total)rows.append(el('p',tipo==='sugestoes'?'Nenhuma sugestão disponível. Cadastre os documentos e associe os valores aos pedidos de compra em comum.':'Nenhum registro encontrado.'));
  const prev=btn('Anterior',async()=>{pagina--;await list();}),next=btn('Próxima',async()=>{pagina++;await list();});prev.disabled=pagina===0;next.disabled=(pagina+1)*30>=r.total;foot.append(prev,el('span','Página '+(pagina+1)+' · '+r.total+' registro(s)'),next);msg.textContent='';
 }
 async function open(id){if(!guard())return;const g=epoch,s=++seq;const r=await api({acao:'fx_detalhe',tipo,id});if(!valid(g)||s!==seq)return;dirty=false;pending=null;current=r;edit(r,false);}
 async function pick(title,loader,columns,done){
  const g=epoch,dialog=el('dialog',undefined,'imp-picker'),q=el('input'),out=el('div',undefined,'scroll'),status=el('p'),toolbar=el('div',undefined,'cadastro-toolbar');let page=0,request=0;
  q.type='search';q.setAttribute('aria-label','Buscar no seletor cambial');const close=()=>{dialog.close();dialog.remove();dialogs.delete(dialog);};dialogs.add(dialog);root.append(dialog);
  toolbar.append(q,btn('Buscar',async()=>{page=0;await load();}),btn('Fechar',close));const prev=btn('Anterior',async()=>{page--;await load();}),next=btn('Próxima',async()=>{page++;await load();});dialog.append(el('h2',title),toolbar,status,out,prev,next);dialog.addEventListener('cancel',close);dialog.showModal();
  async function load(){const s=++request;status.textContent='Consultando…';try{const r=await loader(page,q.value);if(!valid(g)||!dialog.open||s!==request)return;out.replaceChildren();const table=el('table');
   for(const x of r.linhas){const tr=el('tr');columns(x).forEach(v=>tr.append(el('td',v)));const td=el('td');td.append(btn('Selecionar',async()=>{try{await done(x);close();}catch(e){status.textContent=e.message;}}));tr.append(td);table.append(tr);}out.append(table);status.textContent=r.total+' registro(s) · página '+(page+1);prev.disabled=page===0;next.disabled=(page+1)*30>=r.total;
  }catch(e){status.textContent=e.message;}}
  await load();
 }
 async function chooseLink(contract=null,declaration=null){
  const g=epoch;
  if(!contract){await pick('Selecionar contrato',(pagina,busca)=>api({acao:'fx_listar',tipo:'contratos',pagina,busca}),x=>[x.referencia,x.fornecedor,money(x.disponivel,x.moeda)],async x=>{if(x.status!=='Ativo')throw Error('Selecione contrato ativo.');if(valid(g))await chooseLink(x,declaration);});return;}
  if(!declaration){await pick('Selecionar DI / DUIMP',(pagina,busca)=>api({acao:'fx_listar',tipo:'declaracoes',pagina,busca}),x=>[x.referencia,x.fornecedor,money(x.disponivel,x.moeda)],async x=>{if(x.status!=='Ativo'||x.moeda!==contract.moeda||String(x.fornecedor_id)!==String(contract.fornecedor_id))throw Error('Selecione declaração ativa do mesmo fornecedor e moeda.');if(valid(g))await chooseLink(contract,x);});return;}
  const common=contract.pedidos.filter(x=>declaration.pedidos.some(y=>y.pedido_id===x.pedido_id));
  if(!common.length)throw Error('Associe o mesmo pedido ao contrato e à declaração antes de vincular.');
  await pick('Selecionar pedido em comum',async(page,q)=>{const rows=common.filter(x=>x.pedido.toLowerCase().includes(q.toLowerCase()));return {total:rows.length,linhas:rows.slice(page*30,page*30+30)};},x=>[x.pedido,money(x.valor,contract.moeda)],x=>{
   if(!valid(g))return;const dm=declaration.pedidos.find(y=>y.pedido_id===x.pedido_id);
   const max=Math.min(Number(x.valor)-Number(x.utilizado),Number(dm.valor)-Number(dm.utilizado),Number(contract.disponivel),Number(declaration.disponivel));
   if(max<=0)throw Error('Não há saldo disponível para este pedido.');
   tipo='vinculos';tabs();dirty=false;pending=null;edit({contrato_id:contract.id,declaracao_id:declaration.id,pedido_id:x.pedido_id,contrato:contract.referencia,declaracao:declaration.referencia,pedido:x.pedido,moeda:contract.moeda,valor:max,status:'Preparado'},true,true);
  });
 }
 async function fromSuggestion(x){
  const g=epoch;const [c,d]=await Promise.all([api({acao:'fx_detalhe',tipo:'contratos',id:x.contrato_id}),api({acao:'fx_detalhe',tipo:'declaracoes',id:x.declaracao_id})]);if(!valid(g))return;
  const cm=c.pedidos.find(p=>p.pedido_id===x.pedido_id),dm=d.pedidos.find(p=>p.pedido_id===x.pedido_id);
  const max=Math.min(Number(cm?.valor||0)-Number(cm?.utilizado||0),Number(dm?.valor||0)-Number(dm?.utilizado||0),Number(c.disponivel),Number(d.disponivel));
  if(max<=0)throw Error('Saldo mudou. Atualize as sugestões.');
  tipo='vinculos';tabs();dirty=false;pending=null;edit({...x,valor:max,status:'Preparado'},true,true);
 }
 function balances(item,where){
  const cards=el('div',undefined,'erp-stats');
  for(const [label,v] of [['Original',item.valor],['Disponível para vincular',item.disponivel],['Preparado',item.preparado],['Enviado ao banco',item.enviado],['Baixa confirmada',item.baixado]]){
   const c=el('div',undefined,'stat-card');c.append(el('span',label),el('strong',money(v,item.moeda)));cards.append(c);
  }where.append(cards);
  if(item.tipo==='contratos'){
   where.append(el('p','Saldo a comprovar até confirmação do banco: '+money(item.a_comprovar,item.moeda)+' · Prazo: '+date(item.dados.prazo_comprovacao)));
   const today=new Date().toLocaleDateString('en-CA',{timeZone:'America/Sao_Paulo'});if(item.status==='Ativo'&&Number(item.a_comprovar)>0&&item.dados.prazo_comprovacao&&item.dados.prazo_comprovacao<today)where.append(el('p','Prazo de comprovação vencido.','status error'));
   if(item.dados.saldo_banco!==''&&item.dados.saldo_banco!=null){const diff=Number(item.dados.saldo_banco)-Number(item.a_comprovar);where.append(el('p','Posição do banco em '+date(item.dados.data_posicao_banco)+': '+money(item.dados.saldo_banco,item.moeda)+' · Diferença para o saldo atual do ERP: '+money(diff,item.moeda)+'. A posição é histórica; confira movimentações posteriores.'));}
  }
 }
 async function anexosContrato(item,where){
  const g=epoch,box=el('fieldset'),out=el('div'),status=el('p');box.append(el('legend','Arquivos do contrato e SWIFT'),out,status);where.append(box);
  async function load(){const r=await api({acao:'fxdoc_listar',contrato_id:item.id});if(!valid(g)||current?.id!==item.id||!box.isConnected)return;out.replaceChildren();
   for(const f of r.linhas){const row=el('p');row.append(el('span',(f.categoria==='SWIFT'?'SWIFT':'Contrato de câmbio')+' · '+f.nome+' · '+Math.ceil(f.tamanho/1024)+' KB '),btn('Baixar '+f.nome,async()=>{const r=await api({acao:'fxdoc_baixar',id:f.id});const url=new URL(r.url);if(url.protocol!=='https:')throw Error('Endereço de arquivo inválido');const a=el('a');a.href=url.href;a.rel='noopener noreferrer';a.target='_blank';a.click();}));out.append(row);}
   if(!r.linhas.length)out.append(el('p','Nenhum arquivo anexado.'));
  }
  if(opts.editar&&item.status==='Ativo'){
   const controls=el('div',undefined,'import-mapping'),category=field(controls,'categoria_anexo','Tipo do arquivo','CONTRATO','text',[['CONTRATO','Contrato de câmbio'],['SWIFT','Comprovante SWIFT']]),file=field(controls,'arquivo_cambio','Arquivo PDF','','file');file.accept='.pdf,application/pdf';file.required=true;const check=el('input');check.type='checkbox';check.required=true;Object.assign(check.style,{width:'18px',height:'18px',minHeight:'0',margin:'0',flex:'0 0 18px'});const label=el('label','Confirmo que o arquivo pertence ao contrato '+item.referencia);Object.assign(label.style,{display:'flex',flexDirection:'row',alignItems:'center',gap:'8px',margin:'16px 0'});label.prepend(check);let retry=null;
   file.onchange=()=>{retry=null;check.checked=false;};category.onchange=()=>{retry=null;check.checked=false;};
   box.append(el('p','PDF de até 8 MB. O anexo preserva o original e não preenche valores nem confirma baixa bancária.'),controls,label,btn('Anexar arquivo',async()=>{
    if(!validarCampos(box))return;const f=file.files?.[0];if(!f)throw Error('Selecione o arquivo PDF.');if(!check.checked)throw Error('Confirme o vínculo do arquivo com este contrato.');if(f.size>8388608||!f.size)throw Error('Selecione PDF de até 8 MB.');
    if(!retry){const bytes=new Uint8Array(await f.arrayBuffer());if(new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-')throw Error('Selecione um arquivo PDF válido.');let binary='';for(let i=0;i<bytes.length;i+=32768)binary+=String.fromCharCode(...bytes.subarray(i,i+32768));retry={acao:'fxdoc_upload',contrato_id:item.id,categoria:category.value,nome:f.name,conteudo:btoa(binary),confirmado:true,requisicao_id:crypto.randomUUID()};}
    busy=true;try{await api(retry);retry=null;file.value='';check.checked=false;await load();status.textContent='Arquivo anexado. Para registrar o pagamento, abra o pedido ou a parcela e use Contrato e SWIFT — registrar pagamento.';}finally{busy=false;}
   }));
  }
  try{await load();}catch(e){status.textContent=e.message;}
 }
 function entradaPDF(where,item){
  const box=el('fieldset'),file=el('input'),status=el('p');box.append(el('legend','Começar pelo PDF do contrato'),el('p','Carregue o documento, confira os dados preenchidos e escolha o fornecedor. Nada será cadastrado durante a leitura.'));file.type='file';file.accept='.pdf,application/pdf';file.setAttribute('aria-label','PDF do novo contrato');let escolhido=null;
  file.onchange=()=>{escolhido=file.files?.[0]||null;pdfPrecisaLer=!!escolhido;};box.append(file,btn('Ler PDF e preencher contrato',async()=>{
   if(!escolhido)throw Error('Selecione o PDF do contrato.');if(dirty&&!confirm('Substituir os dados em preenchimento pela leitura do PDF?'))return;
   busy=true;file.disabled=true;const escolhidoAtual=escolhido,g=epoch;try{const paginas=await lerPDFImportacao(escolhidoAtual,t=>status.textContent=t);const bytes=new Uint8Array(await escolhidoAtual.arrayBuffer());let binary='';for(let i=0;i<bytes.length;i+=32768)binary+=String.fromCharCode(...bytes.subarray(i,i+32768));const conteudo=btoa(binary);const r=await api({acao:'fxdoc_ler',conteudo,paginas});if(!valid(g)||!box.isConnected)return;
    const normalize=s=>String(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase().replace(/[^A-Z0-9]/g,'');const matched=opts.fornecedores.filter(f=>r.beneficiario&&normalize(f.nome)===normalize(r.beneficiario));
    pdfPrecisaLer=false;pdfNovo={nome:escolhidoAtual.name,conteudo,paginas,leitura:r};dirty=false;pending=null;edit({...r.dados,status:'Ativo',fornecedor_id:matched.length===1?matched[0].id:'',pedidos:[]},true,true);dirty=true;
   }finally{busy=false;if(file.isConnected)file.disabled=false;}
  }),status);
  if(pdfNovo){box.append(el('p','Arquivo selecionado: '+pdfNovo.nome),el('p','Beneficiário identificado: '+(pdfNovo.leitura.beneficiario||'Não identificado')+'. Confira o fornecedor cadastrado.'));for(const a of pdfNovo.leitura.avisos)box.append(el('p',a));const sources=el('details');sources.append(el('summary','Origem dos dados extraídos'));for(const x of pdfNovo.leitura.origens)sources.append(el('p',x.campo+': '+x.valor+' — '+x.trecho));box.append(sources);}
  where.append(box);
 }
 function edit(item,editing=true,isNew=false){
  const g=epoch,t=tipo;current=item;body.replaceChildren();msg.textContent='';
  const toolbar=el('div',undefined,'cadastro-toolbar');toolbar.append(btn('Voltar à lista',async()=>{if(!guard())return;dirty=false;pending=null;current=null;await list();}));
  if(!editing&&opts.editar&&item?.status!=='Cancelado')toolbar.append(btn('Editar registro',()=>edit(item,true)));
  body.append(toolbar,el('h3',tipo==='vinculos'?'Vínculo contrato × DI/DUIMP':tipo==='contratos'?'Contrato de câmbio':'Declaração de importação'));
  if(item?.id&&tipo!=='vinculos')balances(item,body);
  if(item?.id&&t==='contratos'&&!editing&&opts.editar&&!item.dados?.data_liquidacao)toolbar.append(btn('Sugerir liquidação pelo SWIFT',async()=>{
   const s=await api({acao:'fx_liquidacao_sugerir',tipo:'contratos',id:item.id});if(!valid(g)||current?.id!==item.id)return;
   const dialog=el('dialog',undefined,'imp-picker');const close=()=>{dialog.close();dialog.remove();dialogs.delete(dialog);};dialogs.add(dialog);root.append(dialog);
   dialog.append(el('h3','Conferir liquidação do contrato '+s.referencia),el('p','Data da liquidação: '+(s.anterior?date(s.anterior):'Não informada')+' → '+date(s.data)),el('p','Data-valor do SWIFT (campo 32A). Confira se corresponde à liquidação efetiva antes de aprovar. A comprovação por DI/DUIMP permanece separada.'));
   for(const f of s.fontes)dialog.append(el('p',f.arquivo+' · '+money(f.valor,item.moeda)+' · '+date(f.data)+' · '+(f.origem||[]).join(' ')));
   const label=el('label'),check=el('input');check.type='checkbox';check.setAttribute('aria-label','Conferi a data do SWIFT e confirmo a liquidação');label.append(check,el('span','Conferi a data do SWIFT e confirmo a liquidação'));dialog.append(label);
   dialog.append(btn('Cancelar',close),btn('Aprovar data de liquidação',async()=>{if(!check.checked)throw Error('Confirme a conferência da data antes de aprovar.');busy=true;try{await api({acao:'fx_liquidacao_aprovar',tipo:'contratos',id:s.id,versao:s.versao,data:s.data,confirmado:true});}finally{busy=false;}close();if(!valid(g))return;await open(item.id);msg.textContent='Data de liquidação confirmada pelo SWIFT. Histórico e origem preservados. Recalcule a prévia do custo.';}));dialog.addEventListener('cancel',ev=>{ev.preventDefault();close();});dialog.showModal();
  }));

  if(tipo==='contratos'&&!item?.id)entradaPDF(body,item);
  if(tipo==='contratos'){if(item?.id&&!editing)void anexosContrato(item,body);else if(item?.id)body.append(el('p','Salve as alterações para consultar os anexos.'));else if(!pdfNovo)body.append(el('p','Você também pode preencher manualmente e anexar os arquivos depois.'));}
  const form=el('form');form.onsubmit=e=>e.preventDefault();form.addEventListener('input',changed);form.addEventListener('change',changed);body.append(form);
  let collect;
  if(tipo==='vinculos'){
   form.append(el('p','Contrato: '+item.contrato+' · DI/DUIMP: '+item.declaracao+' · Pedido: '+item.pedido+' · Moeda: '+item.moeda));
   const f=fields(grid(form,'Valor e acompanhamento bancário'),[
    ['valor','Valor deste vínculo','number'],['status','Situação do vínculo','text',['Preparado','Enviado','Baixado','Cancelado']],['data_envio','Data de envio ao banco','date'],['data_baixa','Data da baixa confirmada','date'],
    ['evidencia','Confirmação do banco (e-mail, planilha ou referência)'],['motivo','Justificativa de cancelamento'],['observacoes','Observações do vínculo','textarea']
   ],item);
   f.valor.step='0.01';if(item.id)f.valor.disabled=true;
   form.append(el('p','Preparado e Enviado reservam o saldo. Somente Baixado reduz o saldo a comprovar. Para corrigir valor ou documentos, cancele com justificativa e crie outro vínculo.'));
   collect=()=>({contrato_id:item.contrato_id,declaracao_id:item.declaracao_id,pedido_id:item.pedido_id,...values(f)});
  }else{
   const f=fields(grid(form,'Identificação e valor original'),[
    ['referencia',tipo==='contratos'?'Número do contrato':'Número da DI / DUIMP'],['fornecedor_id','Fornecedor','text',[['','Selecionar fornecedor'],...opts.fornecedores.map(x=>[String(x.id),x.nome])]],
    ['moeda','Moeda das mercadorias','text',moedas],['valor',tipo==='contratos'?'Valor do contrato em moeda estrangeira':'Valor das mercadorias para comprovação (FOB)','number'],['status','Situação do documento','text',['Ativo','Cancelado']]
   ],item||{moeda:'USD',status:'Ativo'});f.valor.step='0.01';
   const defs=tipo==='contratos'?[
    ['banco','Banco'],['data_contratacao','Data da contratação','date'],['data_liquidacao','Data da liquidação','date'],['prazo_comprovacao','Prazo de comprovação ao banco','date'],
    ['proforma','Proforma / invoice do pagamento'],['swift','Referência SWIFT / UETR'],['taxa','Taxa efetiva do banco para BRL','number'],['valor_brl','Valor efetivamente pago em BRL','number'],
    ['saldo_banco','Saldo pendente informado pelo banco','number'],['data_posicao_banco','Data da posição do banco','date'],['fonte_banco','Referência da planilha / e-mail do banco']
   ]:[
    ['especie','Tipo de declaração','text',['DI','DUIMP']],['chave_acesso','Chave de acesso da DI / DUIMP'],['data_registro','Data do registro','date'],['data_desembaraco','Data do desembaraço','date'],
    ['invoices','Invoices comerciais deste processo'],['processo','Referência do processo / embarque AXE']
   ];
   const meta=fields(grid(form,tipo==='contratos'?'Dados bancários e posição de saldo':'Documentos aduaneiros'),[...defs,['referencia_documento','Referência do documento original'],['motivo','Motivo de cancelamento'],['observacoes','Observações','textarea']],item?.dados||{especie:'DUIMP'});
   form.append(el('p',tipo==='contratos'?'O prazo é de comprovação bancária, separado das datas de embarque. Valores em reais são informativos nesta conciliação e não alteram o custo do estoque.':'Informe o valor de mercadorias aplicável à comprovação. Frete, seguro, impostos e total da nota não são somados automaticamente ao valor disponível.'));
   const section=el('fieldset');section.append(el('legend','Distribuição do valor entre pedidos'));const box=el('div');section.append(box);form.append(section);let maps=[];
   const summary=el('p');section.append(summary);
   function refresh(){const total=maps.reduce((s,x)=>s+Number(x.input.value||0),0);summary.textContent='Associado a pedidos: '+money(total,f.moeda.value)+' · Sem pedido definido: '+money(Number(f.valor.value||0)-total,f.moeda.value);}
   function add(x){
    if(maps.some(m=>m.pedido_id===x.pedido_id))throw Error('Pedido já associado.');
    const row=el('div',undefined,'imp-line');row.append(el('h3',x.pedido));const input=field(row,'valor_pedido','Valor deste documento para '+x.pedido,x.valor??'','number');input.step='0.01';
    const m={pedido_id:x.pedido_id,input};maps.push(m);if(x.utilizado!=null)row.append(el('p','Já utilizado: '+money(x.utilizado,f.moeda.value)));
    if(editing)row.append(btn('Remover pedido',()=>{maps=maps.filter(z=>z!==m);row.remove();changed();refresh();}));box.append(row);input.addEventListener('input',refresh);return input;
   }(item?.pedidos||[]).forEach(add);
   if(editing)section.append(btn('Associar pedido',async()=>{
    if(!f.fornecedor_id.value)throw Error('Selecione o fornecedor.');if(maps.length>=100)throw Error('Até 100 pedidos por documento.');
    const supplier=f.fornecedor_id.value,currency=f.moeda.value;
    await pick('Selecionar pedido de compra',(pagina,busca)=>api({acao:'v2_listar',tipo:'pedidos',pagina,busca}),x=>[x.referencia,x.fornecedor,x.moeda,money(x.total,x.moeda)],x=>{
     if(String(x.fornecedor_id)!==supplier||x.moeda!==currency||x.status==='Cancelado')throw Error('Selecione pedido ativo do mesmo fornecedor e moeda.');
     const input=add({pedido_id:x.id,pedido:x.referencia,valor:''});changed();refresh();setTimeout(()=>input.focus(),0);
    });
   }));
   form.addEventListener('input',refresh);form.addEventListener('change',refresh);refresh();
   collect=()=>({...values(f),dados:values(meta),pedidos:maps.map(x=>({pedido_id:x.pedido_id,valor:x.input.value}))});
   if(item?.id&&!editing){const refs=el('section');refs.append(el('h3','Vínculos deste documento'));for(const v of item.vinculos||[]){
    refs.append(el('p',v.contrato+' × '+v.declaracao+' · '+v.pedido+' · '+money(v.valor,v.moeda)+' · '+v.status),btn('Abrir vínculo',()=>{tipo='vinculos';tabs();return open(v.id);}));
   }body.append(refs);}
  }
  if(!editing)for(const e of form.querySelectorAll('input,select,textarea'))e.disabled=true;
  if(editing){
   let aceite=null;if(t==='contratos'&&!item?.id&&pdfNovo){const label=el('label','Conferi os dados preenchidos, o fornecedor e o PDF do contrato.');aceite=el('input');aceite.type='checkbox';aceite.required=true;aceite.setAttribute('aria-label','Conferência dos dados do contrato e PDF');Object.assign(aceite.style,{width:'18px',height:'18px',minHeight:'0',margin:'0',flex:'0 0 18px'});Object.assign(label.style,{display:'flex',flexDirection:'row',gap:'8px',alignItems:'center'});label.prepend(aceite);form.append(label);}
   const save=btn(pdfNovo&&!item?.id&&t==='contratos'?'Salvar contrato com PDF':'Salvar '+(tipo==='vinculos'?'vínculo':tipo==='contratos'?'contrato':'declaração'),async()=>{
    if(t==='contratos'&&!item?.id&&pdfPrecisaLer)throw Error('Clique em Ler PDF e preencher contrato antes de salvar o arquivo selecionado.');
    const st=form.querySelector('[name=status]')?.value;for(const n of form.querySelectorAll('[name=data_envio]'))n.required=t==='vinculos'&&['Enviado','Baixado'].includes(st);for(const n of form.querySelectorAll('[name=motivo]'))n.required=st==='Cancelado';for(const n of form.querySelectorAll('[name=data_posicao_banco]'))n.required=!!form.querySelector('[name=saldo_banco]')?.value;for(const n of form.querySelectorAll('[name=data_baixa],[name=evidencia]'))n.required=t==='vinculos'&&form.querySelector('[name=status]')?.value==='Baixado';if(!validarCampos(form))return;
    if(!pending)pending=pdfNovo&&!item?.id&&t==='contratos'?{acao:'fxdoc_criar',requisicao_id:crypto.randomUUID(),nome:pdfNovo.nome,conteudo:pdfNovo.conteudo,paginas:pdfNovo.paginas,confirmado:aceite?.checked===true,dados:collect()}:{acao:'fx_salvar',tipo:t,id:isNew?null:item?.id||null,versao:isNew?null:item?.versao||null,requisicao_id:crypto.randomUUID(),dados:collect()};
    busy=true;const controls=[...root.querySelectorAll('input,select,textarea,button')],states=controls.map(x=>x.disabled);controls.forEach(x=>x.disabled=true);
    let r;try{r=await api(pending);}finally{busy=false;if(valid(g))controls.forEach((x,i)=>x.disabled=states[i]);}
    if(!valid(g))return;dirty=false;pending=null;pdfNovo=null;pdfPrecisaLer=false;await open(r.id);msg.textContent='Registro salvo. Saldos recalculados e histórico preservado.';msg.className='status';
   });form.append(save);
  }else if(item?.id){
   const history=el('details');history.append(el('summary','Histórico financeiro'));const out=el('div');history.append(btn('Consultar histórico financeiro',async()=>{const r=await api({acao:'fx_historico',tipo:t,id:item.id});if(!valid(g)||current?.id!==item.id)return;out.replaceChildren();for(const e of r.linhas){const d=el('details');d.append(el('summary',new Date(e.criado_em).toLocaleString('pt-BR')+' · '+(e.anterior?'Alteração':'Criação')),el('pre',JSON.stringify(e,null,2)));out.append(d);}}),out);body.append(history);
  }
 }
 window.addEventListener('beforeunload',e=>{if((dirty||busy)&&!root.hidden){e.preventDefault();e.returnValue='';}});
 return {canLeave:guard,async show(v){
  epoch++;seq++;closeDialogs();root.hidden=!v;if(!v){dirty=false;pending=null;pdfNovo=null;return;}
  tipo='contratos';pagina=0;busca='';dirty=false;pending=null;current=null;tabs();const g=epoch;
  try{opts=await api({acao:'fx_opcoes'});if(valid(g))await list();}catch(e){if(valid(g))msg.textContent=e.message;}
 },reset(){epoch++;seq++;closeDialogs();root.hidden=true;dirty=false;pending=null;current=null;pdfNovo=null;opts={editar:false,fornecedores:[]};body.replaceChildren();}};
}

