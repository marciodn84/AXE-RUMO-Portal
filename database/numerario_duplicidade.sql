create or replace function public.axe_imp_numerario(p_dados jsonb,p_usuario uuid) returns jsonb language plpgsql set search_path='' as $$
declare a text:=p_dados->>'acao';papel text;pid uuid;did uuid;doc public.imp_num_documentos; n public.imp_numerarios;res jsonb;v numeric;dt date;item jsonb; old jsonb;eid uuid;begin
 select m.papel into papel from public.gestao_membros m join public.axe_rumo_revisores r on r.usuario_id=m.usuario_id and r.ativo where m.usuario_id=p_usuario and m.ativo;
 if papel is null then raise exception 'Usuário sem acesso';end if;
 if a='num_financeiro' then return jsonb_build_object('processos',(select coalesce(jsonb_agg(jsonb_build_object('processo_id',z.id,'referencia',(select string_agg(p.referencia||' / '||lpad(ip.parcial::text,2,'0'),', ') from public.imp_importacao_pedidos ip join public.imp_pedidos p on p.id=ip.pedido_id where public.axe_imp_processo_raiz(ip.processo_id)=z.id),'resumo',public.axe_num_resumo(z.id))),'[]') from public.imp_importacao_processos z where z.estado<>'Consolidado' and exists(select 1 from public.imp_numerarios nn where public.axe_imp_processo_raiz(nn.processo_id)=z.id)),'movimentos',(select coalesce(jsonb_agg(to_jsonb(m) order by m.data desc),'[]') from public.financeiro_num_movimentos m where not m.estornado));end if;
 pid:=public.axe_imp_processo_raiz(nullif(p_dados->>'processo_id','')::uuid);if not exists(select 1 from public.imp_importacao_processos where id=pid) then raise exception 'Processo não encontrado';end if;
 if a='num_contexto' then return jsonb_build_object('editar',papel in('ADMIN','EDITOR'),'resumo',public.axe_num_resumo(pid),'cadastro',(select to_jsonb(nn) from public.imp_numerarios nn where nn.processo_id=pid),'despachantes',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'nome',razao_social) order by razao_social),'[]') from public.fornecedores where ativo),'documentos',(select coalesce(jsonb_agg(to_jsonb(dd)-'caminho' order by dd.criado_em desc),'[]') from public.imp_num_documentos dd where public.axe_imp_processo_raiz(dd.processo_id)=pid and pronto),'movimentos',(select coalesce(jsonb_agg(to_jsonb(mm) order by mm.data desc),'[]') from public.financeiro_num_movimentos mm where public.axe_imp_processo_raiz(mm.processo_id)=pid),'despesas',(select coalesce(jsonb_agg(to_jsonb(de)||jsonb_build_object('comprovado',coalesce((select sum(c.valor) from public.imp_num_comprovantes c where c.despesa_id=de.id),0))),'[]') from public.financeiro_num_despesas de join public.imp_numerarios nn on nn.fechamento_id=de.documento_id where nn.processo_id=pid));end if;
 did:=nullif(p_dados->>'id','')::uuid;
 if a='num_arquivo' then select * into doc from public.imp_num_documentos where id=did and pronto and public.axe_imp_processo_raiz(processo_id)=pid;if not found then raise exception 'Arquivo não disponível';end if;return jsonb_build_object('nome',doc.nome,'caminho',doc.caminho);end if;
 if papel not in('ADMIN','EDITOR') then raise exception 'Sem permissão para alterar';end if;
 perform pg_advisory_xact_lock(728103147);
 if a='num_autorizar' then return '{}';end if;
 insert into public.imp_numerarios(processo_id)values(pid)on conflict do nothing;
 select * into n from public.imp_numerarios where processo_id=pid for update;old:=to_jsonb(n);
 if a='num_despachante' then
 if not exists(select 1 from public.fornecedores where id=(p_dados->>'despachante_id')::bigint and ativo and not bloqueado_comercial)then raise exception 'Escolha um despachante ativo e liberado';end if;
 if n.despachante_id is not null and n.despachante_id<>(p_dados->>'despachante_id')::bigint and exists(select 1 from public.financeiro_num_movimentos where processo_id=pid)then raise exception 'Há movimentos para o despachante atual. Corrija os vínculos antes de trocar';end if;
 update public.imp_numerarios set despachante_id=(p_dados->>'despachante_id')::bigint where processo_id=pid;
 elsif a='num_reservar' then
 select * into doc from public.imp_num_documentos where sha256=p_dados->>'sha256';if found then if public.axe_imp_processo_raiz(doc.processo_id)<>pid or doc.categoria<>p_dados->>'categoria' or doc.dados is distinct from p_dados->'dados' then raise exception 'Arquivo já registrado com outro vínculo ou dados';end if;return jsonb_build_object('id',doc.id,'caminho',doc.caminho,'pronto',doc.pronto);end if;
 did:=(p_dados->>'requisicao_id')::uuid;
 insert into public.imp_num_documentos(id,processo_id,categoria,nome,sha256,caminho,dados,criado_por)values(did,pid,p_dados->>'categoria',left(p_dados->>'nome',200),p_dados->>'sha256',p_usuario::text||'/numerario/'||did||'.pdf',p_dados->'dados',p_usuario) returning * into doc;
 return jsonb_build_object('id',doc.id,'caminho',doc.caminho,'pronto',false);
 elsif a='num_confirmar' then
 select * into doc from public.imp_num_documentos where id=did and public.axe_imp_processo_raiz(processo_id)=pid for update;if not found then raise exception 'Reserva não encontrada';end if;if doc.pronto then return jsonb_build_object('id',did);end if;
 if n.despachante_id is null then raise exception 'Selecione o despachante';end if;
 if doc.categoria in('Adiantamento','Complemento','Devolução')then
 v:=(doc.dados->>'valor')::numeric;dt:=(doc.dados->>'data')::date;if v is null or v<=0 or dt is null then raise exception 'Valor e data do comprovante são obrigatórios';end if;
 if exists(select 1 from public.financeiro_num_movimentos mm join public.imp_num_documentos dd on dd.id=mm.documento_id where not mm.estornado and mm.tipo=doc.categoria and ((doc.dados->>'referencia_bancaria' is not null and dd.dados->>'referencia_bancaria'=doc.dados->>'referencia_bancaria')or(public.axe_imp_processo_raiz(mm.processo_id)=pid and mm.valor=v and mm.data=dt and (doc.dados->>'referencia_bancaria' is null or dd.dados->>'referencia_bancaria' is null))))then raise exception 'Possível pagamento duplicado. Consulte o movimento existente; use comprovante com identificação bancária distinta para outra transferência igual';end if;
 insert into public.financeiro_num_movimentos(processo_id,documento_id,tipo,valor,data,criado_por)values(pid,did,doc.categoria,v,dt,p_usuario);
 elsif doc.categoria='Numerário prévio' then
 v:=(doc.dados->>'valor')::numeric;if v is null or v<=0 then raise exception 'Valor do numerário obrigatório';end if;update public.imp_numerarios set previa=v where processo_id=pid;
 elsif doc.categoria='Fechamento' then
 if n.fechamento_id is not null and n.fechamento_id<>did and p_dados->>'substituir' is distinct from n.fechamento_id::text then raise exception 'Já existe fechamento. Confirme a substituição preservando o anterior';end if;
 if jsonb_array_length(coalesce(doc.dados->'linhas','[]'))=0 or jsonb_array_length(coalesce(doc.dados->'resumo'->'avisos','[]'))>0 then raise exception 'Totais do fechamento não conferem';end if;
 for item in select value from jsonb_array_elements(doc.dados->'linhas') loop
 if item->>'classe'='Revisar' or(item->>'classe'='Financeiro' and item->>'tipo'='D' and upper(translate(item->>'descricao','çãõéáíóúê','caoeaioue')) !~ 'DEVOL|ESTORNO')then raise exception 'Classificação financeira não identificada no fechamento';end if;
 if item->>'tipo'='D' and item->>'classe'<>'Financeiro' then insert into public.financeiro_num_despesas(documento_id,linha,descricao,classe,valor,data)values(did,item->>'id',item->>'descricao',item->>'classe',(item->>'valor')::numeric,(item->>'data')::date);end if;end loop;
 update public.imp_numerarios set fechamento_id=did where processo_id=pid;
 end if;
 update public.imp_num_documentos set pronto=true where id=did;
 elsif a='num_vincular' then
 select * into doc from public.imp_num_documentos where id=did and pronto and public.axe_imp_processo_raiz(processo_id)=pid and categoria in('Comprovante de despesa','Fechamento');if not found then raise exception 'Selecione um comprovante deste processo';end if;
 eid:=(p_dados->>'despesa_id')::uuid;v:=(p_dados->>'valor')::numeric;
 if not exists(select 1 from public.financeiro_num_despesas d where d.id=eid and d.documento_id=n.fechamento_id and v>0 and v<=d.valor-coalesce((select sum(c.valor) from public.imp_num_comprovantes c where c.despesa_id=eid and c.documento_id<>did),0))then raise exception 'Valor excede a despesa ou vínculo de outro fechamento';end if;
 if doc.categoria='Comprovante de despesa' and (doc.dados->>'valor')::numeric is not null and v+coalesce((select sum(c.valor) from public.imp_num_comprovantes c where c.documento_id=did and c.despesa_id<>eid),0)>(doc.dados->>'valor')::numeric then raise exception 'Valor excede o comprovante';end if;
 insert into public.imp_num_comprovantes values(eid,did,v)on conflict(despesa_id,documento_id)do update set valor=excluded.valor;
 elsif a='num_estornar' then
 if length(trim(coalesce(p_dados->>'motivo','')))<5 then raise exception 'Informe o motivo do estorno';end if;
 update public.financeiro_num_movimentos set estornado=true where id=did and public.axe_imp_processo_raiz(processo_id)=pid and not estornado;if not found then raise exception 'Movimento não disponível';end if;
 elsif a='num_conciliar' then
 res:=public.axe_num_resumo(pid);
 if not(res->>'fechamento')::boolean or (res->>'saldo')::numeric<>0 or (res->>'comprovantes_bancarios_pendentes')::numeric<>0 or(res->>'despesas_sem_comprovante')::int<>0 then raise exception 'Resolva o saldo e os comprovantes pendentes antes de conciliar';end if;
 update public.imp_numerarios set conciliado_em=now(),conciliado_por=p_usuario where processo_id=pid;
 else raise exception 'Ação não permitida';end if;
 if a<>'num_conciliar' then update public.imp_numerarios set conciliado_em=null,conciliado_por=null where processo_id=pid;end if;
 update public.imp_numerarios set versao=versao+1 where processo_id=pid;
 insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('numerario',pid,p_usuario,old,jsonb_build_object('acao',a,'dados',p_dados-'conteudo','resumo',public.axe_num_resumo(pid)));
 return jsonb_build_object('id',did,'resumo',public.axe_num_resumo(pid));
end $$;
