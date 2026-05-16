<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection OWASP A04:2021 Insecure Design
 * NE PAS déployer en production.
 */

$pdo = new PDO('mysql:host=localhost;dbname=app', 'root', 'root');

// ─── Faille 1 : Reset de mot de passe par question secrète ───────────────────────
// Le "nom de jeune fille de ta mère" est trouvable sur les réseaux sociaux
function resetPassword(PDO $pdo, string $email, string $secretAnswer): bool {
    $stmt = $pdo->prepare("SELECT * FROM users WHERE email = ? AND secret_answer = ?");
    $stmt->execute([$email, $secretAnswer]);
    return $stmt->fetch() !== false;
    // aucune limite de tentatives — brute-force possible
}

// ─── Faille 2 : Race condition sur solde bancaire ─────────────────────────────────
// Deux requêtes simultanées peuvent dépasser le plafond (double spend)
function withdraw(PDO $pdo, int $userId, float $amount): bool {
    $row = $pdo->query("SELECT balance FROM accounts WHERE user_id = $userId")->fetch();
    if ($row['balance'] >= $amount) {
        // Fenêtre de race entre le SELECT et l'UPDATE
        usleep(100); // simule latence — la faille existe même sans ce sleep
        $pdo->exec("UPDATE accounts SET balance = balance - $amount WHERE user_id = $userId");
        return true;
    }
    return false;
}

// ─── Faille 3 : Pas de rate limiting sur l'endpoint de login ─────────────────────
function login(PDO $pdo, string $email, string $password): bool {
    $stmt = $pdo->prepare("SELECT password_hash FROM users WHERE email = ?");
    $stmt->execute([$email]);
    $user = $stmt->fetch();
    return $user && password_verify($password, $user['password_hash']);
    // aucun compteur de tentatives — brute-force sans limite
}

// ─── Faille 4 : Coupon réutilisable à l'infini ───────────────────────────────────
function applyCoupon(PDO $pdo, string $code, int $userId): float {
    $stmt = $pdo->prepare("SELECT discount FROM coupons WHERE code = ? AND active = 1");
    $stmt->execute([$code]);
    $coupon = $stmt->fetch();
    // ne vérifie pas si l'utilisateur a déjà utilisé ce coupon
    return $coupon ? (float)$coupon['discount'] : 0.0;
}

// ─── Faille 5 : Workflow métier contournable — skip d'étape de validation ────────
// Le paiement peut être déclenché sans que la commande soit validée
function processPayment(PDO $pdo, int $orderId, float $amount): void {
    // ne vérifie pas que order.status = 'validated' avant de débiter
    $pdo->exec("INSERT INTO payments (order_id, amount) VALUES ($orderId, $amount)");
}
