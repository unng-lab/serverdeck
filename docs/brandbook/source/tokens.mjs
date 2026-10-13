import fs from 'node:fs/promises';
import { Workbook, SpreadsheetFile } from '@oai/artifact-tool';
const root = new URL('../', import.meta.url);
const rows = JSON.parse(await fs.readFile(new URL('tokens/token-rows.json',root),'utf8'));
const wb = Workbook.create();
const sheet = wb.worksheets.add('Design tokens');
sheet.showGridLines = false;
sheet.getRange('A2').values = [['ServerDeck / Design tokens 1.0']];
sheet.getRange('A2').format.font = {name:'Arial',size:15,bold:true,color:'#172337'};
sheet.getRange(`A4:D${rows.length+3}`).values = rows;
const table=sheet.tables.add(`A4:D${rows.length+3}`,true,'DesignTokens');
table.showFilterButton=true;
sheet.getRange(`A4:D${rows.length+3}`).format.font = {name:'Arial',size:11,color:'#172337'};
sheet.getRange(`A4:D${rows.length+3}`).format.rowHeight=25;
sheet.getRange('A4:D4').format.fill='#172337';
sheet.getRange('A4:D4').format.font={name:'Arial',size:11,bold:true,color:'#FFFFFF'};
sheet.getRange('A:A').format.columnWidth=28;
sheet.getRange('B:C').format.columnWidth=36;
sheet.getRange('D:D').format.columnWidth=62;
sheet.freezePanes.freezeRows(4);
for(let i=1;i<rows.length;i++){
  if(String(rows[i][0]).startsWith('color.')){
    for(const [j,col] of [[1,'B'],[2,'C']]){
      const cell=sheet.getRange(`${col}${i+4}`);
      cell.format.fill=rows[i][j];
      const hex=rows[i][j].slice(1);
      const rgb=[0,2,4].map(p=>parseInt(hex.slice(p,p+2),16)/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4);
      const lum=rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722;
      cell.format.font={name:'Arial',size:11,color:lum>.179?'#000000':'#FFFFFF'};
    }
  }
}
wb.recalculate();
console.log((await wb.inspect({kind:'table',range:'Design tokens!A4:D10',include:'values',tableMaxRows:7,tableMaxCols:4,maxChars:2000})).ndjson);
const png=await wb.render({sheetName:'Design tokens',range:'A2:D18',scale:1.3});
await fs.writeFile(new URL('qa/tokens-preview.png',root),new Uint8Array(await png.arrayBuffer()));
const pngRest=await wb.render({sheetName:'Design tokens',range:`A19:D${rows.length+3}`,scale:1});
await fs.writeFile(new URL('qa/tokens-preview-rest.png',root),new Uint8Array(await pngRest.arrayBuffer()));
await (await SpreadsheetFile.exportXlsx(wb)).save(new URL('tokens/design-tokens.xlsx',root).pathname.replace(/^\/([A-Za-z]:)/,'$1'));
console.log('Exported design-tokens.xlsx');
