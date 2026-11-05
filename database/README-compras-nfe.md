# Entrada nacional de NF-e vinculada ao pedido

No pedido nacional, abrir **Notas fiscais de entrada · XML**, selecionar o XML processado (até 2 MB), conferir os vínculos, a data, as conversões e os custos e confirmar. O fluxo não exige embarque ou DI/DUIMP; pedidos com embarque ativo permanecem no fluxo existente.

A confirmação grava o XML original privado, os dados fiscais extraídos, os vínculos por linha, o recebimento do pedido e as entradas de estoque na mesma transação. A chave ativa é única; repetir a mesma requisição após timeout retorna o resultado anterior. Quantidades superiores ao saldo são bloqueadas. Estorno da nota é integral, mantém o histórico e usa as regras existentes de disponibilidade e custo para não estornar estoque consumido. Depois do estorno, é possível conferir e registrar novamente o mesmo XML.

## Unidade do fornecedor

A unidade do XML e o fator confirmado são salvos em `produtos_fornecedores.unidade_compra` e `fator_conversao`, visíveis na aba Fornecedor do produto. Não há alteração da unidade AXE. Um novo vínculo fica em avaliação, sem aprovação comercial automática. A referência existente conserva sua situação; referências bloqueadas/inativas impedem a entrada. Não se presume equivalência entre unidades diferentes. A conversão exige confirmação e justificativa; notas futuras sugerem o fator cadastrado.

## Limites explícitos

- Compra nacional normal modelo 55, XML de produção com protocolo 100/150 e elemento de assinatura. Confere chave e dígito, emitente do pedido, destinatário AXE, somas e campos obrigatórios. Não consulta SEFAZ, não valida criptograficamente o certificado/assinatura e não substitui a escrituração fiscal.
- Uma linha XML é vinculada integralmente a um item do pedido. O produto e a unidade AXE devem estar cadastrados e a unidade do pedido deve coincidir com a unidade AXE. Recebimentos parciais do pedido são permitidos.
- O custo bruto de referência inclui o valor dos produtos menos desconto, mais frete, seguro, outras despesas, IPI, ST e FCP-ST. Créditos fiscais não são presumidos. O usuário confere o custo total de estoque por linha; diferenças exigem justificativa. Composições especiais, como desoneração, II ou IPI devolvido, são bloqueadas neste fluxo.
- Preserva o XML integral, inclusive IBS/CBS e cobrança. Com `compras_financeiro_nacional.sql`, duplicatas e meios de pagamento integram a conferência financeira obrigatória. A confirmação consolida os títulos e provisões na mesma transação da entrada de estoque. Não transmite notas nem realiza escriturações.
- Ações exigem sessão verificada no backend, revisor ativo e membro ativo. Escrita exige ADMIN/EDITOR. Tabelas e funções sem acesso direto de anon/authenticated; serviço autorizado executa como invoker com search_path fixo.

## Publicação e testes

Aplicar `compras_nfe_xml.sql` uma única vez e publicar `backend/axe-compras-nfe.ts` como `axe-compras-nfe` com verificação JWT. A interface está em `portal/`, conforme `wrangler.jsonc`; os arquivos fiscais nunca entram no pacote público.

Testes: `tests/compras-nfe.sql` é executado em BEGIN/ROLLBACK, com um XML privado de fixture via `axe.test_xml`; cobre parsing decimal, conferência obrigatória, conversão, excesso de saldo, duplicidade, retry, autorização, DTD, destinatário, estorno, nova entrada parcial e proteção contra alteração do pedido. `tests/edge-compras-nfe.mts` cobre autenticação, usuário confiável e allowlist. `tests/ui-compras-nfe.cjs` verifica a conferência e o retorno ao pedido em navegador, inclusive timeout sem duplicação. XMLs reais não pertencem ao repositório.

## Conferência cadastral e correção da obtenção

A ampliação `produto_obtencao_controlada.sql` e `compras_nfe_cadastro.sql` mantém o ID e o código histórico do produto. Administrador autorizado pode corrigir a obtenção mediante versão atual, justificativa e requisição idempotente; o cadastro comum continua impedindo alterações diretas. O histórico registra antes/depois e a justificativa.

A entrada passa a exigir aprovação cadastral antes da confirmação. Campos disponíveis no XML (NCM, CEST, GTIN, código/descrição e origem do fornecedor) completam os vazios. Divergências exigem decisão entre sugestão, cadastro atual com justificativa ou valor informado com justificativa. Part Number não é deduzido silenciosamente de cProd: a equivalência exige confirmação quando não existe PN confiável. Dados não informados no XML, como dimensões e fabricante, não são inventados. Após aprovação explícita, os dados conferidos ficam validados e a referência de compra aprovada, sem fila posterior para resolver estas divergências.

A origem informada pelo fornecedor fica no vínculo de compra; a sugestão de origem AXE considera a obtenção TER (1→2 e 6→7). Referência oficial da tabela: https://sefaz.pb.gov.br/legislacao/99-regulamentos/anexos-icms/1532-anexo-14-codigo-de-situacao-tributaria-cst . O usuário resolve divergências na entrada. A obtenção não é alterada pelo XML.

Notas já confirmadas oferecem **Completar cadastro pela NF-e**, que usa o XML preservado e registra as decisões sem gerar entrada de estoque. Concorrência no produto/referência exige refazer a conferência. Testes SQL e de navegador cobrem correção, versão, permissões, conferência obrigatória, divergência sem decisão, preenchimento, histórico, nova entrada e atualização de nota existente sem estoque duplicado.


## Financeiro nacional integrado

Aplicar `compras_financeiro_nacional.sql` uma vez, após as ampliações cadastrais e de programação automática. A alteração é aditiva e não recebe notas nem altera pagamentos históricos durante a publicação.

- O pedido em Elaboração permite rascunho. Ao salvar como Enviado ou posterior, exige condição financeira completa. Antecipado gera 100% na data do pedido; na entrega provisiona 100% pela previsão de entrega. Parcelado e a prazo usam percentuais, prazos e bases estruturados, cuja soma deve ser 100%. A previsão de entrega é obrigatória para provisionamento. O meio previsto é opcional e será resolvido na conferência da NF-e.
- A programação automática é atualizada enquanto não houver nota confirmada nem intervenção manual/pagamento nas parcelas. Parcelas manuais e pagamentos são preservados; eventual acréscimo gera somente provisão complementar. Depois de uma NF-e, as alterações financeiras passam pela conferência explícita do documento.
- O XML fornece duplicatas e o grupo `pag/detPag`. Códigos conhecidos sugerem o meio, sem registrar baixa bancária. Meios mistos ou não reconhecidos exigem escolha. Código 18 pode abranger carteira digital: a sugestão é sempre conferida pelo usuário.
- A conferência mostra todas as parcelas ativas. O usuário escolhe aproveitar a programação ou as duplicatas, informa vencimento e meio, distribui o valor da nota entre títulos e adiantamentos e mantém apenas a provisão das mercadorias não recebidas. Linhas de valor zero cancelam provisões substituídas; títulos pagos ou ligados a notas anteriores não podem ser alterados. Divergências exigem justificativa e confirmação antes da entrada.
- A soma financeira deve corresponder às notas confirmadas (incluindo a nova) mais o valor contratado das mercadorias ainda a receber. A soma vinculada à nota deve ser exatamente o total fiscal. Tributos/despesas podem justificar diferença em relação ao total comercial do pedido. Crédito de fornecedor ou adiantamento superior à obrigação total exige resolução financeira antes de confirmar, sem baixa ou crédito presumido.
- Locks no pedido, token do financeiro, versão do pedido e idempotência da requisição impedem concorrência e duplicidade. Erro de financeiro reverte também nota, estoque e atualização cadastral. Somente ADMIN/EDITOR autorizado acessa as ações de escrita; tabelas novas têm RLS e acesso restrito ao serviço.
- Estorno restaura a programação anterior e inativa os vínculos financeiros da nota. Pagamento, alteração ou nota posterior que mude esse estado impede o estorno até a resolução correspondente. Nada apaga o histórico de parcelas ou pagamentos.
- Notas históricas não são recebidas novamente nem recebem títulos por migração. Novas entradas passam obrigatoriamente pela conferência integrada.

As parcelas nacionais aparecem em Financeiro → Contas a pagar e como previsão em Fluxo de caixa, com consulta paginada, fornecedor, pedido, NF-e vinculada e abertura do pedido por ícone. O numerário das importações mantém seus registros. `compras_financeiro_consulta.sql` atualiza a consulta de instalações que receberam a primeira versão desta ampliação.

Validação: `tests/compras-financeiro-nacional.sql` em transação revertida cobre provisionamento, nota parcial com IPI, duplicatas, pagamento no título consolidado, rollback integral, retry, concorrência, estorno e adiantamento existente. `tests/ui-programacao-nacional.cjs`, `tests/ui-compras-nfe.cjs` e `tests/compras-financeiro-sugestoes.mjs` verificam os formulários e sugestões.
