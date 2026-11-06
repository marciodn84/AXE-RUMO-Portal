import {perfisCompra} from './compras-perfis-tributarios.js?v=20261106-perfis17';
const impostos = ['ICMS', 'ICMS ST', 'ICMS destino', 'ICMS remetente', 'FCP', 'FCP ST', 'FCP destino', 'IPI', 'PIS', 'PIS ST', 'COFINS', 'COFINS ST', 'II', 'ISS', 'IBS estadual', 'IBS municipal', 'IBS monofásico', 'CBS', 'CBS monofásica', 'IS', 'IRRF', 'INSS', 'CSLL', 'CIDE', 'IOF'];
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
      const configurados = Array.isArray(dados.impostos_perfil) ? dados.impostos_perfil : impostos;
      if (dados.perfil) dialog.append(elemento('p', 'Perfil tributário · ' + perfisCompra[dados.perfil]));
      const fiscais = elemento('section');
      dialog.append(fiscais);
      mostrarTributos(fiscais, dados.fiscais);
      if (origem === 'venda' && dados.editar) {
        const vinculo = elemento('form');
        const label = elemento('label', 'XML da NF-e de venda');
        const arquivo = elemento('input');
        arquivo.type = 'file';
        arquivo.accept = '.xml,application/xml,text/xml';
        arquivo.required = true;
        label.append(arquivo);
        const confirmacao = elemento('label', 'Conferi que a NF-e corresponde integralmente a este pedido');
        const confirmado = elemento('input');
        confirmado.type = 'checkbox';
        confirmado.required = true;
        confirmacao.prepend(confirmado);
        const importar = elemento('button', 'Vincular XML e ler tributos');
        importar.type = 'submit';
        vinculo.append(label, confirmacao, importar);
        dialog.append(vinculo);
        vinculo.onsubmit = async event => {
          event.preventDefault();
          importar.disabled = true;
          try {
            const file = arquivo.files[0];
            if (!file || file.size > 2097152) throw Error('Selecione um XML de até 2 MB');
            const bytes = await file.arrayBuffer();
            const prefixo = new TextDecoder('latin1').decode(bytes.slice(0, 200));
            const encoding = prefixo.match(/encoding\s*=\s*["']([^"']+)/i)?.[1]?.toLowerCase() || 'utf-8';
            if (!['utf-8', 'utf8', 'iso-8859-1', 'windows-1252'].includes(encoding)) throw Error('Use XML em UTF-8 ou ISO-8859-1');
            const xml = new TextDecoder(encoding, {fatal: true}).decode(bytes);
            const nota = await api({acao: 'nf_venda_tributos_upload', pedido_id: Number(registro), confirmado: confirmado.checked, xml});
            const revisado = await api({acao: 'v2_tributos_ler', origem, registro: String(registro)});
            fiscais.replaceChildren();
            mostrarTributos(fiscais, revisado.fiscais);
            status.textContent = 'NF-e ' + nota.numero + ' vinculada.';
            vinculo.reset();
          } catch (error) {
            status.textContent = error.message;
          } finally {
            importar.disabled = false;
          }
        };
      }
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
          if (key === 'imposto') for (const imposto of new Set([...configurados, ...(linha.imposto ? [linha.imposto] : [])])) input.append(new Option(imposto, imposto));
          if (['base', 'aliquota', 'valor'].includes(key)) {
            input.type = 'number';
            input.min = '0';
            input.step = key === 'valor' ? '0.01' : 'any';
          }
          input.required = ['valor', 'referencia'].includes(key);
          input.value = linha[key] ?? (key === 'imposto' ? configurados[0] : key === 'natureza' ? naturezas[0] : '');
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
        novo.disabled = configurados.length === 0;
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
