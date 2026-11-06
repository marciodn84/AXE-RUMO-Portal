import {aplicarIconeAcao,iconeAcao} from './acoes-icones.js?v=20261106-acoes2';

export function acoesLista(titulo, visualizar, carregar, erro) {
  const grupo=document.createElement('span');
  grupo.style.display='inline-flex';
  grupo.style.gap='4px';
  const ver=document.createElement('button'),mais=document.createElement('button');
  ver.type=mais.type='button';
  aplicarIconeAcao(ver,'visualizar','Visualizar '+titulo);
  aplicarIconeAcao(mais,'mais','Mais ações de '+titulo);
  mais.setAttribute('aria-haspopup','menu');
  mais.setAttribute('aria-expanded','false');
  grupo.append(ver,mais);
  let menu;
  function fechar(focar=false) {
    menu?.remove();menu=null;
    mais.setAttribute('aria-expanded','false');
    if(focar&&mais.isConnected)mais.focus();
  }
  ver.onclick=async()=>{
    fechar();ver.disabled=true;
    try{await visualizar();}catch(e){erro(e.message);}
    finally{ver.disabled=false;}
  };
  mais.onclick=async()=>{
    if(menu){fechar(true);return;}
    mais.disabled=true;
    try{
      const itens=await carregar();
      if(!grupo.isConnected||grupo.closest('[hidden]'))return;
      menu=document.createElement('div');
      menu.className='imp-grid-menu';menu.setAttribute('popover','auto');
      menu.setAttribute('role','menu');menu.setAttribute('aria-label','Ações de '+titulo);
      const heading=document.createElement('div');
      heading.className='imp-grid-menu-title';heading.textContent=titulo;menu.append(heading);
      for(const [nome,icone,acao] of itens){
        const b=document.createElement('button'),label=document.createElement('span');
        b.type='button';b.className='imp-grid-menu-item';b.setAttribute('role','menuitem');
        label.textContent=nome;b.append(iconeAcao(icone),label);menu.append(b);
        b.onclick=async()=>{fechar(true);try{await acao();}catch(e){erro(e.message);}};
      }
      if(!itens.length){const p=document.createElement('p');p.textContent='Sem outras ações disponíveis.';menu.append(p);}
      const atual=menu;
      atual.addEventListener('toggle',e=>{if(e.newState==='closed'&&menu===atual)fechar();});
      atual.onkeydown=e=>{
        const bs=[...atual.querySelectorAll('button')],i=bs.indexOf(document.activeElement);
        if(e.key==='Escape'){e.preventDefault();fechar(true);}
        else if(['ArrowDown','ArrowUp','Home','End'].includes(e.key)&&bs.length){
          e.preventDefault();
          bs[e.key==='Home'?0:e.key==='End'?bs.length-1:(i+(e.key==='ArrowDown'?1:bs.length-1)+bs.length)%bs.length].focus();
        }
      };
      grupo.append(atual);atual.showPopover();
      mais.setAttribute('aria-expanded','true');
      const r=mais.getBoundingClientRect();
      atual.style.left=Math.max(8,Math.min(r.right-atual.offsetWidth,innerWidth-atual.offsetWidth-8))+'px';
      atual.style.top=Math.max(8,Math.min(r.bottom+5,innerHeight-atual.offsetHeight-8))+'px';
      atual.querySelector('button')?.focus();
    }catch(e){fechar();erro(e.message);}
    finally{mais.disabled=false;}
  };
  return grupo;
}
