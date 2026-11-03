const el=(t,s,c)=>{const n=document.createElement(t);if(s!=null)n.textContent=s;if(c)n.className=c;return n;};
const qty=v=>v==null?'—':Number(v).toLocaleString('pt-BR',{maximumFractionDigits:6});
const money=v=>v==null?'—':Number(v).toLocaleString('pt-BR',{style:'currency',currency:'BRL',maximumFractionDigits:6});
const date=v=>v?new Date(v.length===10?v+'T12:00:00-03:00':v).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'}):'—';
export function initFichaProduto(api,edit){
 let root=null,host=null,id=null,epoch=0,active='axe',record=null,dirtyForms=new Set(),panes=new Map();
 const dirty=()=>[...dirtyForms].some(f=>f.isConnected);
 const canLeave=()=>!root||!dirty()||confirm('Há alterações ainda não salvas na ficha do produto. Sair sem salvar?');
 function reset(){epoch++;root?.remove();host?.classList.remove('product-editing');root=null;host=null;panes.clear();dirtyForms.clear();}
 const button=(s,fn)=>{const b=el('button',s);b.type='button';b.onclick=async()=>{b.disabled=true;try{await fn();}catch(e){if(root)root.querySelector('.product-status').textContent=e.message;}finally{if(b.isConnected)b.disabled=false;}};return b;};
 const table=(where,heads,rows)=>{const w=el('div',null,'scroll'),t=el('table'),th=el('thead'),h=el('tr');heads.forEach(s=>h.append(el('th',s)));th.append(h);t.append(th);const body=el('tbody');for(const cells of rows){const tr=el('tr');for(const c of cells){const td=el('td');td.append(c instanceof Node?c:document.createTextNode(String(c??'—')));tr.append(td);}body.append(tr);}t.append(body);w.append(t);where.append(w);};
 async function abrir(productId,options={}){
  if(!canLeave())return;reset();const gen=epoch;id=productId?Number(productId):null;
  host=document.getElementById('screen-produtos');if(!host||host.hidden)host=document.getElementById('cadastrosRoot');
  root=el('section',null,'product-sheet');root.setAttribute('aria-label','Ficha única do produto');host.classList.add('product-editing');host.prepend(root);
  const heading=el('h2','Ficha do produto'),status=el('p','Carregando…','product-status');status.setAttribute('role','status');
  root.append(button('Voltar à pesquisa',()=>{if(canLeave())reset();}),heading,status);
  root.addEventListener('input',e=>{const f=e.target.closest('form');if(f)dirtyForms.add(f);});root.addEventListener('change',e=>{const f=e.target.closest('form');if(f)dirtyForms.add(f);});
  try{
   if(id){const q=(await api({acao:'ficha_produto',id,aba:'codigos',pagina:0})).resultado;if(gen!==epoch)return;id=q.produto_id;record=await api({acao:'detalhe',tipo:'produto',id});if(gen!==epoch)return;}
   else record={};
   const updateTitle=()=>{heading.textContent=id?'Ficha do produto · '+(record.codigo_axe||record.codigo_anterior||'#'+id)+' · '+record.descricao_referencia:'Novo produto AXE';};updateTitle();status.textContent='';
   const nav=el('div',null,'product-tabs');nav.setAttribute('role','tablist');nav.setAttribute('aria-label','Seções do produto');root.append(nav);
   for(const [key,label]of [['axe','Dados AXE'],['clientes','Clientes'],['fornecedores','Fornecedores'],['estoque','Estoque'],['historico','Histórico']]){
    const p=el('section',null,'product-tab-panel'),b=button(label,()=>select(key));p.setAttribute('role','tabpanel');p.id='produto-painel-'+key;b.id='produto-aba-'+key;b.setAttribute('role','tab');b.setAttribute('aria-controls',p.id);p.setAttribute('aria-labelledby',b.id);b.disabled=key!=='axe'&&!id;
    b.onkeydown=e=>{if(!['ArrowRight','ArrowLeft','Home','End'].includes(e.key))return;e.preventDefault();const bs=[...nav.querySelectorAll('button')].filter(x=>!x.disabled),i=bs.indexOf(b),next=e.key==='Home'?0:e.key==='End'?bs.length-1:(i+(e.key==='ArrowRight'?1:bs.length-1))%bs.length;bs[next].click();bs[next].focus();};nav.append(b);root.append(p);panes.set(key,{panel:p,tab:b,loaded:false,page:0,seq:0});
   }
   async function select(key){active=key;for(const [k,v]of panes){v.panel.hidden=k!==key;v.tab.setAttribute('aria-selected',String(k===key));v.tab.tabIndex=k===key?0:-1;}const p=panes.get(key);if(!p.loaded){if(key==='axe')await axe();else await list(key);} }
   async function axe(){const p=panes.get('axe');p.loaded=true;p.panel.replaceChildren();const target=el('div');p.panel.append(target);
    await edit('produto',id,{}, {target,ficha:true,valido:()=>gen===epoch,onCancel:()=>{if(canLeave())reset();},onSaved:async saved=>{id=Number(saved.id);record=saved;updateTitle();for(const v of panes.values())v.tab.disabled=false;dirtyForms.delete(target.querySelector('form'));await axe();status.textContent='Dados AXE salvos.';}});
    if(gen!==epoch)return;
    if(id){const codes=el('details');codes.append(el('summary','Códigos e descrições de origem'));const body=el('div');codes.append(body);p.panel.append(codes);let pg=0;
     const more=button('Carregar códigos',async()=>{const r=(await api({acao:'ficha_produto',id,aba:'codigos',pagina:pg})).resultado;if(gen!==epoch||!codes.isConnected)return;table(body,['Origem','Empresa','Código','Descrição','Situação'],r.linhas.map(x=>[x.contexto,x.entidade,x.codigo_produto,x.descricao_produto,x.status_validacao]));pg++;more.hidden=pg*50>=r.total;more.textContent='Mais códigos';if(!r.total)body.append(el('p','Nenhum código adicional.'));});codes.append(more);
    }
   }
   async function relation(key,kind,row,defaults={}){
    const p=panes.get(key);if([...p.panel.querySelectorAll('form')].some(f=>dirtyForms.has(f))&&!confirm('Descartar as alterações deste cadastro?'))return;
    p.seq++;p.panel.replaceChildren();const target=el('div');p.panel.append(target);
    await edit(kind,row?.id,{...(kind==='referencia_cliente'?{}:{produto_id:id}),...defaults},{target,ficha:true,lockProduct:id,valido:()=>gen===epoch,onCancel:()=>{if([...p.panel.querySelectorAll('form')].some(f=>dirtyForms.has(f))&&!confirm('Descartar as alterações deste cadastro?'))return;return list(key);},onSaved:async saved=>{dirtyForms.delete(target.querySelector('form'));if(kind==='referencia_cliente'&&!row){await relation(key,'opcao_cliente',null,{referencia_cliente_id:saved.id,produto_id:id});status.textContent='Referência salva. Confira a unidade e salve o vínculo com este produto AXE.';}else{await list(key);status.textContent='Cadastro salvo na ficha do produto.';}}});
   }
   async function list(key){const p=panes.get(key),n=++p.seq;p.loaded=true;p.panel.replaceChildren(el('p','Carregando…'));
    try{const r=(await api({acao:'ficha_produto',id,aba:key,pagina:p.page})).resultado;if(gen!==epoch||n!==p.seq)return;p.panel.replaceChildren();const toolbar=el('div',null,'com-tools');p.panel.append(toolbar);
     toolbar.append(button('Atualizar',()=>{if([...p.panel.querySelectorAll('form')].some(f=>dirtyForms.has(f))&&!confirm('Descartar alterações não salvas?'))return;return list(key);}));
     if(key==='clientes'){
      toolbar.append(button('Adicionar cliente',()=>relation(key,'referencia_cliente',null)),button('Vincular referência existente',()=>relation(key,'opcao_cliente',null)));
      table(p.panel,['Cliente / CNPJ','Código do cliente','Nome / descrição','Unidade / conversão','Situação','Ações'],r.linhas.map(x=>{const details=el('div');details.append(el('strong',x.descricao_cliente));if(x.descricao_detalhada){const d=el('details');d.append(el('summary','Descrição detalhada'),el('p',x.descricao_detalhada));details.append(d);}const actions=el('div',null,'product-row-actions');actions.append(button('Editar referência',()=>relation(key,'referencia_cliente',x)),button('Editar vínculo',()=>relation(key,'opcao_cliente',x.opcao,{referencia_cliente_id:x.id,produto_id:id})));return[x.cliente_nome+' · '+x.cnpj,x.codigo_cliente,details,(x.unidade_cliente||'—')+' · '+(x.opcao?.fator_conversao??x.fator_conversao_axe??'—'),x.opcao?.situacao||(x.ativo?'Ativa':'Inativa'),actions];}));
     }else if(key==='fornecedores'){
      toolbar.append(button('Adicionar fornecedor',()=>relation(key,'produto_fornecedor',null)));
      table(p.panel,['Fornecedor','Código do fornecedor','Descrição','Unidade / conversão','Situação','Ações'],r.linhas.map(x=>[x.fornecedor_nome+' · '+(x.documento||''),x.codigo_fornecedor,x.descricao_fornecedor,(x.unidade_compra||'—')+' · '+(x.fator_conversao??'—'),x.situacao+(x.preferencial?' · Preferencial':''),button('Editar fornecedor do produto',()=>relation(key,'produto_fornecedor',x))]));
     }else if(key==='estoque'){
      const s=r.saldo||{},summary=el('div',null,'product-stock-summary');for(const [label,value]of [['Saldo',qty(s.quantidade)+' '+(s.unidade||'')],['Custo médio',money(s.custo_medio)],['Valor em estoque',money(s.valor_estoque)],['Última entrada / reposição',money(s.custo_reposicao)]]){const c=el('article',null,'source-card');c.append(el('span',label),el('strong',value));summary.append(c);}p.panel.append(summary);
      table(p.panel,['Data','Movimento','Quantidade','Custo unitário','Valor','Documento / referência','Cadastro original'],r.linhas.map(x=>[date(x.data_movimento),x.tipo+' · '+x.motivo+(x.estornado?' · Estornado':x.estorno_de?' · Estorno':''),qty(x.quantidade)+' '+x.unidade,money(x.custo_unitario),money(x.valor_total),x.referencia,x.cadastro_original?.codigo||x.cadastro_original?.id||id]));
     }else if(key==='historico'){
      table(p.panel,['Data','Origem','Alteração','Responsável','Detalhes'],r.linhas.map(x=>{const d=el('details');d.append(el('summary','Ver alterações'));const keys=new Set([...Object.keys(x.anterior||{}),...Object.keys(x.atual||{})]);let changes=0;for(const k of keys){if(['atualizado_em','criado_em'].includes(k)||JSON.stringify(x.anterior?.[k])===JSON.stringify(x.atual?.[k]))continue;changes++;d.append(el('p',k.replaceAll('_',' ')+': '+format(x.anterior?.[k])+' → '+format(x.atual?.[k])));}if(!changes)d.append(el('p','Evento registrado sem mudança de campos.'));return[date(x.criado_em),x.origem,x.acao,x.responsavel||'Integração / não informado',d];}));
     }
     if(!r.total)p.panel.append(el('p',key==='estoque'?'Nenhuma movimentação registrada.':key==='historico'?'Nenhum evento registrado.':'Nenhum vínculo cadastrado para este produto.'));
     const paging=el('div',null,'paging'),prev=button('Anterior',()=>{p.page--;return list(key);}),next=button('Próxima',()=>{p.page++;return list(key);});prev.disabled=p.page===0;next.disabled=(p.page+1)*50>=r.total;paging.append(prev,el('span',r.total+' registro(s) · Página '+(p.page+1)),next);p.panel.append(paging);
    }catch(e){if(gen===epoch&&n===p.seq)p.panel.replaceChildren(el('p',e.message,'error'),button('Tentar novamente',()=>list(key)));}
   }
   const format=v=>v==null?'—':typeof v==='object'?JSON.stringify(v):String(v);
   await select(options.aba&&panes.has(options.aba)&&id?options.aba:'axe');root?.scrollIntoView({block:'start'});
  }catch(e){if(gen===epoch)status.textContent=e.message;}
 }
 return{abrir,reset,canLeave,isOpen:()=>!!root};
}
