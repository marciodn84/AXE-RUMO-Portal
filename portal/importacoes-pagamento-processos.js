export function situacaoPagamentoParcela(p){if(p.status==='Cancelada')return 'Cancelada';if(Number(p.valor_pago)>=Number(p.valor))return 'Pagamento efetivado';if(Number(p.valor_pago)>0)return 'Pagamento parcial';return 'Aguardando pagamento';}
const el=(tag,text)=>{const n=document.createElement(tag);if(text!=null)n.textContent=text;return n;};
export function montarAplicacaoProcessos(form,processos,limite,moeda,pedidoPreferido){
 const box=el('fieldset'),legend=el('legend','Aplicar pagamento nos processos abertos'),summary=el('p'),rows=[];box.append(legend,el('p','Distribua o valor do comprovante. O saldo não aplicado permanece disponível.'));
 const table=el('table'),head=el('tr');for(const title of ['PO(s) / parcial','PO da aplicação','Parcela','Valor a aplicar'])head.append(el('th',title));table.append(head);
 for(const p of processos||[]){const tr=el('tr'),desc=el('td',p.pedidos.map(x=>x.referencia+' / '+String(x.parcial).padStart(2,'0')).join(', ')),poCell=el('td'),paCell=el('td'),valueCell=el('td'),po=el('select'),pa=el('select'),value=el('input');
  po.setAttribute('aria-label','PO da aplicação em '+desc.textContent);for(const x of p.pedidos)po.append(new Option(x.referencia,x.id));if(p.pedidos.some(x=>x.id===pedidoPreferido))po.value=pedidoPreferido;po.hidden=p.pedidos.length===1;
  pa.setAttribute('aria-label','Parcela da aplicação em '+desc.textContent);value.type='number';value.min='0';value.step='0.01';value.max=String(limite);value.value='0';value.setAttribute('aria-label','Valor a aplicar em '+desc.textContent);
  function parcelOptions(){pa.replaceChildren(new Option('Identificar automaticamente',''));const order=p.pedidos.find(x=>x.id===po.value),candidates=(order?.parcelas||[]).filter(x=>x.status!=='Cancelada'&&Number(x.valor_pago)<Number(x.valor));for(const x of candidates)pa.append(new Option(x.referencia+' · saldo '+(Number(x.valor)-Number(x.valor_pago)).toFixed(2),x.id));if(candidates.length===1)pa.value=candidates[0].id;pa.hidden=candidates.length<=1;}
  po.onchange=parcelOptions;parcelOptions();poCell.append(po);if(po.hidden)poCell.append(el('span',p.pedidos[0].referencia));paCell.append(pa);valueCell.append(value);tr.append(desc,poCell,paCell,valueCell);table.append(tr);rows.push({p,po,pa,value});
 }
 if(rows.length===1&&rows[0].p.pedidos.length===1){const order=rows[0].p.pedidos[0],unallocated=Math.max(0,Number(order.total||0)-Number(rows[0].p.aplicado||0));rows[0].value.value=String(Math.min(Number(limite),unallocated));}
 if(rows.length)box.append(table);else box.append(el('p','Nenhum processo aberto deste fornecedor e moeda. O pagamento pode permanecer vinculado ao pedido até o envio do PO.'));
 box.append(summary);form.append(box);
 function total(){return rows.reduce((s,x)=>s+Number(x.value.value||0),0);}
 function refresh(){const t=total();for(const row of rows)row.value.setCustomValidity(t>Number(limite)+0.000001?'Total aplicado maior que o comprovante.':'');summary.textContent='Comprovante: '+Number(limite).toFixed(2)+' '+moeda+' · Aplicado: '+t.toFixed(2)+' · Saldo disponível: '+(Number(limite)-t).toFixed(2);}
 box.addEventListener('input',refresh);refresh();
 return{total,collect(){refresh();if(total()>Number(limite)+0.000001)throw Error('A distribuição ultrapassa o comprovante.');return rows.filter(x=>Number(x.value.value)>0).map(x=>({processo_id:x.p.processo_id,pedido_id:x.po.value,parcela_id:x.pa.value||null,valor:x.value.value}));}};
}
