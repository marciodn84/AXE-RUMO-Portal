"""Distribui uma coleta já feita pelo plugin; não abre caixa postal nem cria login."""
import base64
import hashlib
import copy
import uuid

def preparar_mensagem(metadados, anexos):
    """anexos: iterable de (anexo_id, nome, tipo_mime, bytes). IDs vêm do conector."""
    campos = ('conta', 'mensagem_id', 'remetente', 'assunto', 'recebido_em', 'corpo_texto')
    mensagem = {k: metadados.get(k, '') for k in campos}
    if any(not isinstance(mensagem[k], str) or not mensagem[k].strip()
           for k in ('conta', 'mensagem_id', 'remetente', 'recebido_em')):
        raise ValueError('ORIGEM_DA_MENSAGEM_INCOMPLETA')
    mensagem['anexos'] = []
    ids = set()
    for anexo_id, nome, tipo_mime, conteudo in anexos:
        if not anexo_id or anexo_id in ids or not isinstance(conteudo, bytes):
            raise ValueError('ANEXO_INVALIDO_OU_DUPLICADO')
        ids.add(anexo_id)
        mensagem['anexos'].append(dict(anexo_id=anexo_id, nome=nome, tipo_mime=tipo_mime,
            tamanho=len(conteudo), sha256=hashlib.sha256(conteudo).hexdigest()))
    mensagem['anexos'].sort(key=lambda a: a['anexo_id'])
    return mensagem

class EntradaEmail:
    """request(payload) reutiliza a sessão autenticada da execução existente.

    Destino único: /functions/v1/axe-documentos-entrada no projeto AXE.
    Nenhuma senha, refresh token, cookie de Outlook ou service_role é recebida aqui.
    """
    def __init__(self, request):
        self.request = request

    def distribuir_materializados(self, metadados, attachments, agentes, etapa='triagem_v2', download=None):
        from anexos_outlook import baixar_original
        originais = [baixar_original(a, download) for a in attachments]
        anexos = [(a['anexo_id'],a['nome'],a['tipo_mime'],a['conteudo']) for a in originais]
        mensagem = preparar_mensagem(metadados, anexos)
        return self.distribuir(mensagem, agentes, etapa, anexos)

    def distribuir(self, mensagem, agentes, etapa='triagem_v1', anexos=None):
        anexos = list(anexos) if anexos is not None else None
        registro = self.request(dict(acao='email_registrar', mensagem=mensagem))
        falhas = []
        if anexos is not None:
            for anexo_id, nome, tipo_mime, conteudo in anexos:
                try:
                    result = self.request(dict(acao='email_anexar', mensagem_id=registro['id'],
                                  anexo_id=anexo_id, conteudo_base64=base64.b64encode(conteudo).decode('ascii')))
                    if not result.get('arquivo_id'):
                        raise ValueError('ARQUIVO_SEM_CONFIRMACAO')
                except Exception as erro:
                    falhas.append(dict(anexo_id=anexo_id, erro_tipo=type(erro).__name__))
        documento = copy.deepcopy(self.request(dict(acao='email_detalhe', id=registro['id'])))
        documento['falhas_arquivamento'] = falhas
        documento['originais'] = [dict(anexo_id=a,nome=n,tipo_mime=t,conteudo=b) for a,n,t,b in anexos or []]
        # A newly recovered original must trigger a fresh analysis, not reuse a metadata-only result.
        assinatura = '|'.join(sorted(a['sha256'] for a in documento.get('arquivos', []) if a.get('sha256')))
        if assinatura:
            etapa = etapa + ':' + hashlib.sha256(assinatura.encode()).hexdigest()[:16]
        feitos = {(p['agente'], p['chave_processo']) for p in documento['processamentos']}
        saidas = {}
        # O mesmo conteúdo é entregue a todos. Uma falha não marca outros agentes como feitos.
        # Callbacks devem devolver análise/encaminhamento, sem enviar e-mails nem executar pagamentos.
        for nome, analisar in agentes.items():
            if (nome, etapa) in feitos:
                saidas[nome] = dict(estado='JA_ANALISADO')
                continue
            try:
                resultado = analisar(copy.deepcopy(documento))
                if not isinstance(resultado, dict):
                    raise ValueError('RESULTADO_DE_ANALISE_INVALIDO')
                if 'proposta' in resultado:
                    proposta = copy.deepcopy(resultado['proposta'])
                    if falhas:
                        proposta.setdefault('pendencias', []).append('Arquivamento de '+str(len(falhas))+' anexo(s) não confirmado; reprocessar antes do aceite.')
                    chave = str(uuid.uuid5(uuid.NAMESPACE_URL, registro['id']+'|'+nome+'|'+etapa))
                    self.request(dict(proposta, acao='email_propor', mensagem_id=registro['id'],
                                      agente=nome, chave_processo=etapa, requisicao_id=chave))
                self.request(dict(acao='email_resultado', mensagem_id=registro['id'],
                                  agente=nome, chave_processo=etapa, resultado=resultado))
                saidas[nome] = dict(estado='ANALISADO')
            except Exception as erro:
                # Não imprimir conteúdo de mensagem nem credenciais em logs do GitHub.
                saidas[nome] = dict(estado='PENDENTE', erro_tipo=type(erro).__name__)
        return dict(mensagem_id=registro['id'], agentes=saidas, falhas_arquivamento=falhas)
