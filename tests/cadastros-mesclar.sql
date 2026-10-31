begin;
set local role service_role;
do $$
declare uid uuid:='f296afe4-eca8-48ad-a79a-388188988730';typ text;tab text;sid bigint;did bigint;pre jsonb;res jsonb;ch jsonb;x jsonb;cnt bigint;aftercnt bigint;refs record;v text;v2 text;
begin
 insert into public.imp_custos(embarque_id,estado,dados,resultado,atualizado_por)select id,'Final','{}','{}',uid from public.imp_embarques limit 1 on conflict(embarque_id)do update set estado='Final';
 foreach typ in array array['fornecedor','produto','cliente']loop
 tab:=case typ when 'fornecedor'then 'fornecedores'when 'produto'then 'produtos_conciliacao'else 'clientes'end;
 if typ='fornecedor'then select fornecedor_id into sid from public.imp_pedidos limit 1;insert into public.fornecedores(razao_social)values('TESTE MESCLAGEM')returning id into did;
 elsif typ='produto'then select produto_id into sid from public.imp_pedido_itens where produto_id is not null limit 1;insert into public.produtos_conciliacao(descricao_referencia)values('TESTE MESCLAGEM')returning id into did;
 else select cliente_id into sid from public.pedidos where cliente_id is not null limit 1;insert into public.clientes(nome,legado_grupo)values('TESTE MESCLAGEM',true)returning id into did;end if;
 if sid is null then raise exception 'Fixture sem vínculo para %',typ;end if;
 execute format('select atualizado_em::text from public.%I where id=$1',tab)into v using sid;
 select count(*)into cnt from public.cadastros_mesclagens;
 pre:=public.axe_cadastro_mesclar(jsonb_build_object('acao','cadastro_mesclar_previa','tipo',typ,'origem_id',sid,'destino_id',did),uid);
 if jsonb_array_length(pre->'impedimentos')>0 then raise exception 'Prévia %: %',typ,pre->'impedimentos';end if;
 select count(*)into aftercnt from public.cadastros_mesclagens;if cnt<>aftercnt then raise exception 'Prévia alterou histórico';end if;
 execute format('select atualizado_em::text from public.%I where id=$1',tab)into v2 using sid;if v2<>v then raise exception 'Prévia alterou cadastro';end if;
 select coalesce(jsonb_object_agg(value->>'campo','origem'),'{}') into ch from jsonb_array_elements(pre->'campos')where(value->>'conflito')::boolean;
 res:=public.axe_cadastro_mesclar(jsonb_build_object('acao','cadastro_mesclar_salvar','tipo',typ,'origem_id',sid,'destino_id',did,'versao',pre->>'versao','escolhas',ch),uid);
 if not exists(select 1 from public.cadastros_mesclagens where id=(res->>'id')::uuid and estado='CONCLUIDA' and jsonb_array_length(vinculos)>0)then raise exception 'Histórico de vínculos ausente %',typ;end if;
 for refs in select k.conrelid::regclass rel,a.attname col from pg_constraint k join pg_attribute a on a.attrelid=k.conrelid and a.attnum=any(k.conkey)where k.contype='f' and k.confrelid=to_regclass('public.'||tab)and k.conrelid<>k.confrelid loop execute format('select count(*) from %s where %I=$1',refs.rel,refs.col)into cnt using sid;if cnt<>0 then raise exception 'Vínculo antigo não atualizado %',refs.rel;end if;end loop;
 if public.axe_cadastro_canonico(typ,sid)<>did then raise exception 'ID antigo não resolve';end if;
 if nullif(public.axe_cadastro_aliases(typ,did),'')is null then raise exception 'Pesquisa antiga ausente';end if;
 -- Nenhum estado comercial é desbloqueado pela mesclagem; seleção posterior do ID antigo redireciona.
 if typ='produto'then
 if public.axe_mesclagem_json('{"itens":[{"produto_id":1,"valor":100}]}'::jsonb,1,2)<>'{"itens":[{"produto_id":2,"valor":100}]}'::jsonb then raise exception 'Documento operacional alterou valor';end if;end if;
 end loop;
end $$;
set constraints all immediate;
rollback;
