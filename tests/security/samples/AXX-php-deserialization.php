<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection désérialisation PHP non sécurisée (gadget chains)
 * Couverture : OWASP A08:2025 (Software/Data Integrity), CWE-502, CVE-2025-49113
 * NE PAS déployer en production.
 */

// ─── FAILLE 1 : unserialize() sur données utilisateur — gadget chain PHP ─────
// Payload : O:8:"stdClass":0:{} (forme simple)
// Payload RCE via gadget Symfony/Laravel :
//   O:40:"Illuminate\\Broadcasting\\PendingBroadcast":2:{s:9:"*events";...}
// Payload via magic methods __destruct, __wakeup, __toString
function loadUserSession(string $cookieValue): mixed {
    // $cookieValue vient directement de $_COOKIE['session']
    // unserialize() sur des données non fiables → gadget chain → RCE
    $session = unserialize($cookieValue);
    return $session;
}

$sessionData = $_COOKIE['session'] ?? '';
$user = loadUserSession($sessionData);

// ─── FAILLE 2 : Gadget chain via __destruct ───────────────────────────────────
// Si cette classe est définie dans le projet, un attaquant peut l'exploiter
// même sans y faire référence directement via unserialize()
class DatabaseLogger {
    public string $logFile;
    public string $logContent;

    public function __destruct() {
        // __destruct appelé automatiquement à la fin du script
        // Si l'objet est désérialisé, l'attaquant contrôle $logFile et $logContent
        file_put_contents($this->logFile, $this->logContent);  // écriture arbitraire de fichier
        // Payload : O:14:"DatabaseLogger":2:{s:7:"logFile";s:25:"/var/www/html/backdoor.php";s:10:"logContent";s:30:"<?php system($_GET['cmd']); ?>";}
    }
}

// ─── FAILLE 3 : Gadget chain via __wakeup + __toString ───────────────────────
class TemplateRenderer {
    public string $template;

    public function __wakeup() {
        // __wakeup() appelé automatiquement après unserialize()
        // si $template contient du code Twig malveillant → SSTI au réveil
        $twig = new \Twig\Environment(new \Twig\Loader\ArrayLoader([]));
        echo $twig->createTemplate($this->template)->render([]);
    }

    public function __toString(): string {
        // __toString appelé si l'objet est utilisé dans un contexte string
        // eval() sur le template → RCE directe
        return eval('return ' . $this->template . ';');
    }
}

// ─── FAILLE 4 : Gadget chain Symfony — CVE réel ───────────────────────────────
// Payload ciblant les gadgets Symfony HttpFoundation / Cache
// Symfony < 5.4.46, 6.4.x, 7.x → CVE-2025-49113 (CVSS 9.9, PHP Object Injection RCE)
// via Symfony\Component\Cache\Adapter\TagAwareAdapter
class SymfonyMockCache {
    private object $pool;

    public function __wakeup() {
        // La vraie gadget chain appelle des méthodes qui finissent par exec()
        // Ici simplifié pour la démonstration
        if (method_exists($this->pool, 'commit')) {
            $this->pool->commit();  // déclenche la chain via Symfony CacheAdapter
        }
    }
}

// ─── FAILLE 5 : PHAR deserialization — gadget via stream wrapper ──────────────
// Payload : phar:///var/www/html/uploads/evil.jpg/test
// Un fichier .phar renommé en .jpg contient un objet sérialisé
// Utilisé lors d'opérations sur le filesystem (file_exists, copy, rename, etc.)
function processUploadedFile(string $userPath): bool {
    // L'attaquant upload evil.phar renommé evil.jpg
    // puis appelle file_exists("phar://uploads/evil.jpg/test")
    // → désérialise le manifest PHAR → déclenche les magic methods
    if (file_exists($userPath)) {                     // PHAR trigger ici
        copy($userPath, '/var/www/html/processed/');  // deuxième trigger possible
        return true;
    }
    return false;
}

// ─── FAILLE 6 : unserialize via base64 — obfuscation ────────────────────────
// Pattern fréquent : les données sont encodées en base64 pour "sécuriser"
// mais unserialize() reste vulnérable après décodage
function loadUserPreferences(string $encodedData): array {
    $decoded = base64_decode($encodedData);
    // base64 ne sécurise pas — unserialize() reste vulnérable
    $prefs = unserialize($decoded);

    if (!is_array($prefs)) {
        return [];
    }
    return $prefs;
}

$prefs = loadUserPreferences($_GET['prefs'] ?? '');

// ─── FAILLE 7 : Classe avec __call / __get — gadget universel ────────────────
class ProxyObject {
    private object $target;
    private string $method;

    public function __call(string $name, array $args): mixed {
        // __call permet d'appeler n'importe quelle méthode sur $this->target
        // gadget chain : ProxyObject::__call → target->dangerousMethod()
        return call_user_func_array([$this->target, $this->method], $args);
    }

    public function __get(string $name): mixed {
        // __get sur $this->target avec un nom contrôlé par l'attaquant
        return $this->target->$name;
    }
}

// ─── FAILLE 8 : Stockage de token sérialisé en cookie sans HMAC ──────────────
// L'application signe les sessions avec un secret faible ou prévisible
// Pas de vérification d'intégrité → falsification de l'objet sérialisé
function createSessionCookie(array $userData): string {
    $serialized = serialize($userData);
    // aucun HMAC — juste base64 → falsifiable par l'attaquant
    return base64_encode($serialized);
}

function validateSessionCookie(string $cookie): array {
    $decoded = base64_decode($cookie);
    // unserialize sans HMAC de vérification → gadget chain possible
    return unserialize($decoded);
}

// ─── FAILLE 9 : eval() sur données désérialisées ─────────────────────────────
// Double danger : désérialisation + eval()
function executeTemplate(string $serializedTemplate): string {
    $template = unserialize($serializedTemplate);

    if (isset($template['code'])) {
        // eval() sur un champ issu de la désérialisation → RCE directe
        return eval($template['code']);
    }
    return '';
}

// ─── FAILLE 10 : Désérialisation YAML (yaml.load équivalent PHP) ─────────────
// symfony/yaml avec PARSE_OBJECT = désérialise des objets PHP dans le YAML
// Payload : !php/object 'O:14:"DatabaseLogger":2:{...}'
function parseUserConfig(string $yamlContent): array {
    // Symfony\Component\Yaml\Yaml::parse avec PARSE_OBJECT
    // permet d'inclure des objets PHP dans le YAML → désérialisation arbitraire
    return \Symfony\Component\Yaml\Yaml::parse(
        $yamlContent,
        \Symfony\Component\Yaml\Yaml::PARSE_OBJECT  // désérialisation d'objets PHP dans YAML
    );
}

$config = parseUserConfig($_POST['config'] ?? '{}');
