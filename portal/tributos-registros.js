const impostos = ['ICMS', 'ICMS ST', 'ICMS destino', 'ICMS remetente', 'FCP', 'FCP ST', 'FCP destino', 'IPI', 'PIS', 'PIS ST', 'COFINS', 'COFINS ST', 'II', 'ISS', 'IBS estadual', 'IBS municipal', 'IBS monofásico', 'CBS', 'CBS monofásica', 'IS'];
const naturezas = ['Previsto', 'Documentado', 'Recolhido'];
const campos = [
  ['natureza', 'Natureza do valor'],
  ['item', 'Item'], ['imposto', 'Tributo'], ['base', 'Base de cálculo'],
  ['aliquota', 'Alíquota (%)'], ['valor', 'Valor'], ['cst', 'CST'],
  ['classificacao', 'Classificação tributária'], ['referencia', 'Referência']
];
function elemento(tag, texto) {
  const node = document.createElement(tag);
  if (texto != null) node.textContent = texto;
  return node;
}
function tabela(titulos) {
  const scroll = elemento('div');
  scroll.className = 'scroll';
  const table = elemento('table');
  const header = table.createTHead().insertRow();
  for (const titulo of titulos) {
    const th = elemento('th', titulo);
    th.scope = 'col';
    header.append(th);
  }
  scroll.append(table);
  return { scroll, body: table.createTBody() };
}
export function mostrarTributos(destino, linhas = []) {
  if (!linhas.length) return;
  const section = elemento('details');
  section.append(elemento('summary', 'Tributos destacados no XML'));
  const { scroll, body } = tabela(['NF-e', 'Item', 'Tributo', 'Base', 'Alíquota (%)', 'Efetiva (%)', 'Valor (R$)', 'CST', 'Classificação', 'Base em quantidade', 'Alíquota por unidade', 'Situação da nota']);
  for (const linha of linhas) {
    const row = body.insertRow();
    for (const key of ['nota', 'item', 'imposto', 'base', 'aliquota', 'aliquota_efetiva', 'valor', 'cst', 'classificacao', 'base_quantidade', 'aliquota_especifica', 'estado']) {
      const value = linha[key];
      row.insertCell().textContent = value == null ? '—' : typeof value === 'number' ? value.toLocaleString('pt-BR', {maximumFractionDigits: 8}) : value;
    }
  }
  section.append(scroll);
  destino.append(section);
}

export function botaoTributos(api, origem, registro, moeda) {
  const abrir = elemento('button', 'Tributos');
  abrir.type = 'button';
  abrir.onclick = async () => {
    abrir.disabled = true;
    const dialog = elemento('dialog');
    dialog.className = 'imp-ack';
    dialog.setAttribute('aria-label', 'Tributos do registro');
    const fechar = elemento('button', 'Fechar');
    fechar.type = 'button';
    fechar.onclick = () => dialog.close();
    dialog.addEventListener('close', () => dialog.remove(), {once: true});
    const status = elemento('p', 'Consultando tributos…');
    status.setAttribute('role', 'status');
    dialog.append(elemento('h2', 'Tributos do registro'), fechar, status);
    const host = abrir.closest('dialog') || document.body;
    host.append(dialog);
    dialog.showModal();
    try {
      const dados = await api({acao: 'v2_tributos_ler', origem, registro: String(registro)});
      if (!dialog.isConnected) return;
      status.textContent = '';
      mostrarTributos(dialog, dados.fiscais);
      if (!dados.editar && !dados.linhas.length && !dados.fiscais.length) {
        status.textContent = 'Não há tributos discriminados neste registro.';
        return;
      }
      if (!dados.editar && !dados.linhas.length) return;
      dialog.append(elemento('h3', origem === 'estoque' ? 'Tributos informados no movimento' : origem === 'entrada_importacao' ? 'Tributos informados no documento' : 'Tributos informados no pedido'));
      dialog.append(elemento('p', 'Informe a referência que sustenta cada valor. Campos em branco indicam dados ausentes. Valores na moeda do registro' + (moeda ? ' (' + moeda + ').' : '.')));
      const form = elemento('form');
      const { scroll, body } = tabela([...campos.map(([,titulo]) => titulo), ...(dados.editar ? ['Ação'] : [])]);
      form.append(scroll);
      function adicionar(linha = {}) {
        const row = body.insertRow();
        for (const [key, titulo] of campos) {
          const cell = row.insertCell();
          const input = elemento(['imposto', 'natureza'].includes(key) ? 'select' : 'input');
          input.name = key;
          input.setAttribute('aria-label', titulo);
          if (key === 'natureza') for (const natureza of naturezas) input.append(new Option(natureza, natureza));
          if (key === 'imposto') for (const imposto of impostos) input.append(new Option(imposto, imposto));
          if (['base', 'aliquota', 'valor'].includes(key)) {
            input.type = 'number';
            input.min = '0';
            input.step = key === 'valor' ? '0.01' : 'any';
          }
          input.required = ['valor', 'referencia'].includes(key);
          input.value = linha[key] ?? (key === 'imposto' ? impostos[0] : key === 'natureza' ? naturezas[0] : '');
          input.disabled = !dados.editar;
          cell.append(input);
        }
        if (dados.editar) {
          const remover = elemento('button', 'Remover');
          remover.type = 'button';
          remover.onclick = () => row.remove();
          row.insertCell().append(remover);
        }
      }
      for (const linha of dados.linhas) adicionar(linha);
      if (dados.editar) {
        const novo = elemento('button', 'Adicionar tributo');
        novo.type = 'button';
        novo.onclick = () => adicionar();
        const salvar = elemento('button', 'Salvar tributos');
        salvar.type = 'submit';
        form.append(novo, salvar);
        form.onsubmit = async event => {
          event.preventDefault();
          salvar.disabled = true;
          try {
            const linhas = Array.from(body.rows, row => Object.fromEntries(Array.from(row.querySelectorAll('input,select'), input => [input.name, input.value.trim()])));
            const resposta = await api({acao: 'v2_tributos_salvar', origem, registro: String(registro), versao: dados.versao, linhas});
            dados.versao = resposta.versao;
            status.textContent = 'Tributos salvos.';
          } catch (error) {
            status.textContent = error.message;
          } finally {
            salvar.disabled = false;
          }
        };
      }
      dialog.append(form);
    } catch (error) {
      status.textContent = error.message;
    } finally {
      abrir.disabled = false;
    }
  };
  return abrir;
}
