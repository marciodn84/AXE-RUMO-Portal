const paths={
 bloquear:['M6 10h12v11H6Z','M8 10V6a4 4 0 0 1 8 0v4'],
 desbloquear:['M6 10h12v11H6Z','M8 10V6a4 4 0 0 1 7.5-2'],
 historico:['M3 3v5h5','M3 8a9 9 0 1 1 0 8','M12 7v5l3 2'],
 editar:['M12 20h9','M16.5 3.5a2.1 2.1 0 0 1 3 3L9 17l-4 1 1-4Z'],
 visualizar:['M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z','M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z'],
 vincular:['M10 13a5 5 0 0 0 7 .5l3-3a5 5 0 0 0-7-7l-2 2','M14 11a5 5 0 0 0-7-.5l-3 3a5 5 0 0 0 7 7l2-2'],
 conferir:['M9 12l2 2 4-4','M12 3l8 4v5c0 5-8 9-8 9s-8-4-8-9V7Z'],
 versao:['M9 9h11v12H9Z','M5 15H3V3h11v2'],
 ativar:['M5 12l4 4L19 6'],
 inativar:['M8 5v14','M16 5v14'],
 voltar:['M19 12H5','M12 5l-7 7 7 7'],
 mais:['M5 12h.01','M12 12h.01','M19 12h.01'],
 exportar:['M12 3v12','M7 10l5 5 5-5','M4 17v4h16v-4'],
 importar:['M12 16V4','M7 9l5-5 5 5','M4 17v4h16v-4'],
 transporte:['M2 5h12v12H2Z','M14 9h4l4 4v4h-8','M7 19a2 2 0 1 0 0-4 2 2 0 0 0 0 4','M18 19a2 2 0 1 0 0-4 2 2 0 0 0 0 4'],
 tributos:['M19 5L5 19','M8 5a3 3 0 1 0 0 6 3 3 0 0 0 0-6','M16 13a3 3 0 1 0 0 6 3 3 0 0 0 0-6'],
 aceite:['M6 3h9l4 4v14H6Z','M15 3v5h4','M8 14l2 2 5-5'],
 servico:['M14 3l7 7-4 4-7-7Z','M13 11l-8 8-2-2 8-8'],
 entrada:['M5 3h14v18H5Z','M12 7v10','M7 12h10'],
 saida:['M5 3h14v18H5Z','M7 12h10'],
 documento:['M14 2H5v20h14V7Z','M14 2v5h5','M8 12h8M8 16h8'],
 anexo:['M21 11l-9 9a6 6 0 0 1-8-8L15 1a4 4 0 0 1 6 6L10 18a2 2 0 0 1-3-3L17 5'],
 expandir:['M6 9l6 6 6-6'],
 recolher:['M9 6l6 6-6 6'],
 custo:['M5 2h14v20H5ZM8 6h8M8 11h1M15 11h1M8 15h1M15 15h1M8 19h1M15 19h1'],
 pagamento:['M3 5h18v14H3Z','M3 10h18','M6 15h4'],
 criar:['M12 5v14','M5 12h14'],
 enviar:['M22 2L2 9l8 3 3 8Z','M10 12L22 2'],
 revisar:['M4 4h16v13H9l-5 4Z','M8 8h8M8 12h5'],
 recusar:['M4 4h16v13H9l-5 4Z','M9 8l6 5M15 8l-6 5'],
 cancelar:['M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20','M5 5l14 14'],
 converter:['M3 7h17l-4-4M21 17H4l4 4'],
 origem:['M13 5h6v6M19 5l-8 8','M10 5H5v14h14v-5'],
 mensagem:['M3 5h18v14H3Z','M3 6l9 7 9-7']
};
// Os ícones representam ações. Ações sem correspondência preservam seu rótulo.
const porTitulo={
 'Abrir':'visualizar','Abrir parcela':'visualizar','Abrir embarque':'visualizar','Consultar':'visualizar',
 'Visualizar pedido':'visualizar','Ver etapa':'visualizar','Endereços e cobrança':'visualizar',
 'Ver códigos':'visualizar','Produtos aceitos':'visualizar','Abrir tributação':'visualizar',
 'Simular aplicação':'conferir','Abrir processo de importação':'transporte','Abrir processo':'transporte',
 'Voltar à lista':'voltar','Voltar':'voltar','Consultar histórico':'historico',
 'Histórico de bloqueios':'historico','Histórico de estoque':'historico','Entrada de estoque':'entrada',
 'Saída de estoque':'saida','Exportar pedido em PDF':'exportar','Tributos':'tributos',
 'ACK do fornecedor':'aceite','Entrada de NFS-e · XML':'servico','Notas fiscais de entrada · XML':'importar',
 'Ativar':'ativar','Inativar':'inativar','Conferir regra':'conferir','Validar regra':'conferir','Nova versão':'versao'
};
export function iconeAcao(kind) {
  const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');
  for(const [key,value] of Object.entries({viewBox:'0 0 24 24',fill:'none',stroke:'currentColor',
    'stroke-width':kind==='mais'?'3.5':'1.8','stroke-linecap':'round','stroke-linejoin':'round','aria-hidden':'true',focusable:'false'}))svg.setAttribute(key,value);
  for(const d of paths[kind]||paths.documento){
    const p=document.createElementNS(svg.namespaceURI,'path');p.setAttribute('d',d);svg.append(p);
  }
  return svg;
}
export function aplicarIconeAcao(button,kind,title=button.textContent.trim()) {
  if(!paths[kind])return;
  button.setAttribute('aria-label',title);button.title=title;button.classList.add('action-icon');
  button.replaceChildren(iconeAcao(kind));
}
export function padronizarAcoes(container) {
  for(const button of container.querySelectorAll('td button,.purchase-order-actions button,.fiscal-screen .source-card button')){
    if(button.classList.contains('action-icon'))continue;
    const title=button.textContent.trim();
    const kind=button.dataset.acao||porTitulo[title]||
      (/^Bloquear (cliente|produto|fornecedor)$/.test(title)?'bloquear':
       /^Desbloquear (cliente|produto|fornecedor)$/.test(title)?'desbloquear':
       /^Editar\b/.test(title)?'editar':
       /^Criar nova versão/.test(title)?'versao':
       /^(Vincular|Selecionar|Sugerir ou cadastrar|Consultar \/ trocar produto)/.test(title)?'vincular':null);
    if(kind)aplicarIconeAcao(button,kind,title);
  }
}
