<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection OWASP A10:2021 Server-Side Request Forgery (SSRF)
 * NE PAS déployer en production.
 */

// ─── Faille 1 : SSRF basique — URL contrôlée par l'utilisateur ───────────────────
// Payloads :
//   http://169.254.169.254/latest/meta-data/iam/security-credentials/ (AWS metadata)
//   http://localhost:6379/             (Redis sans auth)
//   http://internal-admin.corp/        (réseau interne)
//   file:///etc/passwd                 (lecture de fichier local)
function fetchUrl(string $url): string {
    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true); // suit les redirections
    $result = curl_exec($ch);
    curl_close($ch);
    return $result;
}
echo fetchUrl($_GET['url']);

// ─── Faille 2 : SSRF via import d'image/document ─────────────────────────────────
function importFromUrl(string $imageUrl): string {
    // permet d'importer une image depuis une URL externe
    // sans validation de l'hôte → SSRF vers réseau interne
    $data = file_get_contents($imageUrl);
    $filename = '/var/www/html/uploads/' . basename($imageUrl);
    file_put_contents($filename, $data);
    return $filename;
}

// ─── Faille 3 : SSRF via Webhook ─────────────────────────────────────────────────
function registerWebhook(string $callbackUrl, string $event): void {
    global $pdo;
    // stocke et utilisera cette URL pour envoyer des notifications
    // aucune validation — l'attaquant pointe vers http://localhost:9200 (Elasticsearch)
    $pdo->exec("INSERT INTO webhooks (url, event) VALUES ('$callbackUrl', '$event')");
}

function triggerWebhook(string $callbackUrl, array $payload): void {
    $ch = curl_init($callbackUrl);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
    curl_exec($ch); // émet une requête POST vers l'URL choisie par l'attaquant
}

// ─── Faille 4 : SSRF via parsing XML (XXE → SSRF) ────────────────────────────────
// Payload XML :
// <?xml version="1.0"?>
// <!DOCTYPE foo [<!ENTITY xxe SYSTEM "http://169.254.169.254/latest/meta-data/">]>
// <root>&xxe;</root>
function parseUserXml(string $xmlData): \SimpleXMLElement {
    // libxml_disable_entity_loader(true) non appelé → XXE + SSRF
    return simplexml_load_string($xmlData, 'SimpleXMLElement', LIBXML_NOENT);
}

// ─── Faille 5 : SSRF via PDF/screenshot generator ───────────────────────────────
function generatePdf(string $htmlUrl): string {
    // Wkhtmltopdf ou Puppeteer rendent l'URL passée
    // l'attaquant passe http://internal-app/admin pour capturer la page interne
    $output = '/tmp/out_' . uniqid() . '.pdf';
    exec("wkhtmltopdf $htmlUrl $output"); // injection de commande + SSRF en prime
    return $output;
}
