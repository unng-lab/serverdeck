"""Build the offline design atlas from versioned source and canonical assets."""

import base64
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / 'docs/design'
SOURCE = DESIGN / 'source'


def build():
    template = (SOURCE / 'index.html').read_text(encoding='utf-8')
    css = (SOURCE / 'style.css').read_text(encoding='utf-8')
    css += '\n' + (SOURCE / 'components.css').read_text(encoding='utf-8')
    assets = {}
    for folder, names, mime in [
        ('fonts', ['NotoSans-Regular.ttf', 'NotoSans-SemiBold.ttf', 'NotoSansMono-Regular.ttf'], 'font/ttf'),
        ('logos', ['logo-dark.svg', 'logo-light.svg', 'mark-dark.svg', 'mark-light.svg'], 'image/svg+xml'),
    ]:
        for name in names:
            key = f'assets/{folder}/{name}'
            data = (ROOT / 'assets/brand' / folder / name).read_bytes()
            url = f'data:{mime};base64,' + base64.b64encode(data).decode('ascii')
            assets[key] = url
            css = css.replace(key, url)
            template = template.replace(key, url)
    bootstrap = 'window.SERVERDECK_ASSETS=' + json.dumps(assets) + ';'
    registry = DESIGN / 'components/registry.json'
    if registry.exists():
        bootstrap += 'window.SERVERDECK_COMPONENT_REGISTRY=' + registry.read_text(encoding='utf-8') + ';'
    def script(text):
        return '<script>' + text.replace('</script', '<\\/script') + '</script>'
    scripts = script(bootstrap)
    for name in ['design-system.js']:
        scripts += script((SOURCE / name).read_text(encoding='utf-8'))
    scripts += script('document.addEventListener("DOMContentLoaded",()=>{\n' +
                      (SOURCE / 'component-gallery.js').read_text(encoding='utf-8') + '\n});')
    template = template.replace('<link rel="stylesheet" href="style.css">', '<style>' + css + '</style>')
    template = template.replace('<!-- ATLAS_SCRIPTS -->', scripts)
    (DESIGN / 'ServerDeck-design.html').write_text(template, encoding='utf-8')
    print('Built docs/design/ServerDeck-design.html (offline; C01–C30 only)')


if __name__ == '__main__':
    build()
