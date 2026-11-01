// Offline browser validation of the actual generated atlas. No real infrastructure.
const fs=require('node:fs');
const path=require('node:path');
const {pathToFileURL}=require('node:url');
const {chromium}=require(process.env.PLAYWRIGHT_PATH||'C:/Users/user/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const root=path.resolve(__dirname,'..');
const output=path.join(root,'output/design-components-2026-11-01');
const screens=JSON.parse(fs.readFileSync(path.join(root,'docs/design/screens.json'),'utf8'));
const registry=JSON.parse(fs.readFileSync(path.join(root,'docs/design/components/registry.json'),'utf8'));
const base=pathToFileURL(path.join(root,'docs/design/ServerDeck-design.html')).href;
const report={scope:'Offline HTML design only; not Flutter acceptance',checks:[],errors:[]};
const frames=[{width:1100,height:760},{width:800,height:600},{width:390,height:800},{width:360,height:800}];
async function main(){
 fs.mkdirSync(output,{recursive:true});
 const browser=await chromium.launch({headless:true,channel:'msedge'});
 const queue=[];
 for(const theme of ['dark','light'])for(const frame of frames){
  for(const screen of screens)queue.push({theme,frame,id:screen.id,view:'screens'});
  for(const c of registry.components)for(const state of c.applicableStates)queue.push({theme,frame,id:c.id,view:'components',state});
 }
 await Promise.all(Array.from({length:4},async()=>{
  const page=await browser.newPage();
  let errors=[];
  page.on('pageerror',e=>errors.push(String(e)));
  await page.route('http**/*',route=>{errors.push('Unexpected network access');return route.abort();});
  while(queue.length){
   const job=queue.shift();errors=[];
   try{
    await page.setViewportSize(job.frame);
    const parameters=job.view==='components'?`view=components&component=${job.id}`:`preview=1&screen=${job.id}`;
    await page.goto(`${base}?${parameters}&theme=${job.theme}`);
    await page.waitForFunction(()=>document.body.dataset.ready==='true');
    if(job.view==='components'&&job.state!=='default')await page.locator('#component-state').selectOption(job.state);
    if(['hover','pressed'].includes(job.state)){
     const control=page.locator('#component-preview button:not(:disabled),#component-preview input:not(:disabled),#component-preview summary').filter({visible:true}).first();
     if(await control.count()){await control.hover();if(job.state==='pressed')await page.mouse.down();}
    }
    await page.evaluate(()=>document.fonts.ready);
    const result=await page.evaluate(view=>{
     const content=document.querySelector(view==='components'?'#component-preview':'#app-root');
     return {bodyWidth:document.documentElement.scrollWidth,viewport:innerWidth,text:content.innerText.length,components:content.querySelectorAll('[data-component]').length,broken:[...document.images].filter(i=>!i.complete||!i.naturalWidth).length,hiddenCells:[...content.querySelectorAll('tbody td')].filter(cell=>!cell.closest('[hidden],details:not([open]),dialog:not([open])')&&getComputedStyle(cell).display==='none').map(cell=>cell.textContent)};
    },job.view);
    if(result.bodyWidth>result.viewport+1)errors.push(`Horizontal overflow ${result.bodyWidth}>${result.viewport}`);
    if(result.text<(job.view==='components'?8:30))errors.push('Missing meaningful content');
    if(result.components===0)errors.push('No shared components rendered');
    if(result.broken)errors.push('Broken assets');
    if(result.hiddenCells.length)errors.push(`Hidden supplied fields: ${result.hiddenCells.join(', ')}`);
    if(job.view==='components'&&job.state==='default'&&['C02','C03','C06','C13','C24'].includes(job.id)||job.view==='screens'&&['05-server-list','07-profile-create','22-server-logs','27-job-list'].includes(job.id)){
     await page.screenshot({path:path.join(output,`${job.view}-${job.id}-${job.theme}-${job.frame.width}.png`),fullPage:true});
    }
    if(job.state==='pressed')await page.mouse.up();
    report.checks.push({...job,...result,errors:[...errors]});
    if(report.checks.length%250===0)console.log(`Checked ${report.checks.length} cases`);
    if(errors.length)report.errors.push({...job,errors:[...errors]});
   }catch(error){report.errors.push({...job,errors:[String(error)]});}
  }
  await page.close();
 }));
 await browser.close();
 fs.writeFileSync(path.join(output,'browser-verification.json'),JSON.stringify(report,null,2));
 console.log(JSON.stringify({checks:report.checks.length,errors:report.errors.length,examples:report.errors.slice(0,10)}));
 process.exitCode=report.errors.length?1:0;
}
main().catch(error=>{console.error(error);process.exitCode=1;});
