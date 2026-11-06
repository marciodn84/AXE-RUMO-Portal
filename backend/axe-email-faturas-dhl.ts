import {extrairPaginasPDF} from './pdf-paginas.ts';

const origins = new Set(['https://erp.axeengenharia.com','https://axe-rumo-portal.marciodnmachado.workers.dev','https://marciodn84.github.io']);

function extrair(texto: string) {
  if (!/FATURA DE SERVIÇO/i.test(texto) || !/58[. ]?890[. ]?252[/ ]?0001[- ]?13/.test(texto)) return null;
  function unico(padrao: RegExp) {
    const valores = new Set([...texto.matchAll(padrao)].map(m=>m[1]));
    return valores.size===1 ? [...valores][0] : null;
  }
  const numero=unico(/\bFatura:\s*(GRU[A-Z0-9]{5,30})\b/gi);
  const emissao=unico(/Emissão:\s*(\d{2}\/\d{2}\/\d{4})/gi);
  const vencimento=unico(/Prazo de Pagamento:\s*(\d{2}\/\d{2}\/\d{4})/gi);
  const awb=unico(/^\s*(\d{10})\s+\d{2}\/\d{2}\/\d{4}\s/gm);
  const total=unico(/Valor Total\s*\(BRL\)\s+[\d.,]+\s+[\d.,]+\s+([\d.]+,\d{2})/gi);
  const detalhe=unico(/\bTotal\s*\(BRL\):\s*([\d.]+,\d{2})/gi);
  if(total&&detalhe&&total!==detalhe)return null;
  const valor=total||detalhe;
  if (!numero || !emissao || !vencimento || !awb || !valor) return null;
  const iso=(d:string)=>d.split('/').reverse().join('-');
  return {numero:numero.toUpperCase(),awb,emissao:iso(emissao),vencimento:iso(vencimento),valor:valor.replaceAll('.','').replace(',','.')};
}

Deno.serve(async req=>{
  const origin=req.headers.get('origin')||'';
  const headers:Record<string,string>={'content-type':'application/json','cache-control':'no-store','vary':'Origin',
    'access-control-allow-headers':'authorization,apikey,content-type','access-control-allow-methods':'POST,OPTIONS'};
  if(origins.has(origin))headers['access-control-allow-origin']=origin;
  const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers});
  if(req.method==='OPTIONS')return reply({});
  if(req.method!=='POST')return reply({erro:'Método não permitido'},405);
  try{
    const authorization=req.headers.get('authorization')||'';
    if(!authorization.startsWith('Bearer '))return reply({erro:'Faça login novamente'},401);
    const base=Deno.env.get('SUPABASE_URL'), anon=Deno.env.get('SUPABASE_ANON_KEY')!, service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const auth=await fetch(base+'/auth/v1/user',{headers:{authorization,apikey:anon}});
    if(!auth.ok)return reply({erro:'Sessão inválida'},401);
    const user=await auth.json();
    const rpc=async(name:string,body:unknown)=>{
      const r=await fetch(base+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:service,authorization:'Bearer '+service,'content-type':'application/json'},body:JSON.stringify(body)});
      if(!r.ok)throw Error('Não foi possível consultar os anexos do e-mail');
      return r.json();
    };
    const arquivos=await rpc('axe_dhl_email_arquivos',{p_usuario:user.id});
    let preparadas=0,nao_lidas=0;
    for(const f of arquivos){
      try{
        const paginas=await extrairPaginasPDF(Uint8Array.from(atob(f.pdf),c=>c.charCodeAt(0)));
        const dados=extrair(paginas.map(p=>p.texto).join('\n'));
        if(!dados){nao_lidas++;continue;}
        await rpc('axe_documentos_entrada',{p_usuario:user.id,p_dados:{acao:'email_propor',tipo:'FATURA_TRANSPORTADORA',
          mensagem_id:f.mensagem_id,aplicacao:{...dados,arquivo_id:f.arquivo_id}}});
        preparadas++;
      }catch{nao_lidas++;}
    }
    return reply({preparadas,nao_lidas});
  }catch{return reply({erro:'Não foi possível verificar faturas da DHL no e-mail.'},400);}
});
