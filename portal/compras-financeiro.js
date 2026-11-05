const el=(t,s)=>{const e=document.createElement(t);if(s!==undefined)e.textContent=s;return e;};
const cents=v=>Math.round(Number(v||0)*100),money=v=>Number(v||0).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
const meios=[['PIX','PIX'],['CARTAO','Cartão de crédito'],['BOLETO','Boleto'],['TRANSFERENCIA_BANCARIA','Transferência bancária']];
const addDays=(date,days)=>{if(!date)return '';const d=new Date(date+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+Number(days||0));return d.toISOString().slice(0,10);};
export function meioXML(documento){const hits=[...new Set((documento.pagamentos||[]).filter(p=>Number(p.valor)>0).map(p=>({'03':'CARTAO','04':'CARTAO','15':'BOLETO','17':'PIX','18':'TRANSFERENCIA_BANCARIA'})[p.codigo]).filter(Boolean))];return hits.length===1?hits[0]:'';}
export function sugerirFinanceiro(ctx,doc,entrada,expected,xml=false,id=()=>crypto.randomUUID()){
 const existing=(ctx.parcelas||[]).map(p=>({...p,valor:Number(p.valor),valor_nota:0,locked:Number(p.valor_pago)>0||Number(p.confirmado)>0}));
 const protectedRows=existing.filter(p=>p.locked),free=existing.filter(p=>!p.locked);let allocate=cents(doc.totais.vNF);const result=[];const suggested=meioXML(doc);
 const dups=xml?doc.duplicatas||[]:[];const dupTotal=dups.reduce((s,p)=>s+cents(p.valor),0);
 for(const row of protectedRows){const available=Math.max(0,cents(row.valor)-cents(row.confirmado));const used=Math.min(available,Math.max(0,allocate-(dups.length?dupTotal:0)));row.valor_nota=used/100;allocate-=used;result.push(row);}
 let slot=0;
 const make=(v,date,ref,nota)=>{const original=free[slot++];const row={...(original||{}),id:original?.id||id(),referencia:ref||original?.referencia||'NF-e '+doc.numero,valor:v,valor_nota:nota,vencimento:date||'',meio_pagamento:original?.meio_pagamento||ctx.meio_pagamento||suggested,locked:false};result.push(row);return row;};
 if(dups.length){for(const d of dups){make(Number(d.valor),d.vencimento,'NF-e '+doc.numero+' / '+d.numero,Number(d.valor));allocate-=cents(d.valor);}}
 else{
 for(const p of free){if(allocate<=0)break;const used=Math.min(cents(p.valor),allocate);const date=p.financeiro?.base==='Entrega'?addDays(entrada,p.financeiro?.dias):p.vencimento;make(used/100,date,p.referencia,used/100);allocate-=used;}
 if(allocate>0){make(allocate/100,ctx.forma==='NA_ENTREGA'?entrada:'','NF-e '+doc.numero,allocate/100);allocate=0;}
 }
 const provision=cents(expected)-result.reduce((s,p)=>s+cents(p.valor),0);
 if(provision>0){const date=free[slot]?.vencimento||ctx.previsao_entrega||'';make(provision/100,date,'Saldo do pedido a receber',0);}
 // Explicit zero rows cancel superseded provisions; paid and previously confirmed rows are retained.
 for(const p of free.slice(slot))result.push({...p,valor:0,valor_nota:0});
 return result;
}
export function criarConferenciaFinanceira(parent,ctx,doc,date,getNominal,onChange){
 const box=el('fieldset');box.className='compra-financeiro';box.append(el('legend','Financeiro da compra nacional'),el('p','Confira títulos, vencimentos e meio de pagamento. Vincule adiantamentos já registrados e mantenha somente a provisão do saldo ainda não recebido. O XML não comprova o pagamento bancário. Após ajustar produtos ou data de entrada, use uma das opções abaixo para recalcular a proposta antes de conferi-la.'));
 parent.append(box);if(!ctx?.token){box.append(el('p','Reabra o XML para consultar o financeiro atualizado.'));return{collect(){throw Error('Reabra o XML e confira o financeiro.');}};}
 const source=el('p');source.textContent='Pedido: '+({ANTECIPADO:'Pagamento antecipado',PARCELADO:'Pagamento parcelado',NA_ENTREGA:'Pagamento na entrega',A_PRAZO:'Pagamento a prazo'}[ctx.forma]||'Forma não informada')+' · '+(ctx.condicao||'Condição não informada');box.append(source);
 if(doc.pagamentos?.length)box.append(el('p','Pagamento informado no XML: '+doc.pagamentos.map(p=>(meios.find(m=>m[0]===({'03':'CARTAO','04':'CARTAO','15':'BOLETO','17':'PIX','18':'TRANSFERENCIA_BANCARIA'})[p.codigo])?.[1]||p.descricao||'Código '+p.codigo)+' · '+money(p.valor)).join('; ')));
 const expected=()=>Number(doc.totais.vNF)+Number(ctx.confirmado||0)+Math.max(0,Number(ctx.saldo_mercadorias||0)-getNominal());
 const controls=el('div'),scroll=el('div'),table=el('table'),head=el('thead'),tr=el('tr'),body=el('tbody'),status=el('p');scroll.className='scroll';
 for(const title of ['Parcela / título','Valor total','Valor desta NF-e','Vencimento','Meio de pagamento','Situação']){const th=el('th',title);th.scope='col';tr.append(th);}head.append(tr);table.append(head,body);scroll.append(table);box.append(controls,scroll,status);let lines=[];
 const button=(label,fn)=>{const b=el('button',label);b.type='button';b.onclick=fn;controls.append(b);return b;};
 const reasonLabel=el('label','Justificativa da consolidação financeira'),reason=el('textarea');reason.setAttribute('aria-label','Justificativa da consolidação financeira');reasonLabel.append(reason);box.append(reasonLabel);
 const checkLabel=el('label'),checked=el('input');checked.type='checkbox';checked.setAttribute('aria-label','Conferi parcelas, adiantamentos e resolvi as divergências financeiras');checkLabel.style.cssText='display:flex;flex-direction:row;align-items:center;gap:8px';checkLabel.append(checked,document.createTextNode(' Conferi parcelas, adiantamentos e resolvi as divergências financeiras'));box.append(checkLabel);
 function changed(){onChange();checked.checked=false;refresh();}
 function add(p={}){const row=el('tr'),inputs={};for(const [key,type,label]of [['referencia','text','Identificação do título'],['valor','number','Valor total do título'],['valor_nota','number','Valor vinculado a esta NF-e'],['vencimento','date','Vencimento do título'],['meio_pagamento','select','Meio de pagamento do título']]){const td=el('td'),i=el(type==='select'?'select':'input');if(type!=='select')i.type=type;else{ i.append(new Option('Selecionar',''));for(const [v,t]of meios)i.append(new Option(t,v));}i.setAttribute('aria-label',label);if(type==='number'){i.min='0';i.step='0.01';}i.value=p[key]??'';i.disabled=p.locked&&key!=='valor_nota';i.oninput=changed;td.append(i);row.append(td);inputs[key]=i;}const state=el('td',p.locked?'Pago: '+money(p.valor_pago)+' · Vinculado a notas anteriores: '+money(p.confirmado):p.id&&(ctx.parcelas||[]).some(x=>x.id===p.id)?'Parcela existente':'Novo título');row.append(state);body.append(row);lines.push({id:p.id||crypto.randomUUID(),inputs,p});}
 function build(xml){body.replaceChildren();lines=[];sugerirFinanceiro(ctx,doc,date.value,expected(),xml).forEach(add);changed();}
 button('Consolidar programação do pedido',()=>build(false));if(doc.duplicatas?.length)button('Usar duplicatas do XML',()=>build(true));button('Adicionar título ou provisão',()=>{add({valor:0,valor_nota:0});changed();});
 function values(){return lines.map(l=>({id:l.id,...Object.fromEntries(Object.entries(l.inputs).map(([k,i])=>[k,i.value]))}));}
 function refresh(){const rows=values(),total=rows.reduce((s,p)=>s+cents(p.valor),0),allocated=rows.reduce((s,p)=>s+cents(p.valor_nota),0);status.textContent='Total do financeiro: '+money(total/100)+' · Esperado (notas e saldo a receber): '+money(expected())+' · Vinculado a esta NF-e: '+money(allocated/100)+' de '+money(doc.totais.vNF)+'. Valores zero cancelam apenas provisões substituídas.';status.className=total===cents(expected())&&allocated===cents(doc.totais.vNF)?'status':'status error';}
 date.addEventListener('input',()=>{checked.checked=false;onChange();refresh();});reason.oninput=()=>{checked.checked=false;onChange();};checked.onchange=onChange;box.addEventListener('focusin',refresh);build(Boolean(doc.duplicatas?.length));
 return{refresh,collect(){refresh();const rows=values();if(!checked.checked||reason.value.trim().length<5)throw Error('Confira as parcelas e justifique a consolidação financeira.');if(rows.reduce((s,p)=>s+cents(p.valor),0)!==cents(expected())||rows.reduce((s,p)=>s+cents(p.valor_nota),0)!==cents(doc.totais.vNF))throw Error('Resolva os valores do financeiro e o vínculo integral desta NF-e antes de confirmar.');for(const p of rows){if(!Number.isFinite(Number(p.valor))||!Number.isFinite(Number(p.valor_nota))||Number(p.valor)<0||Number(p.valor_nota)<0||Number(p.valor_nota)>Number(p.valor))throw Error('Confira os valores dos títulos.');if(Number(p.valor)>0&&(!p.referencia.trim()||!p.vencimento||!p.meio_pagamento))throw Error('Informe identificação, vencimento e meio de pagamento de todos os títulos.');}return{token:ctx.token,parcelas:rows,conferido:true,justificativa:reason.value.trim()};}};
}
