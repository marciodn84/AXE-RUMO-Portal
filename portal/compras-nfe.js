import {botaoTributos, mostrarTributos} from './tributos-registros.js?v=20261106-perfis17';
import {criarConferenciaFinanceira} from './compras-financeiro.js?v=20261104-financeiro13';
import {criarConferenciaCadastro}from './cadastro-nfe.js?v=20261104-cadastro2';
const el=(tag,text)=>{const x=document.createElement(tag);if(text!==undefined)x.textContent=text;return x;};
const brl=v=>Number(v||0).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo'}).format(new Date());
export function sugerirVinculoNFe(item,itens){
 const hits=itens.filter(p=>String(p.codigo_fornecedor||'')===item.codigo||p.fornecedores?.some(v=>v.codigo_fornecedor===item.codigo));
 if(hits.length!==1)return null;
 const p=hits[0],v=p.fornecedores?.find(v=>v.codigo_fornecedor===item.codigo&&String(v.unidade_compra||'').toUpperCase()===String(item.unidade).toUpperCase()&&!['INATIVO','BLOQUEADO'].includes(v.situacao));
 return {pedido_item_id:p.id,fator:v?.fator_conversao??(String(p.unidade_axe).toUpperCase()===String(item.unidade).toUpperCase()?1:''),custo_total:item.valor_bruto,salvar_fornecedor:true};
}
export function initComprasNFe(api,root,onSaved){
 let dialog=null,busy=false,dirty=false;
 const reset=()=>{if(dialog){dialog.close();dialog.remove();dialog=null;}dirty=false;busy=false;};
 async function show(pedido,editar){
  if(dialog)return;dialog=el('dialog');dialog.className='imp-ack';dialog.style.cssText='width:min(1100px,94vw);max-height:90vh;overflow:auto';root.append(dialog);
  const dlg=dialog,msg=el('p');msg.setAttribute('role','status');const content=el('div');
  const button=(label,fn)=>{const b=el('button',label);b.type='button';b.onclick=async()=>{if(busy)return;busy=true;b.disabled=true;try{await fn();}catch(e){msg.textContent=e.message;msg.className='status error';}finally{busy=false;b.disabled=false;}};return b;};
  const close=()=>{if(busy)return;if(dirty&&!confirm('Descartar a conferência não confirmada?'))return;reset();};
  const closing=el('button','Fechar');closing.type='button';closing.onclick=close;dlg.addEventListener('cancel',e=>{e.preventDefault();close();});
  dlg.append(el('h2','Notas fiscais de entrada · '+pedido.referencia),closing,msg,content);dlg.showModal();
  let xml='',nome='',preview=null,pending=null,rows=[];
  const field=(parent,label,value='',type='text')=>{const l=el('label',label),input=el(type==='textarea'?'textarea':'input');if(type!=='textarea')input.type=type;input.value=value;input.setAttribute('aria-label',label);if(type==='number'){input.step='any';input.min='0';}l.append(input);parent.append(l);return input;};
  const check=(parent,label)=>{const l=el('label'),input=el('input');l.style.cssText='flex-direction:row;align-items:flex-start;gap:8px';input.type='checkbox';input.setAttribute('aria-label',label);l.append(input,document.createTextNode(' '+label));parent.append(l);return input;};
  async function history(){
   const r=await api({acao:'compra_nf_listar',pedido_id:pedido.id});if(!dlg.isConnected)return;
   const list=el('section');list.append(el('h3','Notas vinculadas ao pedido'));
   if(!r.notas.length)list.append(el('p','Nenhuma nota de entrada registrada.'));
   for(const n of r.notas){const box=el('fieldset');box.append(el('legend','NF-e '+n.numero+' / '+n.serie+' · '+n.estado),el('p',brl(n.valor)+' · Entrada '+n.data_entrada),el('p','Chave: '+n.chave));
    box.append(botaoTributos(api,'entrada',n.id,'BRL'));
    box.append(button('Baixar XML da NF-e '+n.numero,async()=>{const f=await api({acao:'compra_nf_baixar',pedido_id:pedido.id,id:n.id});const url=URL.createObjectURL(new Blob([f.xml],{type:'application/xml'})),a=el('a');a.href=url;a.download=f.nome;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}));
    if(editar&&n.estado==='Confirmada')box.append(button('Completar cadastro pela NF-e '+n.numero,async()=>{const r=await api({acao:'compra_nf_cadastro_previa',pedido_id:pedido.id,id:n.id});renderCadastroExistente(n,r);}));
    if(editar&&n.estado==='Confirmada'){const why=field(box,'Justificativa do estorno da NF-e '+n.numero,'','textarea');let req=null;box.append(button('Estornar NF-e '+n.numero,async()=>{if(why.value.trim().length<5)throw Error('Justifique o estorno.');if(!confirm('Estornar toda esta nota e suas entradas de estoque?'))return;req??={acao:'compra_nf_estornar',pedido_id:pedido.id,id:n.id,requisicao_id:crypto.randomUUID(),confirmado:true,justificativa:why.value.trim()};await api(req);dirty=false;reset();await onSaved(pedido.id);}));}list.append(box);
   }content.append(list);
  }
  if(editar){
   const upload=el('fieldset');upload.append(el('legend','Importar XML de compra nacional'));
   const file=field(upload,'XML da NF-e (até 2 MB)','','file');file.accept='.xml,application/xml,text/xml';
   const reading=button('Ler XML e conferir',async()=>{
    const f=file.files[0];if(!f||!f.size||f.size>2097152)throw Error('Selecione um XML de até 2 MB.');
    xml=await f.text();nome=f.name;preview=null;pending=null;dirty=false;
    const r=await api({acao:'compra_nf_ler',pedido_id:pedido.id,xml});if(!dlg.isConnected)return;
    preview=r;dirty=true;render();
   });upload.append(reading);content.append(upload);
  }
  const review=el('section');content.append(review);await history();
  function renderCadastroExistente(n,r){
   review.replaceChildren(el('h3','Completar cadastro pela NF-e '+n.numero),el('p','Esta operação atualiza somente o cadastro. Não altera a nota nem gera outra entrada de estoque.'));
   pending=null;dirty=true;
   const confs=r.cadastros.map(c=>{const item=r.documento.itens.find(i=>i.linha===c.linha);review.append(el('h4','Linha '+c.linha+' · '+item.codigo));return {linha:c.linha,pedido_item_id:c.pedido_item_id,ui:criarConferenciaCadastro(review,c.cadastro,()=>pending=null)};});
   review.append(button('Salvar cadastro conferido pela nota',async()=>{const vinculos=confs.map(c=>({linha:c.linha,pedido_item_id:c.pedido_item_id,cadastro:c.ui.collect()}));pending??={acao:'compra_nf_cadastro_salvar',pedido_id:pedido.id,id:n.id,requisicao_id:crypto.randomUUID(),confirmado:true,vinculos};await api(pending);dirty=false;reset();await onSaved(pedido.id);}));
  }
  function render(){
   review.replaceChildren();const d=preview.documento;
   review.append(el('h3','Conferência da NF-e '+d.numero+' / '+d.serie),el('p',d.emitente+' · CNPJ '+d.cnpj),el('p','Chave: '+d.chave),el('p','Produtos: '+brl(d.totais.vProd)+' · IPI: '+brl(d.totais.vIPI)+' · Total da nota: '+brl(d.totais.vNF)),el('p','O XML informa protocolo de autorização. A situação atual na SEFAZ e a assinatura digital não são verificadas por esta tela.'));
   mostrarTributos(review,d.tributos);
   const date=field(review,'Data do recebimento',today(),'date');date.min=d.emissao.slice(0,10);date.max=today();
   rows=d.itens.map(item=>{
    const box=el('fieldset');box.append(el('legend','Linha '+item.linha+' · Código '+item.codigo),el('p',item.descricao),el('p',item.quantidade+' '+item.unidade+' · Mercadorias '+brl(item.valor)+' · Valor bruto com despesas e tributos '+brl(item.valor_bruto)));
    const label=el('label','Item do pedido'),select=el('select');select.setAttribute('aria-label','Item do pedido da linha '+item.linha);select.append(new Option('Selecionar item',''));
    for(const p of preview.itens_pedido||[])select.append(new Option('Linha '+p.linha+' · '+p.descricao+' · Saldo '+(Number(p.quantidade)-Number(p.recebida))+' '+p.unidade,p.id));
    label.append(select);box.append(label);const factor=field(box,'Unidades AXE por '+item.unidade+' da linha '+item.linha,'','number');factor.step='0.00000001';factor.min='0.00000001';
    const info=el('p');box.append(info);const cost=field(box,'Custo total de estoque da linha '+item.linha,item.valor_bruto,'number');cost.step='0.000001';
    const cadastroBox=el('section');let cadastroUI=null;
    const save=check(box,'Salvar unidade '+item.unidade+' e conversão na aba Fornecedor do produto (linha '+item.linha+')');save.checked=true;
    const suggest=()=>{const p=preview.itens_pedido.find(p=>p.id===select.value),v=p?.fornecedores?.find(v=>v.codigo_fornecedor===item.codigo&&String(v.unidade_compra||'').toUpperCase()===String(item.unidade).toUpperCase());factor.value=v?.fator_conversao??(p&&String(p.unidade_axe).toUpperCase()===item.unidade.toUpperCase()?1:'');update();};
    function update(){const p=preview.itens_pedido.find(p=>p.id===select.value);info.textContent=p?'Produto AXE: '+(p.produto_codigo||'#'+p.produto_id)+' · Unidade '+(p.unidade_axe||'pendente')+' · Entrada '+(Number(item.quantidade)*Number(factor.value||0))+' '+(p.unidade_axe||'')+' · Preço do pedido '+brl(p.valor_unitario):'Selecione o item do pedido.';pending=null;}
    function cadastroRender(){cadastroBox.replaceChildren();const c=preview.cadastros?.find(c=>c.linha===item.linha)?.opcoes.find(c=>c.pedido_item_id===select.value)?.cadastro;cadastroUI=c?criarConferenciaCadastro(cadastroBox,c,()=>pending=null):null;if(!c)cadastroBox.append(el('p','Selecione um item com produto AXE cadastrado para conferir os dados.'));}
    select.onchange=()=>{suggest();cadastroRender();};factor.oninput=update;cost.oninput=()=>pending=null;save.onchange=()=>pending=null;
    const suggested=sugerirVinculoNFe(item,preview.itens_pedido||[]);if(suggested){select.value=suggested.pedido_item_id;factor.value=suggested.fator;}update();box.append(cadastroBox);cadastroRender();review.append(box);
    return {item,select,factor,cost,save,cadastro:()=>{if(!cadastroUI)throw Error('Confira o cadastro de todas as linhas.');return cadastroUI.collect();}};
   });
   review.append(el('p','Informe o custo de estoque após conferir tributos recuperáveis e despesas. O valor bruto do XML é uma referência; nenhum crédito tributário é deduzido automaticamente. A unidade do fornecedor será cadastrada sem alterar a unidade AXE.'));
   const reason=field(review,'Justificativa da conversão ou diferença de preço/código/custo','','textarea');reason.maxLength=2000;
   const checked=check(review,'Conferi produtos, quantidades, conversões, custos e recebimento físico');
   for(const x of [date,reason,checked])x.oninput=()=>pending=null;
   if(d.duplicatas?.length){review.append(el('h4','Cobrança informada no XML'));for(const x of d.duplicatas)review.append(el('p',x.numero+' · '+x.vencimento+' · '+brl(x.valor)));}
   const financeiro=criarConferenciaFinanceira(review,preview.financeiro,d,date,()=>rows.reduce((sum,r)=>{const it=preview.itens_pedido.find(i=>i.id===r.select.value);return sum+Math.round(Number(it?.valor_unitario||0)*Number(r.item.quantidade)*Number(r.factor.value||0)*100)/100;},0),()=>pending=null);
   review.append(el('p','A confirmação consolida o financeiro conferido, registra a nota e atualiza estoque e recebimento na mesma operação.'));
   review.append(button('Confirmar entrada da nota e estoque',async()=>{
    if(!checked.checked)throw Error('Confirme a conferência do recebimento.');
    if(!date.value)throw Error('Informe a data do recebimento.');
    const vinculos=rows.map(({item,select,factor,cost,save,cadastro})=>{if(!select.value||!factor.value||Number(factor.value)<=0||cost.value===''||Number(cost.value)<0)throw Error('Complete item, fator e custo de todas as linhas.');return {linha:item.linha,pedido_item_id:select.value,fator:factor.value,custo_total:cost.value,salvar_fornecedor:save.checked,cadastro:cadastro()};});
    pending??={acao:'compra_nf_confirmar',pedido_id:pedido.id,pedido_versao:preview.pedido_versao,xml,nome,data_entrada:date.value,justificativa:reason.value.trim(),vinculos,requisicao_id:crypto.randomUUID(),confirmado:true,custos_conferidos:true,financeiro:financeiro.collect()};
    const result=await api(pending);dirty=false;reset();await onSaved(pedido.id);return result;
   }));
  }
 }
 return {show,reset,canLeave:()=>!busy&&(!dialog||!dirty||confirm('Descartar a conferência de NF-e não confirmada?'))};
}
