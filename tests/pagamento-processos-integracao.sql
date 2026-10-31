set constraints all deferred;
do $test$
declare uid uuid;rm public.imp_remessas;f public.imp_cambio_arquivos;c public.imp_fin_documentos;pid uuid;prid uuid;payload jsonb;r jsonb;antes numeric;depois numeric;limite numeric;rejeitou boolean:=false;
begin
 select * into rm from public.imp_remessas order by criado_em limit 1;
 select * into f from public.imp_cambio_arquivos where id=rm.arquivo_id;
 select * into c from public.imp_fin_documentos where id=rm.contrato_id;
 select pa.pedido_id,pa.atualizado_por into pid,uid from public.imp_remessa_parcelas rp join public.imp_parcelas pa on pa.id=rp.parcela_id where rp.remessa_id=rm.id limit 1;
 select public.axe_imp_processo_raiz(pp.processo_id) into prid from public.imp_importacao_pedidos pp where pp.pedido_id=pid order by pp.parcial desc limit 1;
 delete from public.imp_remessa_processos where remessa_id=rm.id;
 select sum(valor) into antes from public.imp_remessa_parcelas where remessa_id=rm.id;
 payload:=jsonb_build_object('acao','pagdoc_aprovar','pedido_id',pid,'requisicao_id',gen_random_uuid(),'contrato_id',c.id,'versao_contrato',c.versao,'swift_arquivo_id',f.id,'arquivo',jsonb_build_object('sha256',f.sha256),'swift',jsonb_build_object('moeda',rm.moeda,'valor',rm.valor,'data',rm.data_pagamento,'referencia',c.referencia,'uetr',rm.uetr),'confirmado',true,'nao_duplicado',true,'dados',jsonb_build_object('processos',jsonb_build_array(jsonb_build_object('processo_id',prid,'pedido_id',pid,'valor',100))));
 r:=public.axe_pagamento_processos(payload,uid);
 select sum(valor) into depois from public.imp_remessa_parcelas where remessa_id=rm.id;if antes<>depois then raise exception 'Aplicar pagamento já registrado não pode pagá-lo novamente';end if;
 perform public.axe_pagamento_processos(payload,uid);
 select sum(valor) into depois from public.imp_remessa_processos where remessa_id=rm.id;if depois<>100 then raise exception 'Repetição deve ser idempotente: %',depois;end if;
 begin
  payload:=payload||jsonb_build_object('requisicao_id',gen_random_uuid(),'dados',jsonb_build_object('processos',jsonb_build_array(jsonb_build_object('processo_id',prid,'pedido_id',pid,'valor',rm.valor+1))));perform public.axe_pagamento_processos(payload,uid);
 exception when sqlstate 'P0001' then rejeitou:=true;end;
 if not rejeitou then raise exception 'Total acima do comprovante deve falhar';end if;
 -- Exercita o registro de uma quantia ainda não distribuída; tudo será revertido.
 delete from public.imp_remessa_processos where remessa_id=rm.id;
 delete from public.imp_remessa_parcelas where remessa_id=rm.id;
 payload:=payload||jsonb_build_object('requisicao_id',gen_random_uuid(),'dados',jsonb_build_object('processos',jsonb_build_array(jsonb_build_object('processo_id',prid,'pedido_id',pid,'valor',100))));
 perform public.axe_pagamento_processos(payload,uid);
 select sum(valor) into depois from public.imp_remessa_parcelas where remessa_id=rm.id;if depois<>100 then raise exception 'Parcela deve receber somente a quantia aplicada';end if;
end $test$;
