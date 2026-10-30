const el=(t,s)=>{const n=document.createElement(t);if(s!=null)n.textContent=s;return n;};
const clean=v=>String(v??'').replace(/[.\/-]|\s/g,'');
const valid=v=>{if(!/^\d{14}$/.test(v)||/^(\d)\1+$/.test(v))return false;for(let len=12;len<=13;len++){let sum=0,w=len-7;for(let i=0;i<len;i++){sum+=Number(v[i])*w;w=w===2?9:w-1;}if(Number(v[len])!==(sum%11<2?0:11-sum%11))return false;}return true;};
export function montarConsultaCNPJ(form,inputs,api,tipo,{valido=()=>true}={}){
 const input=inputs.cnpj?.input;if(!input||!['cliente','fornecedor'].includes(tipo))return null;
 let sequence=0,pending=false,source=null,last='',fields=[];
 input.maxLength=18;const trigger=el('button','Buscar CNPJ'),message=el('p'),panel=el('section');trigger.type='button';message.setAttribute('role','status');panel.className='cnpj-preview';panel.hidden=true;input.closest('label').append(trigger,message);form.append(panel);
 const present=()=>form.closest('dialog')?.open&&valido();
 const norm=(k,v)=>['telefone','inscricao_estadual'].includes(k)?String(v).replace(/\W/g,''):String(v).trim().replace(/\s+/g,' ').toLocaleUpperCase('pt-BR');
 async function consultar(explicit=false){
  const cnpj=clean(input.value);if(!valid(cnpj)){if(explicit)message.textContent='Informe um CNPJ válido.';return;}
  if(tipo==='fornecedor'&&inputs.pais?.input.value&&inputs.pais.input.value.toUpperCase()!=='BR'){if(explicit)message.textContent='A consulta é destinada a fornecedores com CNPJ brasileiro.';return;}
  if(pending||!explicit&&cnpj===last)return;const n=++sequence;pending=true;trigger.disabled=true;message.textContent='Consultando CNPJ.ws…';
  try{const r=await api({acao:'consultar_cnpj',tipo,cnpj});if(!present()||n!==sequence||clean(input.value)!==cnpj)return;source=r;last=cnpj;const d=r.dados;if(d?.cnpj!==cnpj)throw Error('A consulta retornou outro CNPJ.');
   const values={...d,[tipo==='cliente'?'nome':'razao_social']:d.razao_social,...(tipo==='fornecedor'?{endereco:d.endereco_texto}: {})};let filled=0;fields=[];panel.replaceChildren();
   for(const key of ['nome','razao_social','nome_fantasia','inscricao_estadual','email','telefone','pais','endereco']){const target=inputs[key]?.input,value=values[key];if(!target||!value)continue;if(!target.value.trim()){target.value=value;filled++;}else if(norm(key,target.value)!==norm(key,value))fields.push({key,input:target,value});}
   panel.append(el('h3','Dados da CNPJ.ws'),el('p','Situação cadastral: '+(d.situacao_cadastral||'não informada')+(d.atualizado_em?' · Atualização da fonte: '+d.atualizado_em.slice(0,10).split('-').reverse().join('/'):'')+(r.cache?' · Consulta reutilizada':'')));
   if(tipo==='cliente'&&d.endereco_texto)panel.append(el('p','Endereço cadastral: '+d.endereco_texto),el('small',['cep','logradouro','numero','bairro','municipio','uf'].every(k=>d.endereco?.[k])?'Ao salvar, este endereço será registrado em Faturamento. Se houver mudança, a versão anterior será preservada no histórico.':'O endereço da consulta está incompleto. Complete em Endereços e cobrança após salvar.'));
   if(tipo==='cliente'&&r.faturamento_atual){const old=r.faturamento_atual.endereco;if(!old||['cep','logradouro','numero','complemento','bairro','municipio','uf'].some(k=>norm(k,old[k]||'')!==norm(k,d.endereco?.[k]||''))){panel.append(el('p','O endereço de faturamento cadastrado difere da consulta.'),el('p','Atual: '+(old?Object.values(old).filter(Boolean).join(', '):r.faturamento_atual.bloco_original||'Endereço legado')),el('p','Ao salvar, o endereço da CNPJ.ws ficará em Faturamento, preservando a versão anterior no histórico.'));}}
   if(d.inscricoes_estaduais?.length>1){const label=el('label','Inscrição estadual da UF'),select=el('select');select.append(new Option('Selecionar IE',''));for(const ie of d.inscricoes_estaduais)select.append(new Option(ie,ie));select.onchange=()=>{if(select.value)inputs.inscricao_estadual.input.value=select.value;};label.append(select);panel.append(label);}
   for(const warning of d.avisos||[])panel.append(el('p',warning));
   if(fields.length){const table=el('table'),head=el('tr');for(const title of ['Campo','Valor preenchido','CNPJ.ws','Usar consulta'])head.append(el('th',title));table.append(head);
    for(const f of fields){const row=el('tr'),box=el('input');box.type='checkbox';box.setAttribute('aria-label','Usar consulta: '+f.key);f.check=box;row.append(el('td',({nome:'Razão social',razao_social:'Razão social',nome_fantasia:'Nome fantasia',inscricao_estadual:'Inscrição estadual',email:'E-mail',telefone:'Telefone',pais:'País',endereco:'Endereço'})[f.key]),el('td',f.input.value),el('td',f.value));const td=el('td');td.append(box);row.append(td);table.append(row);}const scroll=el('div');scroll.className='scroll';scroll.append(table);panel.append(el('p','Os dados abaixo diferem do preenchimento atual. Selecione somente os que deseja substituir.'),scroll);
    const apply=el('button','Aplicar diferenças selecionadas');apply.type='button';apply.onclick=()=>{for(const f of fields)if(f.check.checked){f.input.value=f.value;f.check.checked=false;}message.textContent='Diferenças selecionadas aplicadas ao formulário. Salve para gravar.';};panel.append(apply);
   }
   panel.hidden=false;message.textContent=filled+' campo(s) preenchido(s).'+(fields.length?' Há diferenças para conferir.':' Salve o cadastro para gravar.');
  }catch(e){if(present()&&n===sequence){source=null;last='';message.textContent=e.message||'Consulta indisponível. Preencha manualmente.';}}finally{if(n===sequence){pending=false;trigger.disabled=false;}}
 }
 input.addEventListener('input',()=>{input.value=input.value.replace(/\D/g,'').slice(0,14);sequence++;pending=false;source=null;last='';trigger.disabled=false;panel.hidden=true;message.textContent='';});
 trigger.onclick=()=>void consultar(true);
 return {cnpj:()=>source?.dados?.cnpj===clean(input.value)?source.dados.cnpj:null,pendente:()=>pending};
}
