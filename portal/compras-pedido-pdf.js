const idiomas = {
  pt: ['pt-BR','Português','Pedido de compra','Fornecedor','Entrega','Condições comerciais','Pagamento','Frete / Incoterm','Observações ao fornecedor','Itens do pedido','Linha|Código AXE|Ref. fornecedor|Descrição|Un.|Qtde.|Preço unitário|Subtotal','Tributos informados no pedido','Linha|Tributo|Base de cálculo|Alíquota|Valor|Natureza','Subtotal dos itens','Total do documento','Moeda','Confirme o recebimento deste pedido e a previsão de entrega.','Tributos sem discriminação no pedido.','Previsto|Documentado|Recolhido','Endereço de entrega','Previsão de entrega','Pedido cancelado','Pedido em elaboração'],
  en: ['en-US','English','Purchase order','Supplier','Delivery','Commercial terms','Payment','Freight / Incoterm','Notes to supplier','Order items','Line|AXE code|Supplier ref.|Description|Unit|Qty.|Unit price|Subtotal','Taxes stated on the order','Line|Tax|Tax base|Rate|Amount|Status','Items subtotal','Document total','Currency','Please confirm receipt of this purchase order and the expected delivery date.','No tax breakdown has been recorded for this order.','Estimated|Documented|Paid','Delivery address','Expected delivery','Cancelled order','Draft order'],
  es: ['es-ES','Español','Orden de compra','Proveedor','Entrega','Condiciones comerciales','Pago','Flete / Incoterm','Observaciones al proveedor','Artículos del pedido','Línea|Código AXE|Ref. proveedor|Descripción|Ud.|Cant.|Precio unitario|Subtotal','Impuestos indicados en el pedido','Línea|Impuesto|Base imponible|Tasa|Importe|Estado','Subtotal de artículos','Total del documento','Moneda','Confirme la recepción de esta orden y la fecha prevista de entrega.','El pedido no contiene un desglose de impuestos.','Estimado|Documentado|Pagado','Dirección de entrega','Entrega prevista','Orden cancelada','Borrador'],
  de: ['de-DE','Deutsch','Bestellung','Lieferant','Lieferung','Geschäftsbedingungen','Zahlung','Fracht / Incoterm','Hinweise an den Lieferanten','Bestellpositionen','Pos.|AXE-Code|Lieferantenreferenz|Beschreibung|Einheit|Menge|Einzelpreis|Zwischensumme','In der Bestellung ausgewiesene Steuern','Pos.|Steuer|Bemessungsgrundlage|Satz|Betrag|Status','Zwischensumme der Positionen','Dokumentgesamtbetrag','Währung','Bitte bestätigen Sie den Erhalt dieser Bestellung und den voraussichtlichen Liefertermin.','Für diese Bestellung sind keine Steuern einzeln ausgewiesen.','Geschätzt|Dokumentiert|Bezahlt','Lieferadresse','Voraussichtliche Lieferung','Stornierte Bestellung','Entwurf'],
  fr: ['fr-FR','Français','Bon de commande','Fournisseur','Livraison','Conditions commerciales','Paiement','Transport / Incoterm','Notes au fournisseur','Articles commandés','Ligne|Code AXE|Réf. fournisseur|Description|Unité|Qté|Prix unitaire|Sous-total','Taxes indiquées sur la commande','Ligne|Taxe|Base imposable|Taux|Montant|État','Sous-total des articles','Total du document','Devise','Veuillez confirmer la réception de cette commande et la date de livraison prévue.','Aucun détail des taxes n’est indiqué sur la commande.','Estimé|Documenté|Payé','Adresse de livraison','Livraison prévue','Commande annulée','Brouillon'],
  it: ['it-IT','Italiano','Ordine di acquisto','Fornitore','Consegna','Condizioni commerciali','Pagamento','Trasporto / Incoterm','Note al fornitore','Articoli ordinati','Riga|Codice AXE|Rif. fornitore|Descrizione|Unità|Qtà|Prezzo unitario|Subtotale','Imposte indicate nell’ordine','Riga|Imposta|Base imponibile|Aliquota|Importo|Stato','Subtotale articoli','Totale del documento','Valuta','Si prega di confermare la ricezione di questo ordine e la data di consegna prevista.','Il dettaglio delle imposte non è indicato nell’ordine.','Stimato|Documentato|Pagato','Indirizzo di consegna','Consegna prevista','Ordine annullato','Bozza']
};
const paises = {
  pt:'BR PT AO MZ CV GW ST TL', es:'ES AR BO CL CO CR CU DO EC GT HN MX NI PA PE PY SV UY VE',
  de:'DE AT LI', fr:'FR MC SN CI', it:'IT SM'
};
const enderecoAxe='Rua Esper Jorge Chueri · Cajuru · Curitiba – PR · 82930-220 · Brasil';

export function idiomaDoPedido(pais) {
  const codigo=String(pais||'').trim().toUpperCase();
  return Object.keys(paises).find(i=>paises[i].split(' ').includes(codigo))||'en';
}

function el(tag,text) {
  const n=document.createElement(tag);
  if(text!=null)n.textContent=text;
  return n;
}
function tabela(titulos,linhas) {
  const t=el('table'),h=t.createTHead().insertRow(),b=t.createTBody();
  for(const titulo of titulos.split('|')){const c=el('th',titulo);c.scope='col';h.append(c);}
  for(const linha of linhas){const r=b.insertRow();for(const valor of linha)r.append(el('td',valor??'—'));}
  return t;
}
function secao(pai,titulo,...filhos) {
  const s=el('section');
  s.append(el('h2',titulo),...filhos);
  pai.append(s);
}
function item(label,value) {
  const p=el('p');
  p.append(el('strong',label+' '),document.createTextNode(value||'—'));
  return p;
}
function lerPadrao(chave,padrao) {
  try{return localStorage.getItem(chave)??padrao;}catch{return padrao;}
}

function montar(dados,idioma,termos) {
  const [locale,,titulo,fornecedor,entrega,comercial,pagamento,frete,notas,itens,cols,impostos,colsTax,
    subtotal,total,moeda,,semTributos,naturezas,endereco,previsao,cancelado,rascunho]=idiomas[idioma];
  const p=dados.pedido,f=dados.fornecedor||{},t=dados.tributos;
  const formato=new Intl.NumberFormat(locale,{style:'currency',currency:p.moeda,currencyDisplay:'code'});
  const preco=new Intl.NumberFormat(locale,{style:'currency',currency:p.moeda,currencyDisplay:'code',maximumFractionDigits:8});
  const num=new Intl.NumberFormat(locale,{maximumFractionDigits:6});
  const date=new Intl.DateTimeFormat(locale,{dateStyle:'medium',timeZone:'UTC'});
  const country=new Intl.DisplayNames([locale],{type:'region'});
  const dia=x=>x?date.format(new Date(x.slice(0,10)+'T00:00:00Z')):'—';
  const dinheiro=x=>x==null||x===''?'—':formato.format(Number(x));
  const doc=el('article');doc.className='po-documento';doc.lang=locale;
  const head=el('header'),empresa=el('div'),ref=el('div'),logo=el('img');
  logo.src='./axe-logo-pedido.jpg';logo.alt='AXE Engenharia e Sistemas';
  empresa.append(logo,el('strong','AXE ENGENHARIA E SISTEMAS LTDA'),el('p','CNPJ 39.893.713/0001-67 · IE 9087109248'),el('p',enderecoAxe),el('p','marcio@axeengenharia.com.br'));
  ref.append(el('h1',titulo),el('strong',p.referencia),el('p',dia(p.data_pedido)),item(moeda,p.moeda));
  if(p.status==='Cancelado'||p.status==='Elaboração')ref.append(el('p',p.status==='Cancelado'?cancelado:rascunho));
  head.append(empresa,ref);doc.append(head);
  const caixas=el('div');caixas.className='po-duas-colunas';doc.append(caixas);
  const pais=String(f.pais||'').trim().toUpperCase();
  secao(caixas,fornecedor,el('strong',f.nome||p.fornecedor),el('p',[f.documento,f.inscricao&&'IE '+f.inscricao].filter(Boolean).join(' · ')),
    el('p',f.endereco),el('p',/^[A-Z]{2}$/.test(pais)?country.of(pais):pais),el('p',[f.contato,f.email,f.telefone].filter(Boolean).join(' · ')));
  secao(caixas,entrega,item(endereco,termos.entrega),item(previsao,dia(p.previsao_entrega)));
  const linhas=p.itens||[];
  const centavos=linhas.map(x=>Math.round(Number(x.subtotal??Number(x.quantidade)*Number(x.valor_unitario))*100));
  secao(doc,itens,tabela(cols,linhas.map((x,i)=>[x.linha,x.codigo_axe,x.codigo_fornecedor,x.descricao,x.unidade,
    num.format(x.quantidade),preco.format(x.valor_unitario),dinheiro(centavos[i]/100)])));
  const totais=el('div');totais.className='po-totais';
  totais.append(item(subtotal,dinheiro(centavos.reduce((a,b)=>a+b,0)/100)));
  if(t.total_documento!=null)totais.append(item(total,dinheiro(t.total_documento)));
  doc.append(totais);
  const situacoes=Object.fromEntries(['Previsto','Documentado','Recolhido'].map((x,i)=>[x,naturezas.split('|')[i]]));
  const fiscais=t.linhas||[];
  secao(doc,impostos,fiscais.length?tabela(colsTax,fiscais.map(x=>[x.item||'—',x.imposto,dinheiro(x.base),
    x.aliquota==null||x.aliquota===''?'—':num.format(x.aliquota)+'%',dinheiro(x.valor),situacoes[x.natureza]||'—'])):el('p',semTributos));
  secao(doc,comercial,item(pagamento,termos.pagamento),item(frete,termos.frete));
  if(termos.notas.trim())secao(doc,notas,el('p',termos.notas));
  return doc;
}

export async function abrirPedidoPdf(api,id) {
  const dados=await api({acao:'v2_pedido_pdf',pedido_id:id});
  const dialog=el('dialog');dialog.className='po-preview';
  const controls=el('div'),preview=el('div'),status=el('p');controls.className='po-controles';
  status.setAttribute('role','status');
  function campo(nome,tipo) {
    const l=el('label',nome),c=el(tipo);l.append(c);controls.append(l);return c;
  }
  function botao(nome,fn) {
    const b=el('button',nome);b.type='button';b.onclick=fn;controls.append(b);return b;
  }
  const idioma=campo('Idioma do documento','select');
  for(const [key,labels] of Object.entries(idiomas))idioma.append(new Option(labels[1],key));
  idioma.value=idiomaDoPedido(dados.fornecedor?.pais);
  const entrega=campo('Endereço de entrega','input'),pagamento=campo('Condição de pagamento para o fornecedor','textarea');
  const frete=campo('Frete / Incoterm','input'),notas=campo('Texto padrão e observações para o fornecedor','textarea');
  entrega.value=enderecoAxe;pagamento.value=dados.pedido.condicao_pagamento||'';
  const chave=()=> 'axe.po.texto-padrao.'+idioma.value;
  function padrao(){notas.value=lerPadrao(chave(),idiomas[idioma.value][16]);}
  function gerar(){return montar(dados,idioma.value,{entrega:entrega.value,pagamento:pagamento.value,frete:frete.value,notas:notas.value});}
  function atualizar(){preview.replaceChildren(gerar());}
  padrao();
  idioma.onchange=()=>{padrao();atualizar();};
  for(const c of [entrega,pagamento,frete,notas])c.oninput=atualizar;
  botao('Salvar texto padrão neste navegador',()=>{
    try{localStorage.setItem(chave(),notas.value);status.textContent='Texto padrão salvo para este idioma.';}
    catch{status.textContent='Não foi possível salvar o texto padrão neste navegador.';}
  });
  const exportar=botao('Exportar PDF',async()=>{
    exportar.disabled=true;
    const print=gerar();print.id='axe-pedido-print';document.body.append(print);
    const original=document.title;
    const limpar=()=>{
      print.remove();document.body.classList.remove('axe-pedido-imprimindo');
      document.title=original;exportar.disabled=false;
    };
    try{
      await print.querySelector('img').decode();
      document.body.classList.add('axe-pedido-imprimindo');
      document.title=dados.pedido.referencia;
      window.print();
    }catch{status.textContent='Não foi possível imprimir o pedido. Confira o carregamento do logotipo.';}
    finally{limpar();}
  });
  botao('Fechar',()=>dialog.close());
  dialog.append(el('h2','Prévia do pedido de compra'),controls,status,el('p','Na janela de impressão, selecione Salvar como PDF.'),preview);
  dialog.addEventListener('close',()=>dialog.remove(),{once:true});
  document.body.append(dialog);atualizar();dialog.showModal();
}
