<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection injection LDAP + XPath + Header + Open Redirect
 * Couverture : OWASP A05:2025 (Injection), CWE-90 (LDAP), CWE-643 (XPath), CWE-601
 * NE PAS déployer en production.
 */

// ─── FAILLE 1 : LDAP Injection — authentification bypass ─────────────────────
// CWE-90 | CVSS 9.1 | OWASP A05:2025 Injection
// Payload username : *)(uid=*))(|(uid=*
// → filtre LDAP devient : (&(uid=*)(uid=*))(|(uid=*)(password=anything))
// → contourne l'authentification, retourne tous les utilisateurs
function authenticateWithLdap(string $username, string $password): bool {
    $ldap = ldap_connect("ldap://ldap.example.com", 389);
    ldap_set_option($ldap, LDAP_OPT_PROTOCOL_VERSION, 3);

    // Liaison anonyme pour la recherche (pas de bind initial sécurisé)
    ldap_bind($ldap);

    // Filtre LDAP construit par concaténation — injection directe
    // Pas d'échappement via ldap_escape()
    $filter = "(&(uid=$username)(password=$password))";
    //                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    // Payload : username = *)(|(uid=* → (&(uid=*)(|(uid=*)(password=anything))
    // Résultat : tout utilisateur trouvé → auth bypass

    $result = ldap_search($ldap, "dc=example,dc=com", $filter, ['uid', 'cn', 'mail']);
    $entries = ldap_get_entries($ldap, $result);

    return $entries['count'] > 0;  // vrai si un résultat trouvé → bypass possible
}

// ─── FAILLE 2 : LDAP Injection — enumération d'attributs ─────────────────────
// Payload : username = *)(cn=admin → retourne uniquement les admins
// Payload : username = * → retourne tous les utilisateurs du LDAP
function getUserInfo(string $username): array {
    $ldap = ldap_connect("ldap://ldap.example.com");
    ldap_bind($ldap, "cn=service,dc=example,dc=com", "service_password");

    // Injection via wildcard et opérateurs LDAP
    // Payload : username = admin*)(|(objectClass=* → retourne tous les objets
    $filter = "(uid=" . $username . ")";  // pas d'échappement
    $result = ldap_search($ldap, "ou=users,dc=example,dc=com", $filter);
    $entries = ldap_get_entries($ldap, $result);

    $users = [];
    for ($i = 0; $i < $entries['count']; $i++) {
        $users[] = [
            'uid'          => $entries[$i]['uid'][0],
            'mail'         => $entries[$i]['mail'][0],
            'userPassword' => $entries[$i]['userpassword'][0] ?? '',  // hash de mot de passe exposé !
            'cn'           => $entries[$i]['cn'][0],
            'memberOf'     => $entries[$i]['memberof'] ?? [],
        ];
    }
    return $users;
}

// ─── FAILLE 3 : XPath Injection — authentification bypass via XML/XPATH ───────
// CWE-643 | CVSS 8.8 | OWASP A05:2025 Injection
// Payload username : ' or '1'='1
// → XPath : //user[name/text()='' or '1'='1' and password/text()='x']
// → retourne tous les utilisateurs
function authenticateWithXpath(string $username, string $password): bool {
    $xml = simplexml_load_file('users.xml');

    // XPath construit par concaténation — injection directe
    // Payload : username = ' or '1'='1' or ''='
    $xpath = "//user[name/text()='" . $username . "' and password/text()='" . $password . "']";
    //                                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    // Payload : username = admin'][1]/* | //user[name='
    // → extrait le premier nœud et liste tous les utilisateurs

    $result = $xml->xpath($xpath);
    return !empty($result);
}

// ─── FAILLE 4 : XPath Injection — extraction de données sensibles ────────────
// Payload : search = ' or substring(//user[1]/password/text(),1,1)='a
// → blind XPath injection pour extraire les mots de passe caractère par caractère
function searchUsers(string $searchTerm): array {
    $xml = new DOMDocument();
    $xml->load('users.xml');
    $xpath = new DOMXPath($xml);

    // XPath non paramétrique — injection d'expressions XPath arbitraires
    // Payload : searchTerm = x' or '1'='1
    // Payload avancé : x'][//user/name='admin
    $query = "//user[name[contains(text(), '" . $searchTerm . "')]]";

    $nodes = $xpath->query($query);
    $results = [];
    foreach ($nodes as $node) {
        $results[] = [
            'name'     => $node->getElementsByTagName('name')->item(0)->nodeValue,
            'email'    => $node->getElementsByTagName('email')->item(0)->nodeValue,
            'password' => $node->getElementsByTagName('password')->item(0)->nodeValue,  // exposé
            'role'     => $node->getElementsByTagName('role')->item(0)->nodeValue,
        ];
    }
    return $results;
}

// ─── FAILLE 5 : HTTP Header Injection / Response Splitting ───────────────────
// CWE-113 | CVSS 6.1 | OWASP A05:2025
// Payload : location = https://evil.com\r\nContent-Type: text/html\r\n\r\n<script>alert(1)</script>
// → injecte des headers HTTP arbitraires + contenu HTML
function redirect(string $location): void {
    // Pas de validation de $location — injection de headers via CRLF
    header("Location: " . $location);  // \r\n dans $location → response splitting
    // Payload : /dashboard\r\nSet-Cookie: admin=true\r\n → injection de cookie
    // Payload : /dashboard\r\nContent-Length: 0\r\n\r\nHTTP/1.1 200 OK\r\n → cache poisoning
    exit();
}

function setCustomHeader(string $headerName, string $headerValue): void {
    // Double injection : nom ET valeur du header
    // Payload headerName : X-Injected: evil\r\nX-Another
    // Payload headerValue : normal\r\nSet-Cookie: session=hijacked
    header($headerName . ": " . $headerValue);
}

// ─── FAILLE 6 : Open Redirect — redirection vers un site externe ──────────────
// CWE-601 | CVSS 6.1 | OWASP A01:2025
// Payload : next = https://evil.com → phishing après logout
// Payload : next = //evil.com → protocol-relative redirect
// Payload : next = javascript:alert(document.cookie) → XSS
function safeRedirect(string $next): void {
    // Validation insuffisante — cherche uniquement "/" au début
    if (!empty($next) && $next[0] === '/') {
        header("Location: " . $next);  // mais //evil.com commence aussi par /
        exit();
    }

    // Deuxième check : vérifie si l'URL contient le domaine autorisé
    if (strpos($next, 'example.com') !== false) {
        // Bypass : https://evil.com?ref=example.com → passe le check
        header("Location: " . $next);
        exit();
    }

    header("Location: /home");
}

function loginRedirect(string $returnUrl): void {
    // Pas de validation — redirection directe après login
    // Payload : /login?return=https://evil.com/phishing
    // Payload : /login?return=javascript:eval(atob('...'))
    // Payload : /login?return=/%09/evil.com (tab-encoded)
    header("Location: " . $returnUrl);
    exit();
}

// ─── FAILLE 7 : LDAP Injection avancée — modification d'attributs ────────────
// Si le compte de service a les droits en écriture :
// Payload : dn modification pour modifier les rôles/mots de passe
function updateLdapUserEmail(string $username, string $newEmail): bool {
    $ldap = ldap_connect("ldap://ldap.example.com");
    ldap_bind($ldap, "cn=admin,dc=example,dc=com", "admin_password");

    // Recherche de l'utilisateur — injection dans le filtre
    $filter = "(uid=" . $username . ")";  // injection → peut modifier d'autres utilisateurs
    $result = ldap_search($ldap, "dc=example,dc=com", $filter);
    $entries = ldap_get_entries($ldap, $result);

    if ($entries['count'] > 0) {
        $dn = $entries[0]['dn'];
        // Modification d'attribut — $newEmail non validé
        // Payload newEmail : user@example.com)(mail=hacker@evil.com → inject attributes
        $modification = ['mail' => $newEmail];
        return ldap_modify($ldap, $dn, $modification);
    }
    return false;
}

// ─── FAILLE 8 : XPath blind injection — extraction via timing ─────────────────
// Technique similaire à la blind SQLi — extraction bit à bit via boolean conditions
function checkUserExists(string $username): string {
    $xml = new DOMDocument();
    $xml->load('users.xml');
    $xpath = new DOMXPath($xml);

    // Payload : username = admin' and substring(password,1,1)='a
    // Si vrai → "exists", si faux → "not found" → extraction aveugle du mot de passe
    $query = "/users/user[username='" . $username . "']";
    $result = $xpath->query($query);

    if ($result->length > 0) {
        return "User exists";   // leakage : différencie existant/non-existant
    }
    return "User not found";    // leakage : permet d'énumérer les utilisateurs
}

// ─── FAILLE 9 : Email Header Injection — spam/phishing via mail() ─────────────
// CWE-93 | OWASP A05:2025
// Payload subject : Subject: Test\r\nBcc: victim@evil.com
// → envoie le mail à des destinataires supplémentaires → spam relay
function sendContactEmail(string $name, string $email, string $subject, string $message): bool {
    // Pas d'échappement des headers email — injection possible
    // Payload email : user@example.com\r\nBcc: spam@evil.com,spam2@evil.com
    // Payload name : John\r\nFrom: fake@legitimate.com
    $headers = "From: " . $name . " <" . $email . ">";
    // ^^ injection dans From/Reply-To via \r\n dans $name ou $email

    return mail(
        "contact@example.com",
        $subject,  // injection dans le sujet
        $message,
        $headers   // headers injectés
    );
}

// ─── FAILLE 10 : HTTP Request Smuggling (config) + Host Header Injection ──────
// CWE-444 | OWASP A05:2025
// Le Host header est utilisé pour générer des URLs — injection possible
function generatePasswordResetLink(string $userEmail): string {
    // Le Host header est truqué par l'attaquant
    // Payload Host header : evil.com → le lien de reset pointe vers evil.com
    $host = $_SERVER['HTTP_HOST'];         // contrôlé par l'attaquant (header HTTP)
    $token = bin2hex(random_bytes(16));

    // Le lien de reset contient le host fourni par l'attaquant
    $resetLink = "https://" . $host . "/reset-password?token=" . $token . "&email=" . $userEmail;
    // Si Host: evil.com → lien envoyé à la victime : https://evil.com/reset-password?token=...

    sendResetEmail($userEmail, $resetLink);
    return $token;
}

function sendResetEmail(string $email, string $link): void {
    mail($email, "Password Reset", "Click here: " . $link);
}
