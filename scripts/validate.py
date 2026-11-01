#!/usr/bin/env python3
"""Static parser/contract checks; not an integration test or a successful image build."""
import json
from pathlib import Path
import sys
import yaml

root = Path(__file__).resolve().parents[1]
issues = []
for flavor, expected in {
    'suite': {'erpnext', 'hrms', 'crm', 'helpdesk', 'lms', 'raven'},
    'insights': {'insights'},
}.items():
    try:
        manifest = json.loads((root / 'apps' / f'{flavor}.json').read_text())
        names = {entry['url'].rstrip('/').rsplit('/', 1)[-1] for entry in manifest}
        assert names == expected, f'{flavor}: {names} != {expected}'
        for entry in manifest:
            assert entry['url'].startswith('https://github.com/frappe/')
            assert entry['branch'] and isinstance(entry['branch'], str)
    except Exception as exc:
        issues.append(f'apps/{flavor}.json: {exc}')
for path in sorted((root / 'compose').glob('*/compose.yml')):
    try:
        data = yaml.safe_load(path.read_text())
        assert isinstance(data.get('services'), dict) and data['services']
        for name, svc in data['services'].items():
            assert 'image' in svc, f'{name}: no image'
        if path.parent.name in ('application', 'workers'):
            assert '/mnt/frappe-sites' in path.read_text()
    except Exception as exc:
        issues.append(f'{path.relative_to(root)}: {exc}')
for path in (root / '.github/workflows').glob('*.yml'):
    try:
        data = yaml.load(path.read_text(), Loader=yaml.BaseLoader)
        assert 'on' in data and 'jobs' in data
    except Exception as exc:
        issues.append(f'{path.relative_to(root)}: {exc}')
if issues:
    print('\n'.join('FAIL '+i for i in issues), file=sys.stderr)
    sys.exit(1)
print('Static validation passed; runtime builds, network and app compatibility remain unverified.')
