<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection OWASP A05:2021 Security Misconfiguration
 * NE PAS déployer en production.
 */

// ─── Faille 1 : Affichage des erreurs activé en production ───────────────────────
ini_set('display_errors', '1');
ini_set('display_startup_errors', '1');
error_reporting(E_ALL);
// révèle les chemins, variables, structure DB dans les messages d'erreur

// ─── Faille 2 : phpinfo() exposé publiquement ─────────────────────────────────────
// GET /info.php → révèle config serveur complète, extensions, chemins, env vars
phpinfo();

// ─── Faille 3 : Credentials par défaut ───────────────────────────────────────────
$config = [
    'db_host'     => 'localhost',
    'db_user'     => 'root',
    'db_password' => '',           // mot de passe MySQL root vide
    'db_name'     => 'app',
    'redis_auth'  => null,         // Redis sans authentification
    'admin_pass'  => 'admin123',   // mot de passe admin en clair dans le code
];

// ─── Faille 4 : Headers de sécurité absents ──────────────────────────────────────
// Pas de : Content-Security-Policy, X-Frame-Options, X-Content-Type-Options,
//          Strict-Transport-Security, Permissions-Policy
header('Access-Control-Allow-Origin: *'); // CORS ouvert à tous

// ─── Faille 5 : Répertoire d'upload listé et exécutable ──────────────────────────
// /uploads/ accessible en lecture + PHP peut y être exécuté (pas de .htaccess dédié)
function uploadFile(array $file): string {
    $destination = '/var/www/html/uploads/' . $file['name']; // nom non sanitisé
    move_uploaded_file($file['tmp_name'], $destination);
    return $destination;
    // un attaquant upload shell.php et l'exécute via GET /uploads/shell.php
}

// ─── Faille 6 : Clés d'API dans le code source ────────────────────────────────────
define('STRIPE_SECRET',    'sk_live_XXXXXXXXXXXXXXXXXXXX');
define('SENDGRID_API_KEY', 'SG.XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX');
define('AWS_SECRET',       'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY');
// Ces constantes seront commitées dans git → exposition définitive

// ─── Faille 7 : Session sans configuration sécurisée ────────────────────────────
session_start();
// pas de session.cookie_secure, session.cookie_httponly, session.use_strict_mode
// timeout de session non défini → session éternelle
