function el(tag,text) {
  const n=document.createElement(tag);
  if(text!=null)n.textContent=text;
  return n;
}
export function initCadastroEmpresas(api) {
  const root=el('section');root.className='cadastro-screen';root.hidden=true;
  document.getElementById('cadastrosRoot').append(root);
  let ciclo=0, ocupado=false, alterado=false;
  const canLeave=()=>!ocupado&&(!alterado||confirm('Descartar as alterações do cadastro da empresa?'));
  function btn(texto,acao) {
    const b=el('button',texto);b.type='button';b.onclick=acao;return b;
  }
  async function show(visivel) {
    const g=++ciclo;
    root.hidden=!visivel;alterado=false;
    if(!visivel)return;
    const status=el('p','Consultando empresas…');status.setAttribute('role','status');
    root.replaceChildren(status);
    try{
      const r=await api({acao:'v2_empresas_listar'});
      if(g!==ciclo)return;
      status.textContent='';
      const bar=el('div');bar.className='cadastro-toolbar';
      if(r.editar)bar.append(btn('Nova empresa',()=>editar({},true)));
      const scroll=el('div');scroll.className='scroll';
      const tabela=el('table'),h=tabela.createTHead().insertRow(),body=tabela.createTBody();
      for(const t of ['Razão social','CNPJ','Situação','Ação'])h.append(el('th',t));
      for(const e of r.linhas){
        const tr=body.insertRow();
        tr.append(el('td',e.razao_social),el('td',e.cnpj),el('td',e.logo_padrao?'Empresa padrão':e.ativa?'Ativa':'Inativa'));
        tr.insertCell().append(btn(r.editar?'Editar':'Consultar',()=>editar(e,r.editar)));
      }
      scroll.append(tabela);root.append(bar,scroll);
    }catch(e){if(g===ciclo)status.textContent=e.message;}
  }
  function editar(empresa,podeEditar) {
    const form=el('form'), status=el('p'), grid=el('div');
    grid.className='import-mapping';
    status.setAttribute('role','status');
    root.replaceChildren(btn('Voltar à lista',()=>{if(canLeave())void show(true);}),
      el('h2',empresa.id?empresa.razao_social:'Nova empresa'),status,form);
    form.append(grid);
    const campos={};
    for(const [chave,label,tipo,limite] of [
      ['razao_social','Razão social','text',200],['nome_fantasia','Nome fantasia','text',200],
      ['cnpj','CNPJ','text',18],['inscricao_estadual','Inscrição estadual','text',40],
      ['endereco','Endereço da empresa','textarea',600],['endereco_entrega','Endereço padrão de entrega','textarea',600],
      ['email','E-mail','email',254],['telefone','Telefone','tel',60]
    ]){
      const l=el('label',label),c=el(tipo==='textarea'?'textarea':'input');
      if(tipo!=='textarea')c.type=tipo;
      c.value=empresa[chave]||'';c.maxLength=limite;c.required=['razao_social','cnpj','endereco'].includes(chave);
      c.disabled=!podeEditar||(chave==='cnpj'&&Boolean(empresa.id));l.append(c);grid.append(l);campos[chave]=c;
    }
    const previa=el('img');previa.alt='Logotipo da empresa';previa.style.maxWidth='180px';previa.hidden=!empresa.logo;
    if(empresa.logo)previa.src=empresa.logo;
    form.append(previa);
    if(!podeEditar)return;
    const label=el('label','Logotipo PNG ou JPG, até 150 KB'),arquivo=el('input');
    arquivo.type='file';arquivo.accept='image/png,image/jpeg';label.append(arquivo);form.append(label);
    const salvar=el('button','Salvar empresa');salvar.type='submit';form.append(salvar);
    form.addEventListener('input',()=>{alterado=true;});
    form.onsubmit=async event=>{
      event.preventDefault();if(ocupado||!form.reportValidity())return;
      const dados={id:empresa.id,versao:empresa.versao,...Object.fromEntries(Object.entries(campos).map(([k,v])=>[k,v.value]))};
      const g=ciclo;ocupado=true;salvar.disabled=true;
      try{
        const file=arquivo.files[0];
        if(file){
          if(!['image/jpeg','image/png'].includes(file.type)||file.size>150000)throw Error('Selecione um PNG ou JPG de até 150 KB.');
          dados.logo='data:'+file.type+';base64,'+btoa(Array.from(new Uint8Array(await file.arrayBuffer()),c=>String.fromCharCode(c)).join(''));
          const img=new Image();img.src=dados.logo;
          await img.decode();
        }
        await api({acao:'v2_empresa_salvar',dados});
        if(g===ciclo){alterado=false;await show(true);}
      }catch(e){status.textContent=e.message;}
      finally{ocupado=false;salvar.disabled=false;}
    };
  }
  return {show,canLeave};
}
