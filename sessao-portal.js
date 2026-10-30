// Restore the existing tab session. Token refresh must not rebuild the screen.
export function observarSessao(auth,{entrar,sair,recuperar,erro}){
 let usuario=null,versao=0,disposed=false,recovery=false;
 function aplicar(event,session){
  if(disposed)return;
  if(event==='PASSWORD_RECOVERY'){recovery=true;usuario=null;recuperar();return;}
  if(session?.user?.id){if(recovery)return;if(usuario!==session.user.id){usuario=session.user.id;entrar(session);}return;}
  usuario=null;sair(event);
 }
 const {data:{subscription}}=auth.onAuthStateChange((event,session)=>{versao++;aplicar(event,session);});
 const inicio=versao;
 const ready=auth.getSession().then(({data,error})=>{if(disposed||inicio!==versao)return;if(error){erro(error);return;}aplicar('RESTORE_SESSION',data.session);}).catch(error=>{if(!disposed)erro(error);});
 return {ready,setRecoveryMode(value){recovery=!!value;},dispose(){disposed=true;subscription.unsubscribe();}};
}
