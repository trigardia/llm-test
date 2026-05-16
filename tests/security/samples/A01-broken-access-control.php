<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection OWASP A01:2021 Broken Access Control
 * NE PAS déployer en production.
 */

// ─── Faille 1 : IDOR — accès direct à un objet sans vérification d'autorisation ───
// L'utilisateur peut modifier ?user_id=42 pour accéder au profil d'un autre
$user_id = $_GET['user_id'];
$pdo = new PDO('mysql:host=localhost;dbname=app', 'root', 'root');
$stmt = $pdo->prepare("SELECT * FROM users WHERE id = ?");
$stmt->execute([$user_id]);
$user = $stmt->fetch();
echo json_encode($user); // expose tous les champs, y compris password_hash, phone, ssn

// ─── Faille 2 : Path traversal — lecture de fichier arbitraire ───────────────────
$filename = $_GET['file'];
$content  = file_get_contents('/var/www/uploads/' . $filename);
// ../../../etc/passwd fonctionne

// ─── Faille 3 : Élévation de privilège — rôle modifiable côté client ─────────────
session_start();
$_SESSION['role'] = $_POST['role']; // l'utilisateur envoie role=admin

// ─── Faille 4 : Endpoint admin sans vérification de session ──────────────────────
// Route /admin/delete accessible à tous si on connaît l'URL
function deleteUser(int $id): void {
    global $pdo;
    // aucune vérification que l'appelant est admin
    $pdo->exec("DELETE FROM users WHERE id = $id");
}
if (isset($_GET['delete'])) {
    deleteUser((int)$_GET['delete']);
}

// ─── Faille 5 : Forced browsing — fichier de config exposé ───────────────────────
// Accessible via GET /config.php?show=1
if ($_GET['show'] ?? false) {
    include __DIR__ . '/../config/database.php'; // credentials DB en clair
}
