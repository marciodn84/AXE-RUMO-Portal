# Estoque e movimentações AXE

## Livro e custos

O módulo usa estoque_movimentos como livro imutável de entradas e saídas. Não existe saldo manual paralelo: estoque_saldos agrega quantidades e valores assinados do livro. Os valores são BRL líquidos dos créditos no caso de importação, usando custo_total final apurado. Cada entrada mantém valor total e custo unitário próprios; a saída usa o valor disponível dividido pela quantidade disponível. Na saída integral, usa o valor residual exato, evitando resíduo financeiro com quantidade zero. Quantidades/valores usam numeric, não float; arredondamento do lançamento em 6 casas e unitário em 8.

A valorização segue a ordem de registro (ordem), preservando a data operacional informada separadamente. Um lançamento retroativo não reavalia saídas já contabilizadas. Estornos criam uma contrapartida com os valores originais e não apagam movimentos. Entradas já consumidas ou que deixariam saldo/valor negativo ou custo residual sem quantidade não podem ser estornadas até regularizar os movimentos posteriores. Não há estoque negativo.

Novas movimentações manuais exigem produto existente, ativo, liberado, unidade e controle de estoque. Motivos são listas fechadas, com referência documental obrigatória; não são criados cadastros de produtos ou unidades por digitação livre. Saldo inicial só antes da primeira movimentação. Não foram importados saldos do Nomus nem inventados saldos iniciais. Não há reserva, multi-local, rastreamento de lotes/séries ou baixa automática de nota de venda nesta etapa.

## Importações

A entrada é liberada após recebimento integral, nota(s) conciliada(s), quantidades do XML vinculadas ao produto AXE e custo Final. A quantidade de estoque vem de imp_nota_vinculos.quantidade_axe, respeitando a conversão já conciliada entre unidade de compra e unidade AXE. O valor vem do custo_total por pedido_item_id do custo real; o unitário é esse valor dividido pela quantidade AXE. A soma dos itens deve fechar o custo total. Zero, provisório, recebimento incompleto, produto sem unidade e divergências documentais não são preenchidos por estimativa.

A confirmação da data de entrada e a finalização do custo acionam o hook de integração. Existe no máximo um lote por embarque/versão de custo, com uma entrada por item; repetição não duplica saldo. Custo, nota e confirmação que originaram estoque ativo ficam protegidos. Para corrigir, estornar o lote completo, reabrir/corrigir/finalizar o custo e integrar a nova versão. A versão estornada não pode ser reutilizada. A tela Importações apresenta prévia e pendências, sem gravar na leitura.

Os PDFs/XML originais permanecem nas importações, referenciados pela nota/embarque. O lote guarda o snapshot da origem; o movimento guarda o produto original e o usuário/data do lançamento. A integração não executa pagamento ou baixa de câmbio.

## Mesclagem

O FK estoque_movimentos.produto_id é transferido pela mesclagem existente. O guard aceita apenas essa troca de identidade durante a transação auditada; quantidade, tipo, valor, custo unitário, data, referência e cadastro_original ficam intactos. O saldo consolidado é a soma das posições líquidas, e a média passa a ser valor líquido total dividido pela quantidade total. O custo das saídas históricas não é reescrito. A prévia de mesclagem mostra os valores antes/depois. Os IDs/códigos antigos continuam pesquisáveis. Unidades incompatíveis impedem a mesclagem. Nenhuma entrada artificial é gerada para somar os saldos.

## Acesso, concorrência e operação

Tabelas privadas com RLS; acesso direto anon/authenticated revogado. O endpoint axe-estoque exige JWT e resolve o usuário pelo servidor; axe_estoque verifica revisor e membro ativo, ADMIN/EDITOR para gravação. As funções são invoker com search_path vazio. Gravações usam o mesmo lock de transação das importações/mesclagens e UUID de idempotência com comparação dos dados e usuário. Queries são paginadas em 50 registros.

Aplicar estoque_movimentacoes.sql após as migrações de importações/mesclagem, depois estoque_mesclagem.sql. Publicar backend/axe-estoque.ts no endpoint axe-estoque com verify_jwt=true e os arquivos do portal. Nenhuma integração de estoque é executada em lote durante a migração; embarques antigos elegíveis aparecem na tela para registro explícito.

Verificações: tests/estoque-livro.sql (média, saída, saldo negativo, idempotência, imutabilidade, mesclagem e estorno); tests/estoque-importacao.sql (conversão CAIXA/UN, custo final, entrada única, proteção e estorno completo); tests/ui-estoque.cjs e tests/edge-estoque.mts. Os testes SQL usam ROLLBACK e forçam constraints deferred antes de encerrar.
