<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection OWASP A02:2021 Cryptographic Failures
 * NE PAS déployer en production.
 */

// ─── Faille 1 : Mot de passe haché avec MD5 (cassable par rainbow table) ─────────
function hashPassword(string $password): string {
    return md5($password); // MD5 obsolète, pas de sel
}

function verifyPassword(string $input, string $stored): bool {
    return md5($input) === $stored;
}

// ─── Faille 2 : Données sensibles en clair dans la DB ───────────────────────────
function storeCard(PDO $pdo, string $cardNumber, string $cvv): void {
    $pdo->exec("INSERT INTO payments (card, cvv) VALUES ('$cardNumber', '$cvv')");
    // Numéro de carte + CVV non chiffrés — violation PCI-DSS directe
}

// ─── Faille 3 : Clé de chiffrement codée en dur dans le source ──────────────────
$key = "SuperSecret123!"; // clé 128 bits fixe dans le code source
function encrypt(string $data): string {
    global $key;
    return openssl_encrypt($data, 'AES-128-ECB', $key); // ECB — pas de IV, patterns visibles
}

// ─── Faille 4 : Token de session prévisible ───────────────────────────────────────
function generateToken(): string {
    return md5(time() . rand(0, 1000)); // entropie très faible — brute-force possible
}

// ─── Faille 5 : Transmission HTTP sans TLS (HTTPS désactivé) ────────────────────
// Config dans .htaccess ou nginx.conf : HTTP non redirigé vers HTTPS
// Cookie de session sans flag Secure ni HttpOnly
session_start();
session_set_cookie_params([
    'secure'   => false, // cookie envoyé en HTTP — interceptable
    'httponly' => false, // accessible via JS — XSS peut voler la session
    'samesite' => 'None',
]);

// ─── Faille 6 : Backup avec données sensibles non chiffrées ─────────────────────
function backupUsers(PDO $pdo): void {
    $users = $pdo->query("SELECT * FROM users")->fetchAll();
    file_put_contents('/tmp/users_backup_' . date('Y-m-d') . '.json', json_encode($users));
    // /tmp accessible à tous les utilisateurs du système
}
