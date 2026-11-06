const formato = new Intl.DateTimeFormat('pt-BR', {
  dateStyle: 'short', timeStyle: 'short', timeZone: 'America/Sao_Paulo'
});
export function dataHoraPesquisa(valor) {
  if (!valor || !String(valor).includes('T')) return '—';
  const data = new Date(valor);
  return Number.isNaN(data.getTime()) ? '—' : formato.format(data);
}
