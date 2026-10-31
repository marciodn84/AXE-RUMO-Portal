create table public.imp_numerarios(
 processo_id uuid primary key references public.imp_importacao_processos(id), despachante_id bigint references public.fornecedores(id),
 previa numeric(18,2) check(previa>0), fechamento_id uuid, conciliado_em timestamptz, conciliado_por uuid, versao integer not null default 0);
create index on public.imp_numerarios(despachante_id);
create table public.imp_num_documentos(
 id uuid primary key,processo_id uuid not null references public.imp_importacao_processos(id),
 categoria text not null check(categoria in('Numerário prévio','Adiantamento','Complemento','Devolução','Fechamento','Comprovante de despesa')),
 nome text not null,sha256 text not null unique check(sha256~'^[a-f0-9]{64}$'),caminho text not null unique,
 pronto boolean not null default false,dados jsonb not null,criado_por uuid not null,criado_em timestamptz not null default now());
create index on public.imp_num_documentos(processo_id);
alter table public.imp_numerarios add foreign key(fechamento_id) references public.imp_num_documentos(id);
create table public.financeiro_num_movimentos(
 id uuid primary key default gen_random_uuid(),processo_id uuid not null references public.imp_importacao_processos(id),
 documento_id uuid unique references public.imp_num_documentos(id),tipo text not null check(tipo in('Adiantamento','Complemento','Devolução')),
 valor numeric(18,2) not null check(valor>0),data date not null,estornado boolean not null default false,criado_por uuid not null,criado_em timestamptz not null default now());
create index on public.financeiro_num_movimentos(processo_id);
create table public.financeiro_num_despesas(
 id uuid primary key default gen_random_uuid(),documento_id uuid not null references public.imp_num_documentos(id),linha text not null,
 descricao text not null,classe text not null,valor numeric(18,2) not null check(valor>0),data date,unique(documento_id,linha));
create table public.imp_num_comprovantes(
 despesa_id uuid not null references public.financeiro_num_despesas(id),documento_id uuid not null references public.imp_num_documentos(id),
 valor numeric(18,2) not null check(valor>0),primary key(despesa_id,documento_id));
create index on public.imp_num_comprovantes(documento_id);
do $$ declare t text;begin foreach t in array array['imp_numerarios','imp_num_documentos','financeiro_num_movimentos','financeiro_num_despesas','imp_num_comprovantes'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant all on public.%I to service_role',t);end loop;end $$;
create function public.axe_num_resumo(pid uuid) returns jsonb language plpgsql set search_path='' as $$
declare n public.imp_numerarios; f jsonb; cred numeric:=0; despesas numeric:=0; devol_doc numeric:=0; enviados numeric:=0; devolvidos numeric:=0; saldo numeric; pend integer:=0;begin
 select * into n from public.imp_numerarios where processo_id=pid;
 select dados into f from public.imp_num_documentos where id=n.fechamento_id and pronto;
 select coalesce(sum(valor) filter(where tipo<>'Devolução'),0),coalesce(sum(valor) filter(where tipo='Devolução'),0) into enviados,devolvidos from public.financeiro_num_movimentos where public.axe_imp_processo_raiz(processo_id)=pid and not estornado;
 if f is not null then
 select coalesce(sum((x->>'valor')::numeric) filter(where x->>'tipo'='C'),0),coalesce(sum((x->>'valor')::numeric) filter(where x->>'tipo'='D' and x->>'classe'='Financeiro'),0) into cred,devol_doc from jsonb_array_elements(f->'linhas')x;
 select coalesce(sum(valor),0),count(*) filter(where valor>coalesce((select sum(c.valor) from public.imp_num_comprovantes c where c.despesa_id=d.id),0)) into despesas,pend from public.financeiro_num_despesas d where documento_id=n.fechamento_id;
 saldo:=cred-devol_doc-despesas+greatest(0,enviados-cred)-greatest(0,devolvidos-devol_doc);
 else saldo:=null;end if;
 return jsonb_build_object('previa',n.previa,'enviados',enviados,'devolvidos',devolvidos,'despesas',despesas,'creditos_declarados',cred,'devolucoes_declaradas',devol_doc,'saldo',saldo,'a_pagar',case when f is null then greatest(0,coalesce(n.previa,0)-enviados) else greatest(0,-saldo) end,'a_receber',greatest(0,coalesce(saldo,0)),'movimentos_sem_comprovante',(select count(*) from public.financeiro_num_movimentos where processo_id=pid and not estornado and documento_id is null),'comprovantes_bancarios_pendentes',greatest(0,cred-enviados)+greatest(0,devol_doc-devolvidos),'despesas_sem_comprovante',pend,'fechamento',f is not null,'conciliado_em',n.conciliado_em);
end $$;
create function public.axe_imp_numerario(p_dados jsonb,p_usuario uuid) returns jsonb language plpgsql set search_path='' as $$
declare a text:=p_dados->>'acao';papel text;pid uuid;did uuid;doc public.imp_num_documentos; n public.imp_numerarios;res jsonb;v numeric;dt date;item jsonb; old jsonb;eid uuid;manual_id uuid;pagina_contagem integer;begin
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
 elsif a='num_movimento' then
 v:=(p_dados->>'valor')::numeric;dt:=(p_dados->>'data')::date;did:=(p_dados->>'id')::uuid;
 if n.despachante_id is null or v is null or v<=0 or dt is null or did is null or p_dados->>'tipo' not in('Adiantamento','Complemento','Devolução')then raise exception 'Preencha despachante, tipo, valor e data efetiva';end if;
 if exists(select 1 from public.financeiro_num_movimentos where id=did)then
 if not exists(select 1 from public.financeiro_num_movimentos where id=did and processo_id=pid and valor=v and data=dt and tipo=p_dados->>'tipo')then raise exception 'Identificador reutilizado';end if;return jsonb_build_object('id',did);end if;
 insert into public.financeiro_num_movimentos(id,processo_id,tipo,valor,data,criado_por)values(did,pid,p_dados->>'tipo',v,dt,p_usuario);
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
 if exists(select 1 from public.financeiro_num_movimentos mm join public.imp_num_documentos dd on dd.id=mm.documento_id where not mm.estornado and mm.documento_id is not null and mm.tipo=doc.categoria and ((doc.dados->>'referencia_bancaria' is not null and dd.dados->>'referencia_bancaria'=doc.dados->>'referencia_bancaria')or(public.axe_imp_processo_raiz(mm.processo_id)=pid and mm.valor=v and mm.data=dt and (doc.dados->>'referencia_bancaria' is null or dd.dados->>'referencia_bancaria' is null))))then raise exception 'Possível pagamento duplicado. Consulte o movimento existente; use comprovante com identificação bancária distinta para outra transferência igual';end if;
 select count(*),min(mm.id::text)::uuid into pagina_contagem,manual_id from public.financeiro_num_movimentos mm where mm.processo_id=pid and not mm.estornado and mm.documento_id is null and mm.tipo=doc.categoria and mm.valor=v and mm.data=dt;
 if pagina_contagem>1 then raise exception 'Mais de um registro manual corresponde ao comprovante. Corrija a duplicidade antes de vincular';end if;
 if manual_id is not null then update public.financeiro_num_movimentos set documento_id=did where id=manual_id;
 else insert into public.financeiro_num_movimentos(processo_id,documento_id,tipo,valor,data,criado_por)values(pid,did,doc.categoria,v,dt,p_usuario);end if;
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
 if not(res->>'fechamento')::boolean or (res->>'saldo')::numeric<>0 or (res->>'comprovantes_bancarios_pendentes')::numeric<>0 or(res->>'despesas_sem_comprovante')::int<>0 or(res->>'movimentos_sem_comprovante')::int<>0 then raise exception 'Resolva o saldo e os comprovantes pendentes antes de conciliar';end if;
 update public.imp_numerarios set conciliado_em=now(),conciliado_por=p_usuario where processo_id=pid;
 else raise exception 'Ação não permitida';end if;
 if a<>'num_conciliar' then update public.imp_numerarios set conciliado_em=null,conciliado_por=null where processo_id=pid;end if;
 update public.imp_numerarios set versao=versao+1 where processo_id=pid;
 insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('numerario',pid,p_usuario,old,jsonb_build_object('acao',a,'dados',p_dados-'conteudo','resumo',public.axe_num_resumo(pid)));
 return jsonb_build_object('id',did,'resumo',public.axe_num_resumo(pid));
end $$;
revoke all on function public.axe_num_resumo(uuid),public.axe_imp_numerario(jsonb,uuid) from public,anon,authenticated;
grant execute on function public.axe_num_resumo(uuid),public.axe_imp_numerario(jsonb,uuid) to service_role;
