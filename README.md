# Portal AXE-RUMO

Interface de conciliação, notas fiscais e entregas. Acesso aos dados exige login e usuário autorizado no Supabase.

Este repositório público contém somente a interface. Não contém pedidos, PDFs, XMLs, fotos, senhas ou tokens. A chave publishable identifica o projeto e não substitui a autenticação e a autorização no backend.

O painel diferencia quantidade total, saldo, comprovação de entrega, conferência fiscal e alertas da RUMO. Aprovação e publicação no cadastro oficial são ações separadas.

Site: https://marciodn84.github.io/AXE-RUMO-Portal/

## Telas de cadastros

Após login: Clientes, Produtos, Pedidos e itens, Histórico de preços e Regras fiscais. Busca e paginação são executadas no servidor. O histórico abre na versão mais recente por pedido/item, com opção para incluir versões anteriores dos PDFs.

Clientes e produtos podem ser cadastrados e complementados. Endereços geram novas versões; equivalências de códigos e ativação/inativação de regras exigem confirmação. Pedidos e valores documentais são consultados; as alterações de pedido continuam no fluxo controlado de conciliação. Operações de manutenção registram usuário e antes/depois, verificam versões e usam identificação de operação para evitar repetição em timeout. Campos de impostos vazios não viram zero.

Clientes são separados pelo CNPJ completo de faturamento, com razão social e agrupamento comercial. O formulário exige CNPJ único e impede trocar a identidade de clientes existentes. Pedidos e regras exibem o CNPJ; os códigos do cliente são identificados pelo CNPJ, sem compartilhar equivalência automaticamente entre empresas do grupo.

Aba **Resolver pendências**: lista de referências de descrição, unidade e NCM dos produtos, mais vínculos de códigos pendentes. Escolha um valor entre as fontes apresentadas e clique em **Salvar escolha**; a alteração do cadastro e a auditoria ocorrem na mesma operação. **Ver escolhas salvas** abre o histórico. Não altera documentos, pedidos no SAP ou regras fiscais. Pendências sem fonte abrem **Completar cadastro**.
