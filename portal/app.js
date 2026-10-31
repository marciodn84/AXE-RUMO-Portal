import {initFinanceiroNumerario} from './financeiro-numerario.js?v=20261031-num47';
import {observarSessao} from './sessao-portal.js?v=20261029-sessao21';
import './validacao-campos.js?v=20261030-email36';
import {initImportacoesInternacionais} from './importacoes-internacionais.js?v=20261031-num47';
import {initGestao} from './gestao.js?v=20261023-gestao1';
import {initERP} from './erp.js?v=20261031-num47';
import {initFiscal} from './fiscal.js?v=20261030-email36';
import {initCadastros} from './cadastros.js?v=20261030-email36';
import {initCatalogo} from './catalogo.js?v=20261030-email36';
import {initComercial} from './comercial.js?v=20261023-gestao1';
import {initImportacao} from './importacao.js?v=20261029-excel23';

import {createClient} from 'https://esm.sh/@supabase/supabase-js@2.118.0';
const SUPABASE_URL='https://ursezzcnbwlodmbzabmd.supabase.co', KEY='sb_publishable_SLeQ2rBGoGFB3jqMoqCcvw_lv7dAORr';
const sb=createClient(SUPABASE_URL,KEY,{auth:{storage:sessionStorage,persistSession:true,autoRefreshToken:true}});const $=id=>document.getElementById(id);const msg=t=>$('msg').textContent=t;
async function call(payload,endpoint='axe-rumo-revisao'){const {data:{session}}=await sb.auth.getSession();if(!session)throw Error('Faça login novamente');const r=await fetch(SUPABASE_URL+'/functions/v1/'+endpoint,{method:'POST',headers:{'Content-Type':'application/json','apikey':KEY,'Authorization':'Bearer '+session.access_token},body:JSON.stringify(payload)});const data=await r.json();if(!r.ok)throw Error(data.erro||'Erro HTTP '+r.status);return data}
async function load(){try{const data=await call({acao:'listar'});$('rows').replaceChildren();const ds=data.divergencias||[];const dec=data.decisoes||[];$('summary').textContent=ds.length+' campo(s) em '+new Set(ds.map(x=>x.numero_pedido+'|'+x.numero_item)).size+' item(ns) de '+new Set(ds.map(x=>x.numero_pedido)).size+' pedido(s). Registros NOVO indicam cadastro ausente; diferenças normais de saldo não são divergências.';for(const d of ds){const prev=dec.find(x=>x.coleta_id===d.coleta_id&&x.numero_pedido===d.numero_pedido&&x.numero_item===d.numero_item&&x.campo===d.campo);const tr=document.createElement('tr');function td(value){const el=document.createElement('td');el.textContent=value??'(vazio)';tr.append(el);return el}td(d.numero_pedido+' / '+(d.numero_item||'—'));td(d.campo);td(d.valor_sap);td(d.valor_oficial);const action=td('');if(prev&&prev.decisao!=='PENDENTE'){action.textContent=prev.decisao; }else{const note=document.createElement('input');note.placeholder='Observação';note.style.width='140px';action.append(note);for(const choice of ['APROVADO','REJEITADO']){const btn=document.createElement('button');btn.textContent=choice==='APROVADO'?'Aprovar':'Rejeitar';btn.onclick=async()=>{if(!confirm('Confirmar decisão '+choice+' para '+d.numero_pedido+' / '+d.campo+'?'))return;btn.disabled=true;try{await call({acao:'decidir',coleta_id:d.coleta_id,numero_pedido:d.numero_pedido,numero_item:d.numero_item,campo:d.campo,decisao:choice,observacao:note.value});await load()}catch(e){alert(e.message);btn.disabled=false}};action.append(btn)}}$('rows').append(tr)}await loadPublications();await loadAccomp()}catch(e){alert(e.message)}}
async function loadPublications(){try{const {data:{session}}=await sb.auth.getSession();if(!session)throw Error('Sessão encerrada');const response=await fetch(SUPABASE_URL+'/functions/v1/axe-rumo-publicacao',{method:'POST',headers:{'Content-Type':'application/json','apikey':KEY,'Authorization':'Bearer '+session.access_token},body:JSON.stringify({acao:'listar'})});const data=await response.json();if(!response.ok)throw Error(data.erro||'Erro na consulta de publicações');$('pubrows').replaceChildren();for(const d of data.revisoes||[]){const tr=document.createElement('tr');const cell=v=>{const td=document.createElement('td');td.textContent=v??'(vazio)';tr.append(td);return td};cell(d.numero_pedido+' / '+d.numero_item);cell(d.campo);cell(d.valor_sap+' (valor original SAP)');cell(d.publicacao?'PUBLICADO':'APROVADO — aguardando publicação');const action=cell('');if(!d.publicacao){const btn=document.createElement('button');btn.textContent='Publicar no cadastro oficial';btn.onclick=async()=>{const required='PUBLICAR '+d.numero_pedido+' ITEM '+d.numero_item;const typed=prompt('Esta ação ALTERA o pedido oficial. Para confirmar, digite exatamente:\n'+required);if(typed!==required)return;btn.disabled=true;try{const result=await fetch(SUPABASE_URL+'/functions/v1/axe-rumo-publicacao',{method:'POST',headers:{'Content-Type':'application/json','apikey':KEY,'Authorization':'Bearer '+session.access_token},body:JSON.stringify({acao:'publicar',revisao_id:d.id,pedido:d.numero_pedido,item:d.numero_item,confirmacao:'PUBLICAR_PEDIDO_OFICIAL'})});const info=await result.json();if(!result.ok)throw Error(info.erro+' '+(info.detalhe||''));alert('Publicação confirmada. Auditoria ID '+info.publicacao_id);await load()}catch(e){alert(e.message);btn.disabled=false}};action.append(btn)}$('pubrows').append(tr)}}catch(e){alert(e.message)}}
const recoveryMsg=t=>$('recoveryMsg').textContent=t;
$('forgot').onclick=()=>{$('recovery').hidden=!$('recovery').hidden;$('recoveryEmail').value=$('email').value};
$('sendRecovery').onclick=async()=>{const email=$('recoveryEmail').value.trim();if(!email){recoveryMsg('Informe seu e-mail.');return}recoveryMsg('Solicitando envio...');const {error}=await sb.auth.resetPasswordForEmail(email);recoveryMsg(error?(error.message.includes('rate limit')?'Limite temporário de e-mails atingido. Aguarde antes de tentar novamente.':error.message):'Se o endereço estiver cadastrado, o e-mail de recuperação será enviado. Verifique sua caixa de entrada e spam.')};
$('validateRecovery').onclick=async()=>{try{const raw=$('recoveryLink').value.trim();if(!raw)throw Error('Cole o link completo recebido por e-mail.');const link=new URL(raw);if(link.origin!==SUPABASE_URL||!link.pathname.startsWith('/auth/v1/verify'))throw Error('O link não é do Supabase AXE-RUMO.');if(link.searchParams.get('type')!=='recovery')throw Error('O link não é de recuperação de senha.');const token_hash=link.searchParams.get('token')||link.searchParams.get('token_hash');if(!token_hash)throw Error('Token de recuperação não encontrado.');recoveryMsg('Validando link...');sessaoPortal.setRecoveryMode(true);const {error}=await sb.auth.verifyOtp({token_hash,type:'recovery'});if(error)throw error;$('recoveryLink').value='';$('newPasswordBox').hidden=false;recoveryMsg('Link validado. Agora escolha uma nova senha.')}catch(e){sessaoPortal.setRecoveryMode(false);recoveryMsg('Não foi possível validar o link: '+e.message)}};
$('savePassword').onclick=async()=>{const pwd=$('newPassword').value;if(pwd.length<8){recoveryMsg('Use pelo menos 8 caracteres.');return}if(pwd!==$('confirmPassword').value){recoveryMsg('As senhas não coincidem.');return}recoveryMsg('Atualizando senha...');const {error}=await sb.auth.updateUser({password:pwd});if(error){recoveryMsg(error.message);return}$('newPassword').value='';$('confirmPassword').value='';$('newPasswordBox').hidden=true;await sb.auth.signOut({scope:'local'});sessaoPortal.setRecoveryMode(false);recoveryMsg('Senha redefinida com sucesso. Faça login com sua nova senha.');};
$('publishRefresh').onclick=loadPublications;
$('enter').onclick=async()=>{const b=$('enter');b.disabled=true;msg('Autenticando...');try{const {error}=await sb.auth.signInWithPassword({email:$('email').value,password:$('password').value});if(error){msg(error.message);return}$('password').value='';msg('');}catch(e){msg('Não foi possível entrar. '+e.message);}finally{b.disabled=false;}};$('refresh').onclick=load;$('logout').onclick=async()=>{const {error}=await sb.auth.signOut({scope:'local'});if(error)alert('Não foi possível sair. '+error.message);};


const labelStatus=value=>({CONFORME:'Conforme',DIVERGENTE:'Divergente',PENDENTE:'Conferir',DIVERGENCIA_CRITICA:'Divergência crítica',CONFERENCIA_PENDENTE:'Conferência pendente',CONFORME_NOS_PONTOS_CRITICOS_CONFERIDOS:'Conforme nos pontos conferidos',AGUARDANDO_BAIXA_EM_PRAZO:'Aguardando baixa — dentro dos 10 dias',BAIXA_IDENTIFICADA:'Baixa identificada no SAP',ENTREGA_NAO_COMPROVADA:'Entrega ainda sem comprovante',BAIXA_NAO_IDENTIFICADA_APOS_10_DIAS:'Verificar baixa — prazo de 10 dias ultrapassado'}[value]||value||'Não verificado');
const dateBR=value=>value?new Date(value.length===10?value+'T12:00:00-03:00':value).toLocaleDateString('pt-BR',{timeZone:'America/Sao_Paulo'}):'—';
function tableRow(target,values){const tr=document.createElement('tr');for(const v of values){const td=document.createElement('td');td.textContent=v??'—';tr.append(td)}$(target).append(tr);return tr}
async function loadAccomp(){
 try{
  $('acompMsg').textContent='Atualizando acompanhamento...';
  const d=await call({acao:'acompanhamento'});const q=d.consultas;
  for(const target of ['acompRows','fiscalRows','prazoRows','alertaRows'])$(target).replaceChildren();
  for(const r of q.itens.linhas)tableRow('acompRows',[r.numero_pedido+' / '+r.numero_item,r.quantidade_total_pdf,r.saldo_pendente_sap,r.quantidade_baixada_sap,r.numeros_nf_informados||'Ainda não informada',r.entrega_comprovada?'Comprovante preservado no banco':'Sem comprovante preservado']);
  for(const r of q.fiscal.linhas){const c=r.verificacoes;const info=r.informativos||{};const tr=tableRow('fiscalRows',[r.numero_nf+' / '+(r.numero_pedido||'Pedido ausente')+' / '+(r.numero_item_pedido||'Item ausente'),labelStatus(c.pedido)+' / '+labelStatus(c.item),labelStatus(c.cnpj_faturamento),labelStatus(c.unidade)+' ('+(info.unidade_xml||'ausente')+' × '+(info.unidade_pdf||'ausente')+')',labelStatus(c.icms.estado),labelStatus(c.ipi.estado),labelStatus(r.estado)]);tr.className=r.estado==='DIVERGENCIA_CRITICA'?'critical':r.estado==='CONFERENCIA_PENDENTE'?'pending':'okay';const details=document.createElement('details');const summary=document.createElement('summary');summary.textContent='Ver conferência';const pre=document.createElement('pre');pre.textContent=JSON.stringify({verificacoes:c,informativos:info},null,2);details.append(summary,pre);tr.lastChild.append(details)}
  for(const r of q.prazos.linhas)tableRow('prazoRows',[r.numero_nf+' / '+r.numero_pedido,dateBR(r.prazo_baixa.data_entrega),dateBR(r.prazo_baixa.limite_baixa),labelStatus(r.prazo_baixa.estado)]);
  for(const r of q.alertas.linhas)tableRow('alertaRows',[r.numero_nf+' / série '+r.serie,dateBR(r.recebido_em),'Divergência sinalizada pela RUMO; motivo não informado. Recusa não confirmada.']);
  $('acompMsg').textContent='Atualizado em '+new Date().toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo'})+'. XMLs com conferência: '+q.fiscal.total+'. Alertas RUMO capturados: '+q.alertas.total+'.'+(Object.values(q).some(x=>x.limitado)?' Há resultados além do limite desta tela.':'');
 }catch(error){$('acompMsg').textContent='Não foi possível atualizar o acompanhamento. '+error.message}
}

const cadastros=initCadastros(payload=>call(payload,'axe-cadastros'),payload=>call(payload,'axe-catalogo'));

const fiscal=initFiscal(payload=>call(payload,'axe-fiscal'));
const catalogo=initCatalogo(payload=>call(payload,'axe-catalogo'));
const importacao=initImportacao(payload=>call(payload,'axe-importacao'));
const comercial=initComercial(payload=>call(payload,'axe-comercial'));
const gestao=initGestao(payload=>call(payload,'axe-gestao'));
const importacoesInternacionais=initImportacoesInternacionais(payload=>call(payload,(payload.acao?.startsWith('transp_')||payload.acao?.startsWith('lib_')||payload.acao?.startsWith('pagdoc_')||payload.acao?.startsWith('plano_')||payload.acao?.startsWith('fxdoc_')||payload.acao?.startsWith('ack_')||payload.acao?.startsWith('email_'))?'axe-documentos-entrada':(payload.acao?.startsWith('num_')||payload.acao?.startsWith('fech_')||payload.acao?.startsWith('pedido_pdf_'))?'axe-importacoes-fechamento':payload.acao?.startsWith('nf_')?'axe-importacoes-notas':'axe-importacoes-internacionais'));
const financeiroNumerario=initFinanceiroNumerario(p=>call(p,'axe-importacoes-fechamento'));
const erp=initERP(cadastros,payload=>call(payload,'axe-cadastros'),fiscal,catalogo,importacao,comercial,gestao,importacoesInternacionais,financeiroNumerario);
document.addEventListener('axe-tributacao-produto',event=>erp.navigate('tributacao-produtos',event.detail));
new MutationObserver(()=>{if($('panel').hidden){fiscal.reset();catalogo.reset();importacao.reset();comercial.reset();gestao.reset();importacoesInternacionais.reset();}}).observe($('panel'),{attributes:true,attributeFilter:['hidden']});
document.addEventListener('axe-produtos-empresa',event=>erp.navigate('equivalencias',event.detail));

document.addEventListener('axe-simular-proposta',event=>erp.navigate('simulador',event.detail));




$('enter').disabled=true;
const sessaoPortal=observarSessao(sb.auth,{
 entrar(){msg('');$('login').hidden=true;if($('panel').hidden)$('panel').hidden=false;setTimeout(()=>{if(!$('panel').hidden)void load();},0);},
 sair(event){if(event==='SIGNED_OUT'){try{sessionStorage.removeItem('axe:erp:ultima-tela');}catch{}}cadastros.reset();for(const id of ['rows','pubrows','acompRows','fiscalRows','prazoRows','alertaRows'])$(id).replaceChildren();if(!$('panel').hidden)$('panel').hidden=true;$('login').hidden=false;},
 recuperar(){if(!$('panel').hidden)$('panel').hidden=true;$('login').hidden=false;$('recovery').hidden=false;$('newPasswordBox').hidden=false;},
 erro(){msg('Não foi possível restaurar o acesso. Tente entrar novamente.');}
});
sessaoPortal.ready.finally(()=>{$('enter').disabled=false;});


document.addEventListener('axe-importar-cadastro',event=>{if(['cliente','produto','fornecedor'].includes(event.detail?.tipo))erp.navigate('importacao',{tipo:event.detail.tipo});});




