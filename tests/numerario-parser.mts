import {parseNumerario} from '../backend/numerario-parser.ts';
import assert from 'node:assert/strict';
const p=(texto:string)=>[{pagina:1,texto,metodo:'TEXTO'}];
const clean=parseNumerario(p('Valor transferido: R$ 1.234,56\nData da transferencia: 31/10/2026'),'Adiantamento');assert.equal(clean.valor,'1234.56');assert.equal(clean.data,'2026-10-31');
assert.equal(parseNumerario(p('Valor transferido: R$ 1.234,56\nValor transferido: R$ 500,00'),'Adiantamento').valor,null);
assert.throws(()=>parseNumerario(p('Comprovante de agendamento\nValor transferido: R$ 1.234,56'),'Adiantamento'),/agendamento/);
assert.equal(parseNumerario(p('Total do numerario: R$ 8.000,00'),'Numerário prévio').valor,'8000.00');
console.log('PASS: amounts, dates, ambiguity, scheduled transfer and estimate');
