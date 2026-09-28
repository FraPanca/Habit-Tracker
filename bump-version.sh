#!/usr/bin/env bash
# Porta la versione del progetto a X.Y.Z in tutti i file che la contengono.
# Uso:  bash bump-version.sh X.Y.Z
set -euo pipefail

NEW="${1:-1.1.0}"
NEW="${NEW#v}"                      # accetta sia 1.1.0 sia v1.1.0
if [[ ! "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Versione non valida: '$NEW' (atteso X.Y.Z)" >&2
  exit 1
fi
if [[ ! -f docker-compose.yml || ! -f package-lock.json || ! -d charts/habit-tracker ]]; then
  echo "Errore: esegui lo script dalla root del repository Habit-Tracker." >&2
  exit 1
fi

NEW="$NEW" python3 - <<'PY'
import json
import os
import pathlib
import re

NEW = os.environ["NEW"]
TAG = "v" + NEW
report = []


def edit(path, pattern, repl, expected_min=1, regex=False, flags=0):
    p = pathlib.Path(path)
    s = p.read_text()
    if regex:
        s2, n = re.subn(pattern, repl, s, flags=flags)
    else:
        n = s.count(pattern)
        s2 = s.replace(pattern, repl)
    if n < expected_min:
        raise SystemExit(f"ERRORE: in {path} trovate {n} occorrenze di {pattern!r} (attese >= {expected_min}).")
    if s2 != s:
        p.write_text(s2)
    report.append((path, n))


# --- Immagini Docker: default del tag ---------------------------------------
edit("docker-compose.yml", r"\$\{IMAGE_TAG:-v[0-9.]+\}", "${IMAGE_TAG:-" + TAG + "}", 2, regex=True)
edit(".env.example", r"^IMAGE_TAG=.*$", "IMAGE_TAG=" + TAG, 1, regex=True, flags=re.M)

# --- README (IT + EN): default del tag ed esempi di release ------------------
edit("README.md", "v0.3.0", TAG, 10)   # default IMAGE_TAG, tabella variabili terraform-docker (IT + EN)
edit("README.md", r"(?<![\w.])v1\.0\.0(?![\w.])", TAG, 6, regex=True)   # esempi 'git tag' / 'git push origin' / 'es.'

# --- Terraform ---------------------------------------------------------------
edit("terraform-docker/variables.tf", r'(default\s+=\s+)"v[0-9]+\.[0-9]+\.[0-9]+"', r'\g<1>"' + TAG + '"', 2, regex=True)
edit("terraform-docker/terraform.tfvars.example", r'"v[0-9]+\.[0-9]+\.[0-9x]+"', '"' + TAG + '"', 2, regex=True)
edit("terraform-aws/terraform.tfvars.example", r'"v[0-9]+\.[0-9]+\.[0-9x]+"', '"' + TAG + '"', 2, regex=True)

# --- Helm / GitOps -------------------------------------------------------------
edit("charts/habit-tracker/values-eks.yaml", r'(tag: )"v[0-9]+\.[0-9]+\.[0-9]+"', r'\g<1>"' + TAG + '"', 2, regex=True)
edit("charts/habit-tracker/Chart.yaml", r"^version: \S+", "version: " + NEW, 1, regex=True, flags=re.M)
edit("charts/habit-tracker/Chart.yaml", r'^appVersion: "[^"]+"', 'appVersion: "' + NEW + '"', 1, regex=True, flags=re.M)

# --- package.json (root + workspaces) --------------------------------------------
for f in ("package.json", "backend/package.json", "frontend/package.json"):
    edit(f, r'^(\s*"version":\s*)"[^"]+"', r'\g<1>"' + NEW + '"', 1, regex=True, flags=re.M)

# --- package-lock.json: mantenuto coerente (npm ci non deve lamentarsi) ----------
lock_path = pathlib.Path("package-lock.json")
lock = json.loads(lock_path.read_text())
lock["version"] = NEW
for key in ("", "backend", "frontend"):
    lock["packages"][key]["version"] = NEW
lock_path.write_text(json.dumps(lock, indent=2, ensure_ascii=False) + "\n")
report.append(("package-lock.json", 4))

width = max(len(p) for p, _ in report)
for path, n in report:
    print(f"  {path:<{width}}  {n} modifica/he")
print(f"\nVersione impostata a {TAG} (chart e package: {NEW}).")
PY

echo
echo "Verifica: nessuna versione vecchia residua nei file gestiti dallo script:"
if git grep -nE 'v0\.3\.0|v0\.1\.[0-9x]|v1\.0\.[06]\b' -- \
     ':!package-lock.json' ':!*.lock.hcl' ':!*.ndjson' ':!monitoring' ':!.github/workflows/ci.yml' 2>/dev/null; then
  echo "  ^ controlla le righe sopra"
else
  echo "  nessuna."
fi