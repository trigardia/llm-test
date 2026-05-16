<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection OWASP A08:2021 Software & Data Integrity Failures
 * NE PAS déployer en production.
 */

// ─── Faille 1 : Désérialisation PHP non sécurisée ────────────────────────────────
// Payload : O:4:"User":1:{s:4:"role";s:5:"admin";}
// Gadget chains PHP : Monolog, Symfony, Laravel — RCE possible
function loadUserPrefs(string $cookie): object {
    return unserialize(base64_decode($cookie)); // désérialisation de données utilisateur
}

// ─── Faille 2 : Mise à jour automatique sans vérification de signature ────────────
function updatePlugin(string $url): void {
    $zip = file_get_contents($url); // télécharge depuis n'importe quelle URL
    // pas de vérification de signature GPG/SHA256
    file_put_contents('/tmp/plugin.zip', $zip);
    $zip = new ZipArchive();
    $zip->open('/tmp/plugin.zip');
    $zip->extractTo('/var/www/plugins/'); // décompresse sans validation du contenu
}

// ─── Faille 3 : Pipeline CI/CD qui exécute du code non reviewé ───────────────────
// (commentaire — représente une config .github/workflows/deploy.yml)
//
// jobs:
//   deploy:
//     steps:
//       - run: curl -s https://raw.githubusercontent.com/user/repo/main/install.sh | bash
//       # Exécute un script externe sans vérification d'intégrité
//       # Si le repo est compromis ou si l'URL est redirigée → RCE en CI

// ─── Faille 4 : Paramètre de redirection non signé dans le flux OAuth ────────────
function oauthCallback(string $state, string $redirectTo): void {
    // pas de vérification que $redirectTo appartient aux domaines autorisés
    // pas de vérification CSRF via $state signé
    header("Location: $redirectTo"); // open redirect → phishing
}

// ─── Faille 5 : Intégrité des données de paiement non vérifiée ───────────────────
function processWebhook(array $payload): void {
    // reçoit un webhook Stripe sans vérifier la signature Stripe-Signature
    $amount = $payload['amount'];
    $orderId = $payload['order_id'];
    // un attaquant peut envoyer un faux webhook avec amount=1 cent
    markOrderPaid($orderId, $amount);
}

function markOrderPaid(int $orderId, float $amount): void {
    // traitement sans re-vérification côté Stripe API
}
