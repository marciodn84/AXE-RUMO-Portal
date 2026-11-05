-- Execute dentro de BEGIN/ROLLBACK. Dados sintéticos; nenhum pedido real é recebido.
do $test$
declare dia date:=(now() at time zone 'America/Sao_Paulo')::date;uid uuid;fid bigint;prod public.produtos_conciliacao;pid uuid:=gen_random_uuid();iid uuid:=gen_random_uuid();cnpj text;k text;dv int;soma int:=0;peso int:=2;j int;xml_text text;doc jsonb;prev jsonb;decision jsonb;payload jsonb;finance jsonb;paids uuid[];res jsonb;before_count bigint;failed boolean;newid uuid:=gen_random_uuid();n uuid;parcela public.imp_parcelas;begin
 select m.usuario_id into uid from public.gestao_membros m join public.axe_rumo_revisores r on r.usuario_id=m.usuario_id and r.ativo where m.ativo and m.papel='ADMIN'limit 1;
 select id,regexp_replace(f.cnpj,'\D','','g') into fid,cnpj from public.fornecedores f where ativo and pais='BR'and length(regexp_replace(f.cnpj,'\D','','g'))=14 limit 1;
 select * into prod from public.produtos_conciliacao where ativo and not bloqueado_comercial and controla_estoque and unidade_referencia is not null and forma_obtencao='TER'limit 1;
 assert uid is not null and fid is not null and prod.id is not null,'Contexto cadastral ausente';
 insert into public.imp_pedidos(id,fornecedor_id,referencia,moeda,status,data_pedido,forma_pagamento,atualizado_por)values(pid,fid,'TESTE-FIN-'||left(pid::text,8),'BRL','Enviado',dia,'ANTECIPADO',uid);
 insert into public.imp_pedido_itens(id,pedido_id,produto_id,linha,descricao,unidade,quantidade,valor_unitario)values(iid,pid,prod.id,'1','Produto sintético financeiro',prod.unidade_referencia,2,100);
 perform public.axe_imp_programar_parcelas(pid,uid);
 assert(select count(*)from public.imp_parcelas where pedido_id=pid and status='Prevista')=1;
 assert(select valor=200 and vencimento=dia and financeiro->>'fase'='Adiantamento'from public.imp_parcelas where pedido_id=pid and status='Prevista');
 update public.imp_pedidos set forma_pagamento='PARCELADO',previsao_entrega=dia+10,programacao_financeira='[{"percentual":50,"dias":30,"base":"Entrega"},{"percentual":50,"dias":60,"base":"Entrega"}]'where id=pid;
 perform public.axe_imp_programar_parcelas(pid,uid);perform public.axe_imp_programar_parcelas(pid,uid);
 assert(select count(*)from public.imp_parcelas where pedido_id=pid and status='Prevista')=2,'Sem duplicar provisionamento';
 assert(select sum(valor)from public.imp_parcelas where pedido_id=pid and status='Prevista')=200;
 assert(select min(vencimento)from public.imp_parcelas where pedido_id=pid and status='Prevista')=dia+40;
 select array_agg(id order by vencimento)into paids from public.imp_parcelas where pedido_id=pid and status='Prevista';
 k:='35'||to_char(dia,'YYMM')||cnpj||'55001'||'000000789'||'1'||'12345678';
 for j in reverse 43..1 loop soma:=soma+substring(k,j,1)::int*peso;peso:=case when peso=9 then 2 else peso+1 end;end loop;dv:=case when soma%11<2 then 0 else 11-soma%11 end;k:=k||dv;
 xml_text:=format('<nfeProc xmlns="http://www.portalfiscal.inf.br/nfe"><NFe><infNFe Id="NFe%s"><ide><mod>55</mod><tpNF>1</tpNF><finNFe>1</finNFe><tpAmb>1</tpAmb><nNF>789</nNF><serie>1</serie><dhEmi>%sT10:00:00-03:00</dhEmi></ide><emit><CNPJ>%s</CNPJ><xNome>Fornecedor de teste</xNome></emit><dest><CNPJ>39893713000167</CNPJ></dest><det nItem="1"><prod><cProd>FIN-TESTE</cProd><xProd>Produto sintético financeiro</xProd><NCM>85044030</NCM><CFOP>5102</CFOP><uCom>%s</uCom><qCom>1</qCom><vProd>100.00</vProd><vUnCom>100.00</vUnCom><indTot>1</indTot></prod><imposto><ICMS><ICMS00><orig>0</orig></ICMS00></ICMS><IPI><IPITrib><vIPI>10.00</vIPI></IPITrib></IPI></imposto></det><total><ICMSTot><vNF>110.00</vNF><vProd>100.00</vProd><vIPI>10.00</vIPI></ICMSTot></total><cobr><dup><nDup>001</nDup><dVenc>%s</dVenc><vDup>55.00</vDup></dup><dup><nDup>002</nDup><dVenc>%s</dVenc><vDup>55.00</vDup></dup></cobr><pag><detPag><tPag>15</tPag><vPag>110.00</vPag></detPag></pag></infNFe><Signature xmlns="http://www.w3.org/2000/09/xmldsig#"/></NFe><protNFe><infProt><tpAmb>1</tpAmb><cStat>100</cStat><nProt>123456789012345</nProt><chNFe>%s</chNFe></infProt></protNFe></nfeProc>',k,dia,cnpj,prod.unidade_referencia,dia+30,dia+60,k);
 prev:=public.axe_compra_nfe(jsonb_build_object('acao','compra_nf_ler','pedido_id',pid,'xml',xml_text),uid);doc:=prev->'documento';
 assert doc->'pagamentos'->0->>'codigo'='15';assert jsonb_array_length(doc->'duplicatas')=2;
 select jsonb_build_object('produto_versao',c->'produto_versao','fornecedor_versao',c->'fornecedor_versao','conferido',true,'decisoes',(select jsonb_object_agg(x->>'campo',jsonb_build_object('acao','XML'))from jsonb_array_elements(c->'campos')x)) into decision from (select prev->'cadastros'->0->'opcoes'->0->'cadastro' c)z;
 finance:=jsonb_build_object('token',prev->'financeiro'->'token','conferido',true,'justificativa','Consolidação de nota parcial com IPI e duplicatas conferidas','parcelas',jsonb_build_array(
 jsonb_build_object('id',paids[1],'referencia','NF teste / 001','valor',55,'valor_nota',55,'vencimento',dia+30,'meio_pagamento','BOLETO'),
 jsonb_build_object('id',paids[2],'referencia','NF teste / 002','valor',55,'valor_nota',55,'vencimento',dia+60,'meio_pagamento','BOLETO'),
 jsonb_build_object('id',newid,'referencia','Saldo a receber','valor',100,'valor_nota',0,'vencimento',dia+70,'meio_pagamento','BOLETO')));
 payload:=jsonb_build_object('acao','compra_nf_confirmar','pedido_id',pid,'pedido_versao',prev->'pedido_versao','requisicao_id',gen_random_uuid(),'xml',xml_text,'nome','sintetico.xml','data_entrada',dia,'confirmado',true,'custos_conferidos',true,'justificativa','Nota sintética para testar estoque e financeiro na mesma transação','vinculos',jsonb_build_array(jsonb_build_object('linha',1,'pedido_item_id',iid,'fator','1','custo_total','110','salvar_fornecedor',true,'cadastro',decision)),'financeiro',finance);
 select count(*)into before_count from public.estoque_movimentos;
 failed:=false;begin perform public.axe_compra_nfe(jsonb_set(payload,'{financeiro,parcelas,0,valor_nota}','54'),uid);exception when raise_exception then failed:=true;end;assert failed,'Bloqueia financeiro divergente';
 assert(select count(*)from public.estoque_movimentos)=before_count,'Falha financeira reverte estoque';assert not exists(select 1 from public.compras_nfe_entradas where pedido_id=pid),'Falha reverte nota';
 res:=public.axe_compra_nfe(payload,uid);n:=(res->>'id')::uuid;
 assert public.axe_compra_nfe(payload,uid)=res,'Retry idempotente';
 prev:=public.axe_imp_estrutura(jsonb_build_object('acao','v2_listar','tipo','parcelas','origem','nacional','busca','TESTE-FIN-'||left(pid::text,8),'somente_abertas',true),uid);assert (prev->>'total')::int=3,'Parcelas disponíveis em Contas a pagar';assert prev->'linhas'->0->>'fornecedor' is not null;
 assert(select count(*)from public.estoque_movimentos)=before_count+1;
 assert(select sum(valor)from public.compras_nfe_parcelas where entrada_id=n and ativo)=110;
 assert(select sum(valor)from public.imp_parcelas where pedido_id=pid and status='Prevista')=210,'Nota parcial e saldo do pedido';
 assert(select sum(valor_pago)from public.imp_parcelas where pedido_id=pid)=0,'XML não registra pagamento bancário';
 failed:=false;begin perform public.axe_compra_nfe(payload||jsonb_build_object('requisicao_id',gen_random_uuid()),uid);exception when raise_exception then failed:=true;end;assert failed,'Token antigo bloqueado';
 select * into parcela from public.imp_parcelas where id=paids[1];
 perform public.axe_imp_estrutura(jsonb_build_object('acao','v2_salvar','tipo','parcelas','id',parcela.id,'versao',parcela.versao,'requisicao_id',gen_random_uuid(),'dados',to_jsonb(parcela)||jsonb_build_object('valor_pago',10,'data_pagamento',dia)),uid);
 assert(select valor_pago from public.imp_parcelas where id=paids[1])=10,'Pagamento usa o título consolidado mesmo com tributos acima do PO';
 failed:=false;begin perform public.axe_compra_nfe(jsonb_build_object('acao','compra_nf_estornar','pedido_id',pid,'id',n,'requisicao_id',gen_random_uuid(),'confirmado',true,'justificativa','Estorno após pagamento deve bloquear'),uid);exception when raise_exception then failed:=true;end;assert failed,'Protege pagamentos posteriores';
 update public.imp_parcelas set valor_pago=0,data_pagamento=null where id=paids[1];
 perform public.axe_compra_nfe(jsonb_build_object('acao','compra_nf_estornar','pedido_id',pid,'id',n,'requisicao_id',gen_random_uuid(),'confirmado',true,'justificativa','Estorno integral de teste com retorno da provisão'),uid);
 assert not exists(select 1 from public.compras_nfe_parcelas where entrada_id=n and ativo);
 assert(select sum(valor)from public.imp_parcelas where pedido_id=pid and status='Prevista')=200,'Restaura provisões';
 -- Adiantamento já realizado é vinculado à NF parcial sem gerar outra dívida pelo mesmo valor.
 update public.imp_parcelas set status='Cancelada'where id=paids[2];
 update public.imp_parcelas set valor=200,valor_pago=200,data_pagamento=dia,meio_pagamento='PIX',financeiro='{"automatico":false,"fase":"Adiantamento"}'where id=paids[1];
 update public.imp_pedidos set forma_pagamento='ANTECIPADO'where id=pid;
 perform public.axe_imp_programar_parcelas(pid,uid);
 assert(select sum(valor)from public.imp_parcelas where pedido_id=pid and status='Prevista')=200,'Não duplica adiantamento';
 prev:=public.axe_compra_nfe(jsonb_build_object('acao','compra_nf_ler','pedido_id',pid,'xml',xml_text),uid);
 select jsonb_build_object('produto_versao',c->'produto_versao','fornecedor_versao',c->'fornecedor_versao','conferido',true,'decisoes',(select jsonb_object_agg(x->>'campo',jsonb_build_object('acao','XML'))from jsonb_array_elements(c->'campos')x)) into decision from (select prev->'cadastros'->0->'opcoes'->0->'cadastro' c)z;
 select * into parcela from public.imp_parcelas where id=paids[1];
 finance:=jsonb_build_object('token',prev->'financeiro'->'token','conferido',true,'justificativa','Aproveitamento do adiantamento e provisão da diferença de tributo','parcelas',jsonb_build_array(
 jsonb_build_object('id',parcela.id,'referencia',parcela.referencia,'valor',200,'valor_nota',110,'vencimento',parcela.vencimento,'meio_pagamento','PIX'),
 jsonb_build_object('id',gen_random_uuid(),'referencia','Saldo fiscal a provisionar','valor',10,'valor_nota',0,'vencimento',dia+70,'meio_pagamento','BOLETO')));
 payload:=payload||jsonb_build_object('requisicao_id',gen_random_uuid(),'pedido_versao',prev->'pedido_versao','financeiro',finance);
 payload:=jsonb_set(payload,'{vinculos,0,cadastro}',decision);
 res:=public.axe_compra_nfe(payload,uid);
 assert(select sum(valor_pago)from public.imp_parcelas where pedido_id=pid)=200,'Preserva pagamento comprovado';
 assert(select sum(valor)-sum(valor_pago)from public.imp_parcelas where pedido_id=pid and status='Prevista')=10,'Não cria segunda dívida de 110';
 assert(select valor from public.compras_nfe_parcelas where entrada_id=(res->>'id')::uuid and parcela_id=paids[1])=110;
 failed:=false;begin perform public.axe_compra_fin_contexto(pid,null);exception when raise_exception then failed:=true;end;assert failed,'Bloqueia usuário ausente';
 set constraints all immediate;
end $test$;
