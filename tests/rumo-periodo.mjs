import assert from 'node:assert/strict';let handler,url;globalThis.Deno={serve:f=>handler=f,env:{get:k=>k==='SUPABASE_URL'?'https://test.invalid':'test'}};
globalThis.fetch=async s=>{const u=new URL(s);if(u.pathname.includes('/auth/'))return Response.json({id:'u'});if(u.pathname.endsWith('/axe_rumo_revisores'))return Response.json([{}]);url=u;return Response.json([],{headers:{'content-range':'0-0/0'}});};
await import('../backend/axe-cadastros-padrao.ts');
async function call(p){return handler(new Request('https://test.invalid',{method:'POST',headers:{authorization:'Bearer test'},body:JSON.stringify({acao:'listar',secao:'pedidos',pagina:1,status:'ACEITO',situacao_prazo:'ate_10_dias',ordenacao:'data_remessa_asc',...p})}));}
for(const campo of ['data_remessa','data_pedido']){assert.equal((await call({data_campo:campo,data_inicio:'2026-11-03',data_fim:'2026-11-03'})).status,200);const and=url.searchParams.get('and');assert.ok(and.includes(campo+'.gte.2026-11-03'));assert.ok(and.includes(campo+'.lte.2026-11-03'));assert.ok(and.includes('ENTREGUE'));assert.equal(url.searchParams.get('offset'),'50');}
assert.equal((await call({data_inicio:'2026-11-01'})).status,200);assert.ok(url.searchParams.get('and').includes('data_remessa.gte.2026-11-01'));
for(const p of [{data_inicio:'2026-02-30'},{data_fim:'x'},{data_inicio:'2026-12-01',data_fim:'2026-11-01'},{data_campo:'id'}])assert.equal((await call(p)).status,400);
console.log('PASS: datas inclusivas, mesmo dia, só início, dois campos, filtros combinados e validações.');
