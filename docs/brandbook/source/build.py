from pathlib import Path
import csv, json, math, html, base64, subprocess, shutil, zipfile, sys
sys.path.insert(0,str(Path(__file__).resolve().parents[3]/'tmp/branddeps'))
import pymupdf as fitz
from fontTools.ttLib import TTFont as FTFont
from fontTools.pens.svgPathPen import SVGPathPen
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[1]
for folder in ['layouts','logos','qa','tokens']:
    (ROOT/folder).mkdir(parents=True,exist_ok=True)
W,H=1440,900
for n,f in [('Sans','NotoSans-Regular.ttf'),('Bold','NotoSans-SemiBold.ttf'),('Mono','NotoSansMono-Regular.ttf')]:
    pdfmetrics.registerFont(TTFont(n,str(ROOT/'fonts'/f)))
THEMES={
 'dark':dict(bg='#0C121C',surface='#151E2B',raised='#1D2939',hover='#253246',selected='#173E43',text='#EAF0F7',muted='#A7B5C7',border='#35465E',control='#8192A8',accent='#64DFC5',onAccent='#0C121C',accentHover='#8CEBD7',focus='#7DCFFF',disabled='#8B9AAE',available='#72DBAC',unavailable='#FF9DA5',unknown='#BCC7D6',warning='#FFC47A',error='#FF8D98',running='#86C9FF',success='#72DBAC',chart2='#C5ABFF',chart3='#FFC47A'),
 'light':dict(bg='#F3F6FA',surface='#FFFFFF',raised='#EAF0F6',hover='#E2EAF3',selected='#D9F1EC',text='#172337',muted='#526279',border='#CDD7E4',control='#718198',accent='#087565',onAccent='#FFFFFF',accentHover='#075E51',focus='#006AAB',disabled='#627187',available='#137346',unavailable='#B62D42',unknown='#586579',warning='#915000',error='#B6203C',running='#1765A8',success='#137346',chart2='#7650B4',chart3='#915000')}
STATUS=[('available','Доступен','circle','SSH-соединение установлено'),('unavailable','Недоступен','cross','Подключение не установлено'),('unknown','Неизвестно','question','Данные ещё не получены'),('warning','Предупреждение','triangle','Требуется внимание'),('error','Ошибка','octagon','Операция не выполнена'),('running','Выполнение','arc','Операция продолжается'),('success','Успех','check','Операция завершена')]
def lum(h):
    a=[int(h[i:i+2],16)/255 for i in (1,3,5)]
    a=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in a]
    return sum(x*y for x,y in zip(a,[.2126,.7152,.0722]))
def contrast(a,b):
    x,y=sorted([lum(a),lum(b)]);return (y+.05)/(x+.05)
audit=[]
for name,t in THEMES.items():
    for bg in ['bg','surface','raised','hover','selected']:
        for fg in ['text','muted','accent','disabled']+[s[0] for s in STATUS]:
            audit.append([name,fg,bg,t[fg],t[bg],contrast(t[fg],t[bg]),4.5,'text'])
        for fg in ['control','focus','accent','chart2','chart3']:
            audit.append([name,fg,bg,t[fg],t[bg],contrast(t[fg],t[bg]),3,'non-text'])
    for bg in ['accent','accentHover']:
        audit.append([name,'onAccent',bg,t['onAccent'],t[bg],contrast(t['onAccent'],t[bg]),4.5,'text'])
THEMES['dark']['disabled']='#A7B5C7'
THEMES['light']['disabled']='#526279'
for row in audit:
    if row[1]=='disabled':
        row[3]=THEMES[row[0]]['disabled'];row[5]=contrast(row[3],row[4])
assert all(row[5]>=row[6] for row in audit), [r for r in audit if r[5]<r[6]]
with (ROOT/'tokens/contrast-audit.csv').open('w',encoding='utf-8-sig',newline='') as f:
    w=csv.writer(f);w.writerow(['theme','foreground','background','fg_hex','bg_hex','ratio','minimum','role']);w.writerows([[*r[:5],round(r[5],3),*r[6:]] for r in audit])
shared={'space.1':4,'space.2':8,'space.3':12,'space.4':16,'space.6':24,'space.8':32,'space.12':48,'radius.control':8,'radius.card':12,'radius.dialog':16,'stroke.icon':1.5,'size.icon':20,'size.control':36,'size.row.dense':36,'size.row.default':44,'size.focus':2,'size.focusGap':2,'font.ui':'Noto Sans','font.mono':'Noto Sans Mono','font.body':14,'font.body.line':20,'font.table':13,'font.table.line':20,'font.log':13,'font.log.line':20,'font.title':24,'font.title.line':32,'font.label':12,'font.label.line':16,'motion.fast':120,'motion.normal':180,'shadow.dark':'none','shadow.light':'0 4 16 rgba(23,35,55,0.10)'}
tokens={'version':'1.0','themes':THEMES,'shared':shared,'status':[{ 'token':s[0],'label':s[1],'symbol':s[2],'meaning':s[3]} for s in STATUS]}
(ROOT/'tokens/serverdeck.tokens.json').write_text(json.dumps(tokens,ensure_ascii=False,indent=2),encoding='utf-8')
rows=[['Токен','Тёмная тема','Светлая тема','Назначение / единица']]
use={'bg':'Scaffold background','surface':'Card / sheet / table','raised':'Header / toolbar / log gutter','hover':'Hovered row / secondary control','selected':'Selected row / navigation','text':'Primary content','muted':'Secondary content / placeholders','border':'Decorative dividers only','control':'Input borders / essential icons','accent':'Primary fill / links / chart CPU','onAccent':'Text on primary fill','accentHover':'Primary hover fill','focus':'Keyboard focus ring','disabled':'Disabled text, no opacity','chart2':'RAM: dashed + square marker','chart3':'Disk: dotted + triangle marker'}
for k in THEMES['dark']: rows.append(['color.'+k,THEMES['dark'][k],THEMES['light'][k],use.get(k,'Semantic foreground with symbol + label')])
for k,v in shared.items(): rows.append([k,v,v,'ms' if k.startswith('motion') else 'logical px / Flutter dp' if isinstance(v,(int,float)) else 'Shared specification'])
with (ROOT/'tokens/design-tokens.csv').open('w',encoding='utf-8-sig',newline='') as f:csv.writer(f).writerows(rows)
(ROOT/'tokens/token-rows.json').write_text(json.dumps(rows,ensure_ascii=False),encoding='utf-8')

pdf=canvas.Canvas(str(ROOT/'ServerDeck-brandbook.pdf'),pagesize=(W,H))
pdf.setTitle('ServerDeck | Брендбук 1.1');pdf.setAuthor('ServerDeck')
allpages=[]
class Page:
    def __init__(self,title,theme='light',section='Система бренда',footer=True,w=W,h=H):
        self.title,self.t,self.w,self.h=title,THEMES[theme],w,h;self.svg=[]
        self.rect(0,0,w,h,self.t['bg'])
        if footer:
            self.text(56,46,'SERVERDECK  /  '+section.upper(),12,self.t['muted'],'Bold')
            self.text(56,96,title,36,self.t['text'],'Bold')
            self.line(56,h-50,w-56,h-50,self.t['border'])
            self.text(56,h-26,'Брендбук 1.1  /  10.10.2026',11,self.t['muted'])
            self.text(w-110,h-26,f'{len(allpages)+1:02}',11,self.t['muted'],'Mono')
    def rect(self,x,y,w,h,fill,stroke=None,r=0,sw=1):
        pdf.setFillColor(HexColor(fill));pdf.setStrokeColor(HexColor(stroke or fill));pdf.setLineWidth(sw)
        pdf.roundRect(x,self.h-y-h,w,h,r,fill=1,stroke=bool(stroke))
        self.svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke or "none"}" stroke-width="{sw}"/>')
    def text(self,x,y,s,size=16,color=None,font='Sans'):
        s=str(s).replace('→','>').replace('≥','>=')
        color=color or self.t['text'];pdf.setFillColor(HexColor(color));pdf.setFont(font,size);pdf.drawString(x,self.h-y,str(s))
        family='Noto Sans Mono' if font=='Mono' else 'Noto Sans'
        self.svg.append(f'<text x="{x}" y="{y}" font-family="{family}" font-size="{size}" font-weight="{600 if font=="Bold" else 400}" fill="{color}">{html.escape(str(s))}</text>')
    def para(self,x,y,s,width=580,size=19,color=None,font='Sans',leading=None):
        s=s.replace('→',':').replace('≥','>=')
        leading=leading or size*1.55;line=''
        for word in s.split():
            nxt=(line+' '+word).strip()
            if pdfmetrics.stringWidth(nxt,font,size)>width and line:
                self.text(x,y,line,size,color,font);y+=leading;line=word
            else:line=nxt
        if line:self.text(x,y,line,size,color,font);y+=leading
        return y
    def line(self,x1,y1,x2,y2,color,sw=1,dash=None):
        pdf.setStrokeColor(HexColor(color));pdf.setLineWidth(sw);pdf.setDash(dash or []);pdf.line(x1,self.h-y1,x2,self.h-y2);pdf.setDash([])
        self.svg.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{sw}"'+(f' stroke-dasharray="{",".join(map(str,dash))}"' if dash else '')+'/>')
    def circle(self,x,y,r,color,fill=True,sw=1.5):
        pdf.setStrokeColor(HexColor(color));pdf.setFillColor(HexColor(color));pdf.setLineWidth(sw);pdf.circle(x,self.h-y,r,stroke=1,fill=fill)
        self.svg.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{color if fill else "none"}" stroke="{color}" stroke-width="{sw}"/>')
    def symbol(self,x,y,kind,col,s=16):
        r=s/2
        if kind=='circle':self.circle(x,y,r*.65,col,False,2);self.circle(x,y,2,col)
        elif kind=='cross':
            self.line(x-r*.6,y-r*.6,x+r*.6,y+r*.6,col,2);self.line(x+r*.6,y-r*.6,x-r*.6,y+r*.6,col,2)
        elif kind=='question':self.circle(x,y,r,col,False);self.text(x-r*.4,y+r*.55,'?',s*.9,col,'Bold')
        elif kind in ('triangle','octagon'):
            count=3 if kind=='triangle' else 8
            pts=[(x+math.sin(2*math.pi*i/count)*r,y-math.cos(2*math.pi*i/count)*r) for i in range(count)]
            for a,b in zip(pts,pts[1:]+pts[:1]):self.line(*a,*b,col,1.5)
            self.text(x-2.5,y+4,'!',11,col,'Bold')
        elif kind=='arc':
            self.circle(x,y,r,col,False);self.line(x,y,x,y-r*.5,col,2);self.line(x,y,x+r*.5,y,col,2)
        elif kind=='check':self.line(x-r*.7,y,x-r*.1,y+r*.6,col,2);self.line(x-r*.1,y+r*.6,x+r*.8,y-r*.6,col,2)
    def badge(self,x,y,key,label=None):
        s=next(s for s in STATUS if s[0]==key);self.symbol(x+8,y-5,s[2],self.t[key]);self.text(x+26,y,label or s[1],13,self.t[key],'Bold')
    def logo(self,x,y,size=56,word=True,mono=None):
        col=mono or self.t['accent'];u=size/64
        # Approved concept 01: three modules, optically centred on a 64-unit grid.
        # Even-odd contours make indicator/slot holes truly transparent in every export.
        path=pdf.beginPath()
        contours=[]
        def move(a,b):path.moveTo(x+a*u,self.h-y-b*u)
        def line(a,b):path.lineTo(x+a*u,self.h-y-b*u)
        def curve(a,b,c,d,e,f):path.curveTo(x+a*u,self.h-y-b*u,x+c*u,self.h-y-d*u,x+e*u,self.h-y-f*u)
        def rounded(a,b,w,h,r):
            k=r*0.5522847498
            move(a+r,b);line(a+w-r,b);curve(a+w-r+k,b,a+w,b+r-k,a+w,b+r)
            line(a+w,b+h-r);curve(a+w,b+h-r+k,a+w-r+k,b+h,a+w-r,b+h)
            line(a+r,b+h);curve(a+r-k,b+h,a,b+h-r+k,a,b+h-r)
            line(a,b+r);curve(a,b+r-k,a+r-k,b,a+r,b);path.close()
            contours.append(f'M{a+r} {b} H{a+w-r} C{a+w-r+k} {b} {a+w} {b+r-k} {a+w} {b+r} V{b+h-r} C{a+w} {b+h-r+k} {a+w-r+k} {b+h} {a+w-r} {b+h} H{a+r} C{a+r-k} {b+h} {a} {b+h-r+k} {a} {b+h-r} V{b+r} C{a} {b+r-k} {a+r-k} {b} {a+r} {b} Z')
        for row in [9,26,43]:
            rounded(12,row,40,12,3)
            rounded(18,row+4,4,4,1)
            rounded(29,row+4,17,4,1)
        pdf.setFillColor(HexColor(col));pdf.drawPath(path,stroke=0,fill=1,fillMode=0)
        self.svg.append(f'<path transform="translate({x} {y}) scale({u})" fill="{col}" fill-rule="evenodd" d="{" ".join(contours)}"/>')
        if word:
            tx,ty=x+size+size*.28,y+size*.73
            self.text(tx,ty,'ServerDeck',size*.64,mono or self.t['text'],'Bold')
            if getattr(self,'outlineLogo',False):
                ft=FTFont(ROOT/'fonts/NotoSans-SemiBold.ttf');gs=ft.getGlyphSet();cm=ft.getBestCmap();upem=ft['head'].unitsPerEm;scale=size*.64/upem;advance=0;parts=[]
                for char in 'ServerDeck':
                    glyph=gs[cm[ord(char)]];pen=SVGPathPen(gs);glyph.draw(pen)
                    parts.append(f'<path transform="translate({tx+advance*scale} {ty}) scale({scale} {-scale})" fill="{mono or self.t["text"]}" d="{pen.getCommands()}"/>');advance+=glyph.width
                self.svg[-1]=''.join(parts)
    def button(self,x,y,label,kind='primary',w=168,state='normal'):
        t=self.t
        bg=t['accentHover'] if state=='hover' and kind=='primary' else t['accent'] if kind=='primary' else t['hover'] if state=='hover' else t['surface']
        fg=t['onAccent'] if kind=='primary' else t['text']
        border=None if kind=='primary' else t['control']
        if state=='disabled':bg=t['raised'];fg=t['disabled'];border=t['control']
        if state=='focus':self.rect(x-4,y-4,w+8,44,t['bg'],t['focus'],r=12,sw=2)
        self.rect(x,y,w,36,bg,border,r=8)
        if state=='loading':self.symbol(x+18,y+18,'arc',fg,14);x+=18
        self.text(x+14,y+23,label,13,fg,'Bold')
    def finish(self,slug):
        body=''.join(self.svg)
        svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" viewBox="0 0 {self.w} {self.h}"><title>{html.escape(self.title)}</title>{body}</svg>'
        (ROOT/'layouts'/f'{slug}.svg').write_text(svg,encoding='utf-8')
        allpages.append((slug,self.title));pdf.showPage()

p=Page('Инфраструктура под контролем','dark','ServerDeck')
p.logo(64,195,100)
p.text(64,410,'ServerDeck',78,font='Bold');p.text(68,466,'Linux-серверы. Состояние. Изменения.',27,p.t['muted'])
p.para(68,558,'Брендбук для десктопного приложения: визуальная система, две темы и правила ежедневной работы с данными.',660,23)
p.text(68,760,'IDENTITY / PRODUCT / IMPLEMENTATION',13,p.t['accent'],'Mono')
for i,(name,key,val) in enumerate([('lab-a','available','CPU  24%'),('edge-02','warning','RAM  81%'),('db-01','running','Обновление  64%')]):
    y=222+i*166;p.rect(865,y,480,140,p.t['surface'],p.t['border'],12);p.text(895,y+42,name,25,font='Mono');p.badge(895,y+77,key);p.text(895,y+111,val,16,p.t['muted'],'Mono')
p.finish('01-cover')

p=Page('Спокойствие, основанное на ясности',section='Позиционирование')
p.para(56,176,'ServerDeck объединяет серверы, ПО, версии, журналы, ресурсы и задания. Инженер видит состояние инфраструктуры и понимает последствия каждого изменения.',790,25)
for i,(title,body) in enumerate([('Контроль','Статус, источник данных и время проверки рядом с результатом.'),('Прозрачность','Показываем этапы задания, ошибки и доступные действия.'),('Порядок','Одна структура экранов и единые обозначения в обеих темах.'),('Надёжность','Не обещаем защиту, которую продукт не обеспечивает.')]):
    x=56+(i%2)*676;y=365+(i//2)*190;p.rect(x,y,640,162,p.t['surface'],p.t['border'],12);p.text(x+24,y+43,title,24,font='Bold');p.para(x+24,y+82,body,590,18)
p.text(56,803,'Аудитория: системные администраторы, DevOps, разработчики, владельцы небольших инфраструктур.',16,p.t['muted'])
p.finish('02-positioning')

p=Page('Знак: три серверных модуля',section='Логотип')
p.logo(85,210,240,False);p.logo(445,245,100)
p.para(445,430,'Три серверных модуля передают порядок и управляемую инфраструктуру. В каждом модуле есть индикатор и слот. Чёткий силуэт и прозрачные вырезы сохраняются в цветных и монохромных версиях.',830,22)
p.text(85,690,'Основная композиция',22,font='Bold');p.para(85,735,'Знак слева, название справа. Название всегда пишется ServerDeck. Слоган не входит в логотип.',1180,20)
p.finish('03-logo')

p=Page('Версии для фона и монохромное применение',section='Логотип')
for i,(bg,theme,mono,label) in enumerate([('#0C121C','dark',None,'Основной / тёмный фон'),('#FFFFFF','light',None,'Основной / светлый фон'),('#FFFFFF','light','#172337','Монохромный / светлый'),('#0C121C','dark','#FFFFFF','Монохромный / тёмный')]):
    x=56+(i%2)*676;y=165+(i//2)*295;p.rect(x,y,640,250,bg,r=12);orig=p.t;p.t=THEMES[theme];p.logo(x+34,y+65,74,True,mono);p.text(x+34,y+206,label,16,p.t['muted']);p.t=orig
p.finish('04-logo-variants')

p=Page('Охранное поле и масштаб',section='Логотип')
p.rect(92,224,684,192,p.t['selected'],p.t['control'],8);p.logo(124,256,128);p.text(96,205,'x = 1/4 высоты знака',18,p.t['muted']);p.text(100,482,'Со всех сторон: минимум x = 32 при знаке 128 px',17)
p.logo(786,221,64,False);p.logo(898,237,32,False);p.logo(970,245,24,False);p.text(784,329,'Знак: минимум 24 px / 6 мм',20,font='Bold')
p.para(784,378,'Полный логотип: минимум 140 px / 35 мм по ширине. Иконка приложения: квадрат 1024 px, сетка знака 768 px по центру. Маска ОС применяется после экспорта.',570,19)
p.text(56,597,'Недопустимо',25,font='Bold')
p.para(56,649,'Не растягивать, не поворачивать, не добавлять свечение, градиенты, обводку или тень. Не заменять шрифт названия. Не помещать знак на фотографию без спокойной однотонной подложки.',1260,21)
p.para(56,765,'Проверять 24 px при масштабе 100%. Для печати использовать вектор и физические минимальные размеры.',1260,17,p.t['muted'])
p.finish('05-logo-rules')

for theme in ['dark','light']:
    p=Page('Тёмная палитра' if theme=='dark' else 'Светлая палитра',theme,'Цвет')
    keys=['bg','surface','raised','text','muted','border','control','accent','onAccent','focus','hover','selected']
    for i,k in enumerate(keys):
        x=56+(i%4)*338;y=158+(i//4)*201
        p.rect(x,y,310,104,p.t[k],p.t['control'],8)
        p.text(x,y+137,k,19,font='Bold');p.text(x,y+164,p.t[k],16,p.t['muted'],'Mono')
    p.para(56,792,'border разделяет блоки; control обозначает поля и существенные границы. Прозрачность поверхностей не используется.',1270,16,p.t['muted'])
    p.finish('06-palette-'+theme)

p=Page('Статус всегда имеет цвет, символ и подпись',section='Семантика')
p.text(56,169,'Состояние',16,p.t['muted'],'Bold');p.text(402,169,'Тёмный / светлый',16,p.t['muted'],'Bold');p.text(787,169,'Значение',16,p.t['muted'],'Bold')
for i,(key,label,symbol,meaning) in enumerate(STATUS):
    y=208+i*73;p.symbol(70,y-5,symbol,p.t[key],21);p.text(102,y,label,20,font='Bold');p.text(402,y,THEMES['dark'][key]+' / '+p.t[key],18,font='Mono');p.text(787,y,meaning,18);p.line(56,y+25,1384,y+25,p.t['border'])
p.para(56,785,'Доступность описывает соединение. Успех описывает операцию. Неизвестно не означает 0%. Недоступность не доказывает остановку сервера.',1260,17,p.t['muted'])
p.finish('08-status')

p=Page('Типографика для людей и машинных данных',section='Типографика')
p.text(56,197,'Noto Sans',54,font='Bold');p.text(57,248,'Аа Бб Вв Гг Дд / Aa Bb Cc / 0123456789',25)
p.text(766,197,'Noto Sans Mono',38,font='Mono');p.text(766,248,'ssh admin@lab-a',22,font='Mono');p.text(766,292,'Версия 16.4 / CPU 24.0%',22,font='Mono')
items=[('Заголовок экрана','24 / 32','600'),('Основной текст','14 / 20','400'),('Таблица и журнал','13 / 20','400'),('Подпись и метаданные','12 / 16','400'),('Кнопки и заголовки таблиц','13 / 20','600')]
for i,(a,b,c) in enumerate(items):
    y=391+i*65;p.text(56,y,a,20);p.text(662,y,b+' px',20,font='Mono');p.text(1040,y,c,20,font='Mono');p.line(56,y+23,1384,y+23,p.t['border'])
p.para(56,748,'Размеры интерфейса в логических px Flutter. Масштаб текста до 200%: перенос, прокрутка и увеличение строк вместо обрезки. В таблицах числа выравнивать вправо, версии и команды - моноширинным шрифтом.',1280,18)
p.finish('09-typography')

p=Page('Геометрия, иконки и глубина',section='Основы интерфейса')
for i,n in enumerate([4,8,12,16,24,32,48]):
    x=56+i*182;p.rect(x,190,120,n,p.t['accent'],r=0);p.text(x,273,str(n)+' px',19,font='Mono')
for i,(title,body) in enumerate([('Сетка','Базовый шаг 4 px. Внешний отступ 24, между блоками 24, внутри карточки 16. Навигация 210 px. Минимальный рабочий экран 1000 × 700; ниже - компактная навигация и горизонтальная прокрутка таблиц.'),('Скругления','Поле и кнопка 8 px. Карточка 12 px. Диалог 16 px. Таблицы внутри одного контейнера. Не скруглять каждую строку.'),('Иконки','Контур 1.5 px на сетке 20 × 20, в крупных кнопках 24 × 24. Одинаковые окончания и оптический вес. Значимые действия сопровождаются подписью; одиночные иконки имеют tooltip и semanticsLabel.'),('Тени и движение','Тёмная тема: без теней, глубина через поверхность и границу. Светлая: тень только для меню и диалога, 0 / 4 / 16 px, 10%. Переходы 120-180 мс. При reduced motion выключать циклическую анимацию.')]):
    x=56+(i%2)*676;y=340+(i//2)*236;p.text(x,y,title,25,font='Bold');p.para(x,y+47,body,625,18)
p.finish('10-geometry')

for theme in ['dark','light']:
    p=Page('Состояния компонентов / '+('тёмная' if theme=='dark' else 'светлая'),theme,'Компоненты')
    states=[('normal','Обычное','Активное действие'),('hover','Наведение','Изменяется заливка'),('focus','Фокус','Кольцо 2 px, отступ 2 px'),('selected','Выбранное','Заливка + отметка выбора'),('disabled','Отключённое','Без снижения opacity'),('loading','Загрузка','Текст этапа + индикатор'),('error','Ошибка','Причина + способ исправить')]
    for i,(state,label,note) in enumerate(states):
        y=181+i*85;p.text(56,y+20,label,20,font='Bold')
        p.button(339,y,'Проверить' if state!='loading' else 'Проверка…',state=state if state in ['hover','focus','disabled','loading'] else 'normal')
        col=p.t['error'] if state=='error' else p.t['focus'] if state=='focus' else p.t['control']
        fill=p.t['selected'] if state=='selected' else p.t['hover'] if state=='hover' else p.t['surface']
        p.rect(555,y,370,36,fill,col,8,2 if state=='focus' else 1)
        if state=='selected':p.symbol(574,y+18,'check',p.t['accent'])
        p.text(588,y+23,'lab-a' if state!='error' else 'Укажите адрес сервера',13,p.t['error'] if state=='error' else p.t['disabled'] if state=='disabled' else p.t['text'])
        p.text(959,y+23,note,16,p.t['muted'])
    p.text(56,811,'Приоритет: disabled → error → focus → selected → hover. Ошибка сохраняет фокус и выбранное состояние.',16,p.t['muted'])
    p.finish('11-components-'+theme)

def shell(p,title,active):
    t=p.t;x,y=56,151
    p.rect(x,y,1328,652,t['surface'],t['border'],12)
    p.rect(x,y,210,652,t['raised'],r=12);p.logo(x+22,y+24,30)
    for i,(key,label) in enumerate([('servers','Серверы'),('software','ПО и версии'),('logs','Журнал'),('resources','Ресурсы'),('jobs','Задания')]):
        yy=y+114+i*48
        if key==active:p.rect(x+12,yy-26,186,40,t['selected'],r=8);p.rect(x+12,yy-26,3,40,t['accent'])
        p.text(x+29,yy,label,14,t['text'] if key==active else t['muted'],'Bold' if key==active else 'Sans')
    p.text(x+24,y+605,'Локальное хранилище',12,t['muted']);p.circle(x+26,y+620,3,t['available']);p.text(x+39,y+625,'SSH · lab-a',12,t['muted'],'Mono')
    p.text(294,199,title,24,font='Bold');p.text(294,228,'Обновлено 05.10.2026, 10:42:18 MSK',12,t['muted'])
    return 294,259
def table(p,x,y,width,headers,rows,widths):
    t=p.t;p.rect(x,y,width,36,t['raised'],r=8)
    for off,head in zip(widths,headers):p.text(x+off+12,y+23,head,12,t['muted'],'Bold')
    for i,row in enumerate(rows):
        yy=y+36+i*44
        if i==0:p.rect(x,yy,width,44,t['selected'])
        for j,(off,val) in enumerate(zip(widths,row)):
            if isinstance(val,tuple):p.badge(x+off+12,yy+27,val[0],val[1])
            else:p.text(x+off+12,yy+27,val,13,font='Mono' if j in [1,2] else 'Sans')
        p.line(x,yy+44,x+width,yy+44,t['border'])
def chart(p,x,y,w,h):
    t=p.t
    for i,label in enumerate(['100%','75%','50%','25%','0%']):
        yy=y+i*h/4;p.text(x-46,yy+4,label,11,t['muted'],'Mono');p.line(x,yy,x+w,yy,t['border'])
    vals=[[24,31,28,42,38,51,45,32,27,24,26,24],[57,58,58,59,60,61,63,61,60,61,62,62],[44,44,45,45,45,46,46,46,47,47,48,48]]
    for idx,(key,data,dash) in enumerate(zip(['accent','chart2','chart3'],vals,[None,[7,4],[2,4]])):
        pts=[(x+i*w/11,y+h*(1-v/100)) for i,v in enumerate(data)]
        for a,b in zip(pts,pts[1:]):p.line(*a,*b,t[key],2,dash)
        for xx,yy in pts[::3]:
            if idx==0:p.circle(xx,yy,3,t[key])
            elif idx==1:p.rect(xx-3,yy-3,6,6,t[key])
            else:
                for a,b in [((xx,yy-4),(xx-4,yy+3)),((xx-4,yy+3),(xx+4,yy+3)),((xx+4,yy+3),(xx,yy-4))]:p.line(*a,*b,t[key],1.5)
    for i,s in enumerate(['10:30','10:34','10:38','10:42']):p.text(x+i*w/3-18,y+h+25,s,11,t['muted'],'Mono')
    for i,(s,k,d) in enumerate([('CPU · круг','accent',None),('RAM · квадрат','chart2',[7,4]),('Диск · треугольник','chart3',[2,4])]):
        xx=x+i*260;p.line(xx,y+h+56,xx+30,y+h+56,t[k],2,d);p.text(xx+40,y+h+61,s,12,t['text'])

screens=['servers','server','software','logs','resources','jobs']
names=['Список серверов','Карточка сервера','ПО и версии','Просмотр журналов','Показатели ресурсов','Задания']
for screen,title in zip(screens,names):
    for theme in ['dark','light']:
        p=Page(title+' / '+('тёмная' if theme=='dark' else 'светлая'),theme,'Примеры интерфейса')
        x,y=shell(p,title,'servers' if screen=='server' else screen)
        if screen=='servers':
            p.rect(x,y,580,36,p.t['bg'],p.t['control'],8);p.text(x+14,y+23,'Найти по имени, адресу или тегу',13,p.t['muted']);p.button(1175,y,'Добавить сервер',w=185)
            table(p,x,y+62,1066,['Имя','Адрес','Система','Состояние','CPU','RAM'],[['lab-a','10.0.1.12','Ubuntu 24.04',('available','Доступен'),'24%','62%'],['edge-02','10.0.1.18','Debian 12',('warning','RAM 81%'),'12%','81%'],['db-01','10.0.1.21','Ubuntu 24.04',('available','Доступен'),'41%','57%'],['backup','10.0.1.30','Debian 12',('unavailable','Недоступен'),'—','—'],['staging','10.0.2.10','Не получена',('unknown','Неизвестно'),'—','—']],[0,170,340,570,830,944])
            p.rect(x,y+376,1066,116,p.t['raised'],r=12);p.text(x+20,y+411,'5 серверов · 3 соединения установлены',18,font='Bold');p.para(x+20,y+450,'Недоступен: не удалось подключиться к backup. Последний ответ: 10:38 MSK. Проверить адрес и сеть.',1000,14)
        elif screen=='server':
            p.text(x,y+28,'lab-a',28,font='Mono');p.badge(x+174,y+23,'available');p.button(1180,y,'Проверить SSH',w=180)
            for i,(label,value) in enumerate([('Система','Ubuntu 24.04 LTS'),('Адрес','10.0.1.12:22'),('Пользователь','admin'),('Uptime','14 д 06 ч')]):
                xx=x+i*272;p.rect(xx,y+63,250,96,p.t['raised'],r=12);p.text(xx+16,y+91,label,12,p.t['muted']);p.text(xx+16,y+129,value,17,font='Mono')
            p.text(x,y+209,'Ресурсы',20,font='Bold')
            for i,(a,v,k) in enumerate([('CPU','24%','accent'),('RAM','4.9 / 8 GB','chart2'),('Диск','48 / 100 GB','chart3')]):
                xx=x+i*364;p.rect(xx,y+230,338,93,p.t['bg'],p.t['border'],12);p.text(xx+16,y+258,a,13,p.t['muted']);p.text(xx+16,y+299,v,24,p.t[k],'Mono')
            p.text(x,y+374,'Последние изменения',20,font='Bold');p.badge(x,y+418,'success','Nginx обновлён до 1.26.2');p.text(x+520,y+418,'Сегодня, 10:31 MSK',13,p.t['muted'],'Mono');p.badge(x,y+462,'warning','Доступно обновление PostgreSQL');p.button(x,y+491,'Открыть ПО',kind='secondary')
        elif screen=='software':
            p.rect(x,y,610,36,p.t['bg'],p.t['control'],8);p.text(x+14,y+23,'Найти пакет или версию',13,p.t['muted']);p.button(1152,y,'Проверить версии',w=208)
            table(p,x,y+62,1066,['ПО','Установлено','Доступно','Состояние'],[['Nginx','1.26.2','1.26.2',('success','Актуально')],['PostgreSQL','16.4','16.5',('warning','Есть обновление')],['Docker Engine','27.2.0','27.3.1',('warning','Есть обновление')],['OpenSSH','9.6p1','9.6p1',('success','Актуально')],['Redis','7.2.5','—',('unknown','Не проверено')],[ 'Node.js','20.17.0','20.18.0',('warning','Есть обновление')]],[0,285,505,715])
            p.rect(x,y+380,1066,115,p.t['raised'],r=12);p.text(x+20,y+414,'Обновить PostgreSQL до 16.5',18,font='Bold');p.text(x+20,y+447,'Будет перезапущена служба postgresql на lab-a.',14,p.t['muted']);p.button(x+20,y+461,'Создать задание',w=194)
        elif screen=='logs':
            p.button(x,y,'Служба: nginx',kind='secondary',w=190);p.button(x+206,y,'Все уровни',kind='secondary',w=168);p.button(1185,y,'Приостановить',kind='secondary',w=175)
            p.rect(x,y+60,1066,360,p.t['bg'],p.t['control'],8)
            logs=[('10:42:18','INFO','nginx: worker process started'),('10:42:19','INFO','GET /health 200 12ms'),('10:42:21','WARN','upstream response time 820ms'),('10:42:22','INFO','GET /api/servers 200 24ms'),('10:42:25','ERROR','connect() failed: connection refused'),('10:42:26','INFO','retry upstream connection (1/3)'),('10:42:29','INFO','upstream connection restored'),('10:42:30','INFO','GET /health 200 11ms'),('10:42:32','INFO','GET /metrics 200 8ms'),('10:42:36','INFO','Запрос обработан: /health')]
            for i,(time,level,msg) in enumerate(logs):
                yy=y+94+i*29;p.text(x+16,yy,f'{i+1:02}',12,p.t['muted'],'Mono');p.text(x+56,yy,time,13,p.t['muted'],'Mono');p.text(x+184,yy,level,13,p.t['error'] if level=='ERROR' else p.t['warning'] if level=='WARN' else p.t['running'],'Mono');p.text(x+270,yy,msg,13,font='Mono')
            p.text(x,y+457,'Следование хвосту включено · 10 строк · MSK (UTC+03:00)',13,p.t['muted']);p.text(x,y+494,'Поиск: connection     2 совпадения',14);p.button(1185,y+461,'Экспорт журнала',kind='secondary',w=175)
        elif screen=='resources':
            for i,(a,v,k) in enumerate([('CPU','24%','accent'),('RAM','62%','chart2'),('Диск','48%','chart3')]):
                xx=x+i*364;p.rect(xx,y,338,86,p.t['raised'],r=12);p.text(xx+16,y+27,a,13,p.t['muted']);p.text(xx+16,y+65,v,26,p.t[k],'Mono')
            p.text(x,y+122,'Последние 12 минут · интервал 1 мин',14,p.t['muted']);chart(p,x+50,y+153,945,225)
            p.text(x,y+488,'Нет данных: разрыв линии и подпись. Порог: пунктир + числовое значение.',13,p.t['muted'])
        elif screen=='jobs':
            p.button(x,y,'Новое задание',w=183);p.text(x+214,y+23,'lab-a · установка и обновления',14,p.t['muted'])
            table(p,x,y+62,1066,['Задание','Цель','Состояние','Начало'],[['Обновить PostgreSQL','lab-a',('running','Выполнение'),'10:41 MSK'],['Обновить Nginx','lab-a',('success','Успех'),'10:31 MSK'],['Установить Docker','edge-02',('error','Ошибка'),'10:28 MSK']],[0,350,535,830])
            p.rect(x,y+250,1066,256,p.t['raised'],r=12);p.text(x+20,y+289,'Обновление PostgreSQL до 16.5',21,font='Bold');p.badge(x+20,y+329,'running','Загрузка пакетов · 64%');p.rect(x+20,y+352,1026,8,p.t['bg'],r=4);p.rect(x+20,y+352,657,8,p.t['running'],r=4);p.text(x+20,y+394,'Следующий этап: установка и перезапуск postgresql.',14);p.text(x+20,y+425,'Во время перезапуска соединения с БД могут прерваться.',14,p.t['muted']);p.button(x+20,y+450,'Открыть журнал',kind='secondary',w=180);p.button(x+220,y+450,'Отменить загрузку',kind='secondary',w=205)
        p.finish('ui-'+screen+'-'+theme)

p=Page('Плотные данные и доступные графики',section='Поведение')
for i,(a,b) in enumerate([('Таблицы','Строки 36 px в плотном режиме и 44 px по умолчанию. Закреплять заголовок; имя сервера - при горизонтальной прокрутке. Сортировка имеет направление и semantics. Обрезка имени допустима только с полным значением в tooltip и копированием.'),('Журналы','Моноширинный текст 13/20 px. Сохранять переносы и пробелы. По умолчанию горизонтальная прокрутка; перенос строк включается отдельно. При ручной прокрутке вверх приостанавливать следование хвосту. ERROR и WARN видны как текст.'),('Графики','CPU: сплошная линия и круг. RAM: штрих и квадрат. Диск: точки и треугольник. Ось с единицами, период и часовой пояс обязательны. Tooltip доступен клавиатурой; рядом открывается таблица значений. Нет данных - разрыв, а не ноль.'),('Клавиатура и масштаб','Tab следует визуальному порядку. Enter запускает выбранное действие; Escape закрывает меню. Фокус не перекрывается панелями. У интерактивной цели минимум 24 × 24 px, стандарт 36 px. Статус операции объявляется через Semantics liveRegion.')]):
    x=56+(i%2)*676;y=194+(i//2)*292;p.text(x,y,a,26,font='Bold');p.para(x,y+50,b,622,19)
p.finish('24-data-accessibility')

p=Page('Тексты называют действие и последствия',section='Голос бренда')
p.para(56,175,'Профессионально, коротко и спокойно. Сначала результат или проблема, затем следующий шаг. Не обвиняем пользователя, не скрываем причину и не выдаём предположение за факт.',1240,23)
examples=[('Кнопка','Обновить PostgreSQL','Выполнить магию'),('Подтверждение','Перезапустить nginx на lab-a? Активные соединения могут прерваться.','Вы уверены?'),('Ошибка','Не удалось подключиться: истекло время ожидания. Проверить адрес и сеть.','Что-то пошло не так'),('Успех','Nginx обновлён до 1.26.2. Служба запущена.','Всё отлично!'),('Нет данных','Метрики ещё не получены. Повторить проверку.','CPU: 0%')]
for i,(a,b,c) in enumerate(examples):
    y=331+i*92;p.text(56,y,a,18,font='Bold');p.para(284,y,b,705,17);p.text(1055,y,c,16,p.t['muted']);p.line(56,y+58,1384,y+58,p.t['border'])
p.finish('25-voice')

for theme in ['dark','light']:
    p=Page('Сайт, документация и запуск / '+('тёмная' if theme=='dark' else 'светлая'),theme,'Применение')
    p.rect(56,160,780,315,p.t['surface'],p.t['border'],12);p.logo(80,182,32);p.text(520,204,'Документация    Скачать',13,p.t['muted']);p.text(80,297,'Linux-серверы под контролем',31,font='Bold');p.para(80,343,'Состояние, версии и изменения инфраструктуры в одном десктопном приложении.',700,18);p.button(80,405,'Скачать для Windows',w=235)
    p.rect(866,160,518,620,p.t['surface'],p.t['border'],12);p.logo(1065,294,120,False);p.text(1013,471,'ServerDeck',33,font='Bold');p.text(967,515,'Подготовка локального хранилища',16,p.t['muted']);p.line(966,555,1284,555,p.t['control'],4);p.line(966,555,1160,555,p.t['accent'],4);p.text(1035,698,'Версия 0.1.0',13,p.t['muted'],'Mono')
    p.rect(56,505,780,275,p.t['surface'],p.t['border'],12);p.text(80,551,'Документация / Подключение сервера',22,font='Bold');p.para(80,597,'1. Укажите адрес и пользователя SSH. 2. Выберите способ аутентификации. 3. Проверьте соединение.',701,18);p.rect(80,681,732,53,p.t['raised'],p.t['control'],8);p.text(96,714,'ssh admin@10.0.1.12',16,font='Mono')
    p.finish('26-applications-'+theme)

p=Page('Передача во Flutter и проверка контраста',section='Внедрение')
p.para(56,177,'Единый источник значений: serverdeck.tokens.json. Таблица design-tokens.xlsx и CSV содержит обе темы и общую геометрию. Значения цвета непрозрачны и не зависят от Material seed.',1260,22)
for i,(a,b) in enumerate([('ColorScheme','bg → scaffoldBackgroundColor; surface → surface; text → onSurface; accent → primary; onAccent → onPrimary; error → error. onError равен bg. Семантика статусов и графиков хранится в ThemeExtension.'),('Компоненты','TextTheme: bodyMedium 14/20, titleLarge 24/32, labelLarge 13/20. Журналы и версии используют Noto Sans Mono. WidgetStateProperty задаёт hover, focused, selected и disabled явными токенами.'),('Контраст','Текст и подписи ≥ 4.5:1. Значимые границы, фокус и линии графиков ≥ 3:1 к соседним поверхностям. border - только декоративный. Disabled рассчитан без opacity; логотип исключён из требования к тексту.'),('Пределы проверки','Автоматически проверены цветовые пары токенов, включая hover и selected. Это проверка палитры, а не сертификат WCAG всего приложения. После внедрения проверить Semantics, клавиатуру, масштаб 200% и фактические поверхности.')]):
    x=56+(i%2)*676;y=329+(i//2)*205;p.text(x,y,a,24,font='Bold');p.para(x,y+44,b,619,17)
p.text(56,779,f'Проверено {len(audit)} пар. Минимум текста: {min(r[5] for r in audit if r[7]=="text"):.2f}:1.',18,p.t['accent'],'Bold')
p.text(56,813,'Основание: WCAG 2.2, 1.4.3 и 1.4.11. Источники и методика в README.html и contrast-audit.csv.',15,p.t['muted'])
p.finish('28-implementation')
pdf.save()

# Transparent SVG logos with self-contained embedded type. PDF/PNG rendered from same geometry.
fontdata=base64.b64encode((ROOT/'fonts/NotoSans-SemiBold.ttf').read_bytes()).decode()
poppler=Path('C:/Users/user/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/poppler/Library/bin/pdftoppm.exe')
for theme,mono,name in [('dark',None,'dark'),('light',None,'light'),('light','#172337','mono-dark'),('dark','#FFFFFF','mono-white')]:
    for form in ['logo','mark','app-icon']:
        width,height=(520,112) if form=='logo' else (128,128) if form=='mark' else (1024,1024)
        tmp=ROOT/'qa'/f'{form}-{name}.pdf';save=pdf;pdf=canvas.Canvas(str(tmp),pagesize=(width,height))
        p=Page.__new__(Page);p.title='ServerDeck';p.t=THEMES[theme];p.w=width;p.h=height;p.svg=[];p.outlineLogo=True
        if form=='app-icon':p.rect(0,0,width,height,p.t['bg']);p.logo(128,128,768,False,mono)
        elif form=='mark':p.logo(0,0,128,False,mono)
        else:p.logo(16,16,80,True,mono)
        # All internal negative space is transparent; only app-icon has a background.
        svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}"><title>ServerDeck / {form} / {name}</title>'+''.join(p.svg)+'</svg>'
        (ROOT/'logos'/f'{form}-{name}.svg').write_text(svg,encoding='utf-8')
        pdf.save();pdf=save
        doc=fitz.open(tmp);pix=doc[0].get_pixmap(alpha=True);pix.save(ROOT/'logos'/f'{form}-{name}.png');doc.close()
        from PIL import Image
        path=ROOT/'logos'/f'{form}-{name}.png';im=Image.open(path).convert('RGBA')
        im.save(path)
        if form=='app-icon' and name in ['dark','light']:
            for size in [256,128,64,32,24,16]:im.resize((size,size),Image.Resampling.LANCZOS).save(ROOT/'logos'/f'app-icon-{name}-{size}.png')

# PDF render for inspection, one sheet per page and a compact visual index.
subprocess.run([str(poppler),'-scale-to','720','-png',str(ROOT/'ServerDeck-brandbook.pdf'),str(ROOT/'qa/page')],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
from PIL import Image, ImageDraw
thumbs=sorted((ROOT/'qa').glob('page-*.png'))
contact=Image.new('RGB',(1440,math.ceil(len(thumbs)/4)*250),'#DEE4ED');draw=ImageDraw.Draw(contact)
for i,path in enumerate(thumbs):
    im=Image.open(path);im.thumbnail((350,218));xx=(i%4)*360;yy=(i//4)*250;contact.paste(im,(xx,yy));draw.text((xx+8,yy+220),str(i+1)+' '+allpages[i][0],fill='#172337')
contact.save(ROOT/'qa/contact-sheet.png')
reader=PdfReader(ROOT/'ServerDeck-brandbook.pdf')
assert len(reader.pages)==len(allpages)
for page,(_,title) in zip(reader.pages,allpages): assert title in page.extract_text(),title
(ROOT/'qa/verification.json').write_text(json.dumps({'pages':len(allpages),'contrast_pairs':len(audit),'contrast_pass':True,'minimum_text':min(r[5] for r in audit if r[7]=='text'),'minimum_non_text':min(r[5] for r in audit if r[7]=='non-text'),'pdf_text_check':True},indent=2),encoding='utf-8')
toc=''.join(f'<li><a href="layouts/{slug}.svg">{html.escape(title)}</a></li>' for slug,title in allpages)
(ROOT/'README.html').write_text('''<!doctype html><html lang="ru"><meta charset="utf-8"><title>ServerDeck — материалы бренда</title><style>body{font:16px/1.7 Arial,sans-serif;max-width:1000px;margin:48px auto;color:#172337;background:#F3F6FA}h1{font-size:40px}a{color:#087565}code{background:#EAF0F6;padding:3px 5px}li{margin:4px 0}</style><h1>ServerDeck / Брендбук 1.1</h1><p>Создан по брифу от 05.10.2026. Логотип обновлён 10.10.2026: выбран вариант №1 «Модули». Темы сохраняют структуру и развивают существующие цвета приложения #0C121C, #151E2B, #64DFC5.</p><p><a href="ServerDeck-brandbook.pdf">Брендбук PDF</a> · <a href="tokens/design-tokens.xlsx">Таблица токенов XLSX</a> · <a href="tokens/design-tokens.csv">CSV UTF-8</a> · <a href="tokens/serverdeck.tokens.json">JSON</a> · <a href="tokens/contrast-audit.csv">Отчёт контраста</a></p><h2>Редактирование</h2><p>Макеты SVG имеют редактируемые векторные фигуры и текст, размер 1440 × 900. Откройте их в Figma, Illustrator или Inkscape; для живого текста установите приложенные Noto Sans Regular/SemiBold и Noto Sans Mono Regular. Это векторные макеты, не файл с Figma-компонентами и auto-layout. Исходный генератор в source/build.py позволяет пересобрать PDF и SVG одновременно.</p><h2>Логотипы</h2><p>logos содержит цветные и монохромные варианты logo, mark и app-icon. Суффикс dark означает размещение на тёмном фоне, light — на светлом. SVG названия содержит встроенный Noto Sans SemiBold; PNG не требует шрифта. PNG логотипов и знаков имеет прозрачный внешний фон, иконки приложения — сплошной квадрат для маски ОС. Для редактирования логотипа установите приложенные шрифты. Охранное поле указано в PDF; экспорт может требовать дополнительных внешних отступов при размещении.</p><h2>Flutter</h2><p>HEX #RRGGBB → Color(0xFFRRGGBB), размеры → logical px. Сохранить токены bg/surface/text/accent, не генерировать остальные цвета автоматически через fromSeed. Семантические цвета, chart2/chart3, control и selected вынести в ThemeExtension; onError = bg. Токены предназначены для новой реализации клиента. Подключить fonts через pubspec.yaml с лицензией OFL, а также веса 400/600. Плотность строк 36/44 px, текст таблицы 13/20 px. Выделение и фокус могут присутствовать одновременно; focus рисуется поверх выбранного состояния. onAccent допустим только на accent и accentHover.</p><h2>Контраст</h2><p>Отчёт содержит исходные HEX, коэффициенты без округления при оценке, пороги и роль каждой пары. Метод WCAG: преобразование sRGB в линейный RGB, L=0.2126R+0.7152G+0.0722B, отношение (Lmax+0.05)/(Lmin+0.05). Текст ≥4.5:1; существенные границы/фокус/линии ≥3:1. Декоративный border исключён. Цветные подписи и графики разрешены на bg, surface, raised, hover и selected. disabled проверен дополнительно. Для кнопок проверен onAccent на normal/hover. Полная доступность приложения проверяется после внедрения.</p><h2>Источники и лицензии</h2><p><a href="https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html">WCAG 2.2: 1.4.3 Contrast Minimum</a> · <a href="https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html">1.4.11 Non-text Contrast</a> · <a href="https://github.com/notofonts/noto-fonts">Noto fonts / OFL</a> · <a href="fonts/OFL.txt">Приложенная лицензия</a>. Знак разработан для этого брифа; поиск товарных знаков не проводился. Данные серверов, версии и журналы в макетах демонстрационные, не результат проверки инфраструктуры.</p><h2>Все редактируемые листы</h2><ol>'''+toc+'</ol></html>',encoding='utf-8')
readme=ROOT/'README.html'
readme.write_text(readme.read_text(encoding='utf-8').replace('SVG названия содержит встроенный Noto Sans SemiBold; PNG не требует шрифта.','SVG логотипов сохранён контурами и не требует шрифта; PNG также готов к использованию.').replace('Для редактирования логотипа установите приложенные шрифты.','Для редактирования живого текста в макетах установите приложенные шрифты.'),encoding='utf-8')
print(json.dumps({'pages':len(allpages),'contrast_pairs':len(audit),'minimum_text':min(r[5] for r in audit if r[7]=='text'),'root':str(ROOT)},ensure_ascii=False))
