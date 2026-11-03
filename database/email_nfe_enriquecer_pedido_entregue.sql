CREATE OR REPLACE FUNCTION public.axe_email_processar_nfe(p_arquivo uuid,p_usuario uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO '' AS $fn$
DECLARE f public.axe_email_arquivos; m public.axe_email_mensagens; doc xml; h record; line record; items jsonb:='[]'; e jsonb; result jsonb; cnt int; bad boolean:=false; prev jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.gestao_membros gm JOIN public.axe_rumo_revisores rv ON rv.usuario_id=gm.usuario_id AND rv.ativo WHERE gm.usuario_id=p_usuario AND gm.ativo AND gm.papel='ADMIN') THEN RAISE EXCEPTION 'Processamento fiscal restrito à administração';END IF;
 SELECT * INTO f FROM public.axe_email_arquivos WHERE id=p_arquivo;IF NOT FOUND THEN RAISE EXCEPTION 'Arquivo não encontrado';END IF;
 SELECT * INTO m FROM public.axe_email_mensagens WHERE id=f.mensagem_id;
 IF lower(m.remetente)<>'erpindustrial@nomuserp.com.br' OR lower(f.nome) NOT LIKE '%.xml' THEN RETURN jsonb_build_object('estado','NAO_APLICAVEL');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('email_nfe:'||f.sha256,0));
 IF encode(sha256(f.conteudo),'hex') IS DISTINCT FROM f.sha256 THEN RAISE EXCEPTION 'Integridade do XML divergente';END IF;
 IF convert_from(f.conteudo,'UTF8') ~* '<!DOCTYPE|<!ENTITY' THEN RAISE EXCEPTION 'Declaração XML não suportada';END IF;
 doc:=xmlparse(document convert_from(f.conteudo,'UTF8'));
 SELECT * INTO h FROM XMLTABLE(XMLNAMESPACES('http://www.portalfiscal.inf.br/nfe' AS n),'/n:nfeProc' PASSING doc COLUMNS
 chave_nfe text PATH 'n:protNFe/n:infProt/n:chNFe',status text PATH 'n:protNFe/n:infProt/n:cStat',ambiente text PATH 'n:NFe/n:infNFe/n:ide/n:tpAmb',
 id_nfe text PATH 'n:NFe/n:infNFe/@Id',numero_nf text PATH 'n:NFe/n:infNFe/n:ide/n:nNF',serie text PATH 'n:NFe/n:infNFe/n:ide/n:serie',
 data_emissao text PATH 'n:NFe/n:infNFe/n:ide/n:dhEmi',emitente_cnpj text PATH 'n:NFe/n:infNFe/n:emit/n:CNPJ',
 destinatario_cnpj text PATH 'n:NFe/n:infNFe/n:dest/n:CNPJ',valor_total numeric PATH 'n:NFe/n:infNFe/n:total/n:ICMSTot/n:vNF') x;
 IF NOT FOUND THEN RETURN jsonb_build_object('estado','XML_NAO_NFE');END IF;
 IF h.status<>'100' OR h.ambiente<>'1' OR h.emitente_cnpj<>'39893713000167' OR h.id_nfe IS DISTINCT FROM 'NFe'||h.chave_nfe THEN RETURN jsonb_build_object('estado','XML_SEM_AUTORIZACAO_PRODUCAO_AXE');END IF;
 FOR line IN SELECT * FROM XMLTABLE(XMLNAMESPACES('http://www.portalfiscal.inf.br/nfe' AS n),'/n:nfeProc/n:NFe/n:infNFe/n:det' PASSING doc COLUMNS
 item_nf text PATH '@nItem',pedido text PATH 'n:prod/n:xPed',item_pedido text PATH 'n:prod/n:nItemPed',codigo_produto text PATH 'n:prod/n:cProd',descricao text PATH 'n:prod/n:xProd',unidade text PATH 'n:prod/n:uCom',
 quantidade numeric PATH 'n:prod/n:qCom',valor_unitario numeric PATH 'n:prod/n:vUnCom',valor_total numeric PATH 'n:prod/n:vProd',
 ncm text PATH 'n:prod/n:NCM',cfop text PATH 'n:prod/n:CFOP',
 icms_base numeric PATH 'n:imposto/n:ICMS/*/n:vBC',icms_valor numeric PATH 'n:imposto/n:ICMS/*/n:vICMS',icms_aliquota numeric PATH 'n:imposto/n:ICMS/*/n:pICMS',
 ipi_base numeric PATH 'n:imposto/n:IPI/n:IPITrib/n:vBC',ipi_valor numeric PATH 'n:imposto/n:IPI/n:IPITrib/n:vIPI',ipi_aliquota numeric PATH 'n:imposto/n:IPI/n:IPITrib/n:pIPI') x
 LOOP
  IF line.quantidade IS NULL OR line.quantidade<=0 OR line.valor_total IS NULL OR line.valor_total<0 THEN RAISE EXCEPTION 'Quantidade ou valor inválido no XML';END IF;
  SELECT count(*) INTO cnt FROM public.pedidos p JOIN public.pedido_itens i ON i.pedido_id=p.id JOIN public.clientes c ON c.id=p.cliente_id
  WHERE p.numero_pedido=line.pedido AND public.axe_rumo_item_canonico(i.numero_item)=public.axe_rumo_item_canonico(line.item_pedido) AND c.cnpj=h.destinatario_cnpj;
  IF cnt<>1 THEN bad:=true;END IF;
  items:=items||jsonb_build_array(to_jsonb(line)||jsonb_build_object('ipi_sem_destaque_explicito',line.ipi_valor IS NULL));
 END LOOP;
 IF bad OR jsonb_array_length(items)=0 THEN
  result:=jsonb_build_object('estado','VINCULO_A_CONFERIR','nota',h.numero_nf,'motivo','Pedido, item ou CNPJ ausente/ambíguo; não preencher automaticamente');
 ELSE
  e:=to_jsonb(h)-'id_nfe'-'status'-'ambiente'||jsonb_build_object('estado','AUTORIZADA_XML','itens',items,'versao_extrator','nomus_nfe_xml_sql_v2','assinatura_criptografica_verificada',false,'entrega_confirmada',false);
  result:=public.axe_rumo_registrar_documento_externo(jsonb_build_object('confirmacao','REGISTRAR_EVIDENCIA_DOCUMENTAL','canal','EMAIL_NOMUS','conta',m.conta,'mensagem_id',m.mensagem_id,'anexo_id',f.anexo_id,'remetente',m.remetente,'recebido_em',m.recebido_em,'nome_arquivo',f.nome,'tipo_mime',f.tipo_mime,'sha256',f.sha256,'conteudo_base64',encode(f.conteudo,'base64'),'extracao',e),p_usuario);
  result:=result||jsonb_build_object('estado','PROCESSADO','nota',h.numero_nf,'arquivo_id',f.id);
 END IF;
 INSERT INTO public.axe_email_processamentos(mensagem_id,agente,chave_processo,resultado,usuario_id)
 VALUES(m.id,'fiscal.nfe_enriquecimento','XML:'||f.sha256,result,p_usuario)
 ON CONFLICT(mensagem_id,agente,chave_processo) DO UPDATE SET resultado=EXCLUDED.resultado;
 RETURN result;
END $fn$;
REVOKE ALL ON FUNCTION public.axe_email_processar_nfe(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.axe_email_processar_nfe(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.axe_documentos_entrada(p_dados jsonb, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare a text:=p_dados->>'acao'; papel text; p public.axe_email_propostas; d jsonb; r jsonb; i uuid; valido boolean; n int; fid bigint; fornecedor jsonb; ar jsonb; af public.axe_email_arquivos; arquivo uuid;
begin
 if a like 'email_%' and not exists(select 1 from public.gestao_membros gm2 where gm2.usuario_id=p_usuario and gm2.ativo and gm2.papel='ADMIN') then raise exception 'Entrada compartilhada restrita à administração AXE';end if;
 if a='email_anexar' then r:=public.axe_email_documentos(p_dados,p_usuario);begin r:=r||jsonb_build_object('processamento_fiscal',public.axe_email_processar_nfe((r->>'arquivo_id')::uuid,p_usuario));exception when others then insert into public.axe_email_processamentos(mensagem_id,agente,chave_processo,resultado,usuario_id) values((p_dados->>'mensagem_id')::uuid,'fiscal.nfe_enriquecimento','ERRO:'||(r->>'arquivo_id'),jsonb_build_object('estado','ERRO_PROCESSAMENTO','codigo',SQLSTATE,'motivo',left(SQLERRM,240)),p_usuario) on conflict(mensagem_id,agente,chave_processo) do update set resultado=EXCLUDED.resultado;r:=r||jsonb_build_object('processamento_fiscal',jsonb_build_object('estado','ERRO_PROCESSAMENTO'));end;return r;end if;
 if a in ('email_ack_propor','email_arquivo') then return public.axe_email_documentos(p_dados,p_usuario);end if;
 if a='ack_arquivo' then r:=public.axe_email_documentos(p_dados,p_usuario);if r is not null then return r;end if;end if;
 if a='email_detalhe' then return public.axe_documentos_entrada_base(p_dados,p_usuario)||jsonb_build_object('arquivos',(select coalesce(jsonb_agg(jsonb_build_object('arquivo_id',id,'anexo_id',anexo_id,'nome',nome,'tipo_mime',tipo_mime,'sha256',sha256)),'[]') from public.axe_email_arquivos where mensagem_id=(p_dados->>'id')::uuid));end if;
 if a not in ('ack_localizar','email_propor','email_propostas_listar','email_proposta_detalhe','email_decidir') then return public.axe_documentos_entrada_base(p_dados,p_usuario);end if;
 select gm.papel into papel from public.gestao_membros gm join public.axe_rumo_revisores rv on rv.usuario_id=gm.usuario_id and rv.ativo where gm.usuario_id=p_usuario and gm.ativo;
 if papel is null then raise exception 'Usuário sem acesso aos pré-cadastros';end if;
 if a='ack_localizar' then
  select count(*) into n from public.imp_pedidos where upper(referencia)=upper(p_dados->>'referencia') and status<>'Cancelado';
  if n<>1 then raise exception 'Pedido do ACK ausente ou ambíguo. Encaminhe para revisão';end if;
  return (select jsonb_build_object('id',id,'versao',versao,'referencia',referencia,'status',status,'ack_numero',ack_numero,'ack_data',ack_data,'proposta',(select to_jsonb(q) from public.axe_email_propostas q where q.id=nullif(p_dados->>'requisicao_id','')::uuid)) from public.imp_pedidos where upper(referencia)=upper(p_dados->>'referencia') and status<>'Cancelado');
 end if;
 if a='email_propostas_listar' then
  return jsonb_build_object('linhas',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from(select pr.id,pr.tipo,pr.resumo,pr.estado,pr.pendencias,pr.criado_em,pr.decidido_em,m.remetente,m.assunto from public.axe_email_propostas pr join public.axe_email_mensagens m on m.id=pr.mensagem_id where pr.substituida_por is null and (coalesce(p_dados->>'estado','Pendente')='Todos' or pr.estado=coalesce(p_dados->>'estado','Pendente')) order by pr.criado_em desc limit 100 offset greatest(0,least(100000,coalesce((p_dados->>'pagina')::int,0)))*100)z));
 elsif a='email_proposta_detalhe' then
  select * into p from public.axe_email_propostas where id=(p_dados->>'id')::uuid;if not found then raise exception 'Pré-cadastro não encontrado';end if;
  if p.tipo='ACK' then
   select p.aplicacao||jsonb_build_object('alteracoes',jsonb_build_object('pedido',o.referencia,'situacao',jsonb_build_object('anterior',o.status,'novo','Aceito -ACK'),'numero_ack',jsonb_build_object('anterior',o.ack_numero,'novo',f.revisado->>'ack_numero'),'data_ack',jsonb_build_object('anterior',o.ack_data,'novo',f.revisado->>'ack_data')),'itens_documento',f.extraido->'itens','avisos',f.extraido->'avisos','condicoes',f.extraido->'condicoes') into d from public.imp_acks f join public.imp_pedidos o on o.id=f.pedido_id where f.id=(p.aplicacao->>'id')::uuid;
  else d:=p.aplicacao;end if;
  return to_jsonb(p)||jsonb_build_object('aplicacao',d,'arquivos',(select coalesce(jsonb_agg(jsonb_build_object('arquivo_id',id,'nome',nome,'tipo_mime',tipo_mime)),'[]') from public.axe_email_arquivos where mensagem_id=p.mensagem_id or id in (select (value->>'arquivo_id')::uuid from jsonb_array_elements(coalesce(p.aplicacao->'arquivos_documentais','[]')))),'mensagem',(select to_jsonb(m) from public.axe_email_mensagens m where m.id=p.mensagem_id));
 end if;
 if papel not in ('ADMIN','EDITOR') then raise exception 'Sem permissão para aprovar';end if;
 if octet_length(p_dados::text)>500000 then raise exception 'Pré-cadastro excede o limite';end if;
 perform pg_advisory_xact_lock(728102826);
 if a='email_propor' then
  d:=p_dados->'aplicacao';
  valido:=case p_dados->>'tipo'
   when 'GESTAO_TAREFA' then d->>'acao'='gestao_salvar' and d->'dados'->>'tipo'='tarefas'
   when 'COMERCIAL_OPORTUNIDADE' then d->>'acao'='comercial_salvar' and d->>'operacao'='oportunidade'
   when 'COMERCIAL_PROPOSTA' then d->>'acao'='comercial_salvar' and d->>'operacao'='proposta'
   when 'COMERCIAL_PEDIDO' then d->>'acao'='comercial_salvar' and d->>'operacao'='pedido'
   when 'ACK' then d->>'acao'='ack_aplicar'
   when 'PEDIDO_IMPORTACAO' then d->>'acao'='v2_salvar' and d->>'tipo'='pedidos'
   when 'PARCELA_IMPORTACAO' then d->>'acao'='v2_salvar' and d->>'tipo'='parcelas'
   when 'EMBARQUE' then d->>'acao'='v2_salvar' and d->>'tipo'='embarques'
   when 'CONTRATO_CAMBIO' then d->>'acao'='fx_salvar' and d->>'tipo'='contratos'
   when 'SWIFT' then d->>'acao'='fx_salvar' and d->>'tipo'='contratos'
   when 'DI_DUIMP' then d->>'acao'='fx_salvar' and d->>'tipo'='declaracoes'
   when 'NOTA_FISCAL' then d->>'acao'='nf_salvar'
   when 'FECHAMENTO' then d->>'acao'='fech_aplicar'
   when 'CUSTO_IMPORTACAO' then d->>'acao'='custo_salvar' and coalesce(d->>'finalizar','false')='false'
   else false end;
  if valido is distinct from true or jsonb_typeof(d) is distinct from 'object' then raise exception 'Tipo de pré-cadastro ou operação ainda sem processador habilitado';end if;
  if p_dados->>'tipo'='ACK' and not exists(select 1 from public.imp_acks f where f.id=(d->>'id')::uuid and f.pronto and f.email_id=(p_dados->>'mensagem_id')::uuid) then raise exception 'ACK precisa estar anexado à mensagem compartilhada';end if;
  select * into p from public.axe_email_propostas where mensagem_id=(p_dados->>'mensagem_id')::uuid and agente=p_dados->>'agente' and chave_processo=p_dados->>'chave_processo';
  if found then if p.aplicacao is distinct from d or p.tipo is distinct from p_dados->>'tipo' or p.resumo is distinct from p_dados->>'resumo' or p.pendencias is distinct from coalesce(p_dados->'pendencias','[]') then raise exception 'Pré-cadastro já registrado com outros dados. Crie nova etapa de revisão';end if;return jsonb_build_object('id',p.id,'duplicado',true);end if;
  i:=(p_dados->>'requisicao_id')::uuid;
  insert into public.axe_email_propostas(id,mensagem_id,agente,chave_processo,tipo,resumo,aplicacao,pendencias,criado_por) values(i,(p_dados->>'mensagem_id')::uuid,p_dados->>'agente',p_dados->>'chave_processo',p_dados->>'tipo',p_dados->>'resumo',d,coalesce(p_dados->'pendencias','[]'),p_usuario);
  if nullif(d->>'substitui_proposta_id','') is not null then
   update public.axe_email_propostas set substituida_por=i where id=(d->>'substitui_proposta_id')::uuid and mensagem_id=(p_dados->>'mensagem_id')::uuid and tipo=p_dados->>'tipo' and estado='Pendente' and substituida_por is null;
   if not found then raise exception 'Versão anterior não corresponde a este documento pendente';end if;
  end if;
  return jsonb_build_object('id',i,'duplicado',false);
 end if;
 select * into p from public.axe_email_propostas where id=(p_dados->>'id')::uuid for update;
 if not found then raise exception 'Pré-cadastro não encontrado';end if;
 if coalesce(p_dados->>'decisao','') not in ('Aprovar','Rejeitar') or p_dados->>'confirmado' is distinct from 'true' then raise exception 'Confirme o aceite ou a rejeição';end if;
 if p.estado<>'Pendente' then
  if (p.estado='Aprovado' and p_dados->>'decisao'='Aprovar') or (p.estado='Rejeitado' and p_dados->>'decisao'='Rejeitar') then return jsonb_build_object('id',p.id,'estado',p.estado,'resultado',p.resultado,'duplicado',true);end if;
  raise exception 'Pré-cadastro já decidido. Preserve o histórico';
 end if;
 if p_dados->>'decisao'='Rejeitar' then
  if nullif(btrim(p_dados->>'motivo'),'') is null then raise exception 'Informe o motivo da rejeição';end if;
  update public.axe_email_propostas set estado='Rejeitado',motivo=left(p_dados->>'motivo',2000),decidido_por=p_usuario,decidido_em=clock_timestamp() where id=p.id;
  return jsonb_build_object('id',p.id,'estado','Rejeitado');
 end if;
 if p.substituida_por is not null then raise exception 'Existe uma versão mais recente deste pré-cadastro';end if;
 if jsonb_array_length(p.pendencias)>0 then raise exception 'Resolva as pendências e gere nova versão antes de aprovar';end if;
  if p.tipo='CONTRATO_CAMBIO' and p.aplicacao ? 'arquivos_documentais' then
  if jsonb_array_length(p.aplicacao->'arquivos_documentais')=0 then raise exception 'Anexe os documentos originais antes do aceite';end if;
  for ar in select value from jsonb_array_elements(p.aplicacao->'arquivos_documentais') loop
   select * into af from public.axe_email_arquivos where id=(ar->>'arquivo_id')::uuid;
   if not found or af.sha256 is distinct from ar->>'sha256' or encode(sha256(af.conteudo),'hex')<>af.sha256 or ar->>'categoria' not in ('CONTRATO','SWIFT') then raise exception 'Documento original ausente ou divergente';end if;
  end loop;
  fornecedor:=p.aplicacao->'fornecedor_proposto';
  if nullif(p.aplicacao->'dados'->>'fornecedor_id','') is null and fornecedor is not null then
   if nullif(btrim(fornecedor->>'razao_social'),'') is null or coalesce(fornecedor->>'pais','') !~ '^[A-Z]{2}$' then raise exception 'Dados oficiais do fornecedor incompletos';end if;
   select count(*),min(id) into n,fid from public.fornecedores where upper(btrim(razao_social))=upper(btrim(fornecedor->>'razao_social')) and pais=fornecedor->>'pais';
   if n>1 then raise exception 'Fornecedor ambíguo; escolha o cadastro existente';end if;
   if n=0 then
    if fornecedor->>'pais'<>'BR' and nullif(fornecedor->>'documento_fiscal','') is null then
     -- Documentary basic registration: keep an absent foreign tax ID null; never invent one.
     perform pg_advisory_xact_lock(hashtextextended('axe_catalogo_salvar',0));
     insert into public.fornecedores(razao_social,pais,endereco,ativo) values(btrim(fornecedor->>'razao_social'),fornecedor->>'pais',nullif(btrim(fornecedor->>'endereco'),''),true) returning id into fid;
     insert into public.catalogo_alteracoes(tipo,registro_id,usuario_id,anterior,atual) values('fornecedor',fid,p_usuario,null,(select to_jsonb(x) from public.fornecedores x where id=fid)||jsonb_build_object('proposta_origem',p.id));
    else
     r:=public.axe_catalogo_salvar('fornecedor',fornecedor||jsonb_build_object('requisicao_id',p.id,'ativo',true),p_usuario);
     fid:=(r->>'id')::bigint;
    end if;
   end if;
   if fid is null then raise exception 'Fornecedor não cadastrado';end if;
   perform public.axe_exigir_cadastro_liberado('fornecedor',fid);
   p.aplicacao:=jsonb_set(p.aplicacao,'{dados,fornecedor_id}',to_jsonb(fid));
   update public.axe_email_propostas set aplicacao=p.aplicacao where id=p.id;
  end if;
 end if;
 d:=p.aplicacao||jsonb_build_object('requisicao_id',p.id,'confirmado',true);
 if p.tipo='GESTAO_TAREFA' and d->'dados'->'propriedades'->>'Status'='Concluída' then
  if nullif(btrim(d->'conclusao'->>'feito'),'') is null or coalesce(d->'conclusao'->>'data','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Conclusão exige o que foi feito e a data informada';end if;perform (d->'conclusao'->>'data')::date;
 end if;
 if p.tipo='GESTAO_TAREFA' then r:=public.axe_gestao_salvar((d->'dados')||jsonb_build_object('requisicao_id',p.id),p_usuario);
 elsif p.tipo in ('COMERCIAL_OPORTUNIDADE','COMERCIAL_PROPOSTA','COMERCIAL_PEDIDO') then r:=public.axe_comercial_salvar(d->>'operacao',(d->'dados')||jsonb_build_object('requisicao_id',p.id),p_usuario);
 elsif p.tipo='ACK' then r:=public.axe_documentos_entrada_base(d,p_usuario);
 elsif p.tipo in ('PEDIDO_IMPORTACAO','PARCELA_IMPORTACAO','EMBARQUE') then r:=public.axe_imp_estrutura(d,p_usuario);
 elsif p.tipo in ('CONTRATO_CAMBIO','SWIFT','DI_DUIMP') then r:=public.axe_imp_financeiro(d,p_usuario);
 elsif p.tipo='NOTA_FISCAL' then r:=public.axe_imp_notas(d,p_usuario);
 elsif p.tipo='FECHAMENTO' then r:=public.axe_imp_fechamentos(d,p_usuario);
 elsif p.tipo='CUSTO_IMPORTACAO' then r:=public.axe_imp_custos(d,p_usuario);
 else raise exception 'Processador não habilitado';end if;
  if p.tipo='CONTRATO_CAMBIO' and p.aplicacao ? 'arquivos_documentais' then
  for ar in select value from jsonb_array_elements(p.aplicacao->'arquivos_documentais') loop
   select * into af from public.axe_email_arquivos where id=(ar->>'arquivo_id')::uuid;
   select id into arquivo from public.imp_cambio_arquivos where contrato_id=(r->>'id')::uuid and categoria=ar->>'categoria' and sha256=af.sha256;
   if arquivo is null then
    arquivo:=gen_random_uuid();
    insert into public.imp_cambio_arquivos(id,contrato_id,categoria,nome,sha256,tamanho,caminho,pronto,criado_por,email_arquivo_id)
    values(arquivo,(r->>'id')::uuid,ar->>'categoria',af.nome,af.sha256,af.tamanho,'email/'||af.id::text||'/'||af.sha256,true,p_usuario,af.id);
    insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual) values('fx_contratos',(r->>'id')::uuid,p_usuario,null,jsonb_build_object('evento','Original de e-mail vinculado após aceite','arquivo_id',arquivo,'origem_arquivo_id',af.id,'sha256',af.sha256,'proposta_id',p.id));
   end if;
  end loop;
 end if;
 update public.axe_email_propostas set estado='Aprovado',resultado=r,decidido_por=p_usuario,decidido_em=clock_timestamp() where id=p.id;
 return jsonb_build_object('id',p.id,'estado','Aprovado','resultado',r);
end;$function$
