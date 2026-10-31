CREATE OR REPLACE FUNCTION public.axe_fiscal_parametros_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare t jsonb; f public.fiscal_formulas%rowtype;
begin
 if current_user='service_role' and TG_OP='UPDATE' and public.axe_mesclagem_vinculo_permitido(TG_TABLE_NAME,to_jsonb(OLD),to_jsonb(NEW)) then return NEW;end if;
 for t in select value from jsonb_array_elements(NEW.tributos) loop
  if t->>'formula_id' is not null then
   if t->>'formula_id' !~ '^[0-9]+$' then raise exception 'Fórmula inválida';end if;
   select * into f from public.fiscal_formulas where id=(t->>'formula_id')::bigint;
   if not found then raise exception 'Fórmula inexistente';end if;
   if f.componentes ? (t->>'tributo') then raise exception 'A base não pode depender do próprio tributo';end if;
  end if;
  if t->>'efeito_total' is not null and t->>'efeito_total' not in ('EMBUTIDO','ACRESCIMO','NAO_COMPOE') then raise exception 'Efeito no total inválido';end if;
  if t->>'deduz_margem' is not null and jsonb_typeof(t->'deduz_margem')<>'boolean' then raise exception 'Informe o efeito na margem como sim ou não';end if;
 end loop;
 return NEW;
end $function$
;
CREATE OR REPLACE FUNCTION public.axe_fiscal_regra_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare t jsonb; k text; n public.fiscal_naturezas%rowtype; emp public.fiscal_estabelecimento%rowtype;
begin
 if current_user='service_role' and TG_OP='UPDATE' and public.axe_mesclagem_vinculo_permitido(TG_TABLE_NAME,to_jsonb(OLD),to_jsonb(NEW)) then return NEW;end if;
 select * into strict emp from public.fiscal_estabelecimento where id=1;
 select * into strict n from public.fiscal_naturezas where id=NEW.natureza_id;
 -- Inactivation must preserve the historical parameters even if the operation is inactive.
 if TG_OP='UPDATE' and OLD.situacao<>'RASCUNHO' then
  if (to_jsonb(NEW)-array['situacao','atualizado_em']) is distinct from (to_jsonb(OLD)-array['situacao','atualizado_em']) or NEW.situacao not in (OLD.situacao,'INATIVA') then raise exception 'Regra validada é imutável. Crie uma nova versão.';end if;
  NEW.atualizado_em:=clock_timestamp();return NEW;
 end if;
 if not n.ativo then raise exception 'Operação inativa';end if;
 if NEW.empresa_cnpj is not null and NEW.empresa_cnpj<>emp.cnpj then raise exception 'A empresa deve ser o estabelecimento fiscal da AXE';end if;
 if NEW.regime_tributario is not null and NEW.regime_tributario<>emp.regime_tributario then raise exception 'Regime deve ser o do estabelecimento da AXE';end if;
 NEW.empresa_cnpj:=emp.cnpj;NEW.regime_tributario:=emp.regime_tributario;
 NEW.ufs_contraparte:=array(select distinct upper(btrim(x)) from unnest(coalesce(NEW.ufs_contraparte,'{}')) x order by 1);
 NEW.paises_contraparte:=array(select distinct upper(btrim(x)) from unnest(coalesce(NEW.paises_contraparte,'{}')) x order by 1);
 if array_position(NEW.ufs_contraparte,null) is not null or not NEW.ufs_contraparte <@ array['AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO']::text[] then raise exception 'UF inválida';end if;
 if exists(select 1 from unnest(NEW.paises_contraparte) x where x is null or x !~ '^[A-Z]{2}$' or x='BR') then raise exception 'Informe países estrangeiros no formato ISO de duas letras';end if;
 if n.mercado='DOMESTICO' and cardinality(NEW.paises_contraparte)>0 or n.mercado='EXTERIOR' and cardinality(NEW.ufs_contraparte)>0 then raise exception 'Estados ou países incompatíveis com o mercado da operação';end if;
 if n.direcao='SAIDA' then
  if NEW.uf_origem is not null and NEW.uf_origem<>emp.uf then raise exception 'Origem da saída deve ser a AXE no Paraná';end if;
  NEW.uf_origem:=emp.uf;
  NEW.uf_destino:=case when n.mercado='EXTERIOR' then 'EX' when cardinality(NEW.ufs_contraparte)=1 then NEW.ufs_contraparte[1] else null end;
  NEW.pais_origem:=null;
 else
  if NEW.uf_destino is not null and NEW.uf_destino<>emp.uf then raise exception 'Destino da entrada deve ser a AXE no Paraná';end if;
  NEW.uf_destino:=emp.uf;
  NEW.uf_origem:=case when n.mercado='EXTERIOR' then 'EX' when cardinality(NEW.ufs_contraparte)=1 then NEW.ufs_contraparte[1] else null end;
  NEW.pais_origem:=case when cardinality(NEW.paises_contraparte)=1 then NEW.paises_contraparte[1] else null end;
  if NEW.municipio_destino is not null and NEW.municipio_destino is distinct from emp.municipio_ibge then raise exception 'Complete o município fiscal da AXE no estabelecimento antes de restringir a entrada';end if;
 end if;
 if (NEW.cliente_id is not null and NEW.fornecedor_id is not null) or (n.contraparte='CLIENTE' and NEW.fornecedor_id is not null) or (n.contraparte='FORNECEDOR' and (NEW.cliente_id is not null or NEW.perfil_destinatario_id is not null)) then raise exception 'Contraparte incompatível com a operação';end if;
 if NEW.cfop is not null then
  if NEW.cfop !~ (case when n.direcao='ENTRADA' then '^[123][0-9]{3}$' else '^[567][0-9]{3}$' end) or
    (n.mercado='EXTERIOR' and left(NEW.cfop,1)<>(case when n.direcao='ENTRADA' then '3' else '7' end)) or
    (n.mercado='DOMESTICO' and left(NEW.cfop,1) in ('3','7')) then raise exception 'CFOP incompatível com a direção e mercado';end if;
  if n.mercado='DOMESTICO' and cardinality(NEW.ufs_contraparte)>0 and exists(select 1 from unnest(NEW.ufs_contraparte) uf where left(NEW.cfop,1) <> case when n.direcao='ENTRADA' then case when uf=emp.uf then '1' else '2' end else case when uf=emp.uf then '5' else '6' end end) then raise exception 'O CFOP da regra não cobre todas as UFs selecionadas; use os CFOPs do tipo de operação';end if;
  if n.mercado='DOMESTICO' and cardinality(NEW.ufs_contraparte)=0 then raise exception 'Regra para todos os estados deve usar os CFOPs do tipo de operação';end if;
 end if;
 if NEW.situacao='VALIDADA' and n.operacao='VENDA' and (NEW.consumidor_final is null or NEW.finalidade_destinatario is null or NEW.sujeito_st is null) then raise exception 'Venda exige consumidor final, finalidade e condição de ST estruturados';end if;
 if TG_OP='UPDATE' and OLD.situacao<>'RASCUNHO' and
 (to_jsonb(NEW)-array['situacao','atualizado_em']) is distinct from (to_jsonb(OLD)-array['situacao','atualizado_em']) then
  raise exception 'Regra validada é imutável. Crie uma nova versão.';
 end if;
 if TG_OP='UPDATE' and OLD.situacao<>'RASCUNHO' and NEW.situacao not in (OLD.situacao,'INATIVA') then raise exception 'Transição não permitida';end if;
 if exists(select 1 from jsonb_array_elements(NEW.tributos) x group by x->>'tributo' having count(*)>1) then raise exception 'Tributo repetido';end if;
 for t in select value from jsonb_array_elements(NEW.tributos) loop
  if jsonb_typeof(t)<>'object' or coalesce(t->>'tributo','') not in ('II','IPI','ICMS','ICMS_ST','FCP','PIS','COFINS','IBS_UF','IBS_MUN','CBS','IS') then raise exception 'Tributo inválido';end if;
  if coalesce(t->>'tratamento','') not in ('TRIBUTADO','ZERO','ISENTO','SUSPENSO','NAO_INCIDE','DIFERIDO') then raise exception 'Informe tratamento do tributo';end if;
  for k in select unnest(array['aliquota','reducao_base','reducao_aliquota','diferimento']) loop
   if nullif(t->>k,'') is not null and ((t->>k)::numeric<0 or (t->>k)::numeric>100) then raise exception 'Percentual fora do intervalo 0 a 100';end if;
  end loop;
  if NEW.situacao='VALIDADA' then
   if nullif(btrim(t->>'base_calculo'),'') is null then raise exception 'Informe o tratamento da base de cálculo de cada tributo';end if;
   if t->>'tratamento'='TRIBUTADO' and nullif(t->>'aliquota','') is null then raise exception 'Informe alíquota ou deixe como rascunho';end if;
   if t->>'tributo' in ('IBS_UF','IBS_MUN','CBS') and (coalesce(t->>'cst','') !~ '^[0-9]{3}$' or coalesce(t->>'cclass_trib','') !~ '^[0-9]{6}$' or nullif(btrim(NEW.versao_tabela),'') is null) then raise exception 'IBS/CBS exigem CST, cClassTrib e versão da tabela oficial';end if;
  end if;
 end loop;
 NEW.atualizado_em:=now();return NEW;
end $function$
;
CREATE OR REPLACE FUNCTION public.axe_guardar_bloqueio_comercial()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare cid bigint;
begin
 if current_user='service_role' and TG_OP='UPDATE' and public.axe_mesclagem_vinculo_permitido(TG_TABLE_NAME,to_jsonb(OLD),to_jsonb(NEW)) then return NEW;end if;
 if tg_table_name='comercial_pedidos' then
  select cliente_id into cid from public.comercial_propostas where id=new.proposta_id;
  if tg_op='INSERT' or new.proposta_id is distinct from old.proposta_id then perform public.axe_exigir_cliente_liberado(cid);end if;
 else
  cid:=new.cliente_id;
  if tg_op='INSERT' then perform public.axe_exigir_cliente_liberado(cid);
  elsif new.cliente_id is distinct from old.cliente_id then perform public.axe_exigir_cliente_liberado(cid);
  elsif tg_table_name='comercial_propostas' then
   if new.estado is distinct from old.estado and new.estado in ('EM_REVISAO','APROVADA','ENVIADA','ACEITA') then perform public.axe_exigir_cliente_liberado(cid);end if;
  elsif tg_table_name='comercial_oportunidades' then
   if new.etapa is distinct from old.etapa and new.etapa<>'PERDIDA' then perform public.axe_exigir_cliente_liberado(cid);end if;
  end if;
 end if;
 return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.axe_guardar_cadastros_bloqueados()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare itens jsonb;it jsonb;fid bigint;checar boolean:=false;
begin
 if current_user='service_role' and TG_OP='UPDATE' and public.axe_mesclagem_vinculo_permitido(TG_TABLE_NAME,to_jsonb(OLD),to_jsonb(NEW)) then return NEW;end if;
 if tg_table_name in ('imp_pedidos','imp_processos') then
  if tg_op='INSERT' then checar:=true;else checar:=new.fornecedor_id is distinct from old.fornecedor_id;end if;
  if checar then perform public.axe_exigir_cadastro_liberado('fornecedor',new.fornecedor_id);end if;
 elsif tg_table_name='imp_pedido_itens' then
  if tg_op='INSERT' then checar:=true;else checar:=new.produto_id is distinct from old.produto_id or new.pedido_id is distinct from old.pedido_id or new.quantidade>old.quantidade;end if;
  if checar then select fornecedor_id into fid from public.imp_pedidos where id=new.pedido_id;perform public.axe_exigir_cadastro_liberado('fornecedor',fid);perform public.axe_exigir_cadastro_liberado('produto',new.produto_id);end if;
 elsif tg_table_name='comercial_propostas' then
  if tg_op='INSERT' then checar:=true;else checar:=new.documento is distinct from old.documento or (new.estado is distinct from old.estado and new.estado in ('EM_REVISAO','APROVADA','ENVIADA','ACEITA'));end if;
  if checar then itens:=new.documento->'itens';end if;
 elsif tg_table_name='comercial_pedidos' then
  select documento->'itens' into itens from public.comercial_propostas where id=new.proposta_id;
 end if;
 if jsonb_typeof(itens)='array' then for it in select value from jsonb_array_elements(itens) loop perform public.axe_exigir_cadastro_liberado('produto',nullif(it->>'produto_id','')::bigint);end loop;end if;
 return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.axe_imp_custo_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare eid uuid;
begin
 if current_user='service_role' and TG_OP='UPDATE' and public.axe_mesclagem_vinculo_permitido(TG_TABLE_NAME,to_jsonb(OLD),to_jsonb(NEW)) then return NEW;end if;
 if tg_table_name='imp_fin_documentos' then
  if new.valor is distinct from old.valor or new.moeda is distinct from old.moeda or new.fornecedor_id is distinct from old.fornecedor_id or nullif(new.dados->>'taxa','')::numeric is distinct from nullif(old.dados->>'taxa','')::numeric or nullif(new.dados->>'valor_brl','')::numeric is distinct from nullif(old.dados->>'valor_brl','')::numeric then
   if exists(select 1 from public.imp_custo_pagamentos p join public.imp_custos c on c.embarque_id=p.embarque_id where p.contrato_id=old.id and c.estado='Final') then raise exception 'Contrato usado em custo final: reabra o custo antes de alterar os valores';end if;
  end if;return new;
 end if;
 if tg_table_name='imp_embarques' then eid:=old.id;
 elsif tg_op='DELETE' then eid:=old.embarque_id;else eid:=new.embarque_id;end if;
 if exists(select 1 from public.imp_custos c where c.embarque_id=eid and c.estado='Final') then raise exception 'Embarque com custo final. Reabra o custo com justificativa antes de alterar';end if;
 if tg_op='DELETE' then return old;end if;return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.axe_imp_fin_guard_pedido()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if current_user='service_role' and TG_OP='UPDATE' and public.axe_mesclagem_vinculo_permitido(TG_TABLE_NAME,to_jsonb(OLD),to_jsonb(NEW)) then return NEW;end if;
 if (new.fornecedor_id<>old.fornecedor_id or new.moeda<>old.moeda or new.status='Cancelado' and old.status<>'Cancelado') and exists(select 1 from public.imp_fin_pedidos fp join public.imp_fin_documentos fd on fd.id=fp.documento_id where fp.pedido_id=old.id and fd.status='Ativo') then
  raise exception 'Pedido associado ao financeiro cambial: revise os documentos antes de alterar fornecedor, moeda ou cancelar';
 end if;return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.axe_imp_nf_proteger_embarque()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare eid uuid;
begin
 if current_user='service_role' and TG_OP='UPDATE' and public.axe_mesclagem_vinculo_permitido(TG_TABLE_NAME,to_jsonb(OLD),to_jsonb(NEW)) then return NEW;end if;
 perform pg_advisory_xact_lock(728102826);
 if tg_table_name='imp_embarques' then eid:=old.id;else eid:=old.embarque_id;end if;
 if exists(select 1 from public.imp_notas n where n.embarque_id=eid and n.estado='Conciliada') then raise exception 'Embarque possui nota conciliada. Reabra a conciliação antes de alterar a origem';end if;
 return case when tg_op='DELETE' then old else new end;
end $function$
;
CREATE OR REPLACE FUNCTION public.axe_imp_nf_proteger_origem()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare bloqueado boolean:=false;
begin
 if current_user='service_role' and TG_OP='UPDATE' and public.axe_mesclagem_vinculo_permitido(TG_TABLE_NAME,to_jsonb(OLD),to_jsonb(NEW)) then return NEW;end if;
 perform pg_advisory_xact_lock(728102826);
 if tg_table_name='imp_fin_documentos' then
  select exists(select 1 from public.imp_nota_vinculos v join public.imp_notas n on n.id=v.nota_id where v.declaracao_id=old.id and n.estado='Conciliada') into bloqueado;
  if tg_op='UPDATE' and (to_jsonb(new)-array['versao','atualizado_em','atualizado_por'])=(to_jsonb(old)-array['versao','atualizado_em','atualizado_por']) then bloqueado:=false;end if;
 elsif tg_table_name='imp_fin_pedidos' then
  select exists(select 1 from public.imp_nota_vinculos v join public.imp_notas n on n.id=v.nota_id join public.imp_pedido_itens pi on pi.id=v.pedido_item_id where v.declaracao_id=old.documento_id and pi.pedido_id=old.pedido_id and n.estado='Conciliada') into bloqueado;
 elsif tg_table_name='imp_pedido_itens' then
  select exists(select 1 from public.imp_nota_vinculos v join public.imp_notas n on n.id=v.nota_id where v.pedido_item_id=old.id and n.estado='Conciliada') into bloqueado;
  if tg_op='UPDATE' and (to_jsonb(new)-array['disponibilizada','data_disponibilidade'])=(to_jsonb(old)-array['disponibilizada','data_disponibilidade']) then bloqueado:=false;end if;
 elsif tg_table_name='imp_pedidos' then
  select exists(select 1 from public.imp_nota_vinculos v join public.imp_notas n on n.id=v.nota_id join public.imp_pedido_itens pi on pi.id=v.pedido_item_id where pi.pedido_id=old.id and n.estado='Conciliada') into bloqueado;
  if tg_op='UPDATE' and new.referencia=old.referencia and new.fornecedor_id=old.fornecedor_id and new.moeda=old.moeda and (new.status=old.status or (new.status in ('Elaboração','Enviado','Aceito -ACK','Aguardando Recebimento','Aguardando Entrega','Recebimento Parcial','Recebido') and old.status in ('Rascunho','Emitido','ACK recebido','Elaboração','Enviado','Aceito -ACK','Aguardando Recebimento','Aguardando Entrega','Recebimento Parcial','Recebido'))) then bloqueado:=false;end if;
 end if;
 if bloqueado then raise exception 'Origem possui nota conciliada. Reabra a conciliação antes de alterar o vínculo';end if;
 return case when tg_op='DELETE' then old else new end;
end $function$
;
CREATE OR REPLACE FUNCTION public.axe_produto_codigo_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare seq text;
begin
 if current_user='service_role' and TG_OP='UPDATE' and exists(select 1 from public.cadastros_mesclagens m where m.tipo='produto' and m.transacao=txid_current() and m.estado='EXECUTANDO' and ((m.origem_id=OLD.id and NEW.codigo_axe is null and (to_jsonb(NEW)-array['codigo_axe','codigo_anterior','chave_cadastro','mesclado_em_id','ativo','atualizado_em'])=(to_jsonb(OLD)-array['codigo_axe','codigo_anterior','chave_cadastro','mesclado_em_id','ativo','atualizado_em']))or(m.destino_id=OLD.id and OLD.codigo_axe is null and NEW.codigo_axe=m.origem_anterior->>'codigo_axe' and NEW.forma_obtencao is not distinct from m.origem_anterior->>'forma_obtencao')))then return NEW;end if;

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
;
CREATE OR REPLACE FUNCTION public.axe_proteger_regra_ativa()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if current_user='service_role' and TG_OP='UPDATE' and public.axe_mesclagem_vinculo_permitido(TG_TABLE_NAME,to_jsonb(OLD),to_jsonb(NEW)) then return NEW;end if;
 IF TG_OP='DELETE' AND OLD.status<>'RASCUNHO' THEN RAISE EXCEPTION 'Preserve a regra e seu histórico';END IF;
 IF TG_OP='UPDATE' AND OLD.status<>'RASCUNHO' AND (to_jsonb(OLD)-'status') IS DISTINCT FROM (to_jsonb(NEW)-'status') THEN RAISE EXCEPTION 'Crie uma nova versão da regra';END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;END IF;RETURN NEW;
END $function$
;

