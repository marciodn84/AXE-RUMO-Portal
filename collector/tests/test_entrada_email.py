import unittest
from entrada_email import EntradaEmail, preparar_mensagem

class EntradaTest(unittest.TestCase):
    def test_mesma_coleta_varios_agentes_com_retentativa_independente(self):
        msg=preparar_mensagem(dict(conta='teste@example.test',mensagem_id='m1',
            remetente='fornecedor@example.test',recebido_em='2026-10-29T12:00:00Z'),
            [('a1','ack.pdf','application/pdf',b'%PDF-test')])
        feitos=[];chamadas=[];falhar=[True]
        def request(d):
            chamadas.append(d)
            if d['acao']=='email_registrar':return dict(id='id1')
            if d['acao']=='email_detalhe':return dict(msg,processamentos=feitos)
            feitos.append(dict(agente=d['agente'],chave_processo=d['chave_processo']))
            return dict(ok=True)
        vistos=[]
        def compras(d):vistos.append(d);return dict(acao='ACK_AGUARDANDO_REVISAO')
        def financeiro(d):
            vistos.append(d)
            if falhar[0]:falhar[0]=False;raise ValueError('simulado')
            return dict(acao='SEM_PAGAMENTO_AUTOMATICO')
        entrada=EntradaEmail(request)
        a=entrada.distribuir(msg,dict(compras=compras,financeiro=financeiro))
        self.assertEqual(vistos[0],vistos[1])
        self.assertIsNot(vistos[0],vistos[1])
        self.assertEqual(a['agentes']['financeiro']['estado'],'PENDENTE')
        b=entrada.distribuir(msg,dict(compras=compras,financeiro=financeiro))
        self.assertEqual(b['agentes']['compras']['estado'],'JA_ANALISADO')
        self.assertEqual(b['agentes']['financeiro']['estado'],'ANALISADO')
        self.assertEqual(len(feitos),2)
        self.assertTrue(all(c['acao'].startswith('email_') for c in chamadas))

class ArquivamentoTest(unittest.TestCase):
    def test_falha_de_um_anexo_nao_perde_os_demais(self):
        calls=[]
        def request(d):
            calls.append(d)
            if d['acao']=='email_registrar':return {'id':'m'}
            if d['acao']=='email_anexar':
                if d['anexo_id']=='a1':raise ValueError('falha transitória')
                return {'arquivo_id':'f2'}
            if d['acao']=='email_detalhe':return {'processamentos':[],'arquivos':[{'sha256':'abc'}]}
            return {'ok':True}
        result=EntradaEmail(request).distribuir({}, {'financeiro':lambda d:{'proposta':{'tipo':'CONTRATO_CAMBIO','pendencias':[]}}},anexos=[('a1','a.pdf','application/pdf',b'a'),('a2','b.pdf','application/pdf',b'b')])
        self.assertEqual(len(result['falhas_arquivamento']),1)
        proposal=next(c for c in calls if c['acao']=='email_propor')
        self.assertTrue(proposal['pendencias'])
        self.assertEqual(len([c for c in calls if c['acao']=='email_anexar']),2)
    def test_originais_entregues_ao_agente(self):
        seen=[]
        def request(d):
            if d['acao']=='email_registrar':return {'id':'m'}
            if d['acao']=='email_anexar':return {'arquivo_id':'f'}
            if d['acao']=='email_detalhe':return {'processamentos':[]}
            return {'ok':True}
        EntradaEmail(request).distribuir({}, {'agente':lambda d:seen.append(d) or {}},anexos=[('a','a.pdf','application/pdf',b'%PDF-original')])
        self.assertEqual(seen[0]['originais'][0]['conteudo'],b'%PDF-original')

if __name__=='__main__':unittest.main()
