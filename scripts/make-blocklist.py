#!/usr/bin/env python3
"""Gera Fern/Privacy/Resources/blocklist.json a partir de scripts/blocklist-domains.txt.

Lista própria do Fern (sem copiar listas públicas, para não depender da licença delas):
domínios conhecidos de anúncios e rastreamento, um por linha; linhas com # são comentários.
Só bloqueia quando o recurso vem de outro site (third-party), para não quebrar o próprio
site do serviço. Uso: python3 scripts/make-blocklist.py
"""
import json
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
domains = sorted({
    line.strip()
    for line in (root / "scripts/blocklist-domains.txt").read_text().splitlines()
    if line.strip() and not line.strip().startswith("#")
})
rules = [
    {
        "trigger": {
            "url-filter": "^[^:]+://+([^:/]+\\.)?" + domain.replace(".", "\\.") + "[:/]",
            "load-type": ["third-party"],
        },
        "action": {"type": "block"},
    }
    for domain in domains
]
output = root / "Fern/Privacy/Resources/blocklist.json"
output.write_text(json.dumps(rules, indent=1) + "\n")
print(f"{len(rules)} regras em {output.relative_to(root)}")
