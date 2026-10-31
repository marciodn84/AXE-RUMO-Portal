# Arquivamento de anexos na entrada única AXE

A agenda existente do ChatGPT permanece como coletor único Outlook. Este adaptador não cria login, agenda ou acesso independente ao correio.

1. Materializar anexos por `list_attachments` / `fetch_attachment`, preservando IDs exatos.
2. Baixar imediatamente `file_uri.download_url` com `baixar_original`. Usar os bytes retornados para tamanho e SHA-256; o tamanho Graph não é um checksum.
3. Para nova mensagem, `EntradaEmail.distribuir_materializados` prepara o envelope e arquiva os originais. Para envelope existente, `sql_arquivar` prepara chamada à RPC `axe_email_arquivar_original`; executar com o conector administrativo autorizado, nunca com credenciais exportadas.
4. Confirmar `arquivo_id`, tamanho e hash por releitura. Anexos de até 8 MB são preservados sem conversão. Uma falha não impede os demais; respeitar Retry-After e renovar URL vencida.
5. Compartilhar os mesmos originais entre os agentes. O conjunto de hashes versiona a análise, permitindo retomar etapas feitas somente com metadados.
6. Preparar propostas com dados dos documentos e mostrar apenas lacunas reais. Campos de origem podem ser reunidos de mensagens diferentes mediante referência documental explícita. O aceite é sempre do usuário.

## Contratos de câmbio

`aplicacao.arquivos_documentais` recebe os IDs e hashes dos PDFs arquivados, com categoria CONTRATO ou SWIFT. No aceite, a RPC vincula ambos ao contrato e mantém a proveniência. `fornecedor_proposto` recebe nome, país e endereço documentais; fornecedor estrangeiro ainda inexistente pode receber cadastro básico sem inventar identificação fiscal. Se existir mais de um correspondente, o aceite é bloqueado para escolha. O cadastro e o vínculo dos originais são transacionais.

`aplicacao.substitui_proposta_id` prepara uma nova versão de proposta Pendente do mesmo tipo e mensagem. A anterior permanece no histórico e não pode ser aprovada novamente. A listagem mostra a versão atual.

Não associar parcelas, pedidos ou invoices por coincidência de valor. SWIFT utiliza referência bancária explícita e campo 32A para liquidação. Quando o pedido não estiver identificado, o contrato pode ficar sem vínculo ao pedido; não baixar parcela por suposição.

## Evidências de verificação

Testes de download controlado, origem HTTPS, integridade por hash, falha independente por anexo, preservação de bytes e bloqueio de proposta incompleta. Testes de aceite no banco usam transação com rollback: não constituem aceite operacional do usuário.

## Transporte de arquivos maiores

Em chamadas SQL por ferramentas com limite de tamanho de texto, usar `sql_arquivar_partes` em vez de enviar o JSON completo. Cada chamada envia no máximo 32 KiB de bytes; `axe_email_arquivar_parte` recompõe o único original e verifica o SHA-256 antes de chamar o arquivamento privado. Partes repetidas são idempotentes e partes conflitantes são rejeitadas. A confirmação final deve conter `completo=true` e `arquivo_id`. Partes temporárias são privadas e expiram em 24 horas; não representam documentos separados. Nenhuma consulta exige leitura de arquivo no servidor.

A recuperação histórica de 30/10/2026 confirmou 72/72 anexos do inventário compartilhado, com SHA-256 e tamanho íntegros. Isso não equivale a cobertura integral da caixa postal: as mensagens ainda não inventariadas exigem a rotina incremental e sua reconciliação.
