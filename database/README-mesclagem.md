# Mesclagem de cadastros

Clientes, Produtos e Fornecedores usam mesclagem explícita de dois IDs, com prévia e resolução dos campos divergentes. A prévia simula a transação e desfaz seus efeitos. O salvamento confere um hash dos cadastros e vínculos para impedir decisões sobre dados alterados. A ausência de erro não substitui as escolhas de conflitos.

Execute cadastros_mesclar.sql, cadastros_mesclar_codigo_guard.sql e cadastros_mesclar_busca.sql nesta ordem; as funções de busca precisam existir antes de usar a API. O SQL referencia a estrutura já existente do ERP. Todas as novas funções são invoker, search_path vazio e service_role; o RPC verifica membro ADMIN/EDITOR e revisor ativo. Histórico privado com RLS e sem acesso direto do navegador.

Referências relacionais são transferidas via FKs; IDs de produtos no documento operacional de propostas também são substituídos. Valores, quantidades, IDs de transações e arquivos originais são preservados. Exceções nas proteções de documentos e custos finais permitem somente a troca de identidade presente em uma mesclagem EXECUTANDO na mesma transação; não permitem alterar valores. O histórico grava os dois cadastros integrais, as escolhas, resultado, usuário, data e snapshots dos vínculos anteriores. Nenhum documento PDF/XML é regravado. O registro absorvido fica inativo e aponta ao cadastro mantido; não pode ser editado.

A pesquisa inclui IDs, nomes e códigos anteriores, inclusive em cadeias de mesclagem. Códigos AXE anteriores são adicionados como identificadores; o código permanente do cadastro mantido é preservado. Novos vínculos relacionais que utilizarem um ID antigo são redirecionados por trigger. Novas tabelas precisam registrar FKs e instalar axe_mesclagem_referencias_guard ou resolver o ID por axe_cadastro_canonico antes de gravar.

CNPJs/documentos fiscais incompatíveis, unidades diferentes e colisões em subcadastros interrompem a mesclagem sem gravação parcial. O usuário deve resolver o vínculo incompatível antes de tentar novamente. Bloqueios comerciais nunca são removidos pela combinação.

## Estoque

Em 31/10/2026 o módulo Estoque e movimentações está previsto no menu, sem livro de entradas/saídas ou tabela de saldo. Existem apenas confirmações de entrada de importação por embarque. Estas continuam acessíveis através dos itens, notas e custos vinculados ao produto mantido. A prévia informa essa limitação; não inventa ou soma um saldo inexistente.

Quando o módulo de estoque for implementado, entradas/saídas devem manter os IDs de movimentos e sua rastreabilidade documental, com produto_id como FK para produtos_conciliacao. A mesclagem deve transferir as FKs de todos os movimentos e reunir posições por produto/local/lote/série, sem lançar entrada artificial, somar movimentos e saldos simultaneamente ou apagar transações. Recalcular quantidade e custo médio pelo livro, preservando custos de cada entrada. Se houver tabela materializada de saldos, sua consolidação precisa de rotina específica auditada antes de habilitar mesclagem com esse livro; colisões devem bloquear a operação até o tratamento correto. Não foi implementado um módulo de estoque nesta alteração.

## Verificação

- tests/cadastros-mesclar.sql: simula mesclagem dos três tipos com vínculos operacionais reais, custo de importação final, força constraints deferred e ROLLBACK.
- tests/cadastros-mesclar-protecoes.sql: CNPJ, autorização, prévia desatualizada, preservação de bloqueio, pesquisa antiga e proibição de editar absorvido.
- tests/ui-cadastros-mesclar.cjs: seleção, prévia sem gravação, escolha de conflitos, destino mantido, cancelamento e impedimentos.
