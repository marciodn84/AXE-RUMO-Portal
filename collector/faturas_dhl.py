"""Leitura de faturas de serviço DHL em anexos já arquivados."""
from datetime import datetime
from decimal import Decimal
from io import BytesIO
import re


def _unico(pattern, text):
    values = set(re.findall(pattern, text, re.I | re.M))
    return values.pop() if len(values) == 1 else None


def extrair(texto):
    if not re.search(r'FATURA DE SERVIÇO', texto, re.I) or not re.search(r'58[. ]?890[. ]?252[/ ]?0001[- ]?13', texto):
        return None
    numero = _unico(r'\bFatura:\s*(GRU[A-Z0-9]{5,30})\b', texto)
    emissao = _unico(r'Emissão:\s*(\d{2}/\d{2}/\d{4})', texto)
    vencimento = _unico(r'Prazo de Pagamento:\s*(\d{2}/\d{2}/\d{4})', texto)
    awb = _unico(r'^\s*(\d{10})\s+\d{2}/\d{2}/\d{4}\s', texto)
    total = _unico(r'Valor Total\s*\(BRL\)\s+[\d.,]+\s+[\d.,]+\s+([\d.]+,\d{2})', texto)
    if not all((numero, emissao, vencimento, awb, total)):
        return None
    return dict(numero=numero.upper(), awb=awb,
                emissao=datetime.strptime(emissao, '%d/%m/%Y').date().isoformat(),
                vencimento=datetime.strptime(vencimento, '%d/%m/%Y').date().isoformat(),
                valor=str(Decimal(total.replace('.', '').replace(',', '.'))))


def analisar_pdf(conteudo):
    import pdfplumber
    with pdfplumber.open(BytesIO(conteudo)) as pdf:
        return extrair('\n'.join(p.extract_text() or '' for p in pdf.pages[:20]))
