"""Validate current design sources and component/reference joins, offline."""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def validate():
    screens = json.loads((ROOT / 'docs/design/screens.json').read_text(encoding='utf-8-sig'))
    registry = json.loads((ROOT / 'docs/design/components/registry.json').read_text(encoding='utf-8'))
    ids = {s['id'] for s in screens}
    assert len(screens) == len(ids) == 98
    assert sum(bool(s['implemented']) for s in screens) == 35
    components = {c['id']: c for c in registry['components']}
    assert set(components) == {f'C{i:02}' for i in range(1, 31)}
    bindings = registry['screens']
    assert len(bindings) == 98 and {s['screenId'] for s in bindings} == ids
    assert sum(s['kind'] == 'existing' for s in bindings) == 35
    for binding in bindings:
        assert binding['componentIds'] and set(binding['componentIds']) <= components.keys()
        for relative in binding['productionPaths']:
            assert (ROOT / relative).is_file(), relative
        if binding['kind'] == 'concept':
            assert not binding['productionPaths']
    for component in components.values():
        assert component['sourceScreenIds'] and set(component['sourceScreenIds']) <= ids
        assert component['applicableStates'] and 'default' in component['applicableStates']
        assert not set(component['applicableStates']) & component['notApplicableReasons'].keys()
        for field in ['anatomy', 'variants', 'parameters', 'events', 'limitations', 'acceptanceCriteria']:
            assert component[field] and all(isinstance(value, str) and value.strip() for value in component[field]), (component['id'], field)
        assert component['usageExample'].strip()
        assert (ROOT / component['runnableExamplePath']).is_file()
        for field in ['implementationPaths', 'testPaths', 'designEvidence']:
            assert component[field], (component['id'], field)
            for relative in component[field]:
                assert (ROOT / relative).is_file(), relative
    source = ROOT / 'docs/design/source'
    for name in ['index.html', 'app.js', 'style.css', 'components.css', 'design-system.js', 'content-renderers.js', 'component-gallery.js']:
        assert (source / name).is_file(), name
    tokens = json.loads((ROOT / 'docs/brandbook/tokens/serverdeck.tokens.json').read_text(encoding='utf-8-sig'))
    css = (source / 'style.css').read_text(encoding='utf-8')
    for palette in tokens['themes'].values():
        for role, value in palette.items():
            assert f'--{role}:{value}'.lower() in css.lower(), (role, value)
    return {'scope': 'Static source/registry integrity; not runtime acceptance', 'references': 98, 'existing': 35, 'concepts': 63, 'components': 30, 'errors': 0}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--json', action='store_true')
    parser.parse_args()
    print(json.dumps(validate(), ensure_ascii=False))
