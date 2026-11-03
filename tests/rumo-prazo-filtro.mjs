import assert from 'node:assert/strict';
const RealDate=Date;globalThis.Date=class extends RealDate{constructor(...args){super(...(args.length?args:['2026-11-03T02:00:00Z']));}static now(){return new RealDate('2026-11-03T02:00:00Z').getTime();}};
let handler,url;globalThis.Deno={serve:f=>handler=f,env:{get:k=>k==='SUPABASE_URL'?'https://test.invalid':'test'}};
globalThis.fetch=async s=>{const u=new URL(s);if(u.pathname.includes('/auth/'))return Response.json({id:'u'});if(u.pathname.endsWith('/axe_rumo_revisores'))return Response.json([{}]);url=u;return Response.json([],{headers:{'content-range':'0-0/0'}});};
await import('../backend/axe-cadastros-padrao.ts');
async function call(s,incluir=false){return handler(new Request('https://test.invalid',{method:'POST',headers:{authorization:'Bearer test'},body:JSON.stringify({acao:'listar',secao:'pedidos',pagina:1,status:'ACEITO',situacao_prazo:s,incluir_cancelados:incluir,ordenacao:'data_remessa_asc',busca:'4502'})}));}
assert.equal((await call('atrasados')).status,200);assert.equal(url.searchParams.get('data_remessa'),'lt.2026-11-02');assert.equal(url.searchParams.get('offset'),'50');assert.ok(url.searchParams.get('and').includes('ENTREGUE'));assert.ok(url.searchParams.get('or').includes('ACEITO'));
assert.equal((await call('ate_10_dias')).status,200);assert.equal(url.searchParams.get('data_remessa'),'gte.2026-11-02');assert.ok(url.searchParams.get('and').includes('data_remessa.lte.2026-11-12'));
assert.equal((await call('mais_10_dias',true)).status,200);assert.equal(url.searchParams.get('data_remessa'),'gt.2026-11-12');assert.ok(url.searchParams.get('and').includes('Cancelado'));
assert.equal((await call('invalido')).status,400);console.log('PASS: três faixas, hoje e +10 dias inclusivos, fuso São Paulo, filtros combinados, paginação e valor inválido.');
