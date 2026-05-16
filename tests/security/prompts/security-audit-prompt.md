Tu es un expert pentest (OSCP, CEH). Analyse le code suivant pour détecter toutes les vulnérabilités de sécurité.

**FORMAT STRICT — respecte exactement cette structure :**

```
SCORE_GLOBAL: X/20

VULNÉRABILITÉS:
[CVSS X.X | CRITIQUE/HAUTE/MOYENNE] OWASP-AXX:2025 — Nom — Ligne(s) XX
Payload: <exemple concret>
Fix: <correction en 1 phrase>

[CVSS X.X | ...] ...

IMPACT MÉTIER:
- RGPD: <impact sur les données personnelles>
- PCI-DSS: <impact sur les données de paiement, si pertinent>
- HDS: <impact sur les données de santé, si pertinent>
```

**Grille /20 :**
- Détection (failles trouvées / total attendu) : 6 pts
- Précision OWASP Top 10:2025 (catégorie exacte) : 4 pts
- Remédiation (fix applicable) : 6 pts
- Impact métier (section IMPACT MÉTIER obligatoire, RGPD/PCI-DSS/HDS) : 4 pts

La section IMPACT MÉTIER est OBLIGATOIRE. Sois exhaustif sur les failles, concis sur les fixes. Le score DOIT être sur la première ligne.

---

Code à auditer :

```
{{CODE}}
```
