from pathlib import Path
import sys,json,zipfile,xml.etree.ElementTree as ET
sys.path.insert(0,str(Path(__file__).resolve().parents[3]/'tmp/branddeps'))
import pymupdf as fitz
from fontTools.ttLib import TTFont
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[1]
d=fitz.open(root/'ServerDeck-brandbook.pdf')
bad=[]
for i,page in enumerate(d):
    for b in page.get_text('dict')['blocks']:
        for line in b.get('lines',[]):
            for span in line['spans']:
                if span['bbox'][2]>1385 or span['bbox'][0]<0 or span['bbox'][3]>900:
                    bad.append([i+1,span['text']])
assert not bad,bad
fonts={n:TTFont(root/'fonts'/f).getBestCmap() for n,f in [('sans','NotoSans-Regular.ttf'),('bold','NotoSans-SemiBold.ttf'),('mono','NotoSansMono-Regular.ttf')]}
for p in (root/'layouts').glob('*.svg'):
    for t in ET.parse(p).getroot().iter('{http://www.w3.org/2000/svg}text'):
        cmap=fonts['mono' if t.get('font-family')=='Noto Sans Mono' else 'bold' if t.get('font-weight')=='600' else 'sans']
        assert all(ord(c) in cmap for c in (t.text or '')),(p.name,t.text)
for theme in ['dark','light','mono-dark','mono-white']:
    for form in ['logo','mark']:
        p=root/'logos'/f'{form}-{theme}.png'
        im=Image.open(p);assert im.mode=='RGBA' and im.getpixel((0,0))[3]==0,p.name
        # True transparent indicator hole inside the first module.
        pt=(41,35) if form=='logo' else (40,30)
        assert im.getpixel(pt)[3]==0,(p.name,'inner negative space')
        svg=ET.parse(root/'logos'/f'{form}-{theme}.svg')
        assert not list(svg.getroot().iter('{http://www.w3.org/2000/svg}text'))
for theme in ['dark','light']:
    im=Image.open(root/'logos'/f'app-icon-{theme}.png')
    im.save(root/'logos'/f'serverdeck-{theme}.ico',sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
for i in [4,7,10,18,22,28]:d[i].get_pixmap().save(root/'qa'/f'full-{i+1}.png')
pair=Image.new('RGB',(1328,372),'#F3F6FA');dr=ImageDraw.Draw(pair)
for i,idx in enumerate([12,13]):
    page=Image.frombytes('RGB',(1440,900),d[idx].get_pixmap().samples)
    panel=page.crop((56,151,1384,803)).resize((664,326),Image.Resampling.LANCZOS)
    pair.paste(panel,(i*664,36))
    dr.text((i*664+16,12),'ServerDeck / '+('Dark' if i==0 else 'Light'),fill='#172337')
pair.save(root/'preview.png')
v=json.loads((root/'qa/verification.json').read_text())
v.update({'all_svg_fonts_checked':True,'text_page_bounds_checked':True,'logo_png_transparency_checked':True,'logo_svg_outlines_checked':True})
(root/'qa/verification.json').write_text(json.dumps(v,indent=2),encoding='utf-8')
(root/'verification.json').write_text(json.dumps(v,indent=2),encoding='utf-8')
(root/'source/requirements.txt').write_text('reportlab\npypdf\npymupdf\nfonttools\nPillow\n',encoding='utf-8')
archive=root.parents[1]/'output/ServerDeck-brandbook-kit-v1.1.zip'
archive.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for p in root.rglob('*'):
        rel=p.relative_to(root)
        if p.is_file() and not any(part in ['node_modules','qa','__pycache__'] for part in rel.parts) and not p.name.endswith('.ndjson') and p.name!='token-rows.json':
            z.write(p,Path('ServerDeck-brandbook')/rel)
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
print(json.dumps({'archive':str(archive),'size_mb':round(archive.stat().st_size/1e6,2),'verification':v}))
