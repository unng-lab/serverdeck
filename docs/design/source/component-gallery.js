'use strict';
const UI=window.DeckDesign;
const registry=window.SERVERDECK_COMPONENT_REGISTRY;
const gallery=document.getElementById('component-gallery');
const preview=document.getElementById('component-preview');
const query=new URLSearchParams(location.search);
let componentId=registry.components.some(c=>c.id===query.get('component'))?query.get('component'):'C06';
let componentState='default';
let shellSection='Серверы';
let currentView='components';
const action=(label,variant='outlined')=>UI.button(label,{variant,attributes:`data-component-action="${UI.escape(label)}"`});
const row=(label,description='',trailing='')=>UI.list([{title:label,description,trailing}]);
const field=(label,value='atlas-web',type='text')=>UI.field(label,`<input type="${type}" value="${UI.escape(value)}" aria-label="${UI.escape(label)}">`);
const status=(text,tone='available')=>`<span class="status ${tone}" data-component="C10"><i aria-hidden="true">${tone==='error'?'×':tone==='unknown'?'?':'✓'}</i>${UI.escape(text)}</span>`;
const textSample='Имя сервера и параметры подключения. Точное значение сохраняется при смене темы и ширины.';
const tableSample=()=>componentState==='unavailable'?UI.notice('Возможность недоступна','Нет разрешённого источника данных.',{tone:'warning'}):UI.table({columns:['Сервер','Адрес','Состояние','CPU'],interactive:true,ids:['web','db','web-standby','blocked'],blocked:['blocked'],rows:componentState==='empty'?[]:[['atlas-web','192.0.2.14','Доступен','24 %'],['atlas-db',null,'Неизвестно',null],['atlas-web','192.0.2.31','Доступен','12 %'],['atlas-worker','192.0.2.32','Недоступен',null]],cell:(value,column)=>column==='Состояние'?status(value,value==='Доступен'?'available':value==='Неизвестно'?'unknown':'error'):UI.escape(value??'Нет данных')});
const searchBox=()=>`<div class="sample-actions"><input type="search" aria-label="Поиск" placeholder="Поиск" data-component-search value="${componentState==='no-results'?'нет-совпадений':''}">${action('Очистить поиск','text')}</div>`;
const resultText=text=>preview.querySelector('.component-result').textContent=text;


function sample(id){
  if(componentState==='empty'&&['C07','C20','C22','C25','C27'].includes(id))return UI.empty('Записей пока нет','Успешно получен пустой набор данных.');
  if(componentState==='unavailable'&&['C17','C24','C27','C29'].includes(id))return UI.notice('Возможность недоступна','Источник не разрешён в текущем контексте. Действия заблокированы.',{tone:'warning'});
  if(componentState==='unknown'&&id==='C18')return UI.list([{title:'Адрес',description:'Нет подтверждённых данных. Копирование отсутствует.'}]);
  if(componentState==='unknown'&&id==='C21')return UI.list([{title:'CPU',description:'Нет данных'},{title:'Память',description:'Нет данных; лимит неизвестен'}]);
  switch(id){
    case'C01':return `<div class="sample-grid">${['bg','surface','raised','hover','selected','text','muted','border','control','accent','onAccent','accentHover','focus','disabled','available','unavailable','unknown','warning','error','running','success','chart2','chart3'].map(role=>`<div><div class="token-swatch" style="background:var(--${role})"></div><span class="sample-token">${role}</span></div>`).join('')}</div><h1>Заголовок страницы · 24/32</h1><p>${textSample}</p><code>Noto Sans Mono · 13/20 · 192.0.2.14:22</code>`;
    case'C02':return `<div class="sample-actions">${action('Создать профиль','filled')}${action('Редактировать')}${action('Подробнее','text')}${action('Удалить профиль','danger')}${UI.button('Недоступно',{disabled:true})}</div>`;
    case'C03':return `<div class="sample-grid">${field('Имя сервера')}${UI.field('Порт SSH','<div class="input-affix"><span>SSH</span><input aria-label="Порт SSH" value="22" type="number"><span>port</span></div>')}${UI.field('Идентификатор','<input aria-label="Идентификатор" readonly value="server-demo-014">')}${field('Пароль','demo-only','password')}${UI.field('Описание','<textarea aria-label="Описание">Локальный профиль сервера</textarea>')}${UI.field('Адрес','<input aria-label="Адрес" value="" aria-invalid="true">',{error:'Введите адрес сервера'})}</div>`;
    case'C04':return `<div class="sample-grid">${UI.field('Способ доступа','<select aria-label="Способ доступа"><option>Ключ SSH</option><option>Пароль</option></select>')}<div><label class="sample-line"><input type="checkbox" checked>Показывать только доступные</label><label class="sample-line"><input type="radio" name="zone" checked>UTC</label><label class="sample-line"><input type="radio" name="zone">Локальное время</label><label class="sample-line"><input type="checkbox" role="switch" checked>Уведомления</label><div class="segmented" role="group" aria-label="Режим">${['Список','Таблица'].map((label,i)=>`<button type="button" class="button" data-segment aria-pressed="${i===(componentState==='selected'?1:0)}">${label}</button>`).join('')}</div></div></div>`;
    case'C05':return searchBox()+tableSample();
    case'C06':return searchBox()+tableSample();
    case'C07':return UI.list([{title:'atlas-web',description:'192.0.2.14 · Ubuntu 24.04',trailing:UI.button('Выбрать atlas-web',{attributes:`data-list-select aria-pressed="${componentState==='selected'}"`})},{title:'atlas-db',description:'192.0.2.28 · PostgreSQL',trailing:action('Открыть')}]);
    case'C08':return `<div class="sample-actions">${UI.button('Назад',{disabled:true,attributes:'data-page-delta="-1"'})}<span data-page-label data-page="1" data-unknown="${componentState==='unknown'}">Страница 1${componentState==='unknown'?' · всего неизвестно':' из 4'}</span>${UI.button('Далее',{attributes:'data-page-delta="1"'})}${UI.field('Записей на странице','<select aria-label="Записей на странице" data-page-size><option>25</option><option>50</option><option>100</option></select>')}</div>${action('Показать ещё')}`;
    case'C09':return UI.surface('Сведения о сервере',`<div class="panel-body"><p>${textSample}</p>${componentState==='error'?'<p role="alert">Не удалось обновить карточку.</p>':''}${UI.button('Выбрать карточку',{attributes:`data-card-select aria-pressed="${componentState==='selected'}"`})}</div>`,{subtitle:'Заголовок, описание, содержимое и действия',classes:componentState==='selected'?'card-selected':''});
    case'C10':return `<div class="sample-actions">${status('Доступен')}${status('Недоступен','error')}${status('Неизвестно','unknown')}${status('Требует внимания','warning')}${status('Выполняется','running')}<span class="tag">production</span><span class="status error" aria-label="3 уведомления">3</span></div>`;
    case'C11':return `${UI.notice('Профиль сохранён','Параметры обновлены локально.',{tone:'success'})}${UI.notice('SSH-ключ изменился','Подключение заблокировано. Проверьте ключ по доверенному каналу.',{tone:'error'})}${UI.notice('Исход неизвестен','Сначала проверьте состояние операции; повтор не выполняется.',{tone:'warning'})}`;
    case'C12':return componentState==='pending'?'<div class="empty-state"><span class="loader"></span><h2>Получаем данные</h2><p>Первое наблюдение ещё не получено.</p></div>':UI.empty(({error:'Не удалось получить данные','no-results':'Ничего не найдено',unavailable:'Возможность недоступна',stale:'Данные устарели',partial:'Данные получены не полностью',unknown:'Состояние данных неизвестно'})[componentState]||'Записей пока нет',componentState==='stale'?'Предыдущий снимок: atlas-web · 10:42 UTC':componentState==='partial'?'Получены 2 из 3 записей.':componentState==='unknown'?'Подтверждённое наблюдение ещё не получено.':'Проверьте выбранный контекст и допустимый следующий шаг.')+(['focus','hover','pressed','error'].includes(componentState)?action('Повторить чтение'):componentState==='no-results'?action('Очистить поиск'):'');
    case'C13':return UI.surface('Параметры подключения',`<form data-component-form data-validation="profile" novalidate class="panel-body sample-stack"><p data-form-errors role="alert" hidden></p>${UI.field('Имя сервера',`<input aria-label="Имя сервера" required value="${componentState==='error'?'':'atlas-web'}">`)}${field('Адрес','192.0.2.14')}<div class="sample-actions"><button type="submit" class="button primary">Сохранить</button>${action('Отмена','text')}</div></form>`,{subtitle:'Валидация и обработка отправки принадлежат экрану'});
    case'C14':return ['Информационный диалог','Редактирование профиля','Подтверждение удаления'].map((title,i)=>`${UI.surface(title,`<div class="panel-body"><p>atlas-web · 192.0.2.14</p>${i===1?field('Имя профиля'):i===2?UI.notice('Удаление локального профиля','На сервере ничего не изменится.',{tone:'warning'}):'<p>Параметры доступны только локально.</p>'}${UI.button('Открыть '+title,{attributes:`data-open-dialog="dialog-${i}"`})}</div>`)}<dialog id="dialog-${i}" data-catalog-dialog><h2>${title}</h2><p>atlas-web · 192.0.2.14</p>${i===1?field('Новое имя профиля'):i===2?'<p>Будут удалены только локальные параметры.</p>':'<p>Информационное сообщение</p>'}<div class="sample-actions">${UI.button('Отмена',{attributes:'data-close-dialog'})}${UI.button(i===2?'Удалить профиль':'Готово',{variant:i===2?'danger':'filled',attributes:'data-close-dialog'})}</div></dialog>`).join('');
    case'C15':return `<p>Меню: вторичная кнопка мыши или Shift+F10; Escape возвращает фокус.</p><div class="sample-actions"><button type="button" class="button" data-open-menu aria-haspopup="menu" aria-expanded="false">Действия</button><div tabindex="0" data-context-region>Контекстное меню</div><button type="button" class="button" title="Обновить данные" aria-label="Обновить данные" data-component-action="Обновить">↻</button></div><div role="menu" data-sample-menu hidden>${['Открыть','Редактировать','Удалить профиль'].map(label=>UI.button(label,{attributes:`role="menuitem" data-component-action="${label}"`})).join('')}</div>`;
    case'C16':return `<nav class="breadcrumb" aria-label="Путь"><span>Серверы</span><span>/</span><span>atlas-web</span></nav><nav class="tabs" aria-label="Разделы сервера">${['Обзор','Журнал','Параметры'].map((label,i)=>`<button class="tab ${i===0?'active':''}" type="button" data-sample-tab>${label}</button>`).join('')}</nav>`;
    case'C17':{const theme=document.documentElement.dataset.theme==='light'?'light':'dark';const navigation=()=>['Серверы','ПО','Журналы','Задания','Настройки'].map(label=>`<button type="button" class="${label===shellSection?'active':''}" data-shell-section="${label}" aria-label="${label}" title="${label}" aria-current="${label===shellSection?'page':'false'}"><svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 8h8M8 12h8M8 16h5"/></svg><span>${label}</span></button>`).join('');return `<div class="app-shell" data-component="C17"><aside class="app-sidebar"><img class="product-logo" src="${window.SERVERDECK_ASSETS[`assets/logos/logo-${theme}.svg`]}" alt="ServerDeck"><img class="logo-mark" src="${window.SERVERDECK_ASSETS[`assets/logos/mark-${theme}.svg`]}" alt="ServerDeck"><nav class="app-nav" aria-label="Разделы общего каркаса">${navigation()}</nav></aside><div class="app-main"><header class="app-topbar"><span>Общий каркас · C17</span>${status('Готово')}</header><div class="content"><header class="page-header"><div class="page-heading"><h1>${shellSection}</h1><p>Синтетическая цель · 192.0.2.14</p></div></header>${UI.surface('Слот содержимого',`<div class="panel-body" data-shell-slot>Пример слота: ${shellSection}. Предметный экран здесь не создаётся.${action('Локальное действие')}</div>`)}</div></div><nav class="bottom-nav" aria-label="Разделы общего каркаса">${navigation()}</nav></div>`;}
    case'C18':return `<dl class="description-list"><dt>Сервер</dt><dd>atlas-web</dd><dt>Адрес</dt><dd><code>192.0.2.14:22</code></dd><dt>Источник</dt><dd>SSH · последнее разрешённое наблюдение</dd><dt>Время наблюдения</dt><dd>2026-11-01 10:42:18 UTC</dd></dl>${action('Скопировать адрес')}`;
    case'C19':return `<details ${componentState==='expanded'?'open':''}><summary class="button">Технические сведения</summary><div class="panel-body"><p>Параметры и исходные идентификаторы доступны по запросу.</p><code>server-demo-014 · revision 3</code></div></details>`;
    case'C20':return UI.list([{title:'10:42:18 UTC · INFO · nginx',description:'Конфигурация успешно проверена'},{title:'10:42:15 UTC · WARN · nginx',description:'Повторное соединение с upstream'},{title:'Разрыв потока',description:'Пропущены 3 записи; полнота журнала не гарантирована'}]);
    case'C21':return `<div class="sample-grid">${['CPU','Память','Диск /'].map((name,i)=>`<article class="resource-card"><h3>${name}</h3><div class="resource-number">${i===0?'24 %':i===1?'6,2 / 16 ГБ':'Нет данных'}</div><p class="resource-detail">${i===2?'Наблюдение ещё не получено':'SSH · 10:42:18 UTC'}</p></article>`).join('')}</div>`;
    case'C22':return `<svg viewBox="0 0 600 160" role="img" aria-label="История CPU, RAM и диска: разрыв сохранён"><path d="M20 120 L160 70 L280 90 M360 100 L470 60 L580 80" fill="none" stroke="var(--accent)" stroke-width="3"/><path d="M20 70 L160 60 L280 65 M360 60 L470 45 L580 50" fill="none" stroke="var(--chart2)" stroke-width="3" stroke-dasharray="6 4"/><path d="M20 45 L160 40 L280 45 M360 40 L470 35 L580 40" fill="none" stroke="var(--chart3)" stroke-width="3" stroke-dasharray="2 4"/></svg><p>CPU — сплошная линия · RAM — штрих · Диск / — точки. Разрыв данных сохранён.</p><details><summary class="button">Значения истории</summary>${UI.table({columns:['Время UTC','CPU','RAM','Диск /'],rows:[['10:40','24 %','39 %','50 %'],['10:41','30 %','42 %','51 %'],['10:42','20 %','40 %','52 %']]})}</details>`;
    case'C23':{const terminal={success:['Завершено','available',100],error:['Ошибка','error',60],cancelled:['Отменено','warning',60],unknown:['Исход неизвестен','unknown',null]}[componentState]||['Выполняется','running',60];return `${terminal[2]===null?status(terminal[0],terminal[1]):`<progress class="sample-progress" max="100" value="${terminal[2]}" aria-label="${terminal[0]}"></progress>`}${UI.list([{title:'1. Проверка условий',description:'Завершено',trailing:status('Готово')},{title:'2. Изменение пакетов',description:terminal[0],trailing:status(terminal[0],terminal[1])},{title:'3. Проверка результата',description:componentState==='success'?'Завершено':'Подтверждённый результат ещё не получен'}])}`;}
    case'C24':return UI.surface('Проверьте план',`<div class="panel-body sample-stack"><dl class="description-list"><dt>Цель</dt><dd>atlas-db · 192.0.2.28</dd><dt>Изменение</dt><dd>Установить PostgreSQL</dd><dt>Последствия</dt><dd>Будут добавлены пакеты и запущена служба</dd><dt>Срок плана</dt><dd>До 10:46 UTC</dd></dl>${UI.notice('Нужно явное подтверждение','Изменённый план требует нового согласия.',{tone:'warning'})}<label class="sample-line"><input type="checkbox" data-plan-consent>Цель и последствия проверены</label>${UI.button('Подтвердить план',{disabled:true,attributes:'data-plan-confirm'})}${action('Отмена','text')}</div>`);
    case'C25':return '<div class="sample-diff"><p>Было → станет · только просмотр</p><del>− удалено: worker_count: 2</del><ins>+ добавлено: workers: 4</ins><p>Изменено: enabled false → true</p><p>Без изменений: port 22 → 22</p><p>Конфликт: локальное 1 → удалённое 2</p><p>Недоступная сторона: нет данных → 4</p></div>';
    case'C26':return `<form data-validation="json" novalidate class="sample-stack">${UI.field('Конфигурация',`<textarea aria-label="Конфигурация" spellcheck="false" class="mono" data-code-editor>${componentState==='error'?'{ invalid':UI.escape('{\n  "name": "atlas-web",\n  "enabled": true\n}')}</textarea>`,{hint:'Обычный текст; без выполнения команд'})}<p data-form-errors role="alert" hidden></p><div class="sample-actions"><button type="submit" class="button primary">Проверить формат</button>${UI.button('Копировать текст',{attributes:'data-copy-editor'})}</div></form><pre class="sample-code" tabindex="0" aria-label="Только просмотр">${UI.escape(Array.from({length:60},(_,i)=>`line ${i+1}: readonly raw text`).join('\n'))}</pre>`;
    case'C27':return `<nav class="breadcrumb" aria-label="Путь">/ etc / demo-app</nav><details open><summary class="button">demo-app</summary>${UI.list([{title:'config.yaml',description:'Файл · 2 КБ',trailing:UI.button('Выбрать файл',{attributes:`data-list-select aria-pressed="${componentState==='selected'}"`})},{title:'private/',description:'Недостаточно прав',trailing:UI.button('Выбрать private',{disabled:true})}])}<details><summary class="button">conf.d/</summary>${row('site.conf','Файл')}</details></details>`;
    case'C28':return `<form data-validation="date" novalidate class="sample-stack"><div class="sample-grid">${UI.field('Дата',`<input aria-label="Дата" data-date required placeholder="YYYY-MM-DD" value="${componentState==='error'?'2026-02-31':'2026-11-01'}">`)}${UI.field('Время','<input aria-label="Время" data-time required value="10:42" placeholder="HH:MM">')}${UI.field('Часовой пояс','<select aria-label="Часовой пояс"><option>UTC</option><option>Europe/Moscow</option></select>')}</div><p data-form-errors role="alert" hidden></p><button type="submit" class="button primary">Проверить дату</button></form><p>Время события: 10:42:15 UTC · Время наблюдения: 10:42:18 UTC</p>`;
    case'C29':return `${searchBox()}<div class="sample-actions">${action('Проверить готовность')}${action('Удалить выбранные','danger')}${action('Очистить выбор','text')}</div>${UI.table({columns:['Задание','Цель','Фаза'],interactive:true,ids:['job-check-1','job-check-2','job-blocked'],blocked:['job-blocked'],rows:componentState==='empty'?[]:[['Проверка пакетов','atlas-db','Готово'],['Проверка пакетов',null,'Ожидает'],['Резервная копия','atlas-web','Недоступно']]})}`;
    case'C30':return UI.list([{title:'Системные службы',description:'Доступно в текущем контексте',trailing:status('Доступно')+action('Подробнее')},{title:'SMART',description:'Источник не поддерживается на этом сервере',trailing:status('Не поддерживается','unknown')},{title:'Датчики',description:'Подтверждённые сведения ещё не получены',trailing:status('Неизвестно','unknown')},{title:'Изменение доступа',description:'Нужен разрешённый профиль; проверьте полномочия',trailing:status('Заблокировано','error')}]);
    default:return UI.empty('Нет примера','Выберите компонент в каталоге.');
  }
}
function renderComponent(){
  const component=registry.components.find(c=>c.id===componentId);
  document.getElementById('component-id').textContent=componentId;
  document.getElementById('component-title').textContent=component.name;
  document.getElementById('component-description').textContent=component.description;
  document.getElementById('component-usage').textContent=`В Flutter: ${component.implementationPaths.join(', ')||'Material 3 + Deck'}. Данные, действия и полномочия передаёт экран. HTML — дизайн-пример, а не доказательство готовности Flutter.`;
  document.getElementById('component-state').innerHTML=component.applicableStates.map(state=>`<option value="${UI.escape(state)}" ${state===componentState?'selected':''}>${UI.escape(state)}</option>`).join('');
  const section=(title,values)=>`<section><h2>${UI.escape(title)}</h2><p>${values.map(UI.escape).join('<br>')}</p></section>`;
  document.getElementById('component-contract').innerHTML=`<h2>Контракт ${componentId}</h2><div class="component-doc-grid">${section('Анатомия',component.anatomy)}${section('Варианты',component.variants)}${section('Параметры',component.parameters)}${section('События',component.events)}${section('Ограничения',component.limitations)}${section('Критерии приёмки',component.acceptanceCriteria)}${section('Неприменимость',Object.entries(component.notApplicableReasons).map(([key,value])=>`${key}: ${value}`))}</div><h2>Пример подключения</h2><pre class="sample-code">${UI.escape(component.usageExample)}</pre><p>Работающий пример: <code>${UI.escape(component.runnableExamplePath)}</code></p>`;
  preview.dataset.demoState=componentState;
  preview.innerHTML=`<div class="sample-stack" data-component="${componentId}">${componentState==='pending'?UI.notice('Действие выполняется','Повторная отправка заблокирована. Следующий результат передаст владелец.',{tone:'info'}):componentState==='error'?UI.notice('Не удалось выполнить действие','Проверьте введённые значения и контекст. Автоматического повтора нет.',{tone:'error'}):''}${['stale','partial','unknown'].includes(componentState)?UI.notice(({stale:'Данные устарели',partial:'Данные получены не полностью',unknown:'Состояние неизвестно'})[componentState],'Качество и предыдущий снимок переданы владельцем; новых наблюдений нет.',{tone:'warning'}):''}${sample(componentId)}</div><p class="component-result" role="status" aria-live="polite"></p>`;
  UI.enhance(preview);
  preview.querySelectorAll('[data-component-search]').forEach(filterTable);
  if(componentState==='selected')preview.querySelector('[data-row-select]:not(:disabled)')?.click();
  if(componentState==='error')preview.querySelector('form[data-validation]')?.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));
  if(componentState==='focus')preview.querySelector('button:not(:disabled),input:not(:disabled),textarea:not(:disabled),summary,[tabindex="0"]')?.focus();
  if(['disabled','pending'].includes(componentState)){
    preview.querySelectorAll('button,input,textarea,select').forEach(control=>control.disabled=true);
    preview.querySelectorAll('details').forEach(control=>{control.inert=true;control.querySelector('summary')?.setAttribute('aria-disabled','true');});
  }
  document.getElementById('component-list').innerHTML=registry.components.map(c=>`<button type="button" class="component-link ${c.id===componentId?'active':''}" data-component-id="${c.id}" aria-current="${c.id===componentId?'true':'false'}"><span>${c.id}</span><span>${UI.escape(c.name)}</span></button>`).join('');
}
function selectView(view){
  currentView=view;
  gallery.hidden=view!=='components';
  document.querySelectorAll('[data-design-view]').forEach(control=>control.setAttribute('aria-pressed',String(control.dataset.designView===view)));
  if(view==='components')renderComponent();
  const url=new URL(location.href);url.searchParams.set('view',view);url.searchParams.set('component',componentId);history.replaceState(null,'',url);
}
document.addEventListener('click',event=>{
  const button=event.target.closest('button');if(!button)return;
  if(button.dataset.designView)selectView(button.dataset.designView);
  if(button.dataset.componentId){componentId=button.dataset.componentId;componentState='default';document.getElementById('component-state').value='default';selectView('components');}
  if(button.dataset.width)preview.style.setProperty('--frame-width',`${button.dataset.width}px`);
  if(button.hasAttribute('data-component-action')){
    preview.querySelector('.component-result').textContent=`Демонстрация: «${button.dataset.componentAction}». Реальные операции не выполняются.`;
  }
  if(button.hasAttribute('data-sample-tab')){preview.querySelectorAll('[data-sample-tab]').forEach(tab=>tab.classList.toggle('active',tab===button));}
});
document.getElementById('component-state').addEventListener('change',event=>{componentState=event.target.value;renderComponent();});
function filterTable(input){
  const rows=[...preview.querySelectorAll('tbody tr')];
  rows.forEach(tr=>tr.hidden=!tr.textContent.toLowerCase().includes(input.value.toLowerCase()));
  preview.querySelectorAll('[data-table-no-results]').forEach(node=>node.hidden=rows.some(tr=>!tr.hidden)||!rows.length);
}
function updateSelection(){
  preview.querySelectorAll('[data-interactive-table]').forEach(table=>{
    const checks=[...table.querySelectorAll('[data-row-select]')];
    checks.forEach(box=>box.closest('tr').setAttribute('aria-selected',String(box.checked)));
    const selected=checks.filter(box=>box.checked).length;
    table.querySelector('[data-selection-count]').textContent=`Выбрано: ${selected}`;
    const eligible=checks.filter(box=>!box.disabled&&!box.closest('tr').hidden);
    const all=table.querySelector('[data-table-all]');all.checked=eligible.length>0&&eligible.every(box=>box.checked);all.indeterminate=eligible.some(box=>box.checked)&&!all.checked;
  });
}
preview.addEventListener('submit',event=>{
  event.preventDefault(); const form=event.target; let error='';
  if(form.dataset.validation==='profile'&&!form.querySelector('input[required]').value.trim())error='Исправьте ошибки формы: Введите имя';
  if(form.dataset.validation==='json')try{JSON.parse(form.querySelector('textarea').value);}catch(_){error='Некорректный JSON';}
  if(form.dataset.validation==='date'){
    const date=form.querySelector('[data-date]').value,time=form.querySelector('[data-time]').value;
    const parsed=new Date(date+'T00:00:00Z');
    if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||!Number.isFinite(parsed.getTime())||parsed.toISOString().slice(0,10)!==date)error='Введите существующую дату YYYY-MM-DD';
    if(!/^([01]\d|2[0-3]):[0-5]\d$/.test(time))error+=' Введите время HH:MM';
  }
  const summary=form.querySelector('[data-form-errors]');if(summary){summary.hidden=!error;summary.textContent=error;}
  form.querySelectorAll('input,textarea').forEach(input=>input.setAttribute('aria-invalid',String(!!error)));
  resultText(error||'Форма проверена. Запросы не отправлены.');
});
preview.addEventListener('input',event=>{if(event.target.hasAttribute('data-component-search')){filterTable(event.target);updateSelection();}});
preview.addEventListener('change',event=>{
  if(event.target.hasAttribute('data-plan-consent'))preview.querySelector('[data-plan-confirm]').disabled=!event.target.checked;
  if(event.target.hasAttribute('data-table-all'))preview.querySelectorAll('[data-row-select]:not(:disabled)').forEach(box=>{if(!box.closest('tr').hidden)box.checked=event.target.checked;});
  updateSelection();
});
let menuReturnFocus;
function closeMenu(){const menu=preview.querySelector('[data-sample-menu]');if(menu){menu.hidden=true;preview.querySelector('[data-open-menu]').setAttribute('aria-expanded','false');menuReturnFocus?.focus();}}
function openMenu(origin){const menu=preview.querySelector('[data-sample-menu]');if(!menu||['disabled','pending'].includes(componentState))return;menuReturnFocus=origin;menu.hidden=false;preview.querySelector('[data-open-menu]').setAttribute('aria-expanded','true');menu.querySelector('button').focus();}
preview.addEventListener('contextmenu',event=>{const region=event.target.closest('[data-context-region]');if(region){event.preventDefault();openMenu(region);}});
preview.addEventListener('keydown',event=>{
  if(event.key==='F10'&&event.shiftKey&&event.target.closest('[data-context-region]')){event.preventDefault();openMenu(event.target);}
  if(event.key==='Escape')closeMenu();
  if(['ArrowDown','ArrowUp'].includes(event.key)&&event.target.closest('[data-sample-menu]')){event.preventDefault();const items=[...preview.querySelectorAll('[role="menuitem"]')],index=items.indexOf(event.target);items[(index+(event.key==='ArrowDown'?1:items.length-1))%items.length].focus();}
  if(['Home','End'].includes(event.key)&&event.target.closest('[data-sample-menu]')){event.preventDefault();const items=[...preview.querySelectorAll('[role="menuitem"]')];items[event.key==='Home'?0:items.length-1].focus();}
});
preview.addEventListener('click',async event=>{
  // Catalog collections have their own synthetic owner; do not route clicks into the hidden screen atlas.
  event.stopPropagation();
  const button=event.target.closest('button');
  if(button?.disabled)return;
  if(button?.hasAttribute('data-shell-section')){shellSection=button.dataset.shellSection;renderComponent();return;}
  if(button?.hasAttribute('data-list-select')){button.setAttribute('aria-pressed',String(button.getAttribute('aria-pressed')!=='true'));}
  if(button?.hasAttribute('data-open-dialog'))preview.querySelector('#'+button.dataset.openDialog)?.showModal();
  if(button?.hasAttribute('data-close-dialog'))button.closest('dialog')?.close();
  if(button?.hasAttribute('data-page-delta')){const label=preview.querySelector('[data-page-label]'),next=Math.max(1,Math.min(4,Number(label.dataset.page)+Number(button.dataset.pageDelta)));label.dataset.page=next;label.textContent=`Страница ${next}${label.dataset.unknown==='true'?' · всего неизвестно':' из 4'}`;preview.querySelector('[data-page-delta="-1"]').disabled=next===1;preview.querySelector('[data-page-delta="1"]').disabled=next===4;}
  if(button?.hasAttribute('data-open-menu'))openMenu(button);
  if(button?.hasAttribute('data-segment'))preview.querySelectorAll('[data-segment]').forEach(item=>item.setAttribute('aria-pressed',String(item===button)));
  if(button?.hasAttribute('data-card-select')){const selected=button.getAttribute('aria-pressed')!=='true';button.setAttribute('aria-pressed',String(selected));button.closest('.panel').classList.toggle('card-selected',selected);}
  if(button?.hasAttribute('data-sample-tab'))preview.querySelectorAll('[data-sample-tab]').forEach(tab=>tab.classList.toggle('active',tab===button));
  if(button?.hasAttribute('data-copy-editor')){try{await navigator.clipboard.writeText(preview.querySelector('[data-code-editor]').value);resultText('Точный текст скопирован');}catch(_){resultText('Не удалось скопировать текст. Можно выделить и скопировать вручную.');}}
  if(button?.hasAttribute('data-table-sort')){
    const table=button.closest('[data-table-container]'),column=Number(button.dataset.tableSort),previous=table.dataset.sortColumn===String(column)?table.dataset.sortDirection:'none',direction=previous==='none'?'ascending':previous==='ascending'?'descending':'none';table.dataset.sortColumn=column;table.dataset.sortDirection=direction;
    table.querySelectorAll('thead th[aria-sort]').forEach((header,index)=>header.setAttribute('aria-sort',index===column?direction:'none'));
    const rows=[...table.querySelectorAll('tbody tr')];rows.sort((a,b)=>{if(direction==='none')return Number(a.dataset.originalIndex)-Number(b.dataset.originalIndex);const av=a.querySelectorAll('td[data-sort-value]')[column],bv=b.querySelectorAll('td[data-sort-value]')[column];if(av.dataset.null!==bv.dataset.null)return av.dataset.null==='true'?1:-1;return av.dataset.sortValue.localeCompare(bv.dataset.sortValue)*(direction==='ascending'?1:-1)||Number(a.dataset.originalIndex)-Number(b.dataset.originalIndex);});rows.forEach(row=>table.querySelector('tbody').append(row));
  }
  const label=button?.dataset.componentAction;
  if(label==='Очистить поиск'){const input=preview.querySelector('[data-component-search]');if(input){input.value='';filterTable(input);updateSelection();}}
  if(label==='Очистить выбор')preview.querySelectorAll('[data-row-select]').forEach(box=>box.checked=false);
  if(label==='Удалить выбранные')preview.querySelectorAll('[data-row-select]:checked:not(:disabled)').forEach(box=>box.closest('tr').remove());
  if(label){resultText(`Демонстрация: «${label}». Реальные операции не выполняются.`);if(button.closest('[role="menu"]'))closeMenu();}
  if(event.target.closest('[data-plan-confirm]'))resultText('План подтверждён локально. Запросы не отправлены.');
  updateSelection();
});
function applyTheme(theme){
  document.documentElement.dataset.theme=theme;
  document.getElementById('theme-button').querySelector('span').textContent=theme==='dark'?'Светлая':'Тёмная';
  preview.querySelectorAll('img.product-logo,img.logo-mark').forEach(img=>{
    img.src=window.SERVERDECK_ASSETS[`assets/logos/${img.classList.contains('logo-mark')?'mark':'logo'}-${theme}.svg`];
  });
  const url=new URL(location.href);url.searchParams.set('theme',theme);history.replaceState(null,'',url);
}
applyTheme(query.get('theme')==='light'?'light':'dark');
selectView(currentView);
window.SERVERDECK_COMPONENT_GALLERY={select: id=>{componentId=id;selectView('components');},registry};
document.getElementById('theme-button').addEventListener('click',()=>applyTheme(document.documentElement.dataset.theme==='light'?'dark':'light'));
document.body.dataset.ready='true';
