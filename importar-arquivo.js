// Leitura local de CSV/XLSX. Não executa fórmulas, macros ou vínculos externos.
const LIMIT=15000000, XML_LIMIT=10000000;
const xml=text=>{if(/<!DOCTYPE|<!ENTITY/i.test(text))throw Error('XML com entidades externas não é aceito.');const doc=new DOMParser().parseFromString(text,'application/xml');if(doc.querySelector('parsererror'))throw Error('Conteúdo XML inválido.');return doc;};
const all=(doc,name)=>[...doc.getElementsByTagNameNS('*',name)];
const textOf=n=>all(n,'t').map(t=>t.textContent).join('');
function csv(text){
 const first=text.split(/\r?\n/,1)[0];const delimiter=[';',',','\t'].sort((a,b)=>first.split(b).length-first.split(a).length)[0];
 const rows=[];let cells=[],value='',quoted=false;
 for(let i=0;i<=text.length;i++){
  const ch=text[i];if(ch==='"'){if(quoted&&text[i+1]==='"'){value+='"';i++;}else if(quoted||value==='')quoted=!quoted;else value+=ch;}
  else if(!quoted&&(ch===delimiter||ch==='\n'||ch==='\r'||ch===undefined)){
   cells.push(value);value='';if(ch!==delimiter){rows.push({numero:rows.length+1,cells,formulas:[]});cells=[];if(ch==='\r'&&text[i+1]==='\n')i++;}
  }else if(ch!==undefined)value+=ch;
  if(rows.length>5020||cells.length>300||value.length>25000)throw Error('Arquivo excede 5.000 linhas, 300 colunas ou o limite de texto.');
 }if(quoted)throw Error('CSV contém aspas não fechadas.');return [{nome:'CSV',rows}];
}
async function unzip(buffer){
 const bytes=new Uint8Array(buffer),view=new DataView(buffer);let end=-1;
 for(let i=bytes.length-22;i>=Math.max(0,bytes.length-65557);i--)if(view.getUint32(i,true)===0x06054b50){end=i;break;}
 if(end<0)throw Error('Arquivo não é um XLSX válido.');const count=view.getUint16(end+10,true),offset=view.getUint32(end+16,true);if(count>2000||count===65535)throw Error('Arquivo XLSX excede os limites de leitura.');
 const entries=new Map();let pos=offset,total=0;
 for(let i=0;i<count;i++){
  if(pos+46>bytes.length||view.getUint32(pos,true)!==0x02014b50)throw Error('Diretório ZIP inválido.');
  const flags=view.getUint16(pos+8,true),method=view.getUint16(pos+10,true),size=view.getUint32(pos+20,true),expanded=view.getUint32(pos+24,true),len=view.getUint16(pos+28,true),extra=view.getUint16(pos+30,true),comment=view.getUint16(pos+32,true),local=view.getUint32(pos+42,true);
  const name=new TextDecoder().decode(bytes.slice(pos+46,pos+46+len));if(flags&1)throw Error('Arquivo protegido por senha não é aceito.');if(name.includes('..')||name.startsWith('/')||entries.has(name))throw Error('Caminho ZIP inválido.');
  entries.set(name,{method,size,expanded,local});pos+=46+len+extra+comment;
 }
 return async name=>{
  const e=entries.get(name);if(!e)return null;if(e.expanded>XML_LIMIT||total+e.expanded>40000000)throw Error('Planilha descompactada excede o limite.');
  if(e.local+30>bytes.length||view.getUint32(e.local,true)!==0x04034b50)throw Error('Entrada ZIP inválida.');const start=e.local+30+view.getUint16(e.local+26,true)+view.getUint16(e.local+28,true);if(start+e.size>bytes.length)throw Error('Arquivo incompleto.');
  let data=bytes.slice(start,start+e.size);
  if(e.method===8){const reader=new Blob([data]).stream().pipeThrough(new DecompressionStream('deflate-raw')).getReader();let size=0;const chunks=[];for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>XML_LIMIT){await reader.cancel();throw Error('Conteúdo descompactado excede o limite.');}chunks.push(value);}data=new Uint8Array(size);let n=0;for(const chunk of chunks){data.set(chunk,n);n+=chunk.length;}}
  else if(e.method!==0)throw Error('Compressão XLSX não suportada.');if(data.length!==e.expanded)throw Error('Tamanho do conteúdo XLSX inconsistente.');total+=data.length;return new TextDecoder().decode(data);
 };
}
export async function lerArquivo(buffer,name){
 if(buffer.byteLength>LIMIT)throw Error('Use um arquivo de até 15 MB.');
 if(/\.csv$/i.test(name)){let text;try{text=new TextDecoder('utf-8',{fatal:true}).decode(buffer);}catch{throw Error('Salve o CSV em UTF-8 ou utilize XLSX.');}return csv(text.replace(/^\uFEFF/,''));}
 if(!/\.xlsx$/i.test(name))throw Error('Selecione um arquivo XLSX ou CSV.');
 const get=await unzip(buffer),book=await get('xl/workbook.xml'),rels=await get('xl/_rels/workbook.xml.rels');if(!book||!rels)throw Error('Estrutura do XLSX não encontrada.');
 const sharedText=await get('xl/sharedStrings.xml'),strings=sharedText?all(xml(sharedText),'si').map(textOf):[],relationships=new Map(all(xml(rels),'Relationship').filter(r=>r.getAttribute('TargetMode')!=='External').map(r=>[r.getAttribute('Id'),r.getAttribute('Target')]));
 const sheets=[];for(const sheet of all(xml(book),'sheet')){
  if(sheets.length>=20)throw Error('Use um arquivo com até 20 abas.');const rel=sheet.getAttributeNS('http://schemas.openxmlformats.org/officeDocument/2006/relationships','id'),target=relationships.get(rel);if(!target||target.includes('..')||target.includes(':'))continue;
  const path=target.startsWith('/xl/')?target.slice(1):'xl/'+target;const content=await get(path);if(!content)continue;
  const rows=[];for(const row of all(xml(content),'row')){
   const cells=[],formulas=[];for(const cell of all(row,'c')){const ref=cell.getAttribute('r')||'',letters=ref.match(/^[A-Z]+/)?.[0];if(!letters)continue;let index=0;for(const l of letters)index=index*26+l.charCodeAt(0)-64;index--;if(index>=300)throw Error('A planilha excede 300 colunas.');const type=cell.getAttribute('t'),value=all(cell,'v')[0]?.textContent||'';cells[index]=type==='s'?(strings[Number(value)]??''):type==='inlineStr'?textOf(cell):value;if(all(cell,'f').length)formulas.push(index);}
   rows.push({numero:Number(row.getAttribute('r'))||rows.length+1,cells,formulas});if(rows.length>5020)throw Error('A planilha excede 5.000 linhas de dados.');
  }sheets.push({nome:sheet.getAttribute('name')||'Planilha',rows});
 }if(!sheets.length)throw Error('Nenhuma aba de dados foi encontrada.');return sheets;
}
