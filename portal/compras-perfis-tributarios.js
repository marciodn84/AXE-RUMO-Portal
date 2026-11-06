export const perfisCompra = {
  PRODUTO_NACIONAL: 'Produto nacional',
  PRODUTO_IMPORTADO: 'Produto importado',
  SERVICO_NACIONAL: 'Serviço nacional',
  SERVICO_IMPORTADO: 'Serviço importado'
};

export async function mostrarPerfisCompra(destino, api) {
  const dados = await api({acao: 'v2_perfis_tributarios_ler'});
  if (!destino.isConnected) return;
  const intro = document.createElement('p');
  intro.textContent = 'Selecione os tributos disponíveis em cada perfil. O documento fiscal fornece os valores e as alíquotas da operação.';
  destino.append(intro);
  for (const [perfil, nome] of Object.entries(perfisCompra)) {
    const grupo = document.createElement('fieldset');
    const titulo = document.createElement('legend');
    titulo.textContent = nome;
    const status = document.createElement('p');
    status.setAttribute('role', 'status');
    let versao = dados.perfis[perfil]?.versao ?? 0;
    status.textContent = versao ? 'Perfil configurado.' : 'Perfil ainda não configurado.';
    grupo.append(titulo, status);
    const opcoes = document.createElement('div');
    opcoes.className = 'import-mapping';
    const controles = dados.catalogo.map(imposto => {
      const label = document.createElement('label');
      label.style.cssText = 'display:flex;flex-direction:row;align-items:center;gap:8px';
      const input = document.createElement('input');
      input.type = 'checkbox';
      input.style.cssText = 'width:18px;min-height:18px';
      input.value = imposto;
      input.checked = dados.perfis[perfil]?.impostos.includes(imposto) ?? false;
      input.disabled = !dados.editar;
      label.append(input, document.createTextNode(imposto));
      opcoes.append(label);
      return input;
    });
    grupo.append(opcoes);
    if (dados.editar) {
      const salvar = document.createElement('button');
      salvar.type = 'button';
      salvar.textContent = 'Salvar ' + nome.toLowerCase();
      salvar.onclick = async () => {
        salvar.disabled = true;
        controles.forEach(input => input.disabled = true);
        try {
          const impostos = controles.filter(input => input.checked).map(input => input.value);
          const r = await api({acao: 'v2_perfis_tributarios_salvar', perfil, versao, impostos});
          versao = r.versao;
          status.textContent = 'Perfil salvo.';
        } catch (erro) {
          status.textContent = erro.message;
        } finally {
          controles.forEach(input => input.disabled = false);
          salvar.disabled = false;
        }
      };
      grupo.append(salvar);
    }
    destino.append(grupo);
  }
}
