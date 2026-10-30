import {lerPDFImportacao} from './importacoes-di-leitura.js?v=20261028-di1';
import {initCadastrosImportacao} from './importacoes-cadastros.js?v=20261029-fluxo15';
import {validarCampos,marcarErro} from './validacao-campos.js?v=20261029-aceite2';
import {initLeituraDI} from './importacoes-di.js?v=20261029-fluxo15';
const el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
const brl=v=>v==null?'Não apurado':Number(v).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
export function initNotasImportacao(api,parent){
 const controlesVinculos=new WeakMap();
 const root=el('section',undefined,'imp-notas');root.hidden=true;parent.append(root);
 let editable=false,busy=false,dirty=false,epoch=0,page=0,query='',note=null,data=null,shipment=null,pending=null,uploadPending=null;
 const readings=new Map(),products=new Map(),declarations=new Map(),dialogs=new Set(),msg=el('p','','status'),body=el('div');msg.setAttribute('role','status');root.append(msg,body);
 const diReader=initLeituraDI(api,v=>busy=v);
 const guard=()=>diReader.canLeave()&&!busy&&(!dirty||confirm('Há alterações da nota não salvas. Deseja descartá-las?'));
 const changed=()=>{dirty=true;pending=null;for(const row of data?.vinculos||[])delete row.origem_documental;};
 function button(label,action){const b=el('button',label);b.type='button';b.onclick=async()=>{if(busy)return;const e=epoch;try{b.disabled=true;await action();}catch(err){if(e===epoch){msg.textContent=err.message;msg.className='status error';}}finally{if(b.isConnected)b.disabled=false;}};return b;}
 function input(parent,label,value='',type='text'){const l=el('label',label),i=el(type==='textarea'?'textarea':'input');if(type!=='textarea')i.type=type;i.value=value??'';i.setAttribute('aria-label',label);if(type==='number'){i.min='0';i.step='any';}l.append(i);parent.append(l);return i;}
 function checkbox(parent,label,value,change){const l=el('label'),c=el('input');c.type='checkbox';c.checked=!!value;c.onchange=()=>{change(c.checked);changed();};l.append(c,document.createTextNode(' '+label));parent.append(l);return c;}
 function table(parent,headers,rows){const box=el('div',undefined,'scroll'),t=el('table'),h=el('tr');headers.forEach(x=>h.append(el('th',x)));t.append(h);for(const values of rows){const tr=el('tr');for(const v of values){const td=el('td');td.append(v instanceof Node?v:document.createTextNode(String(v??'')));tr.append(td);}t.append(tr);}box.append(t);parent.append(box);}
 async function locked(action){busy=true;const controls=[...root.querySelectorAll('button,input,select,textarea')];controls.forEach(c=>{c.dataset.wasDisabled=String(c.disabled);c.disabled=true;});try{return await action();}finally{busy=false;controls.forEach(c=>c.disabled=c.dataset.wasDisabled==='true');}}
 async function picker(title,loader,columns,pick){
  const dialog=el('dialog',undefined,'imp-picker'),out=el('div'),status=el('p'),q=input(dialog,'Buscar no seletor','','search');let p=0,seq=0;const g=epoch;
  dialog.prepend(el('h2',title));dialogs.add(dialog);dialog.addEventListener('close',()=>{dialogs.delete(dialog);dialog.remove();});
  async function load(){const s=++seq;status.textContent='Consultando…';try{const r=await loader(p,q.value);if(s!==seq||g!==epoch||!dialog.isConnected)return;out.replaceChildren();table(out,columns.map(x=>x[0]).concat('Ação'),r.linhas.map(x=>columns.map(c=>c[1](x)).concat(button('Selecionar',async()=>{dialog.close();await pick(x);} ))));const prev=button('Anterior',async()=>{p--;await load();}),next=button('Próxima',async()=>{p++;await load();});prev.disabled=p===0;next.disabled=(p+1)*30>=r.total;out.append(prev,el('span',' Página '+(p+1)+' · '+r.total+' registro(s) '),next);status.textContent=r.total?'':'Nenhum registro encontrado.';}catch(e){status.textContent=e.message;}}
  dialog.append(button('Buscar',async()=>{p=0;await load();}),status,out,button('Fechar',()=>dialog.close()));document.body.append(dialog);dialog.showModal();await load();
 }
 async function fileBase64(file){return new Promise((resolve,reject)=>{const r=new FileReader();r.onerror=()=>reject(Error('Não foi possível ler o arquivo'));r.onload=()=>resolve(String(r.result).split(',')[1]);r.readAsDataURL(file);});}
 function uploadForm(parent,tipo){
  const box=el('fieldset');box.append(el('legend',tipo==='XML'?'Nova nota de entrada · XML Nomus':'PDF/DANFE da nota'));
  const file=input(box,tipo==='XML'?'Selecionar XML (até 2 MB)':'Selecionar PDF (até 8 MB)','','file');file.accept=tipo==='XML'?'.xml,application/xml,text/xml':'.pdf,application/pdf';
  let preview=null;const out=el('div');file.onchange=()=>{preview=null;uploadPending=null;out.replaceChildren();};
  async function prepare(){const f=file.files[0];if(!f)throw Error('Selecione o arquivo');if(!f.size||f.size>(tipo==='XML'?2097152:8388608))throw Error('Arquivo acima do limite ou vazio');return {tipo,nome:f.name,conteudo:await fileBase64(f),...(tipo==='PDF'?{paginas:await lerPDFImportacao(f,t=>msg.textContent=t)}:{})};}
  if(tipo==='XML')box.append(button('Ler XML e conferir',async()=>{
   const payload=await prepare();const r=await locked(()=>api({acao:'nf_ler_xml',...payload}));preview={payload,xml:r};out.replaceChildren(el('p','NF-e '+r.numero+' · Série '+r.serie+' · '+r.itens.length+' item(ns) · '+brl(r.totais.vNF)),el('p','Chave: '+r.chave));r.avisos.forEach(x=>out.append(el('p',x,'status error')));
   if(r.autorizada)out.append(button('Anexar este XML',async()=>{if(!preview)return;uploadPending??={acao:'nf_upload',...preview.payload,requisicao_id:crypto.randomUUID()};const saved=await locked(()=>api(uploadPending));uploadPending=null;await open(saved.id);msg.textContent='XML anexado. Os vínculos identificados nos documentos foram preenchidos; complete somente as pendências e anexe o PDF.';}));
   else out.append(el('p','Use o XML emitido com protocolo de autorização. O espelho pode ser consultado aqui, mas não será anexado como nota emitida.'));
  }));
  else box.append(button('Anexar PDF',async()=>{if(dirty&&!confirm('Salve primeiro os vínculos para mantê-los. Deseja descartar as alterações e anexar o PDF?'))return;const payload=await prepare();uploadPending??={acao:'nf_upload',...payload,id:note.id,versao:note.versao,requisicao_id:crypto.randomUUID()};const r=await locked(()=>api(uploadPending));uploadPending=null;dirty=false;await open(r.id);msg.textContent='PDF anexado e chave comparada ao XML. A nota será conciliada automaticamente quando não houver pendências.';}));
  box.append(out);parent.append(box);
 }
 async function list(){
  const g=epoch;note=null;data=null;dirty=false;pending=null;body.replaceChildren(el('h2','Notas de entrada · Nomus'),el('p','Anexe o XML e o PDF emitidos no Nomus. Vincule os produtos AXE ao pedido, embarque e DI/DUIMP. Esta conferência preserva o custo real e os saldos cambiais.'));
  if(editable)uploadForm(body,'XML');const toolbar=el('div',undefined,'cadastro-toolbar'),q=input(toolbar,'Buscar por número ou chave',query,'search'),out=el('div');toolbar.append(button('Buscar notas',async()=>{query=q.value;page=0;await list();}));body.append(toolbar,out);msg.textContent='Consultando notas…';
  const r=await api({acao:'nf_listar',pagina:page,busca:query});if(g!==epoch||root.hidden)return;
  table(out,['Nota','Emissão','Valor fiscal','Embarque','Situação','Ação'],r.linhas.map(x=>[x.numero,String(x.emissao||'').slice(0,10).split('-').reverse().join('/'),brl(x.valor),x.embarque||'Não vinculado',x.estado,button('Abrir nota',()=>open(x.id))]));
  const prev=button('Anterior',async()=>{page--;await list();}),next=button('Próxima',async()=>{page++;await list();});prev.disabled=page===0;next.disabled=(page+1)*30>=r.total;out.append(prev,el('span',' Página '+(page+1)+' · '+r.total+' nota(s) '),next);msg.textContent='';
 }
 async function open(id){const g=epoch;const r=await api({acao:'nf_detalhe',id});if(g!==epoch||root.hidden)return;note=r;shipment=r.embarque;data=structuredClone(r.dados||{vinculos:[]});data.vinculos??=[];r.produtos?.forEach(p=>products.set(String(p.id),p));r.declaracoes?.forEach(d=>declarations.set(d.id,d));for(const row of data.vinculos)if(row.leitura_id&&!readings.has(row.leitura_id)){const reading=await api({acao:'nf_di_detalhe',leitura_id:row.leitura_id});if(g!==epoch||root.hidden)return;readings.set(reading.id,reading);}
 dirty=false;pending=null;render();if(r.automatizacao){const a=r.automatizacao;msg.textContent=a.avisos?.length?a.avisos.join(' '):'Vínculos preenchidos pelos documentos. A conferência de valores, tributos e saldos continua automática.';}}
 const productLabel=id=>{const p=products.get(String(id));return p?(p.codigo_axe||'#'+p.id)+' · '+p.descricao_referencia:'Selecionar produto AXE';};
 const declarationLabel=id=>declarations.get(id)?.referencia||'Selecionar DI/DUIMP';
 async function chooseProduct(row){const source=shipment?.itens.find(x=>x.pedido_item_id===row.pedido_item_id);const cad=initCadastrosImportacao(api,root);await cad.escolher('produto',source?{descricao_referencia:source.descricao,unidade_referencia:source.unidade}:{},p=>{products.set(String(p.id),p);row.produto_id=String(p.id);changed();render();});}
 async function chooseDI(row){if(!shipment)throw Error('Selecione o embarque primeiro');await picker('DI/DUIMP do processo',(pagina,busca)=>api({acao:'fx_listar',tipo:'declaracoes',pagina,busca}),[['Declaração',x=>x.referencia],['Fornecedor',x=>x.fornecedor],['Moeda',x=>x.moeda]],async d=>{const full=await locked(()=>api({acao:'fx_detalhe',tipo:'declaracoes',id:d.id}));if(String(full.fornecedor_id)!==String(shipment.fornecedor_id)||full.moeda!==shipment.moeda)throw Error('Selecione uma declaração do mesmo fornecedor e moeda do embarque.');declarations.set(d.id,d);row.declaracao_id=d.id;row.leitura_id='';row.di_item='';changed();render();});}

 function addDIControls(group,grid,row,readOnly){
  const reading=readings.get(row.leitura_id);
  grid.append(button(reading?'Leitura: '+reading.nome+' · Item '+(row.di_item||'não selecionado'):'Selecionar leitura e item da DI/DUIMP',async()=>{
   if(!row.declaracao_id)throw Error('Selecione a DI/DUIMP primeiro.');
   await picker('Leituras da declaração',(pagina)=>api({acao:'nf_di_listar',declaracao_id:row.declaracao_id,pagina}),[['Documento',x=>x.nome],['Situação',x=>x.pronto?'Leitura confirmada':'Envio pendente'],['Data',x=>new Date(x.criado_em).toLocaleString('pt-BR')]],x=>{if(!x.pronto)throw Error('Conclua o envio do documento primeiro.');readings.set(x.id,x);row.leitura_id=x.id;row.di_item='';row.fator_di||='1';changed();render();});
  }));
  if(!readOnly)group.append(button('Ler PDF desta DI/DUIMP',async()=>{
   if(!row.declaracao_id)throw Error('Selecione a DI/DUIMP primeiro.');
   await diReader.open({id:row.declaracao_id,referencia:declarationLabel(row.declaracao_id)},async saved=>{const r=await api({acao:'nf_di_detalhe',leitura_id:saved.id});readings.set(r.id,r);row.leitura_id=r.id;row.di_item='';row.fator_di||='1';changed();render();msg.textContent='Leitura anexada. Selecione o item correspondente e confira os valores.';});
  }));
  if(reading){const l=el('label','Item/adição da DI/DUIMP'),select=el('select');select.setAttribute('aria-label','Item/adição da DI/DUIMP');select.dataset.necessarioConciliar='true';select.append(new Option('Selecionar item',''));for(const item of reading.revisado.itens)select.append(new Option('Item '+item.id+' · NCM '+(item.ncm||'?')+' · Quantidade '+(item.quantidade.valor??'?')+' '+(item.unidade||'unidade a confirmar'),item.id));select.value=row.di_item||'';select.onchange=()=>{row.di_item=select.value;changed();};l.append(select);grid.append(l);
   const hist=el('details');hist.append(el('summary','Revisão da leitura e correções registradas'),el('pre',JSON.stringify(reading.revisado,null,2)));group.append(hist);
   const download=button('Baixar DI/DUIMP original',async()=>{const r=await api({acao:'nf_di_baixar',leitura_id:reading.id});const a=el('a','Abrir original');a.href=r.url;a.target='_blank';a.rel='noopener noreferrer';a.click();});download.dataset.readonlyAllowed='true';group.append(download);
  }
  const factor=input(grid,'Fator: unidade da nota → unidade comercial DI/DUIMP',row.fator_di||'1','number'),reason=input(grid,'Justificativa da unidade/conversão DI/DUIMP',row.justificativa_di||'','textarea');factor.oninput=()=>{row.fator_di=factor.value;changed();};reason.oninput=()=>{row.justificativa_di=reason.value;changed();};
 }

 function render(){
  const readOnly=!editable||note.estado==='Conciliada';body.replaceChildren();msg.textContent='';
  body.append(button('Voltar às notas',async()=>{if(guard()){dirty=false;await list();}}),el('h2','NF-e '+note.xml.numero+' · Série '+note.xml.serie+' · '+note.estado),el('p','Chave: '+note.chave,'nf-chave'),el('p','Emitente: '+note.xml.emitente+' · CNPJ '+note.xml.cnpj),el('p','Valor fiscal: '+brl(note.xml.totais.vNF)+' · Protocolo informado no XML: '+(note.xml.protocolo||'Ausente')));
  const docs=el('fieldset');docs.append(el('legend','Documentos originais'));
  for(const f of note.arquivos){const p=el('p',f.tipo+' · '+f.nome+' · '+(f.pronto?'Anexado':'Envio pendente'));if(f.pronto)p.append(button('Baixar '+f.tipo,async()=>{const r=await api({acao:'nf_baixar',id:note.id,arquivo_id:f.id});const a=el('a','Abrir anexo');a.href=r.url;a.target='_blank';a.rel='noopener noreferrer';a.click();}));docs.append(p);}
  body.append(docs);if(!readOnly&&!note.arquivos.some(f=>f.tipo==='PDF'&&f.pronto))uploadForm(body,'PDF');
  const proc=el('fieldset');proc.append(el('legend','Processo de importação'),el('p',shipment?'Embarque: '+shipment.referencia+' · '+shipment.fornecedor:'Nenhum embarque vinculado'));
  if(!readOnly)proc.append(button('Selecionar embarque',async()=>{
   if(data.vinculos.length&&!confirm('Trocar o embarque remove os vínculos de itens ainda não salvos. Continuar?'))return;
   await picker('Embarque da nota',(pagina,busca)=>api({acao:'v2_listar',tipo:'embarques',pagina,busca}),[['Embarque',x=>x.referencia],['Fornecedor',x=>x.fornecedor],['Situação',x=>x.status]],async x=>{if(x.status==='Cancelado')throw Error('Selecione um embarque ativo');shipment=await locked(()=>api({acao:'v2_detalhe',tipo:'embarques',id:x.id}));data.vinculos=[];changed();render();});
  }));body.append(proc);
  for(const item of note.xml.itens){
   const box=el('fieldset');box.append(el('legend','Linha '+item.linha+' · '+item.codigo),el('p',item.descricao),el('p',item.quantidade+' '+item.unidade+' · NCM '+item.ncm+' · Produtos '+brl(item.valor)),el('p','DI/DUIMP no XML: '+(item.declaracoes.map(x=>x.numero).join(', ')||'Não informada em campo estruturado')));
   const taxes=el('details');taxes.append(el('summary','Valores fiscais da linha'));table(taxes,['Campo','Valor'],[['Frete',brl(item.frete)],['Seguro',brl(item.seguro)],['Outras despesas',brl(item.outras)],...Object.entries(item.impostos).map(([k,v])=>[k,brl(v)])]);box.append(taxes);
   const rows=data.vinculos.filter(x=>x.linha===item.linha);
   for(const row of rows){
    const group=el('fieldset'),grid=el('div',undefined,'import-mapping');group.append(el('legend','Vínculo com pedido e produto'),grid);
    const pb=button(productLabel(row.produto_id),()=>chooseProduct(row)),db=button(declarationLabel(row.declaracao_id),()=>chooseDI(row));grid.append(pb,db);
    const l=el('label','Item do pedido neste embarque'),s=el('select');s.setAttribute('aria-label','Item do pedido neste embarque');s.required=true;s.append(new Option('Selecionar item',''));for(const x of shipment?.itens||[])s.append(new Option(x.pedido+' · Linha '+x.linha+' · '+x.descricao+' · Recebido '+x.recebida+' '+x.unidade,x.pedido_item_id));s.value=row.pedido_item_id||'';s.onchange=()=>{row.pedido_item_id=s.value;const linked=shipment?.itens.find(x=>x.pedido_item_id===s.value);if(linked?.produto_id){row.produto_id=String(linked.produto_id);pb.textContent='Produto do cadastro AXE #'+linked.produto_id;}changed();};l.append(s);grid.append(l);
    addDIControls(group,grid,row,readOnly);
    const qty=input(grid,'Quantidade da nota vinculada',row.quantidade,'number'),factor=input(grid,'Fator: unidade da nota → unidade AXE/pedido',row.fator||'1','number'),reason=input(grid,'Justificativa de conversão / divergência / conferência manual',row.justificativa||'','textarea');
    qty.required=true;qty.min='0.000001';factor.required=true;factor.min='0.000001';controlesVinculos.set(row,{produto:pb,declaracao:db,item:s,leitura:grid.querySelectorAll('button')[2]});
    qty.oninput=()=>{row.quantidade=qty.value;changed();};factor.oninput=()=>{row.fator=factor.value;changed();};reason.oninput=()=>{row.justificativa=reason.value;changed();};
    if(!readOnly)group.append(button('Remover vínculo',()=>{data.vinculos.splice(data.vinculos.indexOf(row),1);changed();render();}));
    if(readOnly)group.querySelectorAll('input,select,textarea,button:not([data-readonly-allowed])').forEach(x=>x.disabled=true);box.append(group);
   }
   if(!readOnly)box.append(button('Adicionar vínculo à linha '+item.linha,()=>{if(!shipment)throw Error('Selecione o embarque primeiro');data.vinculos.push({linha:item.linha,produto_id:rows[0]?.produto_id||'',pedido_item_id:'',declaracao_id:'',quantidade:rows.length?'':item.quantidade,fator:'1',justificativa:'',fator_di:'1',leitura_id:'',di_item:'',justificativa_di:''});changed();render();}));
   body.append(box);
  }
  const checks=el('fieldset');checks.append(el('legend','Conferência documental'),el('p','O ERP compara FOB aduaneiro em reais, frete, seguro e tributos de cada item da DI/DUIMP com o XML. Vincule a leitura e o item da declaração em cada linha. Valores não informados e diferenças impedem a conciliação.'));
  const pdfcheck=checkbox(checks,'Conferi o PDF: corresponde à chave, aos produtos e aos valores deste XML',data.pdf_conferido,v=>data.pdf_conferido=v);pdfcheck.dataset.necessarioConciliar='true';if(data.pdf_fonte_automatica)pdfcheck.closest('label').hidden=true;

  if(note.xml.itens.some(i=>Number(i.outras||0)>0))checkbox(checks,'Conferi as outras despesas do XML nos documentos complementares',data.outras_conferidas,v=>data.outras_conferidas=v).dataset.necessarioConciliar='true';
  const exceptions=el('details');exceptions.append(el('summary','Complementar conferência em caso de divergência'));const ref=input(exceptions,'Referência documental complementar',data.referencia_conferencia||'','textarea');ref.oninput=()=>{data.referencia_conferencia=ref.value;changed();};checks.append(exceptions);if(readOnly)checks.querySelectorAll('input,textarea').forEach(x=>x.disabled=true);body.append(checks);
  const result=el('div');body.append(button('Conferir vínculos e saldos',async()=>{const r=await locked(()=>api({acao:'nf_prever',id:note.id,embarque_id:shipment?.id||null,dados:data}));showResult(result,r);}),result);
  if(note.resultado)showResult(result,note.resultado);
  if(!readOnly){
   body.append(button('Salvar conferência pendente',()=>save(false,result)),button('Conciliar nota com a importação',()=>save(true,result)));
  }else if(editable){body.append(button('Reabrir conciliação',async()=>{const motivo=prompt('Motivo da reabertura da conciliação:');if(!motivo?.trim())return;pending??={acao:'nf_reabrir',id:note.id,versao:note.versao,motivo,requisicao_id:crypto.randomUUID()};const r=await locked(()=>api(pending));dirty=false;pending=null;await open(r.id);}));}
  const history=el('details'),out=el('div');history.append(el('summary','Histórico da nota'),button('Consultar histórico da nota',async()=>{const r=await api({acao:'nf_historico',id:note.id});out.replaceChildren();for(const x of r.linhas){const d=el('details');d.append(el('summary',new Date(x.criado_em).toLocaleString('pt-BR')),el('pre',JSON.stringify(x,null,2)));out.append(d);}}),out);body.append(history);
 }
 function showResult(target,r){target.replaceChildren(el('h3',r.apto?'Conferência sem pendências':'Pendências para conciliação'));for(const p of r.pendencias)target.append(el('p',p,'status error'));if(r.fiscal?.length)table(target,['Linha','Campo (BRL)','DI/DUIMP','XML Nomus','Diferença','Situação','Origem'],r.fiscal.map(x=>[x.linha,x.campo,brl(x.di),brl(x.xml),brl(x.diferenca),x.situacao,x.fontes.map(f=>f.declaracao+' · Item '+f.item+' · Pág. '+(f.pagina??'?')+' · '+(f.origem||'Extraído')+' · Parcial '+f.quantidade_parcial+'/'+f.quantidade_integral).join(' | ')]));if(r.usos_di?.length)table(target,['Item DI/DUIMP','Declarado','Outras notas','Nesta nota','Saldo'],r.usos_di.map(x=>[x.item,x.declarada,x.outras_notas,x.quantidade,x.saldo]));table(target,['Item do pedido','Recebido','Outras notas','Nesta nota (unidade AXE)','Saldo'],r.quantidades.map(x=>[x.pedido_item_id,x.recebida,x.outras_notas,x.vinculada,x.saldo]));target.append(el('p','Valor fiscal da nota: '+brl(r.valor_fiscal)+' · Custo real do embarque: '+brl(r.custo_real)),el('p',r.nota||'A nota não substitui a apuração do custo real.'));}
 async function save(conciliar,target){
  for(const c of body.querySelectorAll('[data-necessario-conciliar]'))c.required=conciliar;let faltando=false;for(const row of data.vinculos){const c=controlesVinculos.get(row);if(c){if(conciliar&&!row.leitura_id&&c.leitura){marcarErro(c.leitura,'Selecione a leitura da DI / DUIMP.');faltando=true;}if(!row.produto_id){marcarErro(c.produto,'Selecione o produto do cadastro.');faltando=true;}if(!row.declaracao_id){marcarErro(c.declaracao,'Selecione a DI / DUIMP.');faltando=true;}}}const camposValidos=validarCampos(body);if(faltando&&camposValidos){const primeiro=body.querySelector('.campo-invalido');primeiro?.scrollIntoView({block:'center'});primeiro?.focus();}if(faltando||!camposValidos)throw Error('Preencha os campos destacados em vermelho.');
  for(const row of data.vinculos)if(!row.produto_id||!row.pedido_item_id||!row.declaracao_id||!Number(row.quantidade)||!Number(row.fator))throw Error('Complete ou remova os vínculos incompletos antes de salvar.');
  if(conciliar){const r=await locked(()=>api({acao:'nf_prever',id:note.id,embarque_id:shipment?.id||null,dados:data}));showResult(target,r);if(!r.apto)throw Error('Resolva as pendências indicadas antes de conciliar.');}
  if(!pending)pending={acao:'nf_salvar',id:note.id,versao:note.versao,embarque_id:shipment?.id||null,dados:structuredClone(data),conciliar,requisicao_id:crypto.randomUUID()};else if(pending.conciliar!==conciliar)throw Error('Repita a última operação de salvamento para confirmar seu resultado antes de mudar a ação.');
  const r=await locked(()=>api(pending));dirty=false;pending=null;await open(r.id);msg.textContent=conciliar?'Nota conciliada. Histórico preservado.':'Conferência salva como pendente.';msg.className='status';
 }
 window.addEventListener('beforeunload',e=>{if(!root.hidden&&(dirty||busy)){e.preventDefault();e.returnValue='';}});
 return {canLeave:()=>root.hidden||guard(),async show(visible){epoch++;for(const d of dialogs)d.close();root.hidden=!visible;if(!visible)return;dirty=false;pending=null;page=0;query='';const g=epoch;try{const o=await api({acao:'nf_opcoes'});if(g!==epoch)return;editable=o.editar;await list();}catch(e){msg.textContent=e.message;}},reset(){diReader.reset();epoch++;for(const d of dialogs)d.close();root.hidden=true;body.replaceChildren();readings.clear();products.clear();declarations.clear();dirty=false;pending=null;uploadPending=null;note=null;data=null;}};
}

