let sequence=0;
export function organizarFormulario(form){
 if(form.dataset.abasImportacao)return;
 const panels=[...form.children].filter(n=>n.tagName==='FIELDSET');if(panels.length<2)return;
 form.dataset.abasImportacao='true';form.classList.add('imp-form-integrado');
 const nav=document.createElement('div');nav.className='client-form-tabs';nav.setAttribute('role','tablist');nav.setAttribute('aria-label','Dados da importação');const id=++sequence,tabs=[];
 function select(index){panels.forEach((panel,n)=>{panel.hidden=n!==index;tabs[n].setAttribute('aria-selected',String(n===index));tabs[n].tabIndex=n===index?0:-1;});}
 panels.forEach((panel,n)=>{const tab=document.createElement('button');tab.type='button';tab.textContent=panel.querySelector('legend')?.textContent||'Dados '+(n+1);tab.id='imp-tab-'+id+'-'+n;panel.id='imp-panel-'+id+'-'+n;tab.setAttribute('role','tab');tab.setAttribute('aria-controls',panel.id);panel.setAttribute('role','tabpanel');panel.setAttribute('aria-labelledby',tab.id);tab.onclick=()=>select(n);tab.onkeydown=e=>{if(!['ArrowLeft','ArrowRight','Home','End'].includes(e.key))return;e.preventDefault();const next=e.key==='Home'?0:e.key==='End'?panels.length-1:(n+(e.key==='ArrowRight'?1:panels.length-1))%panels.length;select(next);tabs[next].focus();};tabs.push(tab);nav.append(tab);
 // Keep the existing related actions inside their section.
 let next=panel.nextElementSibling;while(next?.tagName==='BUTTON'&&!/^Salvar/.test(next.textContent)){const action=next;next=next.nextElementSibling;panel.append(action);}
 });
 form.prepend(nav);select(0);
 const reveal=e=>{const panel=e.target.closest('[role=tabpanel]'),index=panels.indexOf(panel);if(index>=0)select(index);};form.addEventListener('invalid',reveal,true);form.addEventListener('axe-invalid-field',reveal);
}
