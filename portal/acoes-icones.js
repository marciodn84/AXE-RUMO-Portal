const paths={
 editar:['M12 20h9','M16.5 3.5a2.1 2.1 0 0 1 3 3L9 17l-4 1 1-4Z'],
 visualizar:['M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z','M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z'],
 vincular:['M10 13a5 5 0 0 0 7 .5l3-3a5 5 0 0 0-7-7l-2 2','M14 11a5 5 0 0 0-7-.5l-3 3a5 5 0 0 0 7 7l2-2'],
 conferir:['M9 12l2 2 4-4','M12 3l8 4v5c0 5-8 9-8 9s-8-4-8-9V7Z'],
 versao:['M9 9h11v12H9Z','M5 15H3V3h11v2'],
 ativar:['M5 12l4 4L19 6'],
 inativar:['M8 5v14','M16 5v14']
};
export function padronizarAcoes(container){
 for(const button of container.querySelectorAll('td button')){
  if(button.classList.contains('action-icon'))continue;
  const title=button.textContent.trim();
  const kind=/^Editar/.test(title)?'editar':/^(Endereços e cobrança|Ver códigos|Produtos aceitos)$/.test(title)?'visualizar':/^Vincular/.test(title)?'vincular':title==='Conferir regra'?'conferir':title==='Nova versão'?'versao':title==='Ativar'?'ativar':title==='Inativar'?'inativar':null;
  if(!kind)continue;
  const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');
  for(const [key,value]of Object.entries({viewBox:'0 0 24 24',fill:'none',stroke:'currentColor','stroke-width':'1.8','stroke-linecap':'round','stroke-linejoin':'round','aria-hidden':'true',focusable:'false'}))svg.setAttribute(key,value);
  for(const d of paths[kind]){const path=document.createElementNS(svg.namespaceURI,'path');path.setAttribute('d',d);svg.append(path);}
  button.setAttribute('aria-label',title);button.title=title;button.classList.add('action-icon');button.replaceChildren(svg);
 }
}
