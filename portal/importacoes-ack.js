import {initCadastrosImportacao} from './importacoes-cadastros.js?v=20261029-fluxo15';
import {aceiteDocumentoOficial,temConflitoDocumental} from './importacoes-documento-oficial.js?v=20261029-fluxo15';
import {validarCampos} from './validacao-campos.js?v=20261030-imp34';
import {lerPDFImportacao} from './importacoes-di-leitura.js?v=20261028-di1';
const el=(tag,text,cls)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
const dt=v=>v?String(v).slice(0,10).split('-').reverse().join('/'):'Não identificado';
export function initACKImportacao(api,root,onSaved){
 const cadastros=initCadastrosImportacao(api,root);
 let dialog=null,dirty=false,busy=false,controller=null;
 const guard=()=>!busy&&(!dirty||confirm('Há um ACK em revisão. Deseja descartar esta revisão?'));
 function close(){controller?.abort();dialog?.close();dialog?.remove();dialog=null;dirty=false;}
 function btn(text,fn){const b=el('button',text);b.type='button';b.onclick=async()=>{if(busy)return;b.disabled=true;try{await fn();}catch(e){const s=dialog?.querySelector('[role=status]');if(s)s.textContent=e.message;}finally{if(b.isConnected)b.disabled=false;}};return b;}
 function input(parent,label,type,value=''){const l=el('label',label),i=el(type==='textarea'?'textarea':'input');if(type!=='textarea')i.type=type;i.value=value;i.setAttribute('aria-label',label);l.append(i);parent.append(l);return i;}
 async function locked(fn){busy=true;const controls=[...dialog.querySelectorAll('button,input,textarea')],states=controls.map(x=>x.disabled);controls.forEach(x=>x.disabled=true);try{return await fn();}finally{busy=false;controls.forEach((x,i)=>x.disabled=states[i]);}}
 async function show(pedido,editar){
  if(!guard())return;close();dialog=el('dialog',undefined,'imp-picker imp-ack');dialog.setAttribute('aria-label','ACK do pedido');const local=dialog;
  const status=el('p','','status');status.setAttribute('role','status');const list=el('div'),review=el('div');
  dialog.append(el('h2','ACK do pedido '+pedido.referencia),el('p','Anexe a confirmação do fornecedor. Após a revisão, o pedido passa para ACK recebido. Preços, quantidades, disponibilidade e parcelas permanecem conforme o cadastro.'),btn('Fechar',()=>{if(guard())close();}),status,list);
  dialog.addEventListener('cancel',e=>{e.preventDefault();if(guard())close();});root.append(dialog);dialog.showModal();
  async function download(id){const r=await api({acao:'ack_baixar',id});if(dialog!==local)return;const a=el('a','Baixar ACK');a.href=r.url;a.target='_blank';a.rel='noopener noreferrer';a.click();}
  async function apply(id,requisicao_id){return api({acao:'ack_aplicar',id,versao:pedido.versao,requisicao_id,confirmado:true});}
  async function done(){if(dialog!==local)return;dirty=false;close();await onSaved(pedido.id);}
  async function load(){const r=await api({acao:'ack_listar',pedido_id:pedido.id});if(dialog!==local)return;list.replaceChildren(el('h3','Documentos anexados'));if(!r.linhas.length)list.append(el('p','Nenhum ACK anexado.'));
   for(const x of r.linhas){const card=el('article',undefined,'planned-card');card.append(el('p',x.nome+' · ACK '+x.revisado.ack_numero+' · '+dt(x.revisado.ack_data)),el('p',x.aplicado_em?'Recebimento confirmado em '+new Date(x.aplicado_em).toLocaleString('pt-BR'):'Anexado; confirmação do recebimento pendente'),btn('Baixar ACK',()=>download(x.id)));
    if(editar&&!x.aplicado_em&&pedido.status!=='Cancelado'){const check=input(card,'Conferi este ACK e confirmo a atualização abaixo','checkbox');check.checked=false;
     card.append(el('p','Situação: '+pedido.status+' → ACK recebido; número do ACK: '+(pedido.ack_numero||'vazio')+' → '+x.revisado.ack_numero+'; data do ACK: '+dt(pedido.ack_data)+' → '+dt(x.revisado.ack_data)));
     const req=crypto.randomUUID();card.append(btn('Confirmar recebimento deste ACK',async()=>{if(!check.checked)throw Error('Confirme a conferência deste ACK.');await locked(()=>apply(x.id,req));await done();}));}
    list.append(card);
   }
  }
  if(editar&&pedido.status!=='Cancelado'){
   const box=el('fieldset');box.append(el('legend','Anexar ACK em PDF'),el('p','PDF de até 8 MB e 20 páginas. O documento oficial será conferido com o pedido durante a importação.'));
   const file=input(box,'Arquivo de ACK','file');file.accept='.pdf,application/pdf';let selected=null,pages=null,parsed=null,upload=null,applyReq=null;
   file.onchange=()=>{dirty=!!file.files[0];selected=null;pages=null;parsed=null;upload=null;applyReq=null;review.replaceChildren();status.textContent='';};
   box.append(btn('Ler ACK',async()=>{
    const f=file.files[0];if(!f)throw Error('Selecione o PDF do ACK.');review.replaceChildren();controller=new AbortController();
    await locked(async()=>{pages=await lerPDFImportacao(f,t=>status.textContent=t,controller.signal);const bytes=new Uint8Array(await f.arrayBuffer());let binary='';for(let n=0;n<bytes.length;n+=32768)binary+=String.fromCharCode(...bytes.subarray(n,n+32768));selected={nome:f.name,conteudo:btoa(binary),paginas:pages};parsed=await api({acao:'ack_ler',...selected});});
    if(dialog!==local)return;dirty=true;status.textContent='Leitura pronta. Confira os dados antes de confirmar.';
    const grid=el('div',undefined,'import-mapping');review.append(el('h3','Revisão do ACK'),grid);
    const po=input(grid,'Pedido informado no ACK','text',parsed.pedido||''),num=input(grid,'Número do ACK','text',parsed.ack_numero||''),date=input(grid,'Data do ACK','date',parsed.ack_data||''),reason=input(review,'Justificativa para completar ou corrigir os dados lidos','textarea');
    po.required=true;num.required=true;date.required=true;const warnings=el('ul');for(const w of parsed.avisos)warnings.append(el('li',w));if(parsed.pedido&&parsed.pedido!==pedido.referencia)warnings.append(el('li','ATENÇÃO: o pedido do PDF é '+parsed.pedido+', diferente do cadastro aberto ('+pedido.referencia+'). Confira o arquivo.'));if(parsed.moeda&&parsed.moeda!==pedido.moeda)warnings.append(el('li','Moeda do ACK diverge do pedido; o documento não poderá ser aplicado.'));review.append(warnings);
    let conflitoItens=false;const table=el('table'),head=el('tr');['Linha','Código do fornecedor','Quantidade ACK / pedido','Preço ACK / pedido','Data solicitada','Previsão fornecedor','Conferência','Cadastro AXE'].forEach(t=>head.append(el('th',t)));table.append(head);
    for(const x of parsed.itens){const old=pedido.itens.find(y=>String(Number(y.linha))===String(Number(x.linha))),diff=[];
     if(!old)diff.push('Linha não localizada');else{if(Number(old.quantidade)!==Number(x.quantidade))diff.push('Quantidade diferente');if(Number(old.valor_unitario)!==Number(x.valor_unitario))diff.push('Preço diferente');const code=s=>String(s||'').replace(/[^A-Za-z0-9]/g,'').toUpperCase();if(old.codigo_fornecedor&&![x.codigo_fornecedor,x.part_number].some(c=>code(c)===code(old.codigo_fornecedor)))diff.push('Confira o código');}
     if(diff.length)conflitoItens=true;const tr=el('tr');[x.linha,x.codigo_fornecedor,x.quantidade+' / '+(old?.quantidade??'—'),x.valor_unitario+' / '+(old?.valor_unitario??'—'),dt(x.data_solicitada),x.previsao_fornecedor,diff.join('; ')||'Quantidade e preço conferem'].forEach(t=>tr.append(el('td',t)));const td=el('td');if(editar)td.append(btn(old?.produto_id?'Produto AXE #'+old.produto_id:'Selecionar ou cadastrar produto',()=>cadastros.escolher('produto',{codigo_anterior:old?.codigo_axe,part_number:x.codigo_fornecedor,descricao_referencia:old?.descricao,unidade_referencia:old?.unidade||x.unidade},async pr=>{if(old?.id){await api({acao:'custo_cadastro_vincular',tipo:'produto',item_id:old.id,cadastro_id:pr.id});Object.assign(pedido,await api({acao:'v2_detalhe',tipo:'pedidos',id:pedido.id}));}td.textContent=(pr.codigo_axe||'#'+pr.id)+' · '+pr.descricao_referencia;})));tr.append(td);table.append(tr);
    }
    if(parsed.itens.length){const scroll=el('div',undefined,'scroll');scroll.append(table);review.append(scroll);}
    if(parsed.condicoes.length)review.append(el('p','Condições no documento: '+parsed.condicoes.join('; ')));
    const details=el('details');details.append(el('summary','Texto e páginas do documento'));for(const p of parsed.paginas)details.append(el('h4','Página '+p.pagina+' · '+p.metodo),el('pre',p.texto));review.append(details);
    const preview=el('p'),check=input(review,'Conferi o documento, o fornecedor e as diferenças; confirmo o recebimento do ACK','checkbox');
    const update=()=>{preview.textContent='Pedido '+pedido.referencia+' | Situação: '+pedido.status+' → ACK recebido | Número do ACK: '+(pedido.ack_numero||'vazio')+' → '+num.value+' | Data do ACK: '+dt(pedido.ack_data)+' → '+dt(date.value);reason.closest('label').hidden=po.value.trim()===parsed.pedido&&num.value.trim()===parsed.ack_numero&&date.value===parsed.ack_data;upload=null;applyReq=null;check.checked=false;aceiteDocumentoOficial(check,conflitoItens||temConflitoDocumental(parsed.avisos)||po.value.trim()!==parsed.pedido||num.value.trim()!==parsed.ack_numero||date.value!==parsed.ack_data);};
    for(const f of [po,num,date,reason])f.addEventListener('input',update);update();review.append(preview);
    review.append(btn('Importar ACK e atualizar processo',async()=>{
     reason.required=po.value.trim()!==(parsed.pedido||'')||num.value.trim()!==(parsed.ack_numero||'')||date.value!==(parsed.ack_data||'');if(!validarCampos(review))return;if(!check.checked)throw Error('Confirme a revisão do ACK.');if(po.value.trim()!==pedido.referencia)throw Error('O número do pedido precisa corresponder ao cadastro aberto.');
     if(!num.value.trim()||!date.value)throw Error('Informe número e data do ACK.');
     if(!upload)upload={acao:'ack_upload',...selected,pedido_id:pedido.id,requisicao_id:crypto.randomUUID(),confirmado:true,revisado:{pedido:po.value.trim(),ack_numero:num.value.trim(),ack_data:date.value,motivo:reason.value.trim()}};
     if(!applyReq)applyReq=crypto.randomUUID();
     await locked(async()=>{status.textContent='Guardando o anexo e confirmando o recebimento…';const r=await api(upload);await apply(r.id,applyReq);});await done();
    }));
   }),review);dialog.append(box);
  }
  try{await load();}catch(e){status.textContent=e.message;}
 }
 window.addEventListener('beforeunload',e=>{if(dialog&&(dirty||busy)){e.preventDefault();e.returnValue='';}});
 return {show,canLeave:guard,reset:close};
}
