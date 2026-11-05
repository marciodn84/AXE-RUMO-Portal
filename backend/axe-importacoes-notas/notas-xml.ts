import { XMLParser, XMLValidator } from 'npm:fast-xml-parser@5.11.2';
const list=(x:any)=>x==null?[]:Array.isArray(x)?x:[x];
const text=(x:any,limit=2000)=>{if(x!=null&&typeof x==='object')throw Error('Campo XML repetido ou inválido');return String(x??'').trim().slice(0,limit);};
const decimal=(x:any,scale=6,required=false)=>{const v=text(x,80);if(!v&&!required)return '0';if(!new RegExp('^\\d{1,12}(?:\\.\\d{1,'+scale+'})?$').test(v))throw Error('Valor numérico inválido no XML');return v;};
export function parseNFe(xml:string, direcao:"0"|"1"="0"){
 if(!xml||xml.length>2097152||/<!DOCTYPE|<!ENTITY/i.test(xml))throw Error('XML inválido ou com entidades não permitidas');
 if(XMLValidator.validate(xml)!==true)throw Error('XML malformado');
 // Bound nesting before constructing an object, even for small hostile XMLs.
 let depth=0;for(const m of xml.matchAll(/<\/?[A-Za-z_][^>]*>/g)){if(m[0].startsWith('</'))depth--;else if(!m[0].endsWith('/>'))depth++;if(depth>40)throw Error('XML excede a profundidade permitida');}
 const doc=new XMLParser({ignoreAttributes:false,parseTagValue:false,parseAttributeValue:false,removeNSPrefix:true,processEntities:false,trimValues:true}).parse(xml);
 const roots=Object.keys(doc).filter(k=>!k.startsWith('?'));if(roots.length!==1||!['NFe','nfeProc'].includes(roots[0]))throw Error('Selecione um XML de NF-e, modelo 55');
 const proc=doc.nfeProc,nfe=proc?proc.NFe:doc.NFe,inf=nfe?.infNFe,ide=inf?.ide;
 if(!inf||Array.isArray(nfe)||Array.isArray(inf)||!ide||Array.isArray(ide)||text(ide.mod)!=='55'||text(ide.tpNF)!==direcao)throw Error(direcao==='0'?'Selecione uma NF-e de entrada, modelo 55':'Selecione uma NF-e de saída, modelo 55');
 const chave=text(inf['@_Id']).replace(/^NFe/,'');if(!/^\d{44}$/.test(chave))throw Error('Chave da NF-e inválida');
 let sum=0,w=2;for(let i=42;i>=0;i--){sum+=Number(chave[i])*w;w=w===9?2:w+1;}const rem=sum%11;
 if(Number(chave[43])!==(rem<2?0:11-rem))throw Error('Dígito verificador da chave inválido');
 const cnpj=text(inf.emit?.CNPJ),numero=text(ide.nNF),serie=text(ide.serie),emissao=text(ide.dhEmi||ide.dEmi),ambiente=text(ide.tpAmb);
 if(!/^\d{14}$/.test(cnpj)||!/^\d{1,9}$/.test(numero)||!/^\d{1,3}$/.test(serie)||!/^\d{4}-\d{2}-\d{2}(T.*)?$/.test(emissao)||isNaN(Date.parse(emissao)))throw Error('Identificação da NF-e incompleta');
 if(chave.slice(6,20)!==cnpj||chave.slice(20,22)!=='55'||chave.slice(22,25)!==serie.padStart(3,'0')||chave.slice(25,34)!==numero.padStart(9,'0')||chave.slice(2,6)!==emissao.slice(2,4)+emissao.slice(5,7))throw Error('Chave diverge dos dados da nota');
 const prot=proc?.protNFe?.infProt;if(Array.isArray(proc?.protNFe)||Array.isArray(prot))throw Error('Protocolo repetido');
 if(prot&&(text(prot.chNFe)!==chave||text(prot.tpAmb)!==ambiente))throw Error('Protocolo diverge da chave ou do ambiente');
 const protocolo=text(prot?.nProt),autorizada=['100','150'].includes(text(prot?.cStat))&&/^\d{15}$/.test(protocolo)&&ambiente==='1'&&!!nfe.Signature;
 const itens=list(inf.det).map((d:any)=>{
  const p=d.prod;if(!p||Array.isArray(p))throw Error('Produto inválido no XML');
  const linha=text(d['@_nItem']);if(!/^\d{1,4}$/.test(linha)||Number(linha)<1)throw Error('Linha XML inválida');
  const quantidade=decimal(p.qCom,4,true);if(Number(quantidade)<=0)throw Error('Quantidade deve ser positiva');
  const impostos:Record<string,string>={},impostos_presentes:string[]=[];
  function find(o:any,k:string):string|undefined{if(!o||typeof o!=='object')return;for(const [key,v]of Object.entries(o)){if(key===k)return decimal(v,2);const r=find(v,k);if(r!==undefined)return r;}}
  for(const [k,tag]of Object.entries({II:'vII',IPI:'vIPI',ICMS:'vICMS',PIS:'vPIS',COFINS:'vCOFINS',IBS:'vIBS',CBS:'vCBS'})){const v=find(d.imposto,tag);impostos[k]=v||'0';if(v!==undefined)impostos_presentes.push(k);}
  const declaracoes=list(p.DI).map((di:any)=>({numero:text(di.nDI,60),data_registro:text(di.dDI,10),data_desembaraco:text(di.dDesemb,10),adicoes:list(di.adi).map((a:any)=>({numero:text(a.nAdicao,6),sequencia:text(a.nSeqAdic,6)}))}));
  if(declaracoes.length>100)throw Error('Declarações em excesso');
  return {linha:Number(linha),codigo:text(p.cProd,200),descricao:text(p.xProd),ncm:text(p.NCM,8),cfop:text(p.CFOP,4),unidade:text(p.uCom,20),quantidade,valor_unitario:decimal(p.vUnCom,10,true),valor:decimal(p.vProd,2,true),frete:decimal(p.vFrete,2),seguro:decimal(p.vSeg,2),outras:decimal(p.vOutro,2),desconto:decimal(p.vDesc,2),pedido_xml:text(p.xPed,200),linha_pedido_xml:text(p.nItemPed,20),declaracoes,impostos,impostos_presentes};
 });
 if(!itens.length||itens.length>500||new Set(itens.map((x:any)=>x.linha)).size!==itens.length)throw Error('Itens ausentes, repetidos ou acima do limite de 500');
 const t=inf.total?.ICMSTot;if(!t||Array.isArray(t))throw Error('Totais fiscais ausentes');
 const totais:Record<string,string>={};for(const k of ['vNF','vProd','vFrete','vSeg','vOutro','vDesc','vII','vIPI','vICMS','vPIS','vCOFINS'])totais[k]=decimal(t[k],2,k==='vNF'||k==='vProd');
 const cent=(s:string)=>BigInt(s.replace('.','').padEnd(s.includes('.')?s.indexOf('.')+2:s.length+2,'0'));
 // vProd includes only indTot=1; preserve that flag when checking the header.
 const soma=itens.reduce((a:any,x:any,i:number)=>text(list(inf.det)[i].prod.indTot)==='0'?a:a+cent(x.valor),0n);
 const dif=soma-cent(totais.vProd);const avisos:string[]=[];if(dif>1n||dif< -1n)avisos.push('Total dos produtos diverge da soma das linhas do XML');
 if(!autorizada)avisos.push(ambiente!=='1'?'XML de homologação: não pode ser conciliado como nota de produção':'XML sem protocolo de autorização e assinatura informados: trate como rascunho');
 return {chave,numero,serie,emissao,cnpj,emitente:text(inf.emit?.xNome),ambiente,protocolo,autorizada,totais,itens,avisos,observacoes:text(inf.infAdic?.infCpl,10000)};
}

