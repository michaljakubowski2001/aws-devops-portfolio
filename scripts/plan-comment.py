"""Format a bounded plan comment; no expressions from a PR are evaluated as shell."""
import os
from pathlib import Path

body = Path('.artifacts/plan.txt').read_text()
body = body[:55000] + ('\n[Truncated: see workflow artifact.]' if len(body) > 55000 else '')
url = f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
Path('.artifacts/comment.md').write_text(
    f'## Terraform plan\n\n[Workflow and full plan]({url})\n\n```text\n{body}\n```\n'
    'A PR plan is advisory. Main generates a new saved plan for production approval.\n'
)
