begin;
do $$ declare pid uuid;uid uuid:='f296afe4-eca8-48ad-a79a-388188988730';d uuid;fc uuid;pr uuid;expense uuid;s jsonb;counter int;begin
 select id into pid from public.imp_importacao_processos where estado='Aberto' limit 1;
 perform public.axe_imp_numerario(jsonb_build_object('acao','num_despachante','processo_id',pid,'despachante_id',(select id from public.fornecedores where ativo and not bloqueado_comercial limit 1)),uid);
 -- Manual advance is a real fact but remains pending documentary evidence.
 perform public.axe_imp_numerario(jsonb_build_object('acao','num_movimento','processo_id',pid,'id',gen_random_uuid(),'tipo','Adiantamento','valor',1000,'data','2026-10-31'),uid);
 s:=public.axe_num_resumo(pid);if(s->>'movimentos_sem_comprovante')::int<>1 then raise exception 'Missing proof not flagged';end if;
 -- Official transfer 1000, no expense until closing.
 d:=gen_random_uuid();insert into public.imp_num_documentos values(d,pid,'Adiantamento','TEST',md5(d::text)||md5(d::text),'test/'||d,false,'{"valor":"1000.00","data":"2026-10-31"}',uid,now());
 perform public.axe_imp_numerario(jsonb_build_object('acao','num_confirmar','processo_id',pid,'id',d),uid);
 perform public.axe_imp_numerario(jsonb_build_object('acao','num_confirmar','processo_id',pid,'id',d),uid);
 s:=public.axe_num_resumo(pid);if(s->>'movimentos_sem_comprovante')::int<>0 then raise exception 'Manual proof not linked';end if;if (s->>'enviados')::numeric<>1000 or(s->>'despesas')::numeric<>0 then raise exception 'Advance duplicate or expense';end if;
 -- Closing says 1000 credit, 800 expense => receivable 200, not a bank receipt.
 fc:=gen_random_uuid();insert into public.imp_num_documentos values(fc,pid,'Fechamento','TEST',md5(fc::text)||md5(fc::text),'test/'||fc,false,'{"linhas":[{"id":"1","tipo":"C","classe":"Financeiro","descricao":"Adiantamento","valor":"1000.00","data":"2026-10-31"},{"id":"2","tipo":"D","classe":"Despesa","descricao":"Honorários","valor":"800.00","data":"2026-10-31"}],"resumo":{"avisos":[]}}',uid,now());
 perform public.axe_imp_numerario(jsonb_build_object('acao','num_confirmar','processo_id',pid,'id',fc),uid);
 s:=public.axe_num_resumo(pid);if(s->>'a_receber')::numeric<>200 or(s->>'devolvidos')::numeric<>0 then raise exception 'Invented refund';end if;
 begin perform public.axe_imp_numerario(jsonb_build_object('acao','num_conciliar','processo_id',pid),uid);raise exception 'Should not reconcile';exception when raise_exception then if sqlerrm='Should not reconcile' then raise;end if;end;
 d:=gen_random_uuid();insert into public.imp_num_documentos values(d,pid,'Devolução','TEST',md5(d::text)||md5(d::text),'test/'||d,false,'{"valor":"200.00","data":"2026-10-31"}',uid,now());
 perform public.axe_imp_numerario(jsonb_build_object('acao','num_confirmar','processo_id',pid,'id',d),uid);
 pr:=gen_random_uuid();insert into public.imp_num_documentos values(pr,pid,'Comprovante de despesa','TEST',md5(pr::text)||md5(pr::text),'test/'||pr,true,'{"valor":"800.00"}',uid,now());
 select id into expense from public.financeiro_num_despesas where documento_id=fc;
 perform public.axe_imp_numerario(jsonb_build_object('acao','num_vincular','processo_id',pid,'id',pr,'despesa_id',expense,'valor',800),uid);
 perform public.axe_imp_numerario(jsonb_build_object('acao','num_conciliar','processo_id',pid),uid);
 s:=public.axe_num_resumo(pid);if(s->>'saldo')::numeric<>0 or s->>'conciliado_em' is null then raise exception 'Reconciliation failed';end if;
 perform public.axe_imp_numerario(jsonb_build_object('acao','num_estornar','processo_id',pid,'id',(select id from public.financeiro_num_movimentos where documento_id=d),'motivo','Teste de correção'),uid);
 s:=public.axe_num_resumo(pid);if(s->>'a_receber')::numeric<>200 or s->>'conciliado_em' is not null then raise exception 'Invalidation failed';end if;
 -- New official closing: 1200 expenses, complement 200 expected, no fabricated cash.
 pr:=gen_random_uuid();insert into public.imp_num_documentos values(pr,pid,'Fechamento','TEST',md5(pr::text)||md5(pr::text),'test/'||pr,false,'{"linhas":[{"id":"1","tipo":"C","classe":"Financeiro","descricao":"Adiantamento","valor":"1000.00","data":"2026-10-31"},{"id":"2","tipo":"D","classe":"Despesa","descricao":"Honorários","valor":"1200.00","data":"2026-10-31"}],"resumo":{"avisos":[]}}',uid,now());
 perform public.axe_imp_numerario(jsonb_build_object('acao','num_confirmar','processo_id',pid,'id',pr,'substituir',fc),uid);
 s:=public.axe_num_resumo(pid);if(s->>'a_pagar')::numeric<>200 or(s->>'enviados')::numeric<>1000 then raise exception 'Complement expected not correct';end if;
 d:=gen_random_uuid();insert into public.imp_num_documentos values(d,pid,'Complemento','TEST',md5(d::text)||md5(d::text),'test/'||d,false,'{"valor":"200.00","data":"2026-10-31"}',uid,now());
 perform public.axe_imp_numerario(jsonb_build_object('acao','num_confirmar','processo_id',pid,'id',d),uid);
 s:=public.axe_num_resumo(pid);if(s->>'a_pagar')::numeric<>0 or(s->>'despesas')::numeric<>1200 then raise exception 'Complement doubled expense';end if;
 begin perform public.axe_imp_numerario(jsonb_build_object('acao','num_contexto','processo_id',pid),gen_random_uuid());raise exception 'Unauthorized access accepted';exception when raise_exception then if sqlerrm='Unauthorized access accepted' then raise;end if;end;
 raise notice 'PASS: advance, duplicate, expense, refund, evidence, reconciliation, reversal';
end $$;
rollback;
