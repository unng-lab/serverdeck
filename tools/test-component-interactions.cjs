// Synthetic owners only: actual pointer/keyboard/form journeys in the offline atlas.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {pathToFileURL}=require('node:url');
const {chromium}=require(process.env.PLAYWRIGHT_PATH||'C:/Users/user/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const base=pathToFileURL(path.resolve(__dirname,'../docs/design/ServerDeck-design.html')).href;
(async()=>{
 const browser=await chromium.launch({headless:true,channel:'msedge'});
 const page=await browser.newPage();const errors=[],checks=[];
 page.on('pageerror',e=>errors.push(String(e)));
 await page.route('http**/*',route=>{errors.push('Unexpected network');return route.abort();});
 const select=async id=>{await page.goto(`${base}?view=components&component=${id}`);await page.waitForFunction(()=>document.body.dataset.ready==='true');};
 const preview=page.locator('#component-preview');
 const action=label=>preview.getByRole('button',{name:label,exact:true});
 for(const theme of ['dark','light']){
  await page.setViewportSize({width:1000,height:800});
  await page.goto(`${base}?view=components&component=C06&theme=${theme}`);await page.waitForFunction(()=>document.body.dataset.ready==='true');
  const assertCells=async()=>{
   const fields=await preview.locator('tbody td[data-sort-value]').evaluateAll(cells=>cells.map(cell=>({text:cell.textContent,visible:getComputedStyle(cell).display!=='none'&&cell.getClientRects().length>0})));
   assert.equal(fields.length,16);assert(fields.every(cell=>cell.visible),JSON.stringify(fields));assert(fields.some(cell=>cell.text==='24 %'));
  };
  await assertCells();
  await page.setViewportSize({width:1800,height:1000});
  for(const containerWidth of [519,520,521,699,700,701]){
   await preview.evaluate((node,width)=>node.style.setProperty('--frame-width',`${width+50}px`),containerWidth);
   await assertCells();
  }
  checks.push(`C06 ${theme}: every field visible at1000viewport and519/520/521/699/700/701container widths`);
 }
 for(const width of [1100,360]){
  await page.setViewportSize({width,height:800});
  for(const id of ['C06','C29']){
   await select(id);
   const ids=()=>preview.locator('tbody tr').evaluateAll(rows=>rows.map(row=>row.dataset.rowId));
   const original=await ids();assert.equal(original.length,id==='C06'?4:3);
   assert(original.every(value=>id==='C29'?value.startsWith('job-'):!value.startsWith('job-')));
   const sort=preview.locator('[data-table-sort="0"]').filter({visible:true}).first();
   await sort.click();await sort.click();
   const ordered=await ids();
   const twins=id==='C06'?['web','web-standby']:['job-check-1','job-check-2'];
   assert(ordered.indexOf(twins[0])<ordered.indexOf(twins[1]));
   const addressSort=preview.locator('[data-table-sort="1"]').filter({visible:true}).first();
   await addressSort.click();await addressSort.click();assert.equal((await ids()).at(-1),id==='C06'?'db':'job-check-2');
   await preview.locator('[data-row-select]:not(:disabled)').first().check();
   assert.match(await preview.locator('[data-selection-count]').innerText(),/1/);
   await preview.getByRole('searchbox').fill('не-существует');assert(await preview.locator('[data-table-no-results]').isVisible());
   await action('Очистить поиск').click();assert.equal(await preview.locator('tbody tr:visible').count(),original.length);
   if(id==='C29'){await action('Удалить выбранные').click();assert.equal((await ids()).length,2);assert.equal(await preview.locator('[data-row-select]:disabled').count(),1);}
   checks.push(`${id} ${width}: stable sort/null, independent IDs, selection, filter/clear, availability`);
  }
 }
 await select('C13');await preview.getByRole('textbox',{name:'Имя сервера',exact:true}).fill('');await action('Сохранить').click();assert.match(await preview.locator('[data-form-errors]').innerText(),/Введите имя/);await preview.getByRole('textbox',{name:'Имя сервера',exact:true}).fill('new');await action('Сохранить').click();assert(!(await preview.locator('[data-form-errors]').isVisible()));checks.push('C13 reachable validation/summary/recovery');
 await select('C26');await preview.locator('textarea').fill('{invalid');await action('Проверить формат').click();assert.match(await preview.locator('[data-form-errors]').innerText(),/JSON/);const raw='  {"new":true}\n';await preview.locator('textarea').fill(raw);await action('Проверить формат').click();assert(!(await preview.locator('[data-form-errors]').isVisible()));await page.evaluate(()=>Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async value=>window.copied=value}}));await action('Копировать текст').click();assert.equal(await page.evaluate(()=>window.copied),raw);checks.push('C26 current raw copy and JSON recovery');
 await select('C28');await preview.locator('[data-date]').fill('2026-02-31');await action('Проверить дату').click();assert(await preview.locator('[data-form-errors]').isVisible());await preview.locator('[data-date]').fill('2026-02-28');await action('Проверить дату').click();assert(!(await preview.locator('[data-form-errors]').isVisible()));checks.push('C28 rejects normalized invalid date');
 await select('C24');assert(await preview.locator('[data-plan-confirm]').isDisabled());await preview.locator('[data-plan-consent]').check();assert(await preview.locator('[data-plan-confirm]').isEnabled());checks.push('C24 explicit consent guard');
 await select('C15');await preview.locator('[data-context-region]').focus();await page.keyboard.press('Shift+F10');assert(await preview.getByRole('menu').isVisible());await page.keyboard.press('ArrowDown');assert.equal(await page.evaluate(()=>document.activeElement.textContent),'Редактировать');await page.keyboard.press('Escape');assert(!(await preview.getByRole('menu').isVisible()));assert(await preview.locator('[data-context-region]').evaluate(node=>node===document.activeElement));checks.push('C15 context keyboard/arrow/Escape focus return');
 await select('C23');for(const [state,text] of Object.entries({success:'Завершено',error:'Ошибка',cancelled:'Отменено',unknown:'Исход неизвестен'})){await page.locator('#component-state').selectOption(state);assert((await preview.innerText()).includes(text));}checks.push('C23 terminal outcomes');
 await select('C02');const button=action('Создать профиль');await button.hover();assert(await button.evaluate(node=>node.matches(':hover')));await page.mouse.down();assert(await button.evaluate(node=>node.matches(':active')));await page.mouse.up();await page.locator('#component-state').selectOption('focus');assert(await button.evaluate(node=>node===document.activeElement));await page.locator('#component-state').selectOption('disabled');assert(await button.isDisabled());checks.push('C02 real hover/pressed/focus/disabled');
 assert.deepEqual(errors,[]);
 const report={scope:'Offline HTML synthetic interactions; not native Flutter',checks,errors};fs.writeFileSync(path.resolve(__dirname,'../output/design-components-2026-11-01/browser-interactions.json'),JSON.stringify(report,null,2));
 await browser.close();console.log(JSON.stringify(report));
})().catch(error=>{console.error(error);process.exitCode=1;});
