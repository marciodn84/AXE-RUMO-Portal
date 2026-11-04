begin;
-- Arquivos fiscais permanecem no banco privado, nunca nos assets públicos.
create table public.compras_nfe_entradas (
 id uuid primary key default gen_random_uuid(),pedido_id uuid not null references public.imp_pedidos(id),chave text not null check(chave ~ '^\d{44}$'),
 nome text not null,xml_original text not null check(octet_length(xml_original)<=2097152),documento jsonb not null,
 data_entrada date not null,estado text not null default 'Confirmada' check(estado in('Confirmada','Estornada')),justificativa text not null,
 usuario_id uuid not null references auth.users(id),criado_em timestamptz not null default clock_timestamp(),estornado_por uuid references auth.users(id),estornado_em timestamptz);
create unique index compras_nfe_chave_ativa on public.compras_nfe_entradas(chave)where estado='Confirmada';
create table public.compras_nfe_itens (
 entrada_id uuid not null references public.compras_nfe_entradas(id),linha integer not null,pedido_item_id uuid not null references public.imp_pedido_itens(id),
 produto_id bigint not null references public.produtos_conciliacao(id),quantidade numeric(24,6) not null check(quantidade>0),fator numeric(24,8) not null check(fator>0),
 quantidade_axe numeric(24,6) not null check(quantidade_axe>0),quantidade_pedido numeric(24,6) not null check(quantidade_pedido>0),
 custo_total numeric(24,6) not null check(custo_total>=0),movimento_id uuid not null unique references public.estoque_movimentos(id),primary key(entrada_id,linha));
alter table public.compras_nfe_entradas enable row level security;alter table public.compras_nfe_itens enable row level security;
revoke all on public.compras_nfe_entradas,public.compras_nfe_itens from public,anon,authenticated;
grant select,insert,update on public.compras_nfe_entradas to service_role;grant select,insert on public.compras_nfe_itens to service_role;

create function public.axe_nfe_texto(d xml,p text) returns text language plpgsql immutable set search_path='' as $$
declare a xml[];begin a:=xpath(p,d,array[array['n','http://www.portalfiscal.inf.br/nfe'],array['s','http://www.w3.org/2000/09/xmldsig#']]);
if cardinality(a)>1 then raise exception 'Campo repetido no XML: %',p;end if;return nullif(btrim((a[1])::text),'');end $$;
create function public.axe_nfe_numero(t text,casas int default 2)returns numeric language plpgsql immutable set search_path=''as $$
begin if t is null then return 0;end if;if t !~ ('^[0-9]{1,12}([.][0-9]{1,'||casas||'})?$')then raise exception 'Número inválido no XML';end if;return t::numeric;end $$;
create function public.axe_compra_nfe_ler(conteudo text)returns jsonb language plpgsql immutable set search_path=''as $$
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
 row:=jsonb_build_object('linha',linha,'codigo',public.axe_nfe_texto(r,'/n:det/n:prod/n:cProd/text()'),'descricao',public.axe_nfe_texto(r,'/n:det/n:prod/n:xProd/text()'),'unidade',public.axe_nfe_texto(r,'/n:det/n:prod/n:uCom/text()'),'quantidade',q,'valor_unitario',v,'valor',prod,'pedido_xml',public.axe_nfe_texto(r,'/n:det/n:prod/n:xPed/text()'),'linha_pedido_xml',public.axe_nfe_texto(r,'/n:det/n:prod/n:nItemPed/text()'),'ncm',public.axe_nfe_texto(r,'/n:det/n:prod/n:NCM/text()'),'cfop',public.axe_nfe_texto(r,'/n:det/n:prod/n:CFOP/text()'));
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
end $$;
create function public.axe_compra_nfe_recebida(i uuid)returns numeric language sql stable set search_path=''as $$
 select coalesce(sum(x.quantidade_pedido),0)from public.compras_nfe_itens x join public.compras_nfe_entradas n on n.id=x.entrada_id where x.pedido_item_id=i and n.estado='Confirmada'
$$;
create function public.axe_compra_nfe(p_dados jsonb,p_usuario uuid)returns jsonb language plpgsql set search_path=''as $$
declare a text:=p_dados->>'acao';p public.imp_pedidos;f public.fornecedores;pr public.produtos_conciliacao;pi public.imp_pedido_itens;old public.compras_nfe_entradas;nid uuid;req uuid;cache public.estoque_requisicoes;d jsonb;row jsonb;item jsonb;mapping jsonb;res jsonb;qty numeric;factor numeric;qp numeric;cost numeric;received numeric;mov uuid;dt date;reason text:=btrim(coalesce(p_dados->>'justificativa',''));diff boolean:=false;vinc public.produtos_fornecedores;prev jsonb;begin
 if not exists(select 1 from public.axe_rumo_revisores where usuario_id=p_usuario and ativo)or not exists(select 1 from public.gestao_membros where usuario_id=p_usuario and ativo)then raise exception 'Usuário não autorizado';end if;
 select * into p from public.imp_pedidos where id=(p_dados->>'pedido_id')::uuid;
 if not found then raise exception 'Pedido não encontrado';end if;
 if a='compra_nf_listar'then return jsonb_build_object('notas',(select coalesce(jsonb_agg(jsonb_build_object('id',n.id,'chave',n.chave,'nome',n.nome,'numero',n.documento->>'numero','serie',n.documento->>'serie','valor',n.documento->'totais'->'vNF','data_entrada',n.data_entrada,'estado',n.estado,'criado_em',n.criado_em)order by n.criado_em desc),'[]')from public.compras_nfe_entradas n where n.pedido_id=p.id));end if;
 if a='compra_nf_baixar'then select * into old from public.compras_nfe_entradas where id=(p_dados->>'id')::uuid and pedido_id=p.id;if not found then raise exception 'Nota não encontrada neste pedido';end if;return jsonb_build_object('nome',old.nome,'xml',old.xml_original);end if;
 if not exists(select 1 from public.gestao_membros where usuario_id=p_usuario and ativo and papel in('ADMIN','EDITOR'))then raise exception 'Sem permissão para entrada de notas';end if;
 if a not in('compra_nf_ler','compra_nf_confirmar','compra_nf_estornar')then raise exception 'Ação inválida';end if;
 perform set_config('lock_timeout','5s',true);perform pg_advisory_xact_lock(728102826);
 select * into p from public.imp_pedidos where id=p.id for update;
 select * into f from public.fornecedores where id=p.fornecedor_id;
 if p.moeda<>'BRL'or f.pais<>'BR' or p.status='Cancelado'then raise exception 'Selecione um pedido nacional ativo em reais';end if;
 if a in('compra_nf_confirmar','compra_nf_estornar')then
 req:=(p_dados->>'requisicao_id')::uuid;if req is null then raise exception 'Identifique a operação';end if;
 select * into cache from public.estoque_requisicoes where id=req;if found then if cache.usuario_id<>p_usuario or cache.dados<>p_dados then raise exception 'Identificador reutilizado com outros dados';end if;return cache.resultado;end if;
 if p_dados->>'confirmado'is distinct from 'true'then raise exception 'Confirme a operação';end if;
 end if;
 if a='compra_nf_estornar'then
 select * into old from public.compras_nfe_entradas where id=(p_dados->>'id')::uuid and pedido_id=p.id for update;
 if not found or old.estado<>'Confirmada' or length(reason)<5 then raise exception 'Selecione uma nota ativa e justifique o estorno';end if;
 perform set_config('axe.compra_nf_estorno',old.id::text,true);
 for row in select to_jsonb(x)from public.compras_nfe_itens x where entrada_id=old.id order by produto_id,linha loop
 perform public.axe_estoque(jsonb_build_object('acao','stock_estornar','movimento_id',row->>'movimento_id','referencia','Estorno NF-e '||(old.documento->>'numero')||': '||left(reason,170),'requisicao_id',gen_random_uuid()),p_usuario);
 end loop;
 update public.compras_nfe_entradas set estado='Estornada',estornado_por=p_usuario,estornado_em=clock_timestamp()where id=old.id;
 update public.imp_pedidos set versao=versao+1,atualizado_por=p_usuario,atualizado_em=clock_timestamp()where id=p.id;
 perform public.axe_imp_recalcular_status_pedido(p.id);
 res:=jsonb_build_object('id',old.id,'estornada',true);
 insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('pedidos',p.id,p_usuario,jsonb_build_object('nota',old.id,'estado','Confirmada'),res||jsonb_build_object('justificativa',reason,'origem','Estorno NF-e nacional'));
 else
 d:=public.axe_compra_nfe_ler(p_dados->>'xml');
 if regexp_replace(coalesce(f.cnpj,''),'\D','','g')is distinct from d->>'cnpj'then raise exception 'CNPJ do emitente diverge do fornecedor do pedido';end if;
 if exists(select 1 from public.compras_nfe_entradas where chave=d->>'chave'and estado='Confirmada')or exists(select 1 from public.imp_notas where chave=d->>'chave')then raise exception 'Esta chave já está registrada. Consulte a nota existente; não registre a entrada novamente';end if;
 if exists(select 1 from jsonb_array_elements(d->'itens')x where nullif(x->>'pedido_xml','')is not null and upper(btrim(x->>'pedido_xml'))<>upper(p.referencia))then raise exception 'O XML informa outro pedido de compra';end if;
 if exists(select 1 from public.imp_pedido_itens i join public.imp_embarque_itens ei on ei.pedido_item_id=i.id join public.imp_embarques e on e.id=ei.embarque_id where i.pedido_id=p.id and e.status<>'Cancelado')then raise exception 'Pedido já possui embarque ativo. Confira o fluxo existente antes de criar outra entrada';end if;
 if a='compra_nf_ler'then return jsonb_build_object('documento',d,'pedido_versao',p.versao,'itens_pedido',(select jsonb_agg(to_jsonb(i)||jsonb_build_object('unidade_axe',cp.unidade_referencia,'produto_codigo',cp.codigo_axe,'produto_descricao',cp.descricao_referencia,'recebida',public.axe_compra_nfe_recebida(i.id),'fornecedores',(select coalesce(jsonb_agg(to_jsonb(v)),'[]')from public.produtos_fornecedores v where v.produto_id=cp.id and v.fornecedor_id=f.id))order by i.linha)from public.imp_pedido_itens i left join public.produtos_conciliacao cp on cp.id=public.axe_cadastro_canonico('produto',i.produto_id)where i.pedido_id=p.id));end if;
 if p.versao is distinct from (p_dados->>'pedido_versao')::int then raise exception 'Pedido alterado. Leia novamente o XML antes de confirmar';end if;
 dt:=(p_dados->>'data_entrada')::date;
 if dt is null or dt<left(d->>'emissao',10)::date or dt>(clock_timestamp()at time zone 'America/Sao_Paulo')::date then raise exception 'Data da entrada deve ficar entre a emissão da nota e hoje';end if;
 if jsonb_typeof(p_dados->'vinculos')is distinct from 'array' or jsonb_array_length(p_dados->'vinculos')<>jsonb_array_length(d->'itens')then raise exception 'Vincule todos os itens da nota';end if;
 if (select count(distinct x->>'linha')from jsonb_array_elements(p_dados->'vinculos')x)<>jsonb_array_length(d->'itens')then raise exception 'Linha vinculada mais de uma vez';end if;
 if p_dados->>'custos_conferidos'is distinct from 'true'then raise exception 'Confira os custos e os tributos antes de confirmar';end if;
 if length(reason)>2000 then raise exception 'Justificativa excede 2000 caracteres';end if;
 nid:=gen_random_uuid();insert into public.compras_nfe_entradas(id,pedido_id,chave,nome,xml_original,documento,data_entrada,justificativa,usuario_id)values(nid,p.id,d->>'chave',left(coalesce(nullif(p_dados->>'nome',''),'nota.xml'),240),p_dados->>'xml',d,dt,reason,p_usuario);
 for item in select x from jsonb_array_elements(d->'itens')x loop
 select x into mapping from jsonb_array_elements(p_dados->'vinculos')x where x->>'linha'=item->>'linha';
 select * into pi from public.imp_pedido_itens where id=(mapping->>'pedido_item_id')::uuid and pedido_id=p.id for update;
 if not found then raise exception 'Linha %: selecione um item deste pedido',item->>'linha';end if;
 select * into pr from public.produtos_conciliacao where id=public.axe_cadastro_canonico('produto',pi.produto_id)for update;
 if pr.id is null or not pr.ativo or pr.bloqueado_comercial or pr.controla_estoque=false or nullif(btrim(pr.unidade_referencia),'')is null then raise exception 'Linha %: vincule ao pedido um produto ativo com unidade e controle de estoque',pi.linha;end if;
 if upper(btrim(pi.unidade))<>upper(btrim(pr.unidade_referencia))then raise exception 'Unidade do pedido diverge da unidade AXE. Regularize o pedido antes da entrada';end if;
 factor:=public.axe_nfe_numero(nullif(mapping->>'fator',''),8);qty:=(item->>'quantidade')::numeric*factor;qp:=qty;cost:=public.axe_nfe_numero(nullif(mapping->>'custo_total',''),6);
 if nullif(mapping->>'custo_total','')is null or factor<=0 or factor>100000000 or qty<>round(qty,6)or qty>1000000000000 then raise exception 'Informe fator positivo, quantidade até 6 casas e custo total';end if;
 if upper(btrim(item->>'unidade'))=upper(btrim(pr.unidade_referencia))and factor<>1 then raise exception 'Unidades iguais exigem fator 1';end if;
 select * into vinc from public.produtos_fornecedores where produto_id=pr.id and fornecedor_id=f.id and codigo_fornecedor=item->>'codigo' for update;
 if found and vinc.situacao in('BLOQUEADO','INATIVO')then raise exception 'Referência do fornecedor bloqueada ou inativa';end if;
 if found and (upper(coalesce(vinc.unidade_compra,''))<>upper(item->>'unidade')or vinc.fator_conversao is distinct from factor)then diff:=true;end if;
 if upper(btrim(item->>'unidade'))<>upper(btrim(pr.unidade_referencia))then diff:=true;end if;
 if cost is distinct from (item->>'valor_bruto')::numeric or abs((item->>'valor')::numeric/qty-pi.valor_unitario)>.000001 or pi.codigo_fornecedor is distinct from item->>'codigo'then diff:=true;end if;
 if diff and length(reason)<5 then raise exception 'Justifique a conversão de unidade ou a diferença de preço/código/custo';end if;
 received:=public.axe_compra_nfe_recebida(pi.id);if received+qp>pi.quantidade then raise exception 'Linha %: quantidade supera o saldo do pedido (% %)',pi.linha,pi.quantidade-received,pi.unidade;end if;
 if mapping->>'salvar_fornecedor'is distinct from 'true'and(upper(item->>'unidade')<>upper(pr.unidade_referencia)or vinc.id is null or upper(coalesce(vinc.unidade_compra,''))<>upper(item->>'unidade')or vinc.fator_conversao is distinct from factor)then raise exception 'Confirme o cadastro da unidade e conversão na aba Fornecedor do produto';end if;
 if mapping->>'salvar_fornecedor'='true'then
 prev:=case when vinc.id is null then null else to_jsonb(vinc)end;
 insert into public.produtos_fornecedores(produto_id,fornecedor_id,codigo_fornecedor,descricao_fornecedor,unidade_compra,fator_conversao,situacao,moeda,observacoes)
 values(pr.id,f.id,item->>'codigo',item->>'descricao',item->>'unidade',factor,'EM_AVALIACAO','BRL','Unidade conferida na NF-e '||(d->>'chave'))
 on conflict(produto_id,fornecedor_id,codigo_fornecedor)do update set unidade_compra=excluded.unidade_compra,fator_conversao=excluded.fator_conversao,atualizado_em=clock_timestamp();
 insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('pedidos',p.id,p_usuario,prev,jsonb_build_object('origem','Unidade do fornecedor na NF-e','produto_id',pr.id,'fornecedor_id',f.id,'codigo',item->>'codigo','unidade_compra',item->>'unidade','fator_conversao',factor,'justificativa',reason));
 end if;
 insert into public.estoque_movimentos(produto_id,tipo,quantidade,valor_total,custo_unitario,unidade,data_movimento,motivo,referencia,pedido_item_id,cadastro_original,usuario_id)values(pr.id,'ENTRADA',qty,cost,round(cost/qty,8),pr.unidade_referencia,dt,'COMPRA_NACIONAL',p.referencia||' · NF-e '||(d->>'numero')||'/'||(d->>'serie')||' · '||(d->>'chave'),pi.id,jsonb_build_object('id',pr.id,'codigo',pr.codigo_axe,'descricao',pr.descricao_referencia,'unidade',pr.unidade_referencia,'nota_id',nid,'linha_xml',item->'linha'),p_usuario)returning id into mov;
 insert into public.compras_nfe_itens(entrada_id,linha,pedido_item_id,produto_id,quantidade,fator,quantidade_axe,quantidade_pedido,custo_total,movimento_id)values(nid,(item->>'linha')::int,pi.id,pr.id,(item->>'quantidade')::numeric,factor,qty,qp,cost,mov);
 end loop;
 update public.imp_pedidos set versao=versao+1,atualizado_por=p_usuario,atualizado_em=clock_timestamp()where id=p.id;
 perform public.axe_imp_recalcular_status_pedido(p.id);
 res:=jsonb_build_object('id',nid,'pedido_id',p.id,'chave',d->>'chave','status',(select status from public.imp_pedidos where id=p.id));
 insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('pedidos',p.id,p_usuario,to_jsonb(p),res||jsonb_build_object('origem','Entrada NF-e nacional','justificativa',reason));
 end if;
 insert into public.estoque_requisicoes(id,usuario_id,dados,resultado)values(req,p_usuario,p_dados,res);return res;
end $$;
-- Estorne a nota inteira para manter o saldo do pedido consistente.
create function public.axe_compra_nfe_estorno_guard()returns trigger language plpgsql set search_path=''as $$
declare nid uuid;begin if new.estorno_de is not null then select entrada_id into nid from public.compras_nfe_itens where movimento_id=new.estorno_de;
 if nid is not null and current_setting('axe.compra_nf_estorno',true)is distinct from nid::text then raise exception 'Movimento de nota nacional: estorne a nota completa no pedido de compra';end if;end if;return new;end $$;
create trigger compra_nf_estorno_guard before insert on public.estoque_movimentos for each row execute function public.axe_compra_nfe_estorno_guard();
create function public.axe_compra_nfe_item_guard()returns trigger language plpgsql set search_path=''as $$
begin if exists(select 1 from public.compras_nfe_itens x join public.compras_nfe_entradas n on n.id=x.entrada_id where x.pedido_item_id=old.id and n.estado='Confirmada')and(tg_op='DELETE'or (to_jsonb(new)-array['disponibilizada','data_disponibilidade'])is distinct from(to_jsonb(old)-array['disponibilizada','data_disponibilidade']))then raise exception 'Item com NF-e recebida: estorne a nota antes de alterar o pedido';end if;return case when tg_op='DELETE'then old else new end;end $$;
create trigger compra_nf_item_guard before update or delete on public.imp_pedido_itens for each row execute function public.axe_compra_nfe_item_guard();
create function public.axe_compra_nfe_pedido_guard()returns trigger language plpgsql set search_path=''as $$
begin if exists(select 1 from public.compras_nfe_entradas where pedido_id=old.id and estado='Confirmada')and(tg_op='DELETE'or new.fornecedor_id is distinct from old.fornecedor_id or new.moeda is distinct from old.moeda or new.referencia is distinct from old.referencia or new.status='Cancelado')then raise exception 'Pedido com NF-e recebida: estorne a nota antes de cancelar ou alterar fornecedor, moeda ou referência';end if;return case when tg_op='DELETE'then old else new end;end $$;
create trigger compra_nf_pedido_guard before update or delete on public.imp_pedidos for each row execute function public.axe_compra_nfe_pedido_guard();
revoke all on function public.axe_compra_nfe_pedido_guard()from public,anon,authenticated;grant execute on function public.axe_compra_nfe_pedido_guard()to service_role;
revoke all on function public.axe_nfe_texto(xml,text),public.axe_nfe_numero(text,int),public.axe_compra_nfe_ler(text),public.axe_compra_nfe_recebida(uuid),public.axe_compra_nfe(jsonb,uuid),public.axe_compra_nfe_estorno_guard(),public.axe_compra_nfe_item_guard()from public,anon,authenticated;
grant execute on function public.axe_nfe_texto(xml,text),public.axe_nfe_numero(text,int),public.axe_compra_nfe_ler(text),public.axe_compra_nfe_recebida(uuid),public.axe_compra_nfe(jsonb,uuid),public.axe_compra_nfe_estorno_guard(),public.axe_compra_nfe_item_guard()to service_role;

CREATE OR REPLACE FUNCTION public.axe_imp_recalcular_status_pedido(pid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare p public.imp_pedidos; novo text; itens int; completos int; recebidos numeric; embarcado boolean;
begin
 select * into p from public.imp_pedidos where id=pid for update;
 if not found or p.status='Cancelado' then return;end if;
 select count(*),count(*) filter(where recebida>=quantidade),coalesce(sum(recebida),0) into itens,completos,recebidos
 from (select pi.quantidade,coalesce((select sum(ei.recebida) from public.imp_embarque_itens ei join public.imp_embarques e on e.id=ei.embarque_id where ei.pedido_item_id=pi.id and e.status<>'Cancelado'),0)+public.axe_compra_nfe_recebida(pi.id) recebida from public.imp_pedido_itens pi where pi.pedido_id=pid) s;
 select exists(select 1 from public.imp_embarque_itens ei join public.imp_pedido_itens pi on pi.id=ei.pedido_item_id join public.imp_embarques e on e.id=ei.embarque_id where pi.pedido_id=pid and e.status<>'Cancelado') into embarcado;
 novo:=case when itens>0 and completos=itens then 'Recebido' when recebidos>0 then 'Recebimento Parcial' when p.status='Aceito -ACK' or (embarcado and (p.ack_numero is not null and p.ack_data is not null or exists(select 1 from public.imp_estrutura_eventos ev where ev.registro_id=p.id and ev.tipo='pedidos' and (ev.atual->>'status'='Aceito -ACK' or ev.anterior->>'status'='Aceito -ACK')))) then 'Aguardando Entrega' when p.status in ('Recebido','Recebimento Parcial') then case when p.ack_numero is not null and p.ack_data is not null then 'Aceito -ACK' else 'Enviado' end else p.status end;
 if novo is distinct from p.status then
  update public.imp_pedidos set status=novo,versao=versao+1,atualizado_em=clock_timestamp() where id=pid;
  insert into public.imp_estrutura_eventos(tipo,registro_id,usuario_id,anterior,atual)values('pedidos',pid,p.atualizado_por,jsonb_build_object('status',p.status),jsonb_build_object('status',novo,'origem','Quantidades dos itens e embarques ativos'));
 end if;
end $function$;

CREATE OR REPLACE FUNCTION public.axe_imp_estrutura_detalhe(t text, i uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select case t
 when 'pedidos' then (
 select to_jsonb(p)||jsonb_build_object('fornecedor',f.razao_social,'fornecedor_pais',f.pais,'aceite_confirmado',(p.status='Aceito -ACK' or exists(select 1 from public.imp_estrutura_eventos ev where ev.tipo='pedidos' and ev.registro_id=p.id and ev.atual->>'status'='Aceito -ACK')),
 'total',(select coalesce(sum(round(x.quantidade*x.valor_unitario,2)),0) from public.imp_pedido_itens x where x.pedido_id=p.id),
 'itens',(select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object(
 'reservada',(select coalesce(sum(ei.quantidade),0) from public.imp_embarque_itens ei join public.imp_embarques e on e.id=ei.embarque_id where ei.pedido_item_id=x.id and e.status<>'Cancelado'),
 'recebida',(select coalesce(sum(ei.recebida),0) from public.imp_embarque_itens ei join public.imp_embarques e on e.id=ei.embarque_id where ei.pedido_item_id=x.id and e.status<>'Cancelado')+public.axe_compra_nfe_recebida(x.id)) order by x.linha),'[]') from public.imp_pedido_itens x where x.pedido_id=p.id),
 'parcelas',(select coalesce(jsonb_agg(to_jsonb(x) order by x.vencimento nulls last,x.criado_em),'[]') from public.imp_parcelas x where x.pedido_id=p.id))
 from public.imp_pedidos p join public.fornecedores f on f.id=p.fornecedor_id where p.id=i)
 when 'parcelas' then (select to_jsonb(p)||jsonb_build_object('pedido',o.referencia,'moeda',o.moeda) from public.imp_parcelas p join public.imp_pedidos o on o.id=p.pedido_id where p.id=i)
 when 'embarques' then (
 select to_jsonb(e)||jsonb_build_object('fornecedor',f.razao_social,'participantes',(select coalesce(jsonb_agg(jsonb_build_object('papel',ep.papel,'id',ep.fornecedor_id,'nome',emp.razao_social)),'[]') from public.imp_embarque_participantes ep join public.fornecedores emp on emp.id=ep.fornecedor_id where ep.embarque_id=e.id),'itens',(
 select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('pedido',p.referencia,'linha',pi.linha,'descricao',pi.descricao,'produto_id',pi.produto_id,'unidade',pi.unidade,'valor_unitario',pi.valor_unitario) order by p.referencia,pi.linha),'[]')
 from public.imp_embarque_itens x join public.imp_pedido_itens pi on pi.id=x.pedido_item_id join public.imp_pedidos p on p.id=pi.pedido_id where x.embarque_id=e.id))
 from public.imp_embarques e join public.fornecedores f on f.id=e.fornecedor_id where e.id=i)
 end
$function$;

commit;
