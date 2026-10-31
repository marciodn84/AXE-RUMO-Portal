import unittest,hashlib
from anexos_outlook import baixar_original,payload_arquivar
class AnexosTest(unittest.TestCase):
 def fixture(self):return dict(id='a',name='swift.pdf',content_type='application/pdf',size_bytes=500,payload_status='materialized',file_uri={'download_url':'https://storage.oaiusercontent.com/raw?sig=assinatura'})
 def test_bytes_do_conector_e_tamanho_real(self):
  a=baixar_original(self.fixture(),lambda u:b'%PDF-original')
  self.assertEqual(a['tamanho'],13);self.assertEqual(a['sha256'],hashlib.sha256(b'%PDF-original').hexdigest());self.assertEqual(payload_arquivar('m',a)['conteudo_base64'],'JVBERi1vcmlnaW5hbA==')
 def test_recusa_endereco_no_corpo_ou_host_falso(self):
  for url in ['http://storage.oaiusercontent.com/a','https://storage.oaiusercontent.com.evil.test/a','https://127.0.0.1/a','https://user:pass@storage.oaiusercontent.com/a']:
   f=self.fixture();f['file_uri']['download_url']=url
   with self.assertRaises(ValueError):baixar_original(f,lambda u:b'x')
 def test_nao_substitui_por_texto(self):
  with self.assertRaises(ValueError):baixar_original(self.fixture(),lambda u:'texto extraído')
if __name__=='__main__':unittest.main()
