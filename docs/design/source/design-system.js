'use strict';

// ServerDeck design system. These primitives also render every screen in the atlas.
// Material 3 component roles, branded by the same tokens as Flutter BrandTheme.
window.DeckDesign = (() => {
  const escape = value => String(value ?? '').replace(/[&<>"']/g, char =>
    ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  function button(label, {variant='outlined', icon='', attributes='', disabled=false}={}) {
    return `<button type="button" class="button ${variant==='filled'?'primary':variant==='danger'?'danger':variant==='text'?'text':''}" data-component="C02" ${disabled?'disabled':''} ${attributes}>${icon}${escape(label)}</button>`;
  }
  function surface(title, body, {subtitle='', trailing='', classes=''}={}) {
    return `<section class="panel ${classes}" data-component="C09"><div class="panel-header"><div><h2>${escape(title)}</h2>${subtitle?`<p>${escape(subtitle)}</p>`:''}</div>${trailing}</div>${body}</section>`;
  }
  function notice(title, message, {tone='info', icon=''}={}) {
    return `<aside class="notice ${tone}" data-component="C11">${icon}<div><strong>${escape(title)}</strong><p>${escape(message)}</p></div></aside>`;
  }
  function field(label, control, {id='', hint='', error='', full=false}={}) {
    return `<div class="form-field ${full?'full':''}" data-component="C03"><label ${id?`for="${escape(id)}"`:''}>${escape(label)}</label>${control}${hint?`<small>${escape(hint)}</small>`:''}${error?`<small class="field-error" role="alert">${escape(error)}</small>`:''}</div>`;
  }
  function table({columns, rows, cell=(value)=>escape(value ?? 'Нет данных'), interactive=false, ids=[], blocked=[]}) {
    const sort=(column,j)=>button(column,{attributes:`data-table-sort="${j}" aria-label="Сортировать: ${escape(column)}"`});
    return `<section class="table-panel panel" data-component="C06" data-table-container ${interactive?'data-interactive-table':''}><div class="narrow-table-tools">${interactive?columns.map(sort).join(''):''}</div><table class="data-table"><thead><tr>${interactive?'<th scope="col"><input type="checkbox" data-table-all aria-label="Выбрать доступные строки"></th>':''}${columns.map((column,j)=>`<th scope="col" aria-sort="none">${interactive?sort(column,j):escape(column)}</th>`).join('')}</tr></thead><tbody>${rows.map((row,i)=>`<tr tabindex="0" role="button" aria-label="Открыть ${escape(row[0])}" data-row="${i}" data-original-index="${i}" data-row-id="${escape(ids[i]??i)}" ${interactive?'aria-selected="false"':''}>${interactive?`<td data-label="Выбор"><input type="checkbox" data-row-select ${blocked.includes(ids[i])?'disabled':''} aria-label="Выбрать ${escape(row[0])}"></td>`:''}${columns.map((column,j)=>`<td data-label="${escape(column)}" data-sort-value="${escape(row[j]??'')}" data-null="${row[j]==null}">${cell(row[j],column,j)}</td>`).join('')}</tr>`).join('')}</tbody></table>${!rows.length?empty('Пока нет данных','Записи появятся после получения данных.'):''}<p data-table-no-results hidden>Ничего не найдено. Очистите поиск.</p><footer class="table-footer"><span data-table-count>${rows.length} записей · демонстрационный снимок</span><span data-selection-count>${interactive?'Выбрано: 0':'Показана вся порция'}</span></footer></section>`;
  }
  function list(items) {
    return `<div class="deck-list" data-component="C07">${items.map(item=>`<div class="deck-list-row"><div><strong>${escape(item.title)}</strong><p>${escape(item.description||'')}</p></div>${item.trailing||''}</div>`).join('')}</div>`;
  }
  function empty(title, message) {
    return `<div class="empty-state" data-component="C12"><span class="empty-symbol" aria-hidden="true">◇</span><h2>${escape(title)}</h2><p>${escape(message)}</p></div>`;
  }
  function enhance(root) {
    const families = {
      C02:'.button,.icon-button', C03:'.form-field', C04:'.toggle,.segmented',
      C05:'.filters,.search-field,.filter-chip', C06:'.table-panel', C07:'.profile-card,.storage-row',
      C08:'.pager,.table-footer', C09:'.panel,.stat-card,.resource-card', C10:'.status,.tag',
      C11:'.notice', C12:'.state-panel,.empty-state,.loading-state', C13:'.form-section,.form-actions',
      C14:'dialog', C15:'.tooltip', C16:'.tabs,.breadcrumb', C17:'.app-shell', C18:'.description-list',
      C19:'details', C20:'.log-panel,.log-line', C21:'.resource-number,.stat-value', C22:'.chart,.sparkline',
      C23:'.job-step,.job-summary', C24:'.plan-card,.confirmation-label', C26:'.code-block', C29:'.selection-toolbar',
      C30:'.capability-list'
    };
    for (const [id,selector] of Object.entries(families)) {
      root.querySelectorAll(selector).forEach(node=>{
        node.dataset.component ||= id;
        // Common component typography is owned by the design system, never by an individual screen.
        if (['C02','C03','C09','C11','C13'].includes(id)) {
          node.style.removeProperty('font-size');
          node.style.removeProperty('line-height');
        }
      });
    }
    root.querySelectorAll('button').forEach(node=>{
      if (!node.getAttribute('aria-label') && !node.textContent.trim()) node.setAttribute('aria-label','Действие');
    });
  }
  return {escape,button,surface,notice,field,table,list,empty,enhance};
})();
