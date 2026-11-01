Найдено 1 замечание, которое стоит исправить.

Готовность к реализации: не готов в визуальном scope T087/T088 — keyboard journey оставляет перекрывающие rail tooltips. Общая готовность003.2 не устанавливается.

Completed read-only reviewer /root/design_0032_visual12_foundation, без child; файлы не менялись, Flutter/native/tests не запускались. Прочитаны AGENTS, DESIGN/brandbook1.1/typography/accessibility, P01/P02/P04/P07/P12, code4/T087/T088/tasks/evidence/quickstart, consumers/test/visual11.

## P2: accumulated rail tooltips

FoundationShell151–154 вызывает ensureTooltipVisible только на focus=true, blur отсутствует. Все8 scroll-shell-context-800-{dark,light}-{100,200}-{start,end}.png показывают3старыхtooltip при100/5при200, хотя editor имеетprimaryfocus. В800-light-200-start «Серверы» перекрывает часть первогоCJKglyph иfocusedge, остальныеlabels перекрываютконтентниже; dark аналогичен.

Это production lifecycle, а не ранний capture: pinned SDK raw_tooltip.dart771–788 manual ensureTooltipVisible не закрывается автоматически. ДополнительныйpumpAndSettle не исправит. Existing design_layout_test994–1024 вручнуюdismissAllToolTips послеunfocus, маскируя накопление. New bounded test glyphPixels>0 не доказывает отсутствие частичного overlay.

Требования DESIGN/brandbook unobscuredfocus→P02raillabels/P04keyboard/P07fulltext→T087/T088. Closure: скрыть старую keyboard tooltip при blur, сохранить hover/longpress; actual sequential Tab/ShiftTab без ручногоdismiss; mandatorychecks/capture/freshreview. Дефект не объявлен впервые появившимсяT087.

## Фактический просмотр

Все160changedmain scope просмотрены на21sheets: contact-{004,005,012,017,018,023,033}-{01,02}.jpg иcontact-006-{01..07}.jpg. Отдельно112currentmain originals:04=8,05=8,06=48,13=8,22=8,23=16,31=8,84=8.

Точныйнабор: всеprimary200 семиorigins04/05/06/13/22/23/84×4frames×2themes; все5supplements06при200×4frames×2themes; все23-*-100; все8actualchanged31изdelta. Включенывсе48changedphone200 ивсе16logrecords; остальные48main100 толькоsheets.

Все64scroll originals отдельно: scroll-{shell-context,log-record}-{1100,800,390,360}-{dark,light}-{100,200}-{start,end}.png; все8sheets scroll/contact-{001,002}-{01..04}.jpg. Итого176current originals+29sheets. Previous4:05-server-list-390x800-light-200,23-log-record-360x800-dark-200,06-server-overview-800x600-light-200-history-plots,84-settings-1100x760-dark-200 изadaptive-versions-final.

Иныхconfirmedvisualdefects нет. Logstart/end/последнийЯ/Mono/UTCabove/close читаемы во16комбинациях; shellпоследнийz/nav/featureactions сохранены. Desktop100start/end одинаковы припомещающемсятексте. Reserve4focuspaint/max240/35%/vertical16 соблюдены, частичные соседниеscrollстроки не объявлены недоступными.

## Identity / matrix

1792actualPNGhash/dimensions проверены:current928+previous864. Exactsets PNG↔records↔inventory,uniqueIDs,filenames/frame/theme/scale/variant,owners/tasks/readiness. Main each744=560primary35×4×2×2+184supplements; component184=focus24+disabled32+versions64+scroll64. Scroll2sites×4×2×2×start/end; version4sites×4×2×2; focus6cases×2phone×2themes×200; disabled2cases×2phone×2themes×2scales×checked/unchecked. Stock56 согласован.

Main352identical/392changed/0added/removed; assigned04=16,05=16,06=56,13=16,22=16,23=16,31=8,84=16. Components120identical/0changed/64new/0removed,120carried records изменили толькоcommand.

MainrecordsSHA56276c78f989961a0fa904ad30616c04b2fa12f9fc1d7b8e052b452ee5c920ac; scroll68084840ab6e66a5ee3deb872f47d694a3a1e9bd56d85daf8e52ea18a8303c1b. Scrollrecords focus2/gap2,contrast5.308–10.940,focuspixels1959–4307,glyphpixels7–134,start/end/viewport verified. Это не исключает найденноеpartialoverlay.

Carry352main только scopedvisual11+chainQA03/04→QA06/QA08/no-other-findingsQA09→QA10→QA11. QA09 целикомclean не объявляется. Components120identitycarry:56paintQA07+64versionQA11, staticpaint неkeyboard/runtime. Вконце1792PNG/records/manifests и4T087sourcehashes повторносовпали.

## Evidence / limits

Прочитаны rootlogs format646/0,analyze0,full1613+1skip,capture712,defaultWindows2,validator98/35/63/0errors,lychee1380/0errors,T08732green. Reviewer не повторял. PNG доselection/copy/close, этиeffects не доказаныкартинками. Automation232/nativeclipboard/service/auth/trust/privacy/full003.2 внеvisualscope.
