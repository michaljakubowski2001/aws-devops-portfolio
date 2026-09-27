"""Capture Grafana and Uptime Kuma through local SSM port-forwarding tunnels.

Open tunnels to ports 20158 and 30157 first (see docs/runbook.md). The pages are private,
so screenshots can only be taken from a machine with an authorized SSM session.
"""
from pathlib import Path
from playwright.sync_api import sync_playwright

output = Path('docs/screenshots')
output.mkdir(parents=True, exist_ok=True)
with sync_playwright() as playwright:
    browser = playwright.chromium.launch(channel='chrome', headless=True)
    page = browser.new_page(viewport={'width': 1440, 'height': 1000}, device_scale_factor=1)
    for name, url in [
        ('grafana-aws', 'http://localhost:20158/d/mikrus-infrastructure?orgId=1&from=now-30m&to=now&timezone=browser'),
        ('kuma-aws', 'http://localhost:30157/status/portfolio'),
    ]:
        response = page.goto(url, wait_until='networkidle', timeout=60000)
        if not response or response.status != 200:
            raise RuntimeError(f'{name}: unexpected response')
        if name.startswith('grafana'):
            # Wait until every panel has rendered and no query is still loading.
            page.wait_for_selector('[data-viz-panel-key]', timeout=30000)
            page.wait_for_function(
                "document.querySelectorAll('[aria-label=\"Panel loading bar\"]').length === 0", timeout=30000)
        page.wait_for_timeout(8000)
        page.screenshot(path=str(output / f'{name}.png'), full_page=True)
        print(f'{name}: {page.title()}')
    browser.close()
