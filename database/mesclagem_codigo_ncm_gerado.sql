CREATE OR REPLACE FUNCTION public.axe_produto_codigo_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare seq text;
begin
 if current_user='service_role' and TG_OP='UPDATE' and exists(select 1 from public.cadastros_mesclagens m where m.tipo='produto' and m.transacao=txid_current() and m.estado='EXECUTANDO' and ((m.origem_id=OLD.id and NEW.codigo_axe is null and (to_jsonb(NEW)-array['codigo_axe','codigo_anterior','chave_cadastro','mesclado_em_id','ativo','atualizado_em','ncm_capitulo','ncm_posicao','ncm_subposicao'])=(to_jsonb(OLD)-array['codigo_axe','codigo_anterior','chave_cadastro','mesclado_em_id','ativo','atualizado_em','ncm_capitulo','ncm_posicao','ncm_subposicao']))or(m.destino_id=OLD.id and OLD.codigo_axe is null and NEW.codigo_axe=m.origem_anterior->>'codigo_axe' and NEW.forma_obtencao is not distinct from m.origem_anterior->>'forma_obtencao')))then return NEW;end if;

 if TG_OP='UPDATE' and OLD.codigo_axe is not null and
 (NEW.codigo_axe is distinct from OLD.codigo_axe or NEW.forma_obtencao is distinct from OLD.forma_obtencao) then
  raise exception 'Código e forma de obtenção são permanentes; cadastre outro produto para outra origem de fornecimento';
 end if;
 if NEW.codigo_axe is not null and (TG_OP='INSERT' or OLD.codigo_axe is null) then
  raise exception 'O código Axe deve ser gerado automaticamente';
 end if;
 if NEW.codigo_axe is null and NEW.forma_obtencao is not null then
  seq := nextval('public.axe_produto_codigo_seq')::text;
  NEW.codigo_axe := NEW.forma_obtencao || '-' || case when length(seq)<6 then lpad(seq,6,'0') else seq end;
 end if;
 return NEW;
end $function$
