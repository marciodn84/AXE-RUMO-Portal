import assert from 'node:assert/strict';
let handler;let captured;
globalThis.Deno={serve:fn=>handler=fn,env:{get:k=>k==='SUPABASE_URL'?'https://test.invalid':'test'}};
globalThis.fetch=async url=>{const u=new URL(url);if(u.pathname==='/auth/v1/user')return Response.json({id:'test-user'});if(u.pathname.endsWith('/axe_rumo_revisores'))return Response.json([{usuario_id:'test-user'}]);captured=u;return Response.json([],{headers:{'content-range':'0-0/53'}});};
await import('../backend/axe-cadastros-padrao.ts');
for(const sort of ['data_pedido_asc','data_pedido_desc','data_remessa_asc','data_remessa_desc']){
 const r=await handler(new Request('https://test.invalid',{method:'POST',headers:{authorization:'Bearer test'},body:JSON.stringify({acao:'listar',secao:'pedidos',pagina:1,status:'AGUARDANDO_ACEITE',busca:'4502',ordenacao:sort})}));
 assert.equal(r.status,200);assert.ok(captured.searchParams.get('and').includes('not.in.(CANCELADO'));assert.equal(captured.searchParams.get('offset'),'50');assert.ok(captured.searchParams.get('order').startsWith(sort.replace(/_(asc|desc)$/,(x,d)=>'.'+d)+'.nullslast'));assert.ok(captured.searchParams.get('or').includes('AGUARDANDO_ACEITE'));assert.equal(captured.searchParams.get('termos_busca'),'ilike.*4502*');
}
const included=await handler(new Request('https://test.invalid',{method:'POST',headers:{authorization:'Bearer test'},body:JSON.stringify({acao:'listar',secao:'pedidos',incluir_cancelados:true,status:'CANCELADO'})}));assert.equal(included.status,200);assert.equal(captured.searchParams.has('and'),false);assert.ok(captured.searchParams.get('or').includes('CANCELADO'));
const bad=await handler(new Request('https://test.invalid',{method:'POST',headers:{authorization:'Bearer test'},body:JSON.stringify({acao:'listar',secao:'pedidos',ordenacao:'id.desc;drop table pedidos'})}));assert.equal(bad.status,400);
console.log('PASS: ordenação global das 4 opções, paginação, filtro, busca, nulos no final e rejeição de parâmetro inválido.');
