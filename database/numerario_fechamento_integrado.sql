create function public.axe_num_fechamento_importado()returns trigger language plpgsql set search_path='' as $$
declare f public.imp_fechamentos;pid uuid;did uuid;item jsonb;begin
 select * into f from public.imp_fechamentos where id=new.fechamento_id and pronto;
 select public.axe_imp_processo_raiz(processo_id) into pid from public.imp_importacao_embarques where embarque_id=f.embarque_id;
 if pid is null then return new;end if;
 insert into public.imp_numerarios(processo_id)values(pid)on conflict do nothing;
 select id into did from public.imp_num_documentos where sha256=f.sha256;
 if did is null then
 did:=gen_random_uuid();insert into public.imp_num_documentos(id,processo_id,categoria,nome,sha256,caminho,pronto,dados,criado_por)values(did,pid,'Fechamento',f.nome,f.sha256,f.caminho,true,f.revisado,f.criado_por);
 for item in select value from jsonb_array_elements(f.revisado->'linhas')loop
 if item->>'tipo'='D' and item->>'classe' in('Despesa','Tributo')then insert into public.financeiro_num_despesas(documento_id,linha,descricao,classe,valor,data)values(did,item->>'id',item->>'descricao',item->>'classe',(item->>'valor')::numeric,(item->>'data')::date);end if;end loop;
 end if;
 update public.imp_numerarios set fechamento_id=did,conciliado_em=null,conciliado_por=null,versao=versao+1 where processo_id=pid and (fechamento_id is null or fechamento_id=did);
 insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,atual)values('numerario',pid,new.criado_por,jsonb_build_object('acao','Fechamento importado nos custos e financeiro','documento_id',did));
 return new;
end $$;
create trigger numerario_fechamento_importado after insert on public.imp_fech_importacoes for each row execute function public.axe_num_fechamento_importado();
create function public.axe_num_preservar_consolidacao()returns trigger language plpgsql set search_path='' as $$begin
 if new.estado='Consolidado' and old.estado<>'Consolidado' and exists(select 1 from public.imp_num_documentos where processo_id=new.id)then raise exception 'Este processo possui numerário documentado. Preserve a conciliação separada antes de consolidar';end if;return new;end $$;
create trigger numerario_preservar_consolidacao before update on public.imp_importacao_processos for each row execute function public.axe_num_preservar_consolidacao();
revoke all on function public.axe_num_fechamento_importado(),public.axe_num_preservar_consolidacao() from public,anon,authenticated;
grant execute on function public.axe_num_fechamento_importado(),public.axe_num_preservar_consolidacao() to service_role;
