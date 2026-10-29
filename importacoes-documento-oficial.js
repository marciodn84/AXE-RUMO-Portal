export const temConflitoDocumental=avisos=>(avisos||[]).some(x=>/diverg|conflit|amb[ií]gu|n[aã]o identificad|n[aã]o localizad|diferen[çc]|OCR|incompat[ií]vel/i.test(String(x)));
// The user defined official documents as evidence; request acceptance only for a conflict.
export function aceiteDocumentoOficial(control,conflito=false){
 const label=control.closest('label');if(label)label.hidden=!conflito;
 control.required=!!conflito;if(!conflito)control.checked=true;
 return !conflito||control.checked;
}
