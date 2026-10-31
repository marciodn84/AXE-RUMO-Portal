"""Bridge from the existing Outlook connector's materialized file to ERP bytes.
No Outlook authentication, mailbox scan, or secondary collector is created here.
"""
import base64
import hashlib
import json
import subprocess
from urllib.parse import urlsplit

MAX_BYTES=8*1024*1024

def baixar_original(attachment, download=None):
    if attachment.get('payload_status')!='materialized':
        raise ValueError('ANEXO_NAO_MATERIALIZADO')
    uri=attachment.get('file_uri') or {}
    url=uri.get('download_url') if isinstance(uri,dict) else None
    parsed=urlsplit(url or '')
    # Only exact, signed connector storage hosts; never URLs found in e-mail text.
    if parsed.scheme!='https' or parsed.username or parsed.password or parsed.port not in (None,443) or not parsed.hostname or not parsed.hostname.endswith('.oaiusercontent.com') or parsed.fragment:
        raise ValueError('ORIGEM_DE_DOWNLOAD_INVALIDA')
    if download is None:
        r=subprocess.run(['curl','--fail','--silent','--show-error','--max-time','45','--max-filesize',str(MAX_BYTES),url],capture_output=True)
        if r.returncode:
            raise IOError('FALHA_AO_RECUPERAR_ORIGINAL')
        data=r.stdout
    else:
        data=download(url)
    if not isinstance(data,bytes) or not 0<len(data)<=MAX_BYTES:
        raise ValueError('ANEXO_VAZIO_OU_ACIMA_DE_8MB')
    # Graph size_bytes is provider metadata, not a checksum of attachment bytes.
    return dict(anexo_id=attachment['id'],nome=attachment['name'],tipo_mime=attachment.get('content_type') or uri.get('mime_type') or 'application/octet-stream',
                conteudo=data,tamanho=len(data),tamanho_provedor=attachment.get('size_bytes'),sha256=hashlib.sha256(data).hexdigest())

def payload_arquivar(mensagem_id,original):
    return dict(mensagem_id=mensagem_id,anexo_id=original['anexo_id'],nome=original['nome'],conteudo_base64=base64.b64encode(original['conteudo']).decode('ascii'))

def sql_arquivar(mensagem_id,original,usuario):
    # Client-side file reads only. The server receives actual bytes, never a local path.
    import uuid
    principal=str(uuid.UUID(usuario));payload=json.dumps(payload_arquivar(mensagem_id,original)).replace("'","''")
    return "select public.axe_email_arquivar_original('"+payload+"'::jsonb,'"+principal+"'::uuid) as resultado;"

def sql_arquivar_partes(mensagem_id,original,usuario):
    """Bounded SQL calls; the server reconstructs one byte-identical original.
    Parts are a transport detail, not separate ERP documents.
    """
    import uuid
    principal=str(uuid.UUID(usuario));data=original['conteudo'];partes=(len(data)+32767)//32768
    for numero in range(partes):
        d={k:original[k] for k in ('anexo_id','nome','sha256')}
        d.update(mensagem_id=mensagem_id,parte=numero,partes=partes,
                 conteudo_base64=base64.b64encode(data[numero*32768:(numero+1)*32768]).decode('ascii'))
        payload=json.dumps(d).replace("'","''")
        yield "select public.axe_email_arquivar_parte('"+payload+"'::jsonb,'"+principal+"'::uuid) as resultado;"
