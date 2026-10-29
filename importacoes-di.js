import {lerPDFImportacao} from './importacoes-di-leitura.js?v=20261028-di1';
const keys=['FOB','Frete','Seguro','II','IPI','ICMS','PIS','COFINS','IBS','CBS'];
const el=(tag,text)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;return e;};
export function initLeituraDI(api,onBusy){
 let dialog=null,busy=false,dirty=false,abort=null;
 const canLeave=()=>!dialog&&!busy;
 function close(force=false){if(busy&&!force){abort?.abort();return;}if(!force&&dirty&&!confirm('Descartar a revisão da leitura ainda não anexada?'))return;dialog?.close();dialog?.remove();dialog=null;dirty=false;}
 async function open(declaration,onSaved){
  if(dialog)return;
  dialog=el('dialog');dialog.className='imp-picker imp-di-review';const d=dialog;dialog.append(el('h2','Ler DI/DUIMP · '+declaration.referencia),el('p','Selecione o extrato em PDF. A leitura usa o texto do arquivo ou OCR no seu navegador. Revise os campos antes de confirmar. Valores ausentes ficam em branco; não copie valores do XML para completar a declaração.'));
  const status=el('p'),out=el('div'),l=el('label','PDF da DI/DUIMP (até 8 MB e 20 páginas)'),file=el('input');file.type='file';file.accept='.pdf,application/pdf';l.append(file);let source=null,pages=null,review=null,pending=null;
  function btn(label,fn){const b=el('button',label);b.type='button';b.onclick=async()=>{if(busy)return;try{b.disabled=true;await fn();}catch(e){status.textContent=e.message;status.className='status error';}finally{if(b.isConnected)b.disabled=false;}};return b;}
  async function lock(fn){busy=true;onBusy(true);const controls=[...d.querySelectorAll('input,textarea,select,button')];controls.forEach(c=>{c.dataset.wasDisabled=String(c.disabled);c.disabled=true;});try{return await fn();}finally{busy=false;onBusy(false);controls.forEach(c=>{if(c.isConnected)c.disabled=c.dataset.wasDisabled==='true';});}}
  function field(parent,label,value,change,type='text'){const lab=el('label',label),i=el(type==='textarea'?'textarea':'input');if(type!=='textarea')i.type=type;i.value=value??'';i.setAttribute('aria-label',label);if(type==='number'){i.min=0;i.step='any';}i.oninput=()=>{change(i.value);dirty=true;pending=null;};lab.append(i);parent.append(lab);return i;}
  function draw(parsed){
   out.replaceChildren();review=structuredClone(parsed);review.motivo=parsed.motivo||'';dirty=true;
   for(const warning of parsed.avisos)out.append(el('p',warning));
   const identity=el('div');identity.className='import-mapping';field(identity,'Número da declaração (somente letras e números)',review.numero,v=>review.numero=v.toUpperCase().replace(/[^A-Z0-9]/g,''));field(identity,'CNPJ do importador',review.cnpj,v=>review.cnpj=v.replace(/\D/g,''));out.append(identity);
   const add=btn('Adicionar item/adição não reconhecido',()=>{const id=prompt('Número do item/adição conforme o PDF:');if(!id||!/^\d{1,5}$/.test(id)||review.itens.some(i=>i.id===String(Number(id))))return;review.itens.push({id:String(Number(id)),ncm:null,unidade:null,descricao:'',quantidade:{valor:null,pagina:null},campos:Object.fromEntries(keys.map(k=>[k,{valor:null,pagina:null}]))});const keep=review;draw(keep);review.motivo=keep.motivo;});
   out.append(add);
   for(const item of review.itens){
    const box=el('fieldset');box.append(el('legend','Item/adição '+item.id),el('p',item.descricao||'Descrição não identificada'));
    const g=el('div');g.className='import-mapping';field(g,'NCM do item '+item.id,item.ncm,v=>item.ncm=v);field(g,'Unidade comercial do item '+item.id,item.unidade,v=>item.unidade=v.toUpperCase());field(g,'Quantidade comercial do item '+item.id,item.quantidade.valor,v=>item.quantidade.valor=v,'number');field(g,'Página da quantidade do item '+item.id,item.quantidade.pagina,v=>item.quantidade.pagina=v,'number');box.append(g);
    const scroll=el('div');scroll.className='scroll';const table=el('table'),head=el('tr');['Campo (BRL)','Valor lido / revisado','Página','Origem / conflito'].forEach(t=>head.append(el('th',t)));table.append(head);
    for(const k of keys){const f=item.campos[k]??={valor:null,pagina:null,trecho:''},tr=el('tr'),v=el('td'),p=el('td'),evidence=el('td');field(v,k+' do item '+item.id,f.valor,x=>f.valor=x,'number');field(p,'Página de '+k+' do item '+item.id,f.pagina,x=>f.pagina=x,'number');const details=el('details');details.append(el('summary',f.conflitos?.length?'Conflito: '+f.conflitos.join(' / '):f.valor==null?'Não informado':'Ver trecho'),el('p',f.trecho||'Não reconhecido. Preencha somente com base no documento.'));evidence.append(details);tr.append(el('td',k),v,p,evidence);table.append(tr);}scroll.append(table);box.append(scroll);out.append(box);
   }
   field(out,'Justificativa e referência documental das correções',review.motivo,v=>review.motivo=v,'textarea');
   const text=el('details');text.append(el('summary','Texto reconhecido e confiança por página'));for(const p of pages){text.append(el('h3','Página '+p.pagina+' · '+p.metodo+(p.confianca==null?'':' · Confiança OCR '+p.confianca+'%')),el('pre',p.texto));}out.append(text);
   const check=el('label'),c=el('input');c.type='checkbox';c.setAttribute('aria-label','Revisei a leitura com o documento original');check.append(c,document.createTextNode(' Revisei a leitura com o documento original, incluindo valores, itens, unidades e páginas de origem.'));out.append(check);
   out.append(btn('Confirmar leitura e anexar original',async()=>{
    if(!c.checked)throw Error('Confirme a revisão da leitura.');
    if(!pending)pending={acao:'nf_di_upload',declaracao_id:declaration.id,nome:source.name,conteudo:await base64(source),paginas:pages,revisado:structuredClone(review),confirmado:true,requisicao_id:crypto.randomUUID()};
    status.textContent='Anexando o original e registrando a revisão…';const saved=await lock(()=>api(pending));dirty=false;close(true);await onSaved(saved);
   }));
  }
  file.onchange=()=>{source=null;pages=null;review=null;pending=null;out.replaceChildren();};
  d.append(l,btn('Ler documento aduaneiro',async()=>{
   const f=file.files[0];if(!f)throw Error('Selecione o PDF.');source=f;abort=new AbortController();
   const parsed=await lock(async()=>{pages=await lerPDFImportacao(f,t=>{status.textContent=t;status.className='status';},abort.signal);status.textContent='Identificando campos e valores…';return api({acao:'nf_di_prever',conteudo:await base64(f),paginas:pages});});
   if(!d.isConnected)return;draw(parsed);status.textContent='Leitura concluída. Confira os valores; campos vazios permanecem pendentes.';
  }),status,out,btn('Fechar leitura',()=>close()));
  d.addEventListener('cancel',e=>{e.preventDefault();close();});document.body.append(d);d.showModal();
 }
 function base64(file){return new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(String(r.result).split(',')[1]);r.onerror=()=>reject(Error('Não foi possível ler o arquivo'));r.readAsDataURL(file);});}
 return {open,canLeave,reset(){abort?.abort();close(true);}};
}
