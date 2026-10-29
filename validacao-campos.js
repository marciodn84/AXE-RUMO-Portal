let sequence=0,scheduled=false,first=null;
function mensagem(e){if(e.validity?.valueMissing)return 'Preencha este campo obrigatório.';if(e.validity?.rangeUnderflow)return 'Informe um valor maior ou igual a '+e.min+'.';if(e.validity?.rangeOverflow)return 'Informe um valor menor ou igual a '+e.max+'.';if(e.validity?.typeMismatch||e.validity?.patternMismatch)return 'Confira o formato deste campo.';return e.validationMessage||'Confira este campo.';}
export function limparErro(e){e.classList.remove('campo-invalido');e.removeAttribute('aria-invalid');const id=e.dataset.erroCampo;if(id){document.getElementById(id)?.remove();const ids=(e.getAttribute('aria-describedby')||'').split(' ').filter(x=>x&&x!==id);if(ids.length)e.setAttribute('aria-describedby',ids.join(' '));else e.removeAttribute('aria-describedby');delete e.dataset.erroCampo;}if(e.dataset.erroEspacos){e.setCustomValidity('');delete e.dataset.erroEspacos;}}
export function marcarErro(e,texto='Preencha este campo obrigatório.'){
 e.classList.add('campo-invalido');e.setAttribute('aria-invalid','true');let id=e.dataset.erroCampo,span=id&&document.getElementById(id);if(!span){id='erro-campo-'+(++sequence);span=document.createElement('span');span.id=id;span.className='erro-campo';span.setAttribute('aria-live','polite');e.insertAdjacentElement('afterend',span);e.dataset.erroCampo=id;e.setAttribute('aria-describedby',[e.getAttribute('aria-describedby'),id].filter(Boolean).join(' '));}span.textContent=texto;
}
function focus(e){if(!e?.isConnected)return;e.scrollIntoView({block:'center',behavior:'smooth'});e.focus({preventScroll:true});}
export function validarCampos(container){
 const fields=[...container.querySelectorAll('input,select,textarea')].filter(e=>e.willValidate);let primeiro=null;
 for(const e of fields){if(e.dataset.erroEspacos){e.setCustomValidity('');delete e.dataset.erroEspacos;}if(e.required&&typeof e.value==='string'&&e.type!=='checkbox'&&e.type!=='radio'&&!e.value.trim()){e.setCustomValidity('Preencha este campo obrigatório.');e.dataset.erroEspacos='true';}if(!e.validity.valid){marcarErro(e,mensagem(e));primeiro??=e;}else limparErro(e);}
 if(primeiro){focus(primeiro);return false;}return true;
}
document.addEventListener('invalid',event=>{const e=event.target;if(!e?.validity)return;event.preventDefault();marcarErro(e,mensagem(e));first??=e;if(!scheduled){scheduled=true;queueMicrotask(()=>{focus(first);first=null;scheduled=false;});}},true);
for(const type of ['input','change'])document.addEventListener(type,event=>{const e=event.target;if(e?.classList?.contains('campo-invalido')){if(e.dataset.erroEspacos){e.setCustomValidity('');delete e.dataset.erroEspacos;}if(!e.validity||e.validity.valid)limparErro(e);else marcarErro(e,mensagem(e));}});
