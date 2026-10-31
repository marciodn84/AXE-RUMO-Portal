export function etapasEmbarque(x){
 const e=x.embarque,docs=x.arquivos_carga||[],di=x.declaracoes||[],notes=x.notas||[];
 const stage=(key,nome,feito,documento,acao,proximo)=>({key,nome,feito:!!feito,documento,acao,proximo});
 return [
 stage('cadastros','Produtos vinculados ao cadastro',e.itens?.every(i=>i.produto_id),'Produto AXE correspondente a cada item do documento','pedido','Mercadoria disponibilizada'),
 stage('carga','Mercadoria disponibilizada',(x.liberacoes||[]).length&&docs.some(f=>f.categoria==='INVOICE')&&docs.some(f=>f.categoria==='PACKING'),'Invoice e packing list da parcial','carga','Preparar transporte'),
 stage('transportador','Transportador vinculado ao cadastro',e.participantes?.some(p=>p.papel==='transportador'),'Empresa transportadora identificada no documento','participantes','Confirmar coleta'),
 stage('transporte','Transporte documentado',x.transporte,'Recibo da transportadora e AWB/BL','transporte','Confirmar coleta'),
 stage('coleta','Coleta realizada',e.dados?.data_coleta,'Confirmação da coleta e data efetiva','embarque','Em trânsito'),
 stage('aduana','Desembaraço registrado',di.some(d=>d.status==='Ativo'&&d.documento_importado&&d.dados?.data_registro&&d.dados?.data_desembaraco),'DI/DUIMP com registro e desembaraço','aduana','Conciliar nota de entrada'),
 stage('nota','Nota de entrada conciliada',notes.some(n=>n.estado==='Conciliada'),'XML e PDF da nota Nomus, vinculados à DI/DUIMP','nota','Confirmar recebimento'),
 stage('recebimento','Mercadoria recebida',e.status==='Recebido'&&e.itens?.every(i=>Number(i.recebida)===Number(i.quantidade)),'Confirmação do recebimento e quantidades','embarque','Confirmar entrada no estoque'),
 stage('estoque','Entrada no estoque confirmada',x.estoque,'Registro da entrada já realizada no Nomus','estoque','Concluir custos e créditos'),
 stage('fechamento','Despesas do processo importadas',(x.fechamentos||[]).some(f=>f.pronto&&f.importado),'Fechamento do despachante e despesas','custo','Concluir custos e créditos'),
 stage('custo','Custos e créditos fechados',x.custo?.estado==='Final','Despesas, tributos e créditos completos na apuração','custo','Parcial concluída')
 ];
}
export function resumirFluxo(data){
 const ships=(data.embarques||[]).map(x=>({...x,etapas:etapasEmbarque(x)}));
 for(const s of ships){s.proxima=s.etapas.find(t=>!t.feito)||null;if(s.proxima){const idx=s.etapas.indexOf(s.proxima);s.proxima.proximo=s.etapas.slice(idx+1).find(t=>!t.feito)?.nome||'Parcial concluída';}s.status=s.proxima?'Aguardando '+s.proxima.nome.toLocaleLowerCase('pt-BR'):'Parcial concluída';}
 const ack=(data.acks||[]).some(x=>x.pronto&&x.aplicado_em),total=Number(data.pedido.total||0),paid=(data.parcelas||[]).filter(x=>x.status!=='Cancelada').reduce((a,x)=>a+Number(x.valor_pago||0),0);
 const saldoFornecedor=(data.pedido.itens||[]).reduce((a,it)=>a+Math.max(0,Number(it.quantidade)-ships.reduce((v,s)=>v+s.embarque.itens.filter(x=>x.pedido_item_id===it.id).reduce((z,x)=>z+Number(x.quantidade),0),0))*Number(it.valor_unitario),0);
 const next=!ack?{nome:'Receber ACK',documento:'ACK do fornecedor',acao:'ack'}:!ships.length?{nome:'Receber a mercadoria pronta',documento:'Invoice e packing list da parcial',acao:'carga'}:ships.find(x=>x.proxima)?.proxima|| (saldoFornecedor>0?{nome:'Aguardar próxima parcial',documento:'Invoice e packing list do saldo',acao:'carga'}:null);
 return {ships,ack,total,paid,saldoFornecedor,next,status:data.pedido.status, andamento:data.pedido.status==='Cancelado'?'Cancelado':!ack?'Aguardando ACK':!ships.length?'Aguardando disponibilização':ships.some(x=>x.proxima)?'Parciais em andamento':saldoFornecedor>0?'Aguardando saldo do fornecedor':'Concluído operacionalmente'};
}
