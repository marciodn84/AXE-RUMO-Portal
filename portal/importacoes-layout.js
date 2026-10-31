import {organizarFormulario} from './importacoes-formulario.js?v=20261030-imp34';
import {padronizarAcoes} from './acoes-icones.js?v=20261030-imp35';
import {indicadorSituacao} from './cadastro-controle.js?v=20261030-padrao32';
const cores={
 'Rascunho':'pending','Emitido':'pending','ACK recebido':'released','Cancelado':'inactive','Cancelada':'inactive',
 'Planejamento':'pending','Aguardando consolidação':'pending','Aguardando coleta':'pending','Em trânsito':'pending','Em desembaraço':'pending','Recebido':'released',
 'Paga':'released','Paga parcialmente':'pending','Aguardando data-base':'pending','Vencida':'blocked','A pagar':'pending',
 'Concluída':'released','Pendente':'pending','Conciliada':'released','Não conciliada':'pending'
};
export function padronizarImportacao(root){
 function atualizar(){
  padronizarAcoes(root);
  for(const form of root.querySelectorAll('form'))organizarFormulario(form);
  for(const td of root.querySelectorAll('td')){if(td.children.length)continue;const text=td.textContent.trim(),cor=cores[text];if(!cor)continue;const badge=indicadorSituacao(text);badge.className='client-commercial-status '+cor;td.replaceChildren(badge);}
 }
 const observer=new MutationObserver(atualizar);observer.observe(root,{childList:true,subtree:true});atualizar();return()=>observer.disconnect();
}
