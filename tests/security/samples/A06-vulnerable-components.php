<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection OWASP A06:2021 Vulnerable & Outdated Components
 * NE PAS déployer en production.
 */

// ─── Faille 1 : Dépendances obsolètes avec CVEs connus ───────────────────────────
// composer.json correspondant (simulé ici en commentaire) :
//
// "require": {
//     "symfony/symfony": "3.4.*",        // EOL depuis 2021 — multiple CVEs
//     "twig/twig": "1.42.0",             // CVE-2022-23614 — sandbox bypass
//     "monolog/monolog": "1.0.0",        // très ancienne — pas de CVE mais plus maintenu
//     "guzzlehttp/guzzle": "6.3.0",      // CVE-2022-29248 — header injection
//     "phpoffice/phpspreadsheet": "1.5.0",// CVE-2022-23817 — XXE
//     "league/flysystem": "1.0.0",       // CVE-2021-32708 — path traversal
//     "php": "7.2.*"                     // EOL depuis 2020 — nombreux CVEs
// }

// ─── Faille 2 : Bibliothèque chargée depuis CDN sans intégrité ──────────────────
// Dans le HTML (simulé) :
// <script src="https://cdn.example.com/jquery-1.11.1.min.js"></script>
// jQuery 1.11.1 — CVE-2015-9251, CVE-2019-11358, CVE-2020-11022
// Pas d'attribut integrity= → si le CDN est compromis, le JS l'est aussi

// ─── Faille 3 : Utilisation de fonctions PHP dépréciées/dangereuses ───────────────
function parseXml(string $data): \SimpleXMLElement {
    // XXE — XML External Entity injection
    // PHP < 8.0 : libxml_disable_entity_loader() non appelé par défaut
    return simplexml_load_string($data);
}

// mcrypt supprimé en PHP 7.2 — si encore présent = vieille version
function oldEncrypt(string $data): string {
    return mcrypt_encrypt(MCRYPT_RIJNDAEL_256, 'key', $data, MCRYPT_MODE_ECB);
}

// ─── Faille 4 : Autoloader Composer non verrouillé ───────────────────────────────
// composer.lock absent du repo → les dépendances peuvent se mettre à jour
// vers des versions malveillantes (supply chain)

// ─── Faille 5 : Pas de processus de veille CVE ────────────────────────────────────
// Aucun appel à : composer audit / npm audit / Dependabot / Snyk
// Pas de politique de mise à jour des dépendances documentée
