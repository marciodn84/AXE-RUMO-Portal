import {camposPlanilha as definitions} from './planilha-cadastros.js?v=20261029-excel23';
import {lerArquivo} from './importar-arquivo.js?v=20261023-gestao1';
const n=(tag,text,cls)=>{const x=document.createElement(tag);if(text!==undefined)x.textContent=text;if(cls)x.className=cls;return x;};
const norm=s=>String(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]/g,'');
const names=Object.fromEntries(Object.values(definitions).flat().map(([k,l])=>[k,l]));
const states={RECEBIDO:'Recebido',NOVO:'Novo cadastro',SEM_ALTERACAO:'Sem alteração',DIVERGENTE:'Diferenças para revisar',INVALIDO:'Dados inválidos',AMBIGUO:'Correspondência ambígua',APLICADO:'Aplicado',IGNORADO:'Ignorado'};
export function initImportacao(api){
 const root=n('section',undefined,'cadastro-screen');root.hidden=true;document.getElementById('cadastrosRoot').append(root);
 root.append(n('h2','Importação e conciliação de cadastros'),n('p','Envie uma exportação XLSX ou CSV, confira o mapeamento e analise a prévia. Códigos AXE, impostos, estoques e movimentos financeiros não são substituídos automaticamente.','intro'));
 let epoch=0,seq=0,lote=null,lotePage=0,itemPage=0,sheets=[],buffer=null,filename='',mapping={},currentRows=[];
 const message=n('p','','status');message.setAttribute('role','status');
 const button=(text,fn)=>{const b=n('button',text);b.type='button';b.onclick=async()=>{b.disabled=true;try{await fn();}catch(e){message.textContent=e.message;message.className='status error';}finally{b.disabled=false;}};return b;};
 const form=n('form',undefined,'import-form'),file=n('input');file.type='file';file.accept='.xlsx,.csv';file.setAttribute('aria-label','Arquivo de cadastros');
 const type=n('select');type.setAttribute('aria-label','Tipo de cadastro');for(const [v,t] of [['produto','Produtos'],['cliente','Clientes'],['fornecedor','Fornecedores']])type.append(new Option(t,v));
 const origin=n('select');origin.setAttribute('aria-label','Origem do arquivo');origin.append(new Option('Nomus da AXE','NOMUS_AXE'),new Option('ERP anterior','ERP_ANTERIOR'));
 const sheet=n('select');sheet.setAttribute('aria-label','Aba da planilha');const header=n('input');header.type='number';header.min=1;header.max=20;header.value=1;header.setAttribute('aria-label','Linha dos cabeçalhos');
 const mapBox=n('div',undefined,'import-mapping'),sample=n('div',undefined,'scroll'),send=button('Enviar e gerar prévia',upload);send.disabled=true;
 const field=(title,input)=>{const l=n('label',title);l.append(input);return l;};
 form.append(field('Tipo de cadastro',type),field('Origem',origin),field('Arquivo XLSX ou CSV',file),field('Aba',sheet),field('Linha dos cabeçalhos',header),mapBox,sample,n('p','Custo e saldo serão guardados apenas como referência do arquivo. Não haverá lançamento de estoque, custo operacional ou financeiro.','intro'),send);form.onsubmit=e=>e.preventDefault();root.append(form,message);
 const history=n('section');history.append(n('h3','Arquivos recebidos'));const historyList=n('div');history.append(historyList);const prevLots=button('Lotes anteriores',()=>{lotePage--;return loadLots();}),nextLots=button('Mais lotes',()=>{lotePage++;return loadLots();});history.append(prevLots,nextLots);root.append(history);
 const preview=n('section');preview.hidden=true;const title=n('h3'),summary=n('p'),filter=n('select');filter.setAttribute('aria-label','Filtrar resultado da importação');filter.append(new Option('Todas as situações',''));for(const [k,t] of Object.entries(states))filter.append(new Option(t,k));
 const reload=button('Reanalisar lote',async()=>{await mutation('analisar',{lote_id:lote});itemPage=0;await loadPreview();});
 const back=button('Página anterior',()=>{itemPage--;return loadPreview();}),next=button('Próxima página',()=>{itemPage++;return loadPreview();}),position=n('span');
 const bindAll=button('Registrar todas as correspondências sem alteração',async()=>{
  if(!confirm('Registrar os vínculos dos itens sem diferenças, sem alterar seus cadastros?'))return;const gen=epoch,current=lote;let result;
  do{result=await mutation('vincular',{lote_id:current,confirmacao:'VINCULAR'});if(gen!==epoch)return;message.textContent='Registrando correspondências… Restantes: '+result.restantes;}while(result.restantes>0&&result.vinculados>0);
  message.className='status';message.textContent='Correspondências registradas sem alterar os cadastros.';await loadPreview();
 });
 const createAll=button('Criar todos os novos cadastros',async()=>{if(!confirm('Criar os registros classificados como novos nesta prévia? Registros com diferenças, erros ou correspondências ambíguas continuarão pendentes.'))return;const gen=epoch,current=lote;let r,total=0;do{r=await mutation('aplicar',{lote_id:current,novos_em_lote:true,confirmacao:'APLICAR_NOVOS'});if(gen!==epoch)return;total+=r.aplicados;message.textContent=total+' cadastros criados. Restantes: '+r.restantes;}while(r.restantes>0&&r.aplicados>0);await loadPreview();message.textContent=total+' novos cadastros criados. Diferenças e erros permanecem para revisão.';});
 const items=n('div',undefined,'import-items');preview.append(title,summary,filter,reload,bindAll,createAll,items,back,position,next);root.append(preview);
 const mutation=async(operacao,dados)=>{const r=await api({acao:'mutacao',operacao,dados});return r.resultado||r;};
 const visible=gen=>gen===epoch&&!root.hidden;
 file.onchange=async()=>{const gen=epoch;send.disabled=true;try{const f=file.files[0];if(!f)return;filename=f.name;buffer=await f.arrayBuffer();sheets=await lerArquivo(buffer,filename);if(gen!==epoch)return;sheet.replaceChildren();sheets.forEach((s,i)=>sheet.append(new Option(s.nome,i)));header.value=1;buildMap();message.textContent='Arquivo lido localmente. Confira as colunas antes de enviar.';}catch(e){message.textContent=e.message;message.className='status error';}};
 type.onchange=sheet.onchange=header.onchange=buildMap;
 function buildMap(){mapBox.replaceChildren();sample.replaceChildren();mapping={};send.disabled=!sheets.length;if(!sheets.length)return;
  const rows=sheets[Number(sheet.value)].rows,head=rows.find(r=>r.numero===Number(header.value));if(!head){send.disabled=true;message.textContent='Linha de cabeçalhos não encontrada.';return;}
  for(const [key,label,...aliases] of definitions[type.value]){const select=n('select');select.dataset.field=key;select.setAttribute('aria-label','Coluna: '+label);select.append(new Option('Não importar',''));head.cells.forEach((value,i)=>select.append(new Option(String(value||'Coluna '+(i+1)),i)));
   const accepted=[label,...aliases,key].map(norm),index=head.cells.findIndex(v=>accepted.includes(norm(v)));if(index>=0)select.value=String(index);select.onchange=()=>mapping[key]=select.value;mapping[key]=select.value;mapBox.append(field(label,select));
  }
  const table=n('table'),tr=n('tr');head.cells.forEach(v=>tr.append(n('th',v)));table.append(tr);for(const row of rows.filter(r=>r.numero>head.numero).slice(0,3)){const tr=n('tr');head.cells.forEach((_,i)=>tr.append(n('td',row.cells[i]??'')));table.append(tr);}sample.append(n('h4','Amostra do arquivo'),table);
 }
 async function upload(){const gen=epoch;message.className='status';if(!buffer)throw Error('Escolha um arquivo.');const required=type.value==='produto'?['codigo_anterior','descricao_referencia']:type.value==='cliente'?['nome','cnpj']:['razao_social'];for(const key of required)if(mapping[key]===''&&!(key==='codigo_anterior'&&mapping.codigo_axe!==''))throw Error('Mapeie a coluna '+names[key]+'.');
  const selected=sheets[Number(sheet.value)],head=selected.rows.find(r=>r.numero===Number(header.value)),rows=[];
  for(const row of selected.rows.filter(r=>r.numero>head.numero)){
   if(!row.cells.some(v=>String(v??'').trim()))continue;const original={};head.cells.forEach((label,i)=>original[String(i+1)+': '+String(label||'Coluna')]=row.cells[i]??'');const dados={};
   for(const [key,index] of Object.entries(mapping))if(index!==''){if(row.formulas.includes(Number(index)))throw Error('Há uma fórmula na linha '+row.numero+'. Exporte valores antes de importar.');dados[key]=row.cells[Number(index)]??'';}
   rows.push({linha:row.numero,original,dados});
  }if(!rows.length||rows.length>5000)throw Error('Use um arquivo com 1 a 5.000 linhas.');
  const hash=[...new Uint8Array(await crypto.subtle.digest('SHA-256',buffer))].map(x=>x.toString(16).padStart(2,'0')).join('');
  const result=await mutation('criar',{origem:origin.value,tipo:type.value,arquivo:filename,hash_arquivo:hash,mapeamento:{aba:selected.nome,cabecalho:Number(header.value),campos:mapping},quantidade:rows.length});if(gen!==epoch)return;lote=result.lote_id;
  let chunk=[];for(let i=0;i<rows.length;i++){
   const candidate=[...chunk,rows[i]];if(new TextEncoder().encode(JSON.stringify({lote_id:lote,linhas:candidate})).length>40000&&chunk.length){await mutation('receber',{lote_id:lote,linhas:chunk});chunk=[];if(gen!==epoch)return;}
   chunk.push(rows[i]);if(chunk.length===25){message.textContent='Enviando '+(i+1)+' de '+rows.length+' linhas…';await mutation('receber',{lote_id:lote,linhas:chunk});chunk=[];if(gen!==epoch)return;}
  }if(chunk.length)await mutation('receber',{lote_id:lote,linhas:chunk});if(gen!==epoch)return;message.textContent='Analisando correspondências e diferenças…';await mutation('analisar',{lote_id:lote});if(gen!==epoch)return;itemPage=0;filter.value='';await loadLots();await loadPreview();message.textContent='Prévia pronta. Nenhum cadastro foi alterado.';
 }
 async function loadLots(){const gen=epoch;const d=await api({acao:'lotes',pagina:lotePage});if(!visible(gen))return;historyList.replaceChildren();for(const r of d.linhas){historyList.append(button(r.arquivo+' · '+r.quantidade+' linhas · '+new Date(r.criado_em).toLocaleDateString('pt-BR',{timeZone:'America/Sao_Paulo'}),async()=>{lote=r.id;itemPage=0;filter.value='';await loadPreview();}));}if(!d.total)historyList.append(n('p','Nenhum arquivo recebido.'));prevLots.disabled=lotePage===0;nextLots.disabled=(lotePage+1)*50>=d.total;}
 filter.onchange=()=>{itemPage=0;loadPreview().catch(e=>{message.textContent=e.message;message.className='status error';});};
 async function loadPreview(){const gen=epoch,request=++seq;if(!lote)return;const current=lote;const [detail,data,totals]=await Promise.all([api({acao:'lote',lote_id:current}),api({acao:'itens',lote_id:current,pagina:itemPage,estado:filter.value}),api({acao:'resumo',lote_id:current})]);if(!visible(gen)||request!==seq||lote!==current)return;
  const batch=detail.linhas[0];preview.hidden=false;title.textContent=batch.arquivo+' — prévia';summary.textContent=totals.linhas.map(x=>(states[x.estado]||x.estado)+': '+x.total).join(' · ');bindAll.hidden=!totals.linhas.some(x=>x.estado==='SEM_ALTERACAO'&&x.total>0);createAll.hidden=!totals.linhas.some(x=>x.estado==='NOVO'&&x.total>0);currentRows=data.linhas;items.replaceChildren();
  for(const row of currentRows){const card=n('article',undefined,'source-card');card.append(n('h4','Linha '+row.linha+' · '+(row.dados.descricao_referencia||row.dados.nome||row.dados.razao_social||row.chave_externa)),n('p',states[row.estado]||row.estado,'badge'),n('p',row.chave_externa+(row.alvo_id?' · Cadastro AXE #'+row.alvo_id:'')));if(row.erro)card.append(n('p',row.erro,'error'));
   const selected=[];
   if(row.estado==='DIVERGENTE'){
    const table=n('table'),head=n('tr');['Atualizar','Campo','Valor AXE','Valor do arquivo'].forEach(v=>head.append(n('th',v)));table.append(head);
    for(const [key,values] of Object.entries(row.diferencas)){const tr=n('tr'),td=n('td'),check=n('input');check.type='checkbox';check.setAttribute('aria-label','Atualizar '+(names[key]||key)+' da linha '+row.linha);selected.push({key,check});td.append(check);tr.append(td,n('td',names[key]||key),n('td',values.atual===null?'Não informado':String(values.atual)),n('td',String(values.arquivo)));table.append(tr);}const wrap=n('div',undefined,'scroll');wrap.append(table);card.append(wrap);
   }
   const evidence=n('details');evidence.append(n('summary','Ver os dados recebidos'),n('pre',JSON.stringify(row.dados_originais,null,2)));card.append(evidence);
   if(['NOVO','DIVERGENTE','SEM_ALTERACAO'].includes(row.estado))card.append(button(row.estado==='NOVO'?'Criar cadastro':row.estado==='SEM_ALTERACAO'?'Registrar vínculo sem alterar cadastro':'Aplicar campos selecionados',async()=>{
    const campos=selected.filter(x=>x.check.checked).map(x=>x.key);if(row.estado==='DIVERGENTE'&&!campos.length)throw Error('Selecione os campos da linha '+row.linha+'.');
    const question=row.estado==='NOVO'?'Criar este cadastro com os dados recebidos?':row.estado==='SEM_ALTERACAO'?'Registrar a correspondência com o ERP, sem alterar os dados do cadastro?':'Atualizar somente estes campos: '+campos.map(k=>names[k]||k).join(', ')+'?';if(!confirm(question))return;
    await mutation('aplicar',{lote_id:current,item_id:row.id,campos,confirmacao:'APLICAR'});await loadPreview();message.className='status';message.textContent='Decisão registrada. Nenhuma movimentação de estoque ou financeira foi criada.';
   }));
   if(!['APLICADO','IGNORADO'].includes(row.estado))card.append(button('Ignorar esta linha',async()=>{await mutation('ignorar',{lote_id:current,item_id:row.id});await loadPreview();}));
   if(row.estado==='APLICADO')card.append(n('p','Campos aplicados: '+(row.campos_aplicados?.map(k=>names[k]||k).join(', ')||'somente vínculo externo')));items.append(card);
  }position.textContent=data.total?' '+(itemPage*50+1)+'–'+(itemPage*50+data.linhas.length)+' de '+data.total+' ':' Nenhuma linha nesta situação ';back.disabled=itemPage===0;next.disabled=(itemPage+1)*50>=data.total;preview.scrollIntoView({block:'start',behavior:'smooth'});
 }
 return {async show(value,contexto={}){epoch++;root.hidden=!value;if(!value)return;if(definitions[contexto?.tipo]){type.value=contexto.tipo;file.value='';buffer=null;sheets=[];mapBox.replaceChildren();sample.replaceChildren();preview.hidden=true;lote=null;send.disabled=true;message.textContent='Selecione a planilha de '+(contexto.tipo==='cliente'?'Clientes':contexto.tipo==='produto'?'Produtos':'Fornecedores')+'.';}try{await loadLots();}catch(e){message.textContent=e.message;}},reset(){epoch++;seq++;root.hidden=true;file.value='';buffer=null;sheets=[];mapBox.replaceChildren();sample.replaceChildren();historyList.replaceChildren();items.replaceChildren();preview.hidden=true;lote=null;send.disabled=true;}};
}

