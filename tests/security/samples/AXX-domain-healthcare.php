<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES (DOMAINE : SANTÉ)
 * Usage : évaluation LLM — détection de failles dans un SIH (Système d'Information Hospitalier)
 * Réglementation : RGPD, HDS (Hébergement Données de Santé), HIPAA, HL7 FHIR
 * OWASP Top 10:2025 appliqué au domaine médical
 * NE PAS déployer en production.
 */

$pdo = new PDO('mysql:host=localhost;dbname=hospital', 'root', '');

// ═══════════════════════════════════════════════════════════════════════
// 1. IDOR sur dossier médical — accès inter-patient (DMP)
// OWASP A01:2025 – Broken Access Control | CVSS 9.1
// Impact : violation RGPD Article 9 — données de santé catégorie spéciale
// ═══════════════════════════════════════════════════════════════════════
// Un patient change patient_id=42 → lit le dossier médical d'un autre patient
$patient_id = $_GET['patient_id'];
$stmt = $pdo->prepare("SELECT * FROM dossiers_medicaux WHERE patient_id = ?");
$stmt->execute([$patient_id]);
$dossier = $stmt->fetch();
echo json_encode($dossier); // expose diagnostics, ordonnances, antécédents, numéro SS

// ═══════════════════════════════════════════════════════════════════════
// 2. SQL INJECTION sur recherche de médicaments
// OWASP A05:2025 – Injection | CVSS 9.8
// Impact : manipulation des stocks de médicaments → risque vital
// ═══════════════════════════════════════════════════════════════════════
$drug_name = $_GET['drug'];
$result = $pdo->query("SELECT * FROM medicaments WHERE nom LIKE '%$drug_name%'");
// Payload : %'; UPDATE medicaments SET stock=0 WHERE id=1; --
// Peut vider les stocks de médicaments critiques

// ═══════════════════════════════════════════════════════════════════════
// 3. Ordonnance électronique modifiable (falsification)
// OWASP A08:2025 – Software or Data Integrity Failures | CVSS 9.5
// Impact : fraude aux médicaments contrôlés, overdose possible
// ═══════════════════════════════════════════════════════════════════════
function updateOrdonnance(int $id, array $data): void {
    global $pdo;
    // aucune vérification que l'appelant est médecin signataire
    // aucune signature numérique de l'ordonnance
    $pdo->exec("UPDATE ordonnances SET medicament='{$data['med']}',
                dose='{$data['dose']}' WHERE id=$id");
    // un patient peut modifier sa propre ordonnance pour augmenter les doses
}

// ═══════════════════════════════════════════════════════════════════════
// 4. Données de santé stockées non chiffrées
// OWASP A04:2025 – Cryptographic Failures | CVSS 8.7
// Impact : violation HDS + RGPD → amende CNIL jusqu'à 4% CA mondial
// ═══════════════════════════════════════════════════════════════════════
function backupPatientData(PDO $pdo): void {
    $patients = $pdo->query("SELECT * FROM patients")->fetchAll();
    // backup en clair : nom, prénom, numéro SS, diagnostics, traitements
    file_put_contents('/tmp/backup_patients_' . date('Y-m-d') . '.json',
        json_encode($patients));
    // /tmp non chiffré, accessible à tous les processus
}

// ═══════════════════════════════════════════════════════════════════════
// 5. Dispositif médical connecté — API sans authentification
// OWASP A07:2025 – Authentication Failures | CVSS 10.0
// CVE pattern : pompes à insuline, moniteurs cardiaques, IRM connectés
// Impact : manipulation à distance d'un dispositif médical → risque létal
// ═══════════════════════════════════════════════════════════════════════
function setInsulinDose(int $device_id, float $units): bool {
    // API REST de la pompe à insuline
    // aucune authentification, aucun chiffrement, aucune validation des doses
    $ch = curl_init("http://device-gateway.hospital.local/pumps/$device_id/dose");
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode(['units' => $units]));
    // dose = 999.9 unités = overdose mortelle
    curl_exec($ch);
    return true;
}

// ═══════════════════════════════════════════════════════════════════════
// 6. Numéro de sécurité sociale logué en clair
// OWASP A09:2025 – Security Logging and Alerting Failures | CVSS 7.5
// Impact : violation RGPD + potentiel usurpation d'identité
// ═══════════════════════════════════════════════════════════════════════
function logPatientAccess(string $nss, string $action): void {
    // NSS (13 chiffres) loggé en clair dans les logs applicatifs
    error_log("[$action] Patient NSS: $nss accessed at " . date('Y-m-d H:i:s'));
    file_put_contents('/var/log/hospital/access.log',
        date('Y-m-d H:i:s') . " NSS=$nss ACTION=$action\n", FILE_APPEND);
}

// ═══════════════════════════════════════════════════════════════════════
// 7. HL7 FHIR — injection via XML/JSON non validé
// OWASP A05:2025 – Injection | CVSS 8.5
// Impact : corruption de données cliniques entre établissements
// ═══════════════════════════════════════════════════════════════════════
function processFhirResource(string $rawJson): array {
    $resource = json_decode($rawJson, true);
    // aucune validation du schéma FHIR
    // aucune vérification des types de ressources autorisées
    // permet d'injecter des ressources Medication avec des doses arbitraires
    $pdo = new PDO('mysql:host=localhost;dbname=hospital', 'root', '');
    $pdo->exec("INSERT INTO fhir_resources (data) VALUES ('" . json_encode($resource) . "')");
    return $resource;
}

// ═══════════════════════════════════════════════════════════════════════
// 8. Manque de contrôle d'accès basé sur les rôles médicaux
// OWASP A01:2025 – Broken Access Control | CVSS 9.0
// Impact : infirmier peut prescrire, externe peut accéder à des données psychiatriques
// ═══════════════════════════════════════════════════════════════════════
function getPsychiatricRecord(int $patient_id): array {
    global $pdo;
    // les dossiers psychiatriques nécessitent une habilitation spéciale
    // mais aucune vérification de rôle ici
    $stmt = $pdo->prepare("SELECT * FROM dossiers_psychiatriques WHERE patient_id = ?");
    $stmt->execute([$patient_id]);
    return $stmt->fetchAll();
}
