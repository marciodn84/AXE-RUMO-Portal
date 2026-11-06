const moeda = new Intl.NumberFormat('pt-BR', {style:'currency', currency:'BRL'});
const valor = n => n == null ? '—' : moeda.format(n);
const taxa = n => n == null ? '—' : new Intl.NumberFormat('pt-BR',{maximumFractionDigits:6}).format(n)+'%';
const data = n => n ? n.slice(0,10).split('-').reverse().join('/') : '—';

function el(tag, texto) {
  const node = document.createElement(tag);
  if (texto != null) node.textContent = texto;
  return node;
}

function tabela(cabecalho, linhas) {
  const table = el('table');
  const head = table.createTHead().insertRow();
  for (const nome of cabecalho) {
    const th = el('th', nome);
    th.scope = 'col';
    head.append(th);
  }
  const body = table.createTBody();
  for (const linha of linhas) {
    const tr = body.insertRow();
    for (const coluna of linha) tr.append(el('td', coluna));
  }
  const wrap = el('div');
  wrap.style.overflowX = 'auto';
  wrap.append(table);
  return wrap;
}

export function initComprasNFSe(api, root, atualizar) {
  let dialog, pendente = false, ocupado = false;
  const canLeave = () => !ocupado && (!pendente || confirm('Descartar a conferência da NFS-e?'));
  function reset() {
    dialog?.close();
    dialog?.remove();
    dialog = null;
    pendente = false;
  }

  async function show(pedido, editar) {
    if (!canLeave()) return;
    reset();
    const dlg = dialog = el('dialog');
    const form = el('form');
    const msg = el('p');
    const content = el('div');
    const fechar = el('button','Fechar');
    fechar.type = 'button';
    fechar.onclick = () => { if (canLeave()) reset(); };
    dlg.addEventListener('cancel', event => {
      event.preventDefault();
      if (canLeave()) reset();
    });
    msg.setAttribute('role','status');
    form.append(el('h2','Entrada de NFS-e · '+pedido.referencia), msg, content, fechar);
    dlg.append(form);
    root.append(dlg);
    dlg.showModal();
    const chamar = dados => api({...dados,pedido_id:pedido.id});
    async function executar(fn) {
      if (ocupado) return;
      ocupado = true;
      msg.textContent = 'Processando…';
      try {
        await fn();
        if (dlg.isConnected) msg.textContent = '';
      } catch (e) {
        if (dlg.isConnected) msg.textContent = e.message || String(e);
      } finally { ocupado = false; }
    }
    function resumo(nota) {
      return [
        el('h3','NFS-e '+nota.numero),
        el('p','Emissão '+data(nota.emissao)+' · Chave '+nota.chave),
        tabela(['Serviço bruto','Descontos','Retenções','Custo de entrada','A pagar ao fornecedor'],
          [[valor(nota.bruto),valor(nota.descontos),valor(nota.retencoes),valor(nota.custo),valor(nota.liquido)]]),
        ...(nota.tributos.length ? [tabela(['Tributo','Base','Alíquota','Valor'],
          nota.tributos.map(t=>[t.imposto,valor(t.base),taxa(t.aliquota),valor(t.valor)]))] : [])
      ];
    }
    function registrada(nota) {
      pendente = false;
      content.replaceChildren(el('p','NFS-e registrada e parcela conciliada.'), ...resumo(nota));
    }
    form.onsubmit = e => e.preventDefault();
    await executar(async () => {
      const r = await chamar({acao:'v2_nfse_listar'});
      if (r.nota) { registrada(r.nota); return; }
      if (!editar || !r.editar) { content.append(el('p','Nenhuma NFS-e registrada.')); return; }
      const arquivo = el('input');
      arquivo.type = 'file';
      arquivo.accept = '.xml,application/xml,text/xml';
      const rotulo = el('label','XML da NFS-e no padrão nacional ');
      rotulo.append(arquivo);
      const ler = el('button','Conferir XML');
      ler.type = 'button';
      const previa = el('div');
      content.append(rotulo,ler,previa);
      arquivo.onchange = () => { previa.replaceChildren(); pendente = Boolean(arquivo.files[0]); };
      ler.onclick = () => executar(async () => {
        previa.replaceChildren();
        const file = arquivo.files[0];
        if (!file || file.size > 350000) throw new Error('Selecione um XML de até 350 KB.');
        const xml = await file.text();
        const r = await chamar({acao:'v2_nfse_conferir',xml});
        if (r.confirmada) { registrada(r.nota); return; }
        if (arquivo.files[0] !== file) return;
        previa.append(...resumo(r.nota),
          el('p','Custo previsto '+valor(r.custo_previsto)+' · Parcela atual '+valor(r.parcela.valor)+' · Já pago '+valor(r.parcela.valor_pago)+' · Vencimento '+data(r.parcela.vencimento)));
        if (r.divergencias.length) previa.append(tabela(['Tributo','Valor no pedido','Valor na nota','Alíquota no pedido','Alíquota na nota'],
          r.divergencias.map(t=>[t.imposto,valor(t.pedido),valor(t.nota),taxa(t.aliquota_pedido),taxa(t.aliquota_nota)])));
        const aceite = el('input');
        aceite.type = 'checkbox';
        const justificativa = el('textarea');
        justificativa.maxLength = 1000;
        if (r.exige_confirmacao) {
          const confirmar = el('label',' Conferi as divergências e autorizo usar os valores da nota. ');
          confirmar.prepend(aceite);
          const motivo = el('label','Justificativa ');
          motivo.append(justificativa);
          previa.append(confirmar,motivo);
        }
        const salvar = el('button','Confirmar entrada e parcela');
        salvar.type = 'button';
        previa.append(salvar);
        salvar.onclick = async () => {
          let concluido = false;
          await executar(async () => {
            if (r.exige_confirmacao && (!aceite.checked || justificativa.value.trim().length < 5)) {
              throw new Error('Confirme as divergências e informe a justificativa.');
            }
            const final = await chamar({acao:'v2_nfse_confirmar',xml,conferencia:r.conferencia,
              aceite:aceite.checked,justificativa:justificativa.value});
            registrada(final.nota);
            concluido = true;
          });
          if (concluido) { reset(); await atualizar(pedido.id); }
        };
      });
    });
  }

  return {canLeave, reset, show};
}
