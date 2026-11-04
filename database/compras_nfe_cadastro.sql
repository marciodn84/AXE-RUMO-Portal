begin;
create table public.compras_nfe_cadastro_eventos(id uuid primary key default gen_random_uuid(),nota_id uuid not null references public.compras_nfe_entradas(id),produto_id bigint not null references public.produtos_conciliacao(id),fornecedor_id bigint not null references public.fornecedores(id),linha integer not null,usuario_id uuid not null references auth.users(id),decisoes jsonb not null,anterior jsonb not null,atual jsonb not null,criado_em timestamptz not null default clock_timestamp());
alter table public.compras_nfe_cadastro_eventos enable row level security;revoke all on public.compras_nfe_cadastro_eventos from public,anon,authenticated;grant select,insert on public.compras_nfe_cadastro_eventos to service_role;
CREATE OR REPLACE FUNCTION public.axe_compra_nfe_ler(conteudo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare d xml;r xml;h text:='/n:nfeProc/n:NFe/n:infNFe/';k text;num text;serie text;cnpj text;emissao text;soma int:=0;peso int:=2;resto int;i int;linha int;items jsonb:='[]';t jsonb:='{}';row jsonb;tag text;prod numeric;q numeric;v numeric;valor numeric;total numeric:=0;outro numeric;trib jsonb;dups jsonb:='[]';begin
 if conteudo is null or octet_length(conteudo)>2097152 or conteudo ~* '<![[:space:]]*(DOCTYPE|ENTITY)'then raise exception 'XML vazio, acima de 2 MB ou com entidades não permitidas';end if;
 if not xml_is_well_formed_document(conteudo)then raise exception 'XML malformado';end if;d:=xmlparse(document conteudo);
 if cardinality(xpath('/n:nfeProc/n:NFe/n:infNFe',d,array[array['n','http://www.portalfiscal.inf.br/nfe']]))<>1 then raise exception 'Envie o XML processado da NF-e com protocolo de autorização';end if;
 if public.axe_nfe_texto(d,h||'n:ide/n:mod/text()')is distinct from '55' or public.axe_nfe_texto(d,h||'n:ide/n:tpNF/text()')is distinct from '1' or public.axe_nfe_texto(d,h||'n:ide/n:finNFe/text()')is distinct from '1'then raise exception 'Use NF-e normal de venda do fornecedor, modelo 55. Devoluções e complementares exigem outro fluxo';end if;
 if public.axe_nfe_texto(d,h||'n:ide/n:tpAmb/text()')is distinct from '1' or public.axe_nfe_texto(d,'/n:nfeProc/n:protNFe/n:infProt/n:tpAmb/text()')is distinct from '1' or coalesce(public.axe_nfe_texto(d,'/n:nfeProc/n:protNFe/n:infProt/n:cStat/text()'),'')not in('100','150') or coalesce(public.axe_nfe_texto(d,'/n:nfeProc/n:protNFe/n:infProt/n:nProt/text()'),'')!~ '^\d{15}$'or cardinality(xpath('/n:nfeProc/n:NFe/s:Signature',d,array[array['n','http://www.portalfiscal.inf.br/nfe'],array['s','http://www.w3.org/2000/09/xmldsig#']]))<>1 then raise exception 'XML de produção sem protocolo de autorização ou assinatura';end if;
 k:=replace(public.axe_nfe_texto(d,h||'@Id'),'NFe','');if k is null or k!~ '^\d{44}$'then raise exception 'Chave inválida';end if;
 for i in reverse 43..1 loop soma:=soma+substring(k,i,1)::int*peso;peso:=case when peso=9 then 2 else peso+1 end;end loop;resto:=soma%11;
 if right(k,1)::int<>(case when resto<2 then 0 else 11-resto end) or public.axe_nfe_texto(d,'/n:nfeProc/n:protNFe/n:infProt/n:chNFe/text()')is distinct from k then raise exception 'Chave e protocolo divergentes';end if;
 cnpj:=public.axe_nfe_texto(d,h||'n:emit/n:CNPJ/text()');num:=public.axe_nfe_texto(d,h||'n:ide/n:nNF/text()');serie:=public.axe_nfe_texto(d,h||'n:ide/n:serie/text()');emissao:=public.axe_nfe_texto(d,h||'n:ide/n:dhEmi/text()');
 if cnpj is null or num is null or serie is null or emissao is null or cnpj!~ '^\d{14}$'or num!~ '^\d{1,9}$'or serie!~ '^\d{1,3}$'or emissao!~ '^\d{4}-\d{2}-\d{2}T' or substring(k,7,14)<>cnpj or substring(k,21,2)<>'55' or substring(k,23,3)<>lpad(serie,3,'0')or substring(k,26,9)<>lpad(num,9,'0')or substring(k,3,4)<>to_char(left(emissao,10)::date,'YYMM') then raise exception 'Identificação da nota diverge da chave';end if;
 if public.axe_nfe_texto(d,h||'n:dest/n:CNPJ/text()')is distinct from '39893713000167'then raise exception 'O destinatário da nota deve ser o CNPJ da AXE';end if;
 foreach tag in array array['vNF','vProd','vFrete','vSeg','vDesc','vOutro','vIPI','vICMS','vST','vFCPST','vPIS','vCOFINS','vII','vIPIDevol','vICMSDeson']loop
 t:=t||jsonb_build_object(tag,public.axe_nfe_numero(public.axe_nfe_texto(d,h||'n:total/n:ICMSTot/n:'||tag||'/text()')));end loop;
 if public.axe_nfe_texto(d,h||'n:total/n:ICMSTot/n:vNF/text()')is null or public.axe_nfe_texto(d,h||'n:total/n:ICMSTot/n:vProd/text()')is null then raise exception 'Totais da nota ausentes';end if;
 foreach r in array xpath('/n:nfeProc/n:NFe/n:infNFe/n:det',d,array[array['n','http://www.portalfiscal.inf.br/nfe']])loop
 linha:=public.axe_nfe_texto(r,'/n:det/@nItem')::int;if linha is null or linha<1 or exists(select 1 from jsonb_array_elements(items)x where(x->>'linha')::int=linha)then raise exception 'Linha inválida ou repetida';end if;
 q:=public.axe_nfe_numero(public.axe_nfe_texto(r,'/n:det/n:prod/n:qCom/text()'),4);prod:=public.axe_nfe_numero(public.axe_nfe_texto(r,'/n:det/n:prod/n:vProd/text()'));v:=public.axe_nfe_numero(public.axe_nfe_texto(r,'/n:det/n:prod/n:vUnCom/text()'),10);
 if q<=0 or public.axe_nfe_texto(r,'/n:det/n:prod/n:vProd/text()')is null or abs(round(v*q,2)-prod)>.01 or public.axe_nfe_texto(r,'/n:det/n:prod/n:indTot/text()')is distinct from '1'then raise exception 'Quantidade/valor divergente ou item fora do total da nota';end if;
 row:=jsonb_build_object('linha',linha,'codigo',public.axe_nfe_texto(r,'/n:det/n:prod/n:cProd/text()'),'descricao',public.axe_nfe_texto(r,'/n:det/n:prod/n:xProd/text()'),'unidade',public.axe_nfe_texto(r,'/n:det/n:prod/n:uCom/text()'),'quantidade',q,'valor_unitario',v,'valor',prod,'pedido_xml',public.axe_nfe_texto(r,'/n:det/n:prod/n:xPed/text()'),'linha_pedido_xml',public.axe_nfe_texto(r,'/n:det/n:prod/n:nItemPed/text()'),'cest',public.axe_nfe_texto(r,'/n:det/n:prod/n:CEST/text()'),'gtin',case when public.axe_nfe_texto(r,'/n:det/n:prod/n:cEAN/text()')~'^[0-9]{8,14}$'then public.axe_nfe_texto(r,'/n:det/n:prod/n:cEAN/text()')end,'origem',public.axe_nfe_texto(r,'/n:det/n:imposto/n:ICMS/*/n:orig/text()'),'ncm',public.axe_nfe_texto(r,'/n:det/n:prod/n:NCM/text()'),'cfop',public.axe_nfe_texto(r,'/n:det/n:prod/n:CFOP/text()'));
 if coalesce(row->>'unidade','')=''or coalesce(row->>'codigo','')=''or coalesce(row->>'cfop','')!~ '^[56][0-9]{3}$'then raise exception 'Item sem unidade/código ou operação incompatível com compra nacional';end if;
 valor:=prod;
 foreach tag in array array['vFrete','vSeg','vOutro','vDesc']loop outro:=public.axe_nfe_numero(public.axe_nfe_texto(r,'/n:det/n:prod/n:'||tag||'/text()'));row:=row||jsonb_build_object(tag,outro);valor:=valor+case when tag='vDesc'then -outro else outro end;end loop;
 trib:='{}';foreach tag in array array['vIPI','vICMS','vICMSST','vFCPST','vPIS','vCOFINS','vIBS','vCBS']loop outro:=public.axe_nfe_numero(public.axe_nfe_texto(r,'/n:det/n:imposto//n:'||tag||'/text()'));trib:=trib||jsonb_build_object(tag,outro);if tag in('vIPI','vICMSST','vFCPST')then valor:=valor+outro;end if;end loop;
 if valor<0 then raise exception 'Valor líquido negativo';end if;row:=row||jsonb_build_object('impostos',trib,'valor_bruto',valor);items:=items||jsonb_build_array(row);total:=total+prod;
 end loop;
 if jsonb_array_length(items)not between 1 and 500 or abs(total-(t->>'vProd')::numeric)>.01 then raise exception 'Itens ausentes, em excesso ou soma dos produtos divergente';end if;
 if abs((select sum((x->>'valor_bruto')::numeric)from jsonb_array_elements(items)x)-(t->>'vNF')::numeric)>.01 or (t->>'vII')::numeric<>0 or(t->>'vIPIDevol')::numeric<>0 or(t->>'vICMSDeson')::numeric<>0 then raise exception 'Composição do total exige conferência fiscal específica. Esta entrada não atende este XML';end if;
 foreach r in array xpath('/n:nfeProc/n:NFe/n:infNFe/n:cobr/n:dup',d,array[array['n','http://www.portalfiscal.inf.br/nfe']])loop dups:=dups||jsonb_build_array(jsonb_build_object('numero',public.axe_nfe_texto(r,'/n:dup/n:nDup/text()'),'vencimento',public.axe_nfe_texto(r,'/n:dup/n:dVenc/text()'),'valor',public.axe_nfe_numero(public.axe_nfe_texto(r,'/n:dup/n:vDup/text()'))));end loop;
 return jsonb_build_object('chave',k,'numero',num,'serie',serie,'cnpj',cnpj,'emitente',public.axe_nfe_texto(d,h||'n:emit/n:xNome/text()'),'emissao',emissao,'totais',t,'itens',items,'duplicatas',dups,'protocolo',public.axe_nfe_texto(d,'/n:nfeProc/n:protNFe/n:infProt/n:nProt/text()'));
end $function$;
create function public.axe_nf_cadastro_previa(pid bigint,fid bigint,item jsonb)returns jsonb language plpgsql stable set search_path=''as $$
declare p public.produtos_conciliacao;v public.produtos_fornecedores;campos jsonb:='[]';spec jsonb;x jsonb;actual text;sug text;orig text;desc_fornecedor text;begin
 select * into p from public.produtos_conciliacao where id=public.axe_cadastro_canonico('produto',pid);
 if p.id is null or not p.ativo or p.bloqueado_comercial then raise exception 'Vincule um produto AXE ao item do pedido antes de conferir o cadastro';end if;
 select * into v from public.produtos_fornecedores where produto_id=p.id and fornecedor_id=fid and codigo_fornecedor=item->>'codigo';
 orig:=case when p.forma_obtencao='TER'then case item->>'origem' when '1'then '2'when '6'then '7'else item->>'origem'end else item->>'origem'end;
 desc_fornecedor:=btrim(regexp_replace(item->>'descricao','[[:space:]]+Pedido de Compra:.*$','','i'));
 spec:=jsonb_build_array(
 jsonb_build_object('campo','produto.ncm_referencia','rotulo','NCM do produto','fonte',item->>'ncm'),
 jsonb_build_object('campo','produto.cest','rotulo','CEST do produto','fonte',item->>'cest'),
 jsonb_build_object('campo','produto.gtin','rotulo','GTIN/EAN do produto','fonte',item->>'gtin'),
 jsonb_build_object('campo','produto.origem_fiscal_padrao','rotulo','Origem fiscal AXE','fonte',orig,'observacao',case when orig is distinct from item->>'origem'then 'Origem ajustada para aquisição no mercado interno; a origem informada pelo fornecedor fica preservada no vínculo.'else 'Confira a origem aplicável à operação da AXE.'end),
 jsonb_build_object('campo','produto.part_number','rotulo','Part Number do fabricante','fonte',coalesce(p.part_number,item->>'codigo'),'confirmar',p.part_number is null,'observacao','O código cProd não comprova o Part Number do fabricante. Confirme a equivalência ou informe o Part Number correto.'),
 jsonb_build_object('campo','fornecedor.codigo_fornecedor','rotulo','Código no fornecedor','fonte',item->>'codigo'),
 jsonb_build_object('campo','fornecedor.descricao_fornecedor','rotulo','Descrição no fornecedor','fonte',desc_fornecedor),
 jsonb_build_object('campo','fornecedor.ncm_informado','rotulo','NCM informado pelo fornecedor','fonte',item->>'ncm'),
 jsonb_build_object('campo','fornecedor.origem_fiscal','rotulo','Origem informada pelo fornecedor','fonte',item->>'origem'),
 jsonb_build_object('campo','fornecedor.part_number','rotulo','Part Number na referência do fornecedor','fonte',coalesce(v.part_number,p.part_number,item->>'codigo'),'confirmar',v.part_number is null and p.part_number is null)
 );
 for x in select z from jsonb_array_elements(spec)z loop
 sug:=nullif(btrim(x->>'fonte'),'');if sug is null then continue;end if;
 actual:=nullif(btrim(case when split_part(x->>'campo','.',1)='produto'then to_jsonb(p)->>split_part(x->>'campo','.',2)else to_jsonb(v)->>split_part(x->>'campo','.',2)end),'');
 campos:=campos||jsonb_build_array(x||jsonb_build_object('atual',actual,'sugerido',sug,'divergente',actual is not null and actual<>sug,'exige_decisao',coalesce((x->>'confirmar')::boolean,false)or(actual is not null and actual<>sug)));
 end loop;
 return jsonb_build_object('produto_id',p.id,'produto_versao',p.atualizado_em,'fornecedor_id',v.id,'fornecedor_versao',v.atualizado_em,'campos',campos);
end $$;
create function public.axe_nf_cadastro_validar(pid bigint,fid bigint,item jsonb,decisao jsonb)returns jsonb language plpgsql stable set search_path=''as $$
declare prev jsonb;values_out jsonb:='{}';x jsonb;choice jsonb;k text;v text;reason text;begin
 prev:=public.axe_nf_cadastro_previa(pid,fid,item);
 if decisao is null or decisao->>'conferido'is distinct from 'true'then raise exception 'Confira os campos cadastrais e resolva todas as divergências antes de concluir';end if;
 if prev->>'produto_versao'is distinct from decisao->>'produto_versao'or prev->>'fornecedor_versao'is distinct from decisao->>'fornecedor_versao'then raise exception 'Cadastro do produto/fornecedor alterado. Refaça a conferência do XML';end if;
 for x in select z from jsonb_array_elements(prev->'campos')z loop
 k:=x->>'campo';choice:=decisao->'decisoes'->k;reason:=btrim(coalesce(choice->>'justificativa',''));
 if(x->>'exige_decisao')::boolean and coalesce(choice->>'acao','')not in('XML','MANTER','INFORMAR')then raise exception 'Resolva a divergência de %',x->>'rotulo';end if;
 if choice is not null and coalesce(choice->>'acao','')not in('XML','MANTER','INFORMAR')then raise exception 'Decisão inválida para %',x->>'rotulo';end if;
 v:=case choice->>'acao'when 'MANTER'then x->>'atual'when 'INFORMAR'then nullif(btrim(choice->>'valor'),'')else x->>'sugerido'end;
 if choice->>'acao'in('MANTER','INFORMAR')and length(reason)not between 5 and 1000 then raise exception 'Justifique a decisão de %',x->>'rotulo';end if;
 if v is null then raise exception 'Informe o valor correto de %; não deixe pendência',x->>'rotulo';end if;
 if k in('produto.ncm_referencia','fornecedor.ncm_informado')and v!~'^[0-9]{8}$'or k='produto.cest'and v!~'^[0-9]{7}$'or k='produto.gtin'and v!~'^([0-9]{8}|[0-9]{12}|[0-9]{13}|[0-9]{14})$'or k in('produto.origem_fiscal_padrao','fornecedor.origem_fiscal')and v!~'^[0-8]$'or length(v)>2000 then raise exception 'Valor inválido para %',x->>'rotulo';end if;
 if k='fornecedor.codigo_fornecedor'and v is distinct from item->>'codigo'then raise exception 'O código do fornecedor deve corresponder ao cProd do XML; escolha o produto correto';end if;
 values_out:=values_out||jsonb_build_object(k,v);
 end loop;
 return jsonb_build_object('previa',prev,'valores',values_out,'decisoes',decisao);
end $$;
create function public.axe_nf_cadastro_aplicar(nid uuid,pid bigint,fid bigint,item jsonb,plano jsonb,uid uuid)returns void language plpgsql set search_path=''as $$
declare before_p jsonb;after_p jsonb;before_v jsonb;after_v jsonb;vals jsonb:=plano->'valores';begin
 select to_jsonb(p)into before_p from public.produtos_conciliacao p where id=pid for update;
 select to_jsonb(v)into before_v from public.produtos_fornecedores v where produto_id=pid and fornecedor_id=fid and codigo_fornecedor=item->>'codigo'for update;
 update public.produtos_conciliacao set ncm_referencia=coalesce(vals->>'produto.ncm_referencia',ncm_referencia),cest=coalesce(vals->>'produto.cest',cest),gtin=coalesce(vals->>'produto.gtin',gtin),origem_fiscal_padrao=coalesce(vals->>'produto.origem_fiscal_padrao',origem_fiscal_padrao),part_number=coalesce(vals->>'produto.part_number',part_number),status_validacao='VALIDADO',atualizado_em=clock_timestamp()where id=pid returning to_jsonb(produtos_conciliacao.*)into after_p;
 update public.produtos_fornecedores set descricao_fornecedor=coalesce(vals->>'fornecedor.descricao_fornecedor',descricao_fornecedor),ncm_informado=coalesce(vals->>'fornecedor.ncm_informado',ncm_informado),origem_fiscal=coalesce(vals->>'fornecedor.origem_fiscal',origem_fiscal),part_number=coalesce(vals->>'fornecedor.part_number',part_number),situacao='APROVADO',atualizado_em=clock_timestamp()where produto_id=pid and fornecedor_id=fid and codigo_fornecedor=item->>'codigo'returning to_jsonb(produtos_fornecedores.*)into after_v;
 if after_v is null then raise exception 'Referência do fornecedor ausente. Confirme o cadastro da unidade e código';end if;
 insert into public.catalogo_alteracoes(tipo,registro_id,usuario_id,anterior,atual)values('produto',pid,uid,before_p,after_p),('produto_fornecedor',(after_v->>'id')::bigint,uid,before_v,after_v);
 insert into public.compras_nfe_cadastro_eventos(nota_id,produto_id,fornecedor_id,linha,usuario_id,decisoes,anterior,atual)values(nid,pid,fid,(item->>'linha')::int,uid,plano->'decisoes',jsonb_build_object('produto',before_p,'fornecedor',before_v),jsonb_build_object('produto',after_p,'fornecedor',after_v));
end $$;
-- Preserva a função transacional de entrada e amplia suas conferências.
alter function public.axe_compra_nfe(jsonb,uuid)rename to axe_compra_nfe_base;
create function public.axe_compra_nfe(p_dados jsonb,p_usuario uuid)returns jsonb language plpgsql set search_path=''as $$
declare a text:=p_dados->>'acao';res jsonb;d jsonb;item jsonb;mp jsonb;plans jsonb:='[]';plan jsonb;p public.imp_pedidos;n public.compras_nfe_entradas;pi public.imp_pedido_itens;uid uuid;cached public.estoque_requisicoes;req uuid;begin
 if not exists(select 1 from public.axe_rumo_revisores where usuario_id=p_usuario and ativo)or not exists(select 1 from public.gestao_membros where usuario_id=p_usuario and ativo)then raise exception 'Usuário não autorizado';end if;
 if a in('compra_nf_confirmar','compra_nf_cadastro_previa','compra_nf_cadastro_salvar','compra_nf_ler')then
 if not exists(select 1 from public.gestao_membros where usuario_id=p_usuario and ativo and papel in('ADMIN','EDITOR'))then raise exception 'Sem permissão para conferir cadastros de entrada';end if;
 perform set_config('lock_timeout','5s',true);perform pg_advisory_xact_lock(728102826);
 select * into p from public.imp_pedidos where id=(p_dados->>'pedido_id')::uuid for update;if not found then raise exception 'Pedido não encontrado';end if;
 if a in('compra_nf_confirmar','compra_nf_cadastro_salvar')then
 req:=(p_dados->>'requisicao_id')::uuid;if req is null then raise exception 'Identifique a operação';end if;
 select * into cached from public.estoque_requisicoes where id=req;if found then if cached.usuario_id<>p_usuario or cached.dados<>p_dados then raise exception 'Identificador reutilizado com outros dados';end if;return cached.resultado;end if;
 end if;
 if a='compra_nf_ler'then
 res:=public.axe_compra_nfe_base(p_dados,p_usuario);d:=res->'documento';
 for item in select x from jsonb_array_elements(d->'itens')x loop
 plans:=plans||jsonb_build_array(jsonb_build_object('linha',item->'linha','opcoes',(select coalesce(jsonb_agg(jsonb_build_object('pedido_item_id',i.id,'cadastro',public.axe_nf_cadastro_previa(i.produto_id,p.fornecedor_id,item))),'[]')from public.imp_pedido_itens i where i.pedido_id=p.id and i.produto_id is not null)));
 end loop;return res||jsonb_build_object('cadastros',plans);
 end if;
 if a in('compra_nf_cadastro_previa','compra_nf_cadastro_salvar')then
 select * into n from public.compras_nfe_entradas where id=(p_dados->>'id')::uuid and pedido_id=p.id and estado='Confirmada'for update;if not found then raise exception 'Selecione uma nota confirmada deste pedido';end if;
 d:=public.axe_compra_nfe_ler(n.xml_original);
 if a='compra_nf_cadastro_previa'then
 for item in select x from jsonb_array_elements(d->'itens')x loop
 select i.* into pi from public.imp_pedido_itens i join public.compras_nfe_itens ni on ni.pedido_item_id=i.id where ni.entrada_id=n.id and ni.linha=(item->>'linha')::int;
 plans:=plans||jsonb_build_array(jsonb_build_object('linha',item->'linha','pedido_item_id',pi.id,'cadastro',public.axe_nf_cadastro_previa(pi.produto_id,p.fornecedor_id,item)));
 end loop;return jsonb_build_object('documento',d,'cadastros',plans);
 end if;
 if p_dados->>'confirmado'is distinct from 'true'then raise exception 'Confirme a atualização cadastral';end if;
 else d:=public.axe_compra_nfe_ler(p_dados->>'xml');end if;
 if jsonb_typeof(p_dados->'vinculos')is distinct from 'array'or jsonb_array_length(p_dados->'vinculos')<>jsonb_array_length(d->'itens')or(select count(distinct x->>'linha')from jsonb_array_elements(p_dados->'vinculos')x)<>jsonb_array_length(d->'itens')then raise exception 'Confira todos os vínculos e campos da nota';end if;
 for item in select x from jsonb_array_elements(d->'itens')x loop
 select x into mp from jsonb_array_elements(p_dados->'vinculos')x where x->>'linha'=item->>'linha';
 select * into pi from public.imp_pedido_itens where id=(mp->>'pedido_item_id')::uuid and pedido_id=p.id for update;
 if pi.id is null then raise exception 'Selecione um item deste pedido';end if;
 if a='compra_nf_cadastro_salvar'and not exists(select 1 from public.compras_nfe_itens where entrada_id=n.id and linha=(item->>'linha')::int and pedido_item_id=pi.id)then raise exception 'Não altere os vínculos da nota recebida';end if;
 perform 1 from public.produtos_conciliacao where id=public.axe_cadastro_canonico('produto',pi.produto_id)for update;
 perform 1 from public.produtos_fornecedores where produto_id=public.axe_cadastro_canonico('produto',pi.produto_id)and fornecedor_id=p.fornecedor_id and codigo_fornecedor=item->>'codigo'for update;
 plan:=public.axe_nf_cadastro_validar(pi.produto_id,p.fornecedor_id,item,mp->'cadastro');
 if exists(select 1 from jsonb_array_elements(plans)prev where prev->>'produto_id'=public.axe_cadastro_canonico('produto',pi.produto_id)::text and exists(select 1 from jsonb_each_text(plan->'valores')vv where vv.key like 'produto.%'and prev->'plano'->'valores'->>vv.key is distinct from vv.value))then raise exception 'O mesmo produto aparece com decisões diferentes na nota. Resolva os campos de todas as linhas';end if;
 plans:=plans||jsonb_build_array(jsonb_build_object('linha',item->'linha','produto_id',public.axe_cadastro_canonico('produto',pi.produto_id),'plano',plan));
 end loop;
 if a='compra_nf_confirmar'then res:=public.axe_compra_nfe_base(p_dados,p_usuario);else res:=jsonb_build_object('id',n.id,'cadastro_atualizado',true);end if;
 for item in select x from jsonb_array_elements(d->'itens')x loop
 select x into plan from jsonb_array_elements(plans)x where x->>'linha'=item->>'linha';
 perform public.axe_nf_cadastro_aplicar((res->>'id')::uuid,(plan->>'produto_id')::bigint,p.fornecedor_id,item,plan->'plano',p_usuario);
 end loop;
 if a='compra_nf_cadastro_salvar'then insert into public.estoque_requisicoes(id,usuario_id,dados,resultado)values(req,p_usuario,p_dados,res);end if;
 return res;
 end if;
 return public.axe_compra_nfe_base(p_dados,p_usuario);
end $$;
revoke all on function public.axe_nf_cadastro_previa(bigint,bigint,jsonb),public.axe_nf_cadastro_validar(bigint,bigint,jsonb,jsonb),public.axe_nf_cadastro_aplicar(uuid,bigint,bigint,jsonb,jsonb,uuid),public.axe_compra_nfe(jsonb,uuid)from public,anon,authenticated;
grant execute on function public.axe_nf_cadastro_previa(bigint,bigint,jsonb),public.axe_nf_cadastro_validar(bigint,bigint,jsonb,jsonb),public.axe_nf_cadastro_aplicar(uuid,bigint,bigint,jsonb,jsonb,uuid),public.axe_compra_nfe(jsonb,uuid)to service_role;

CREATE OR REPLACE FUNCTION public.axe_produto_ficha(p_id bigint, p_aba text, p_pagina integer, p_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE pid bigint;linhas jsonb;total bigint;extra jsonb:='{}';offn int;
BEGIN
IF NOT EXISTS(SELECT 1 FROM public.axe_rumo_revisores WHERE usuario_id=p_usuario AND ativo) THEN RAISE EXCEPTION 'Sem permissão';END IF;
IF p_pagina IS NULL OR p_pagina<0 OR p_pagina>10000 THEN RAISE EXCEPTION 'Página inválida';END IF;offn:=p_pagina*50;
pid:=public.axe_cadastro_canonico('produto',p_id);
IF NOT EXISTS(SELECT 1 FROM public.produtos_conciliacao WHERE id=pid) THEN RAISE EXCEPTION 'Produto não encontrado';END IF;
IF p_aba='clientes' THEN
 SELECT count(*) INTO total FROM public.produtos_clientes_referencias r WHERE r.produto_axe_id=pid OR EXISTS(SELECT 1 FROM public.produtos_clientes_opcoes o WHERE o.referencia_cliente_id=r.id AND o.produto_id=pid);
 SELECT coalesce(jsonb_agg(t.doc ORDER BY t.id),'[]') INTO linhas FROM(
 SELECT r.id,to_jsonb(r)||jsonb_build_object('cliente_nome',c.nome,'cnpj',c.cnpj,'opcao',(SELECT to_jsonb(o) FROM public.produtos_clientes_opcoes o WHERE o.referencia_cliente_id=r.id AND o.produto_id=pid)) AS doc
 FROM public.produtos_clientes_referencias r JOIN public.clientes c ON c.id=r.cliente_id WHERE r.produto_axe_id=pid OR EXISTS(SELECT 1 FROM public.produtos_clientes_opcoes o WHERE o.referencia_cliente_id=r.id AND o.produto_id=pid)
 ORDER BY r.id LIMIT 50 OFFSET offn)t;
ELSIF p_aba='fornecedores' THEN
 SELECT count(*) INTO total FROM public.produtos_fornecedores WHERE produto_id=pid;
 SELECT coalesce(jsonb_agg(t.doc ORDER BY t.id),'[]') INTO linhas FROM(
 SELECT r.id,to_jsonb(r)||jsonb_build_object('fornecedor_nome',f.razao_social,'documento',coalesce(f.cnpj,f.documento_fiscal)) AS doc
 FROM public.produtos_fornecedores r JOIN public.fornecedores f ON f.id=r.fornecedor_id WHERE r.produto_id=pid ORDER BY r.id LIMIT 50 OFFSET offn)t;
ELSIF p_aba='codigos' THEN
 SELECT count(*) INTO total FROM public.produtos_identificadores WHERE produto_id=pid AND status_validacao<>'INATIVO';
 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]') INTO linhas FROM(SELECT * FROM public.produtos_identificadores WHERE produto_id=pid AND status_validacao<>'INATIVO' ORDER BY id LIMIT 50 OFFSET offn)t;
ELSIF p_aba='estoque' THEN
 extra:=jsonb_build_object('saldo',(SELECT to_jsonb(s) FROM public.estoque_saldos s WHERE produto_id=pid));
 SELECT count(*) INTO total FROM public.estoque_movimentos WHERE produto_id=pid;
 SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.ordem DESC),'[]') INTO linhas FROM(SELECT m.*,EXISTS(SELECT 1 FROM public.estoque_movimentos e WHERE e.estorno_de=m.id) AS estornado FROM public.estoque_movimentos m WHERE produto_id=pid ORDER BY ordem DESC LIMIT 50 OFFSET offn)t;
ELSIF p_aba='historico' THEN
 WITH eventos AS(
 SELECT a.criado_em,'Cadastro' AS origem,a.operacao AS acao,a.anterior,a.atual,coalesce(a.usuario_id,(SELECT l.usuario_id FROM public.catalogo_alteracoes l WHERE l.atual=a.atual AND l.registro_id::text=a.registro_id ORDER BY l.id DESC LIMIT 1))::text AS responsavel,a.id::text AS chave
 FROM public.produtos_catalogo_auditoria a WHERE
 (a.tabela='produtos_conciliacao' AND a.registro_id IN(SELECT id::text FROM public.produtos_conciliacao WHERE id=pid OR mesclado_em_id=pid))
 OR (a.anterior->>'produto_id'=pid::text OR a.atual->>'produto_id'=pid::text)
 OR (a.tabela='produtos_clientes_referencias' AND a.registro_id IN(SELECT id::text FROM public.produtos_clientes_referencias r WHERE produto_axe_id=pid OR EXISTS(SELECT 1 FROM public.produtos_clientes_opcoes o WHERE o.referencia_cliente_id=r.id AND produto_id=pid)))
 UNION ALL SELECT c.criado_em,'Correção da forma de obtenção','CORRECAO_CLASSIFICACAO',c.anterior,c.atual||jsonb_build_object('justificativa',c.justificativa),c.usuario_id::text,c.id::text FROM public.produtos_obtencao_correcoes c WHERE c.produto_id=pid AND c.estado='CONCLUIDA'
 UNION ALL SELECT e.criado_em,'Conferência cadastral pela NF-e','CAMPOS_RESOLVIDOS_NA_ENTRADA',e.anterior,e.atual||jsonb_build_object('nota_id',e.nota_id,'linha',e.linha,'decisoes',e.decisoes),e.usuario_id::text,e.id::text FROM public.compras_nfe_cadastro_eventos e WHERE e.produto_id=pid
 UNION ALL SELECT m.criado_em,'Mesclagem','CADASTROS_REUNIDOS',m.origem_anterior,m.destino_atual,m.usuario_id::text,m.id::text FROM public.cadastros_mesclagens m WHERE m.tipo='produto' AND m.estado='CONCLUIDA' AND(m.destino_id=pid OR m.origem_id=pid)
 UNION ALL SELECT e.criado_em,'Descrição do cliente',e.acao,e.anterior,e.atual,e.usuario_id::text,e.id::text FROM public.comercial_eventos e WHERE e.tipo='referencia_cliente' AND e.registro_id IN(SELECT id FROM public.produtos_clientes_referencias WHERE produto_axe_id=pid)
 UNION ALL SELECT d.criado_em,'Bloqueio comercial',d.acao,d.anterior,d.atual,d.usuario_id::text,d.id::text FROM public.cadastros_decisoes d WHERE d.entidade='PRODUTO_COMERCIAL' AND d.referencia=pid::text
 ) SELECT (SELECT count(*) FROM eventos),coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY criado_em DESC,chave DESC) FROM(SELECT * FROM eventos ORDER BY criado_em DESC,chave DESC LIMIT 50 OFFSET offn)t),'[]') INTO total,linhas;
ELSE RAISE EXCEPTION 'Aba inválida';END IF;
RETURN extra||jsonb_build_object('produto_id',pid,'linhas',linhas,'total',total);
END $function$;
commit;
