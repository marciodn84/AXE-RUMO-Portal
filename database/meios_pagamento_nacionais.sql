-- Acrescenta meios de pagamento nacionais sem alterar registros existentes.
insert into public.compras_meios_pagamento(codigo,nome)
values ('BOLETO','Boleto'),('TRANSFERENCIA_BANCARIA','Transferência bancária')
on conflict(codigo) do nothing;
