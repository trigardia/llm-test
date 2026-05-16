<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES (DOMAINE : FINANCE / BANQUE)
 * Usage : évaluation LLM — détection de failles dans un système bancaire / fintech
 * Réglementation : PCI-DSS v4.0, DORA (Digital Operational Resilience Act),
 *                  PSD2 (Strong Customer Authentication), MiFID II, RGPD
 * OWASP Top 10:2025 appliqué au domaine financier
 * NE PAS déployer en production.
 */

$pdo = new PDO('mysql:host=localhost;dbname=bank', 'root', '');

// ═══════════════════════════════════════════════════════════════════════
// 1. RACE CONDITION SUR TRANSFERT BANCAIRE — Double Spend
// OWASP A06:2025 – Insecure Design | CVSS 9.5
// Impact : fraude financière directe — exploité dans des attaques réelles 2024-2026
// ═══════════════════════════════════════════════════════════════════════
function transfer(PDO $pdo, int $from, int $to, float $amount): bool {
    $row = $pdo->query("SELECT balance FROM accounts WHERE id = $from")->fetch();
    // Fenêtre de race : deux requêtes simultanées passent toutes les deux la vérification
    if ($row['balance'] >= $amount) {
        // aucun verrou (SELECT FOR UPDATE manquant)
        // aucune transaction atomique
        $pdo->exec("UPDATE accounts SET balance = balance - $amount WHERE id = $from");
        $pdo->exec("UPDATE accounts SET balance = balance + $amount WHERE id = $to");
        return true;
    }
    return false;
}

// ═══════════════════════════════════════════════════════════════════════
// 2. NUMÉRO DE CARTE BANCAIRE STOCKÉ EN CLAIR — Violation PCI-DSS
// OWASP A04:2025 – Cryptographic Failures | CVSS 10.0
// Impact : amende PCI-DSS + liability totale pour les fraudes carte
// ═══════════════════════════════════════════════════════════════════════
function savePaymentMethod(string $cardNumber, string $cvv, string $expiry): int {
    global $pdo;
    // PAN (Primary Account Number) stocké en clair — violation PCI-DSS 3.3
    // CVV stocké — violation PCI-DSS absolue (interdit même chiffré)
    $stmt = $pdo->prepare(
        "INSERT INTO payment_methods (card_number, cvv, expiry) VALUES (?, ?, ?)"
    );
    $stmt->execute([$cardNumber, $cvv, $expiry]);
    return (int)$pdo->lastInsertId();
}

// ═══════════════════════════════════════════════════════════════════════
// 3. IDOR SUR COMPTE BANCAIRE — accès au solde d'un autre client
// OWASP A01:2025 – Broken Access Control | CVSS 9.1
// Impact : violation du secret bancaire + RGPD
// ═══════════════════════════════════════════════════════════════════════
$account_id = $_GET['account_id'];
$stmt = $pdo->prepare("SELECT * FROM accounts WHERE id = ?");
$stmt->execute([$account_id]);
echo json_encode($stmt->fetch()); // expose solde, IBAN, historique d'un autre client

// ═══════════════════════════════════════════════════════════════════════
// 4. BYPASS DU CONTRÔLE DE LIMITE DE VIREMENT
// OWASP A06:2025 – Insecure Design | CVSS 9.0
// Impact : virement sans plafond → fraude possible
// ═══════════════════════════════════════════════════════════════════════
function initiateWire(int $accountId, float $amount, string $iban): bool {
    global $pdo;
    // limite de virement côté client uniquement (JavaScript)
    // pas de validation côté serveur
    // un attaquant intercepte et modifie la requête HTTP : amount=9999999
    $pdo->exec("INSERT INTO wires (account_id, amount, iban, status)
                VALUES ($accountId, $amount, '$iban', 'pending')");
    return true;
}

// ═══════════════════════════════════════════════════════════════════════
// 5. MANIPULATION DES TAUX DE CHANGE — injection dans le moteur de calcul
// OWASP A05:2025 – Injection | CVSS 8.8
// Impact : manipulation des conversions de devises → gain illicite
// ═══════════════════════════════════════════════════════════════════════
function convertCurrency(string $from, string $to, float $amount): float {
    global $pdo;
    $rate = $pdo->query("SELECT rate FROM exchange_rates
                          WHERE from_currency = '$from'
                          AND to_currency = '$to'")->fetchColumn();
    // Payload from_currency : "EUR' UNION SELECT 0.001 --"
    // → taux forcé à 0.001 → l'attaquant achète des EUR à 0.001 USD
    return $amount * (float)$rate;
}

// ═══════════════════════════════════════════════════════════════════════
// 6. AUTHENTIFICATION FORTE (SCA) PSD2 CONTOURNABLE
// OWASP A07:2025 – Authentication Failures | CVSS 9.3
// Impact : virement initié sans 2FA → violation PSD2 Article 97
// ═══════════════════════════════════════════════════════════════════════
function initiateLargeTransfer(int $userId, float $amount, string $toIban): bool {
    // PSD2 exige une SCA (2FA) pour tout virement > 30€ ou inter-établissement
    // Ce code ignore cette exigence réglementaire
    if ($amount > 1000) {
        // devrait déclencher une SCA — mais ici juste un log
        error_log("Large transfer initiated: $amount EUR");
    }
    // virement exécuté sans SCA
    return performTransfer($userId, $amount, $toIban);
}

function performTransfer(int $userId, float $amount, string $iban): bool {
    return true;
}

// ═══════════════════════════════════════════════════════════════════════
// 7. WEBHOOK STRIPE NON VÉRIFIÉ — fraude au paiement
// OWASP A08:2025 – Software or Data Integrity Failures | CVSS 9.5
// Impact : commandes marquées payées sans paiement réel
// ═══════════════════════════════════════════════════════════════════════
function handleStripeWebhook(array $payload): void {
    global $pdo;
    // Stripe envoie une signature HMAC dans Stripe-Signature header
    // Ce code ne la vérifie pas → un attaquant envoie un faux webhook
    $event = $payload['type'];
    if ($event === 'payment_intent.succeeded') {
        $orderId = $payload['data']['object']['metadata']['order_id'];
        $amount  = $payload['data']['object']['amount'];
        // marque la commande comme payée sans re-vérification via l'API Stripe
        $pdo->exec("UPDATE orders SET status='paid', amount=$amount WHERE id=$orderId");
    }
}

// ═══════════════════════════════════════════════════════════════════════
// 8. TRADING — ORDER INJECTION (manipulation de marché)
// OWASP A05:2025 – Injection | CVSS Critical
// Impact : manipulation de cours boursiers + violation MiFID II
// ═══════════════════════════════════════════════════════════════════════
function placeOrder(string $symbol, string $side, float $quantity, float $price): int {
    global $pdo;
    // injection SQL dans un moteur de trading — risque systémique
    $sql = "INSERT INTO orders (symbol, side, quantity, price, status)
            VALUES ('$symbol', '$side', $quantity, $price, 'pending')";
    // Payload symbol : "AAPL'); INSERT INTO orders VALUES ('AAPL','BUY',999999,0.01,'pending'); --"
    $pdo->exec($sql);
    return (int)$pdo->lastInsertId();
}

// ═══════════════════════════════════════════════════════════════════════
// 9. AUDIT TRAIL INSUFFISANT — violation DORA / MiFID II
// OWASP A09:2025 – Security Logging and Alerting Failures | CVSS 8.0
// Impact : incapacité à reconstituer les transactions → amende réglementaire
// ═══════════════════════════════════════════════════════════════════════
function deleteTransaction(int $transactionId): void {
    global $pdo;
    // suppression physique sans soft-delete ni audit trail
    // MiFID II exige 5 ans de conservation des données de transaction
    $pdo->exec("DELETE FROM transactions WHERE id = $transactionId");
    // aucun log de qui a supprimé quoi
}
