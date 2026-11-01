'use strict';

// Content renderers for the design atlas. They only read the screen manifest.
// The restore review has isolated, in-memory demo controls; no requests or file writes.
(function attachServerDeckContent(global) {
  const kinds = new Set(['status', 'plan', 'detail', 'job', 'chart', 'settings', 'dashboard']);
  const text = value => typeof value === 'boolean' ? (value ? 'Включено' : 'Выключено') : String(value ?? '');
  const items = value => Array.isArray(value) ? value : [];
  const label = value => typeof value === 'string' ? value : text(value?.label || value?.title || value?.name);
  const restoreDemo = {preserve:true, saved:false, target:''};
  let refreshRestoreControls = null;

  function updateRestoreControls(focusSelector) {
    const root = global.document?.querySelector('[data-restore-preservation]');
    if (!root || !refreshRestoreControls) return;
    root.outerHTML = refreshRestoreControls();
    if (focusSelector) global.document.querySelector(focusSelector)?.focus();
  }

  global.document?.addEventListener('change', event => {
    const choice = event.target.closest?.('[data-restore-preserve]');
    if (!choice) return;
    restoreDemo.preserve = choice.checked;
    updateRestoreControls('[data-restore-preserve]');
  });

  global.document?.addEventListener('click', event => {
    const save = event.target.closest?.('[data-restore-save]');
    if (save) {
      // This button is deliberately outside generic data-demo handling.
      event.preventDefault();
      event.stopImmediatePropagation();
      if (!save.disabled && restoreDemo.preserve) {
        restoreDemo.saved = true;
        updateRestoreControls('[data-restore-confirm]');
      }
      return;
    }
    const confirm = event.target.closest?.('[data-restore-confirm]');
    if (confirm && (confirm.disabled || (restoreDemo.preserve && !restoreDemo.saved))) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  }, true);

  function render(screen, ctx) {
    if (!screen || !kinds.has(screen.kind) || screen.id === '06-server-overview') return null;
    const esc = ctx.esc;
    const fields = items(screen.fields).filter(field => field && field.label != null);
    const rows = items(screen.rows);
    const columns = items(screen.columns);
    const field = pattern => fields.find(item => pattern.test(text(item.label)));
    if (screen.id === '51-restore-review') {
      const target = text(field(/^цель$/i)?.value);
      if (restoreDemo.target !== target) {
        restoreDemo.target = target;
        restoreDemo.saved = false;
      }
    }

    // Read a state from explicit fields and the actual title, never from summary,
    // source paths, or a successful SSH example shared by other screens.
    function toneFor(value) {
      const valueText = text(value).toLowerCase();
      if (/неизвест|не подтвержд|не провер|не определ|недостаточно доказательств|неоднознач|не получен|не заверш/.test(valueText)) return 'unknown';
      if (/заблок|запрещ|поврежд|несовместим|недоступ|нет связи|отозван|потеря единствен|ошибка|ошибк|отклон|не поддерж/.test(valueText)) return 'error';
      if (/ист[её]к|устар|требует|нужна|нужно|предупреж|конфликт|ограничен|частичн|остановка запрошена/.test(valueText)) return 'warning';
      if (/выполняется|запуск локаль|завершение работы|восстановление локаль|подключение$|ожидает|ожидается|проверяем/.test(valueText)) return 'running';
      if (/успеш|пройден|актуален|совпадают|проверена|сохранено|завершено|готово/.test(valueText)) return 'success';
      return 'info';
    }

    const stateField = field(/^(состояние|состояние плана|итог|результат|проверка формата)$/i);
    const explicitTone = toneFor(stateField?.value || screen.title);
    const colors = {error:'var(--error)', warning:'var(--warning)', unknown:'var(--unknown)', running:'var(--running)', success:'var(--available)', info:'var(--accent)'};
    const symbols = {error:'close', warning:'warning', unknown:'info', running:'clock', success:'check', info:'info'};

    function exactFields(subset = fields) {
      const visibleFields = screen.id === '51-restore-review' ? subset.filter(item => !/^(сохранить текущее состояние цели|результат сохранения цели)$/i.test(text(item.label))) : subset;
      return `<dl class="description-list">${visibleFields.map(item => `<dt>${esc(text(item.label))}</dt><dd>${esc(text(item.value))}</dd>`).join('')}</dl>`;
    }

    function restoreControls() {
      const checked = restoreDemo.preserve;
      const ready = !checked || restoreDemo.saved;
      const target = esc(restoreDemo.target);
      const choiceLabel = text(field(/^сохранить текущее состояние цели$/i)?.label || 'Сохранить текущее состояние цели');
      const statusTitle = !checked ? 'Текущие данные цели будут заменены без сохранения' : restoreDemo.saved ? 'Демонстрация: состояние цели сохранено и проверено' : 'Сначала сохраните текущее состояние цели';
      const statusMessage = !checked ? `Вы явно отказались от сохранения текущих данных ${restoreDemo.target}. Подтверждение заменит тестовую базу этой цели без сохранения её текущего состояния.` : restoreDemo.saved ? `${restoreDemo.target} · сохранение и проверка показаны в демонстрации. Исходная установка atlas-db не меняется.` : `${restoreDemo.target} · подтверждение восстановления станет доступно после демонстрационного сохранения и проверки текущей цели.`;
      const actions = items(screen.actions).map(label).filter(Boolean).map(action => {
        if (action === 'Сохранить состояние цели') return `<button type="button" class="button ${checked && !restoreDemo.saved ? 'primary' : ''}" data-restore-save ${!checked || restoreDemo.saved ? 'disabled' : ''} style="min-height:44px;font-size:14px;line-height:20px">${esc(action)}</button>`;
        if (action === 'Подтвердить восстановление') return `<button type="button" class="button ${ready ? 'primary' : ''}" data-restore-confirm data-demo="${esc(action)}" aria-describedby="restore-preserve-result" ${!ready ? 'disabled' : ''} style="min-height:44px;font-size:14px;line-height:20px">${esc(action)}</button>`;
        return `<button type="button" class="button" data-demo="${esc(action)}" style="min-height:44px;font-size:14px;line-height:20px">${esc(action)}</button>`;
      }).join('');
      return `<div data-restore-preservation><section class="panel"><div class="panel-header"><div><h2>Состояние текущей цели</h2><p style="font-size:12px;line-height:20px">${target}</p></div></div><div class="panel-body" style="font-size:14px;line-height:22px"><label class="setting-row" style="gap:12px;min-height:44px;cursor:pointer;justify-content:flex-start"><input type="checkbox" data-restore-preserve ${checked ? 'checked' : ''} style="width:20px;height:20px;min-height:20px;flex:none"><span>${esc(choiceLabel)}</span></label><p style="font-size:14px;line-height:22px;margin:14px 0">Сохраняется текущее состояние отдельной цели ${target}, в которой будет заменена тестовая база. Источник atlas-db остаётся без изменений.</p><aside class="notice ${!checked || !restoreDemo.saved ? 'warning' : 'success'}" id="restore-preserve-result" aria-live="polite"><div><p style="font-size:12px;line-height:20px;margin:0 0 6px">Результат сохранения цели</p><strong style="font-size:14px;line-height:22px">${esc(statusTitle)}</strong><p style="font-size:14px;line-height:22px">${esc(statusMessage)}</p></div></aside><div class="manifest-actions" style="gap:8px;padding-top:4px">${actions}</div></div></section></div>`;
    }

    function fieldPanel(title, subset = fields, subtitle = '') {
      if (!subset.length) return '';
      return ctx.panel(title, `<div class="panel-body">${exactFields(subset)}</div>`, subtitle);
    }

    function tabBar() {
      return items(screen.tabs).length ? ctx.tabs(screen, []) : '';
    }

    function actionBar() {
      const actions = items(screen.actions).map(label).filter(Boolean);
      if (!actions.length) return '';
      // The manifest is authoritative: blocked plans have no approval controls;
      // unknown jobs have no invented retry or apply actions.
      return `<div class="content-actions" style="display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin:0 0 20px">${actions.map((action, index) => ctx.button(action, index === 0, /провер|обнов|осмотр|уточнить/i.test(action) ? 'refresh' : /копир/i.test(action) ? 'copy' : /скача|сохранить отч/i.test(action) ? 'download' : '')).join('')}</div>`;
    }

    function exactTable(title = '') {
      if (!columns.length) return '';
      // The shared table helper substitutes demo servers for empty input. Use
      // the same CSS with exact source rows so no placeholder can change scope.
      const markup = `<div class="table-panel panel"><table class="data-table"><caption class="muted" style="text-align:left;padding:12px 14px;font-size:12px;line-height:16px">${esc(title || screen.title)}</caption><thead><tr>${columns.map(column => `<th scope="col">${esc(label(column))}</th>`).join('')}</tr></thead><tbody>${rows.map(row => `<tr>${columns.map((column, index) => `<td data-label="${esc(label(column))}">${esc(text(items(row)[index]))}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
      return markup;
    }

    function stateNotice() {
      const reason = field(/^(причина|пояснение|следующий шаг|ограничение|результат проверки)$/i);
      if (!reason || !['error', 'warning', 'unknown'].includes(explicitTone)) return '';
      return ctx.notice(text(reason.label), text(reason.value), explicitTone === 'unknown' ? 'warning' : explicitTone);
    }

    function hero(title = screen.title, heroFields = fields.slice(0, 2), tone = explicitTone) {
      const emblem = screen.kind === 'dashboard' ? (rows.length ? 'server' : 'plus') : symbols[tone];
      return `<section class="status-hero" data-content-state="${esc(tone)}"><div class="status-emblem" style="color:${colors[tone]};border-color:${colors[tone]};background:var(--surface)">${ctx.icon(emblem)}</div><h2>${esc(title)}</h2>${heroFields.map(item => `<p><span>${esc(text(item.label))}:</span> ${esc(text(item.value))}</p>`).join('')}</section>`;
    }

    function statusView() {
      return `${tabBar()}${hero()}${fieldPanel('Состояние и следующие шаги')}${exactTable()}${actionBar()}`;
    }

    function planView() {
      const consequences = fields.filter(item => /послед|будет|будут|эффект|сохран|перерыв|копи|восстанов|изменение|после|удал[её]н|на сервер|исход|полномоч|блок|разреш|следующ|проверка|ограничен/i.test(text(item.label)));
      let steps = '';
      if (rows.length && columns.length) {
        steps = ctx.panel('Состав плана и проверки', rows.map((row, index) => `<article class="plan-card"><span class="plan-number">${String(index + 1).padStart(2, '0')}</span><div><h3>${esc(text(items(row)[0]))}</h3>${columns.slice(1).map((column, columnIndex) => `<p><span>${esc(label(column))}:</span> ${esc(text(items(row)[columnIndex + 1]))}</p>`).join('')}</div></article>`).join(''));
      }
      const emphasis = stateField ? hero(screen.title, [stateField, ...(field(/^(цель|сервер)$/i) ? [field(/^(цель|сервер)$/i)] : [])]) : '';
      const body = steps
        ? `<div class="two-columns equal"><div>${steps}</div><div>${fieldPanel('Параметры плана')}${consequences.length ? fieldPanel('Последствия и условия', consequences) : ''}</div></div>`
        : `${fieldPanel('Параметры и условия')}${consequences.length ? fieldPanel('Последствия', consequences) : ''}`;
      if (screen.id === '51-restore-review') {
        refreshRestoreControls = restoreControls;
        return `${tabBar()}${emphasis}${stateNotice()}${body}${restoreControls()}`;
      }
      return `${tabBar()}${emphasis}${stateNotice()}${body}${actionBar()}`;
    }

    function detailView() {
      const codeFields = fields.filter(item => /команда|аргумент|отпечаток|хеш|digest|приватный ключ/i.test(text(item.label)));
      return `${tabBar()}${fieldPanel('Сведения')}${exactTable()}${codeFields.length ? ctx.panel('Точные значения', `<div class="panel-body">${codeFields.map(item => `<h3>${esc(text(item.label))}</h3><div class="code-block">${esc(text(item.value))}</div>`).join('')}</div>`) : ''}${actionBar()}`;
    }

    function jobView() {
      let timeline = '';
      if (rows.length) {
        const resultIndex = columns.findIndex(column => /состояние|результат|статус/i.test(label(column)));
        const timeIndex = columns.findIndex(column => /время|начало/i.test(label(column)));
        const nameIndex = columns.findIndex(column => /шаг|действие|операция/i.test(label(column)));
        timeline = `<section class="panel"><div class="panel-header"><div><h2>Ход выполнения</h2></div></div><div style="padding:8px 0">${rows.map((row, index) => {
          const values = items(row);
          const result = resultIndex >= 0 ? text(values[resultIndex]) : '';
          const rowTone = toneFor(result);
          const rowClass = rowTone === 'success' ? 'complete' : rowTone === 'running' ? 'current' : '';
          const name = text(values[nameIndex >= 0 ? nameIndex : 0]);
          const detailCells = columns.map((column, columnIndex) => ({column, columnIndex})).filter(item => item.columnIndex !== nameIndex && item.columnIndex !== timeIndex && !(nameIndex < 0 && item.columnIndex === 0));
          return `<div class="job-step ${rowClass}"><span class="step-dot" style="color:${colors[rowTone]}">${rowTone === 'success' ? '✓' : index + 1}</span><div><strong>${esc(name)}</strong>${detailCells.map(item => `<small>${esc(label(item.column))}: ${esc(text(values[item.columnIndex]))}</small>`).join('')}</div>${timeIndex >= 0 ? `<time>${esc(text(values[timeIndex]))}</time>` : ''}</div>`;
        }).join('')}</div></section>`;
      }
      const headline = stateField ? [stateField] : fields.slice(0, 1);
      return `${tabBar()}${hero(screen.title, headline)}${stateNotice()}${timeline ? `<div class="two-columns equal"><div>${timeline}</div><div>${fieldPanel('Контекст задания')}</div></div>` : fieldPanel('Контекст и проверка результата')}${actionBar()}`;
    }

    function settingsView() {
      const settings = fields.map(item => {
        const value = item.value;
        const valueMarkup = typeof value === 'boolean'
          ? `<button type="button" class="toggle ${value ? 'on' : ''}" data-toggle role="switch" aria-checked="${value}" aria-label="${esc(text(item.label))}"></button>`
          : `<span class="setting-value" style="max-width:58%;overflow-wrap:anywhere;text-align:right;font-size:14px;line-height:20px">${esc(text(value))}</span>`;
        return `<div class="setting-row"><div><h3>${esc(text(item.label))}</h3></div>${valueMarkup}</div>`;
      }).join('');
      return `${tabBar()}${ctx.panel('Настройки и ограничения', `<div class="panel-body">${settings}</div>`)}${exactTable()}${actionBar()}`;
    }

    function percentOf(value) {
      const raw = text(value);
      const percent = raw.match(/(\d+(?:[.,]\d+)?)\s*%/);
      if (percent) return Math.max(0, Math.min(100, Number(percent[1].replace(',', '.'))));
      const ratio = raw.match(/(\d+(?:[.,]\d+)?).*?(?:из|\/)\s*(\d+(?:[.,]\d+)?)/);
      if (ratio && Number(ratio[2].replace(',', '.')) > 0) return Math.max(0, Math.min(100, 100 * Number(ratio[1].replace(',', '.')) / Number(ratio[2].replace(',', '.'))));
      return null;
    }

    function chartView() {
      const normal = !ctx.state?.variant || ctx.state.variant === 'normal';
      const numeric = fields.map(item => ({...item, percent:percentOf(item.value)})).filter(item => item.percent != null);
      // The manifest contains scalar observations, not timestamp/value arrays.
      // Show only those values. Do not invent an hourly history or fill a gap.
      const scalarCharts = normal && numeric.length
        ? `<div class="resource-grid">${numeric.map(item => `<article class="resource-card"><h3>${esc(text(item.label))}</h3><div class="resource-number" style="font-size:18px;letter-spacing:0">${esc(text(item.value))}</div><div class="meter" role="img" aria-label="${esc(text(item.label) + ': ' + text(item.value))}" style="max-width:none;width:100%;height:6px"><span style="--value:${item.percent}%"></span></div></article>`).join('')}</div>`
        : '';
      return `${tabBar()}${scalarCharts}${fieldPanel('Показатели и доступная история')}${exactTable('Текстовые значения')}${actionBar()}`;
    }

    function dashboardView() {
      return `${tabBar()}${hero(screen.title, fields.slice(0, 2), 'info')}${fieldPanel('Рабочее пространство')}${exactTable()}${actionBar()}`;
    }

    return ({status:statusView, plan:planView, detail:detailView, job:jobView, settings:settingsView, chart:chartView, dashboard:dashboardView})[screen.kind]();
  }

  global.SERVERDECK_CONTENT = {render};
})(window);
