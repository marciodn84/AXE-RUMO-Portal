export function prazoEntrega(registro,hoje=new Date().toLocaleDateString('en-CA',{timeZone:'America/Sao_Paulo'})){
 const fase=registro.fase_status_sap||registro.status_texto;
 if(['ENTREGUE','Entregue'].includes(fase))return{texto:'Entregue',cor:'#64748b',icone:'✓'};
 if(['CANCELADO','Cancelado','CANCELADO_PDF_SEM_PRODUTOS','ITEM_EXCLUIDO_PDF'].includes(fase))return{texto:'Cancelado',cor:'#64748b',icone:'—'};
 const parse=value=>{if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value))return null;const n=Date.parse(value+'T00:00:00Z');return Number.isFinite(n)&&new Date(n).toISOString().slice(0,10)===value?n:null;};
 const prazo=parse(registro.data_remessa),dia=parse(hoje);
 if(prazo===null||dia===null)return{texto:'Sem data de remessa',cor:'#64748b',icone:'●'};
 const dias=Math.round((prazo-dia)/86400000);
 return dias<0?{texto:'Atrasado há '+(-dias)+' dia'+(dias===-1?'':'s'),cor:'#dc2626',icone:'●',dias}:dias===0?{texto:'Vence hoje',cor:'#b77900',icone:'●',dias}:{texto:'Faltam '+dias+' dia'+(dias===1?'':'s'),cor:dias>10?'#15803d':'#b77900',icone:'●',dias};
}
