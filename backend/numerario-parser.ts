import {parseFechamento,dataBR} from './fechamento-parser.ts';
export function parseNumerario(pages:any[],categoria:string){
 if(categoria==='Fechamento')return parseFechamento(pages);
 const text=pages.map(p=>p.texto).join('\n').normalize('NFD').replace(/[\u0300-\u036f]/g,'');
 if(['Adiantamento','Complemento','Devolução'].includes(categoria)&&/AGENDADO|AGENDAMENTO|PENDENTE DE EFETIVACAO/i.test(text)&&!/EFETIVADO|CONCLUIDO|REALIZADO COM SUCESSO/i.test(text))throw Error('Documento de agendamento: anexe o comprovante da transferência efetivada.');
 const refs=[...new Set([...text.matchAll(/(?:END\s*TO\s*END|E2E|ID DA TRANSACAO|AUTENTICACAO)\s*[:\-]?\s*([A-Z0-9-]{8,100})/gi)].map(m=>m[1].toUpperCase()))];
 const label=categoria==='Numerário prévio'?'(?:TOTAL (?:DO NUMERARIO|A DEPOSITAR)|VALOR (?:A ANTECIPAR|DO NUMERARIO))':'(?:VALOR (?:TRANSFERIDO|PAGO|DA TRANSFERENCIA|DA TRANSACAO|TOTAL|DO DOCUMENTO)|TOTAL A PAGAR)';
 const re=new RegExp(label+'\\s*[:\\-]?\\s*(?:R\\$\\s*)?([0-9.]+,[0-9]{2})','gi');
 const values=[...new Set([...text.matchAll(re)].map(m=>m[1].replace(/\./g,'').replace(',','.')))];
 const dates=[...new Set([...text.matchAll(/(?:DATA (?:DA TRANSFERENCIA|DO PAGAMENTO|DA TRANSACAO|DE EFETIVACAO)|REALIZADO EM)\s*[:\-]?\s*(\d{2}\/\d{2}\/\d{4})/gi)].map(m=>dataBR(m[1])).filter(Boolean))];
 return {referencia_bancaria:refs.length===1?refs[0]:null,valor:values.length===1?values[0]:null,data:dates.length===1?dates[0]:null,avisos:[...(values.length!==1?['Valor ausente ou ambíguo: confira o documento.']:[]),...(['Adiantamento','Complemento','Devolução'].includes(categoria)&&dates.length!==1?['Data efetiva não identificada: confira o comprovante.']:[])]};
}
