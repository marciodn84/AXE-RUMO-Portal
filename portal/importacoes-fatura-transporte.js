const brl = value => Number(value).toLocaleString('pt-BR', {style:'currency',currency:'BRL'});
const data = value => value.split('-').reverse().join('/');
function el(tag, text) {
  const node = document.createElement(tag);
  if (text != null) node.textContent = text;
  return node;
}

export function initFaturaTransporte(api, root) {
  let dialog, ocupado = false, sujo = false;
  const canLeave = () => !ocupado && (!sujo || confirm('Descartar a conferência da fatura de frete?'));
  function reset() {
    dialog?.close();
    dialog?.remove();
    dialog = null;
    sujo = false;
  }
  async function show(embarque) {
    if (!canLeave()) return;
    reset();
    const modal = dialog = el('dialog');
    modal.className = 'imp-picker imp-ack';
    const form = el('form'), status = el('p'), area = el('div'), fechar = el('button','Fechar');
    fechar.type = 'button';
    fechar.onclick = () => { if (canLeave()) reset(); };
    modal.addEventListener('cancel', e => { e.preventDefault(); if (canLeave()) reset(); });
    status.setAttribute('role','status');
    form.append(el('h2','Fatura da transportadora · '+embarque.referencia),status,area,fechar);
    modal.append(form);
    root.append(modal);
    modal.showModal();
    const call = (acao, dados={}) => api({acao,embarque_id:embarque.id,...dados});
    async function executar(fn) {
      if (ocupado) return;
      ocupado = true;
      status.textContent = 'Processando…';
      try { status.textContent = await fn() || ''; }
      catch (error) { status.textContent = error.message; }
      finally { ocupado = false; }
    }
    function registro(fatura, fornecedor, editar) {
      area.replaceChildren(el('p',fornecedor+' · Fatura '+fatura.numero+' · '+brl(fatura.valor_brl)),
        el('p',fatura.data_pagamento?'Pago por boleto em '+data(fatura.data_pagamento):'A pagar por boleto · Vencimento '+data(fatura.vencimento)));
      const baixar = el('button','Baixar PDF da fatura');
      baixar.type = 'button';
      baixar.onclick = () => executar(async () => {
        const r = await call('v2_frete_fatura_baixar');
        const url = URL.createObjectURL(new Blob([Uint8Array.from(atob(r.pdf),c=>c.charCodeAt(0))],{type:'application/pdf'}));
        const a = el('a');
        a.href = url;
        a.download = r.nome;
        a.click();
        setTimeout(()=>URL.revokeObjectURL(url),1000);
      });
      area.append(baixar);
      form.onsubmit=e=>e.preventDefault();
      if(fatura.situacao!=='A pagar'||!editar)return;
      const label=el('label','Data efetiva do pagamento'), pagamento=el('input');
      pagamento.type='date';pagamento.required=true;pagamento.min=fatura.emissao;
      label.append(pagamento);
      const confirmar=el('button','Confirmar pagamento do boleto');
      confirmar.type='button';
      area.append(label,confirmar);
      confirmar.onclick=()=>{
        if(ocupado||!pagamento.reportValidity())return;
        const dia=pagamento.value;
        if(!confirm('Confirmar a baixa de '+brl(fatura.valor_brl)+' em '+data(dia)+'?'))return;
        void executar(async()=>{
          const r=await call('v2_frete_fatura_baixar_pagamento',{requisicao_id:crypto.randomUUID(),data_pagamento:dia,confirmou_pagamento:true});
          registro(r.fatura,fornecedor,editar);
          return 'Pagamento registrado.';
        });
      };
    }
    form.onsubmit = e => e.preventDefault();
    await executar(async () => {
      const ctx = await call('v2_frete_fatura_ler');
      if (ctx.fatura) { registro(ctx.fatura,ctx.transportadora || 'Transportadora',ctx.editar); return; }
      if (ctx.frete_no_numerario) return 'Frete registrado no numerário ou no fechamento do despachante.';
      if (ctx.custo_final) return 'Reabra o custo final antes de cadastrar a fatura.';
      if (!ctx.transportadora) return 'Vincule a transportadora ao embarque antes de cadastrar a fatura.';
      if (!ctx.editar) return 'Nenhuma fatura de frete cadastrada.';
      area.append(el('p',ctx.transportadora), el('p','Use esta opção quando a AXE contratar e pagar o frete diretamente. Se o despachante pagar com o numerário, registre pelo fluxo de numerário.'));
      function field(label,type) {
        const l=el('label',label), input=el('input');
        input.type=type;input.required=true;
        l.append(input);area.append(l);
        return input;
      }
      const arquivo=field('PDF da fatura de frete','file');
      arquivo.accept='.pdf,application/pdf';
      const numero=field('Número da fatura','text');
      numero.maxLength=100;
      const valor=field('Valor pago em reais','number');
      valor.min='0.01';valor.step='0.01';
      const emissao=field('Data da emissão','date');
      const vencimento=field('Vencimento do boleto','date');
      const direta=field('O frete foi contratado diretamente e está fora do numerário do despachante','checkbox');
      const salvar=el('button','Registrar fatura em Contas a pagar');
      salvar.type='submit';
      area.append(salvar);
      let req;
      form.addEventListener('input',()=>{sujo=true;req=null;});
      form.onsubmit = e => {
        e.preventDefault();
        if (ocupado || !form.reportValidity()) return;
        void executar(async () => {
          const file=arquivo.files[0];
          if (!file || file.size>350000) throw new Error('Anexe um PDF de até 350 KB.');
          const dados={requisicao_id:req??=crypto.randomUUID(),numero:numero.value,valor:valor.value,
            emissao:emissao.value,vencimento:vencimento.value,contratacao_direta:direta.checked,nome:file.name};
          const bytes=new Uint8Array(await file.arrayBuffer());
          const pdf=btoa(Array.from(bytes,c=>String.fromCharCode(c)).join(''));
          const r=await call('v2_frete_fatura_salvar',{...dados,pdf});
          sujo=false;
          registro(r.fatura,ctx.transportadora,ctx.editar);
          return r.pendencias?.some(p=>p.startsWith('Frete:'))?
            'Fatura registrada. Complete o peso bruto dos itens para concluir o rateio.':'Fatura registrada em Contas a pagar.';
        });
      };
    });
  }
  return {show,reset,canLeave};
}
