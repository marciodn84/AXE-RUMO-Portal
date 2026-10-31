// Quantities only: invoice count and payment value never determine shipment scope.
export function classificarEmbarque(itensPedido,itensEmbarque){
 const qty=v=>{if(v===null||v===undefined||v==='')return null;const s=String(v);if(!/^\d+(?:\.\d{1,12})?$/.test(s))return null;const [a,b='']=s.split('.');return BigInt(a)*10n**12n+BigInt(b.padEnd(12,'0'));};
 if(!Array.isArray(itensPedido)||!itensPedido.length||!Array.isArray(itensEmbarque)||!itensEmbarque.length)return 'A conferir';
 const selected=new Map();for(const x of itensEmbarque){const v=qty(x.quantidade);if(!x.pedido_item_id||v===null||v<=0n||selected.has(x.pedido_item_id)||!itensPedido.some(p=>p.id===x.pedido_item_id))return 'A conferir';selected.set(x.pedido_item_id,v);}
 let falta=false,temSaldo=false;for(const p of itensPedido){const ordered=qty(p.quantidade),reserved=qty(p.reservada);if(ordered===null||reserved===null||reserved>ordered)return 'A conferir';const saldo=ordered-reserved,chosen=selected.get(p.id)||0n;if(chosen>saldo)return 'A conferir';if(saldo>0n)temSaldo=true;if(chosen<saldo)falta=true;}
 return !temSaldo?'A conferir':falta?'Parcial':'Total';
}
