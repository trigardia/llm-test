<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection OWASP A09:2021 Security Logging & Monitoring Failures
 * NE PAS déployer en production.
 */

$pdo = new PDO('mysql:host=localhost;dbname=app', 'root', 'root');

// ─── Faille 1 : Aucun log des échecs d'authentification ──────────────────────────
function login(string $email, string $password): bool {
    global $pdo;
    $stmt = $pdo->prepare("SELECT * FROM users WHERE email = ?");
    $stmt->execute([$email]);
    $user = $stmt->fetch();
    if (!$user || !password_verify($password, $user['password'])) {
        // échec silencieux — pas de log → impossible de détecter une attaque brute-force
        return false;
    }
    return true;
}

// ─── Faille 2 : Log des données sensibles ────────────────────────────────────────
function logRequest(array $data): void {
    // logge tout le tableau POST, incluant password, card_number, cvv, token
    error_log(json_encode($data)); // RGPD + PCI-DSS violation
    file_put_contents('/var/log/app/requests.log', print_r($data, true), FILE_APPEND);
}

// ─── Faille 3 : Logs stockés sans rotation et accessibles publiquement ────────────
// /var/log/app/ servi par nginx sans restriction → GET /log/requests.log
// Pas de logrotate configuré → disque plein possible (DoS indirect)

// ─── Faille 4 : Pas de log des actions privilégiées ──────────────────────────────
function deleteUser(PDO $pdo, int $userId): void {
    $pdo->exec("DELETE FROM users WHERE id = $userId");
    // aucun audit trail — impossible de savoir qui a supprimé quoi et quand
}

function changeRole(PDO $pdo, int $userId, string $newRole): void {
    $pdo->exec("UPDATE users SET role = '$newRole' WHERE id = $userId");
    // aucun log de changement de privilèges
}

// ─── Faille 5 : Pas d'alerte sur les erreurs critiques ───────────────────────────
function transferFunds(float $amount, int $from, int $to): void {
    try {
        // logique métier critique
    } catch (\Exception $e) {
        // l'exception est silencieusement ignorée
        // pas d'alerte PagerDuty/Slack/email
        // pas de log d'erreur
    }
}

// ─── Faille 6 : Log injection ────────────────────────────────────────────────────
function logUserAction(string $username, string $action): void {
    // si $username contient des retours à la ligne, l'attaquant peut forger des logs
    // Payload : "admin\n[2026-01-01] admin logged in as root"
    file_put_contents('/var/log/app/audit.log',
        date('Y-m-d H:i:s') . " $username performed $action\n",
        FILE_APPEND
    );
}
