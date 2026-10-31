create index imp_importacao_fornecedor on public.imp_importacao_processos(fornecedor_id,moeda,estado,criado_em);
create index imp_importacao_consolidado on public.imp_importacao_processos(consolidado_em) where consolidado_em is not null;
create index imp_importacao_criado_por on public.imp_importacao_processos(criado_por);
create index imp_remessa_processos_pedido on public.imp_remessa_processos(pedido_id,processo_id);
create index imp_remessa_processos_usuario on public.imp_remessa_processos(usuario_id);
create index imp_pedidos_forma_pagamento on public.imp_pedidos(forma_pagamento);
create index imp_parcelas_meio_pagamento on public.imp_parcelas(meio_pagamento);
