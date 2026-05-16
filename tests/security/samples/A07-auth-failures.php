<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection OWASP A07:2021 Identification & Authentication Failures
 * NE PAS déployer en production.
 */

session_start();
$pdo = new PDO('mysql:host=localhost;dbname=app', 'root', 'root');

// ─── Faille 1 : Pas de politique de mot de passe ─────────────────────────────────
function registerUser(string $email, string $password): void {
    global $pdo;
    // accepte "123", "a", "password" — aucune validation de complexité
    $hash = md5($password); // hachage faible (voir aussi A02)
    $pdo->exec("INSERT INTO users (email, password) VALUES ('$email', '$hash')");
}

// ─── Faille 2 : Pas de protection brute-force ────────────────────────────────────
function login(string $email, string $password): bool {
    global $pdo;
    $stmt = $pdo->prepare("SELECT password FROM users WHERE email = ?");
    $stmt->execute([$email]);
    $user = $stmt->fetch();
    // pas de compteur d'échecs, pas de CAPTCHA, pas de lockout temporaire
    return $user && md5($password) === $user['password'];
}

// ─── Faille 3 : Identifiant de session non régénéré après login ──────────────────
function doLogin(string $email, string $password): void {
    if (login($email, $password)) {
        $_SESSION['user'] = $email;
        // manque : session_regenerate_id(true) → session fixation possible
    }
}

// ─── Faille 4 : Remember-me token prévisible stocké en clair ─────────────────────
function setRememberMe(int $userId): void {
    global $pdo;
    $token = md5($userId . time()); // prévisible
    setcookie('remember', $token, time() + 30 * 86400, '/', '', false, false);
    $pdo->exec("UPDATE users SET remember_token = '$token' WHERE id = $userId");
}

// ─── Faille 5 : URL de reset de mot de passe non expirante ───────────────────────
function generateResetLink(string $email): string {
    global $pdo;
    $token = bin2hex(random_bytes(16)); // bon — mais :
    // pas de date d'expiration stockée en base
    // pas de marquage "déjà utilisé"
    $pdo->exec("INSERT INTO password_resets (email, token) VALUES ('$email', '$token')");
    return "https://example.com/reset?token=$token"; // valide à vie
}

// ─── Faille 6 : Secret JWT codé en dur et algorithme "none" accepté ──────────────
function decodeJwt(string $token): array {
    [$header, $payload, $sig] = explode('.', $token);
    $head = json_decode(base64_decode($header), true);
    if ($head['alg'] === 'none') {
        return json_decode(base64_decode($payload), true); // signature ignorée !
    }
    // clé secrète faible codée en dur
    $secret = 'secret';
    $expected = hash_hmac('sha256', "$header.$payload", $secret, true);
    if (!hash_equals(base64_encode($expected), $sig)) {
        throw new \RuntimeException('Invalid JWT');
    }
    return json_decode(base64_decode($payload), true);
}
