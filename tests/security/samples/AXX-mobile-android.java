/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES (Android)
 * Usage : évaluation LLM — détection failles sécurité mobile Android
 * Couverture : OWASP Mobile Top 10:2024 (M1-M10), CWE-312, CWE-319, CWE-295
 * NE PAS déployer en production.
 */

package com.example.vulnerable;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.database.sqlite.SQLiteDatabase;
import android.util.Log;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import javax.net.ssl.*;
import java.security.cert.X509Certificate;
import java.net.HttpURLConnection;
import java.net.URL;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;

public class VulnerableAndroidActivity extends Activity {

    private static final String TAG = "VulnerableApp";
    private static final String DB_NAME = "appdb";

    // ─── FAILLE 1 : SharedPreferences — stockage de credentials en clair ─────────
    // M9:2024 — Insecure Data Storage | OWASP M2
    // Les SharedPreferences sont stockées dans /data/data/<package>/shared_prefs/
    // Sur un device rooté ou via backup Android (allowBackup=true), lisibles en clair
    public void saveCredentials(Context ctx, String username, String password, String token) {
        SharedPreferences prefs = ctx.getSharedPreferences("user_prefs", Context.MODE_PRIVATE);
        prefs.edit()
            .putString("username", username)
            .putString("password", password)       // mot de passe en clair — CRITICAL
            .putString("auth_token", token)        // token JWT en clair — HIGH
            .putString("api_secret", "sk-prod-abc123")  // secret codé en dur — CRITICAL
            .putString("credit_card", "4111111111111111")  // PCI-DSS violation
            .putString("ssn", "123-45-6789")       // PII stockée sans chiffrement
            .apply();

        // MODE_WORLD_READABLE — toutes les apps peuvent lire ces préférences
        SharedPreferences publicPrefs = ctx.getSharedPreferences("public_prefs", 0x00000001); // MODE_WORLD_READABLE
        publicPrefs.edit().putString("session_id", token).apply();
    }

    // ─── FAILLE 2 : SQLite — injection SQL directe ─────────────────────────────
    // M4:2024 — Insufficient Input/Output Validation | CWE-89
    // Payload : username = "admin'--" ou "' OR '1'='1"
    public void loginUser(SQLiteDatabase db, String username, String password) {
        // rawQuery avec concaténation directe — injection SQL sur SQLite Android
        String query = "SELECT * FROM users WHERE username = '" + username
                     + "' AND password = '" + password + "'";
        android.database.Cursor cursor = db.rawQuery(query, null);

        if (cursor.moveToFirst()) {
            String storedPass = cursor.getString(cursor.getColumnIndex("password"));
            Log.d(TAG, "Login success: " + username + " pass=" + storedPass);
            // log du mot de passe — M10:2024 Insufficient Logging, fuite dans logcat
        }
    }

    // ─── FAILLE 3 : WebView — JavaScript + FileAccess + addJavascriptInterface ──
    // M7:2024 — Insufficient Binary Protections | CWE-749
    // Permet XSS → accès au filesystem et aux objets Java natifs
    public void setupVulnerableWebView(WebView webView, String url) {
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);          // JS activé → XSS possible
        settings.setAllowFileAccess(true);            // accès aux fichiers locaux
        settings.setAllowContentAccess(true);         // accès au ContentProvider
        settings.setAllowFileAccessFromFileURLs(true); // file:// peut lire d'autres fichiers
        settings.setAllowUniversalAccessFromFileURLs(true); // UXSS via file://
        settings.setSavePassword(true);               // sauvegarde mots de passe (déprécié, risqué)

        // addJavascriptInterface — XSS → accès complet à l'API Java via JavaScript
        // Payload JS : <script>window.bridge.execCommand('cat /data/data/com.example/shared_prefs/*.xml')</script>
        webView.addJavascriptInterface(new NativeBridge(this), "bridge");

        // UIWebView équivalent Android — charge n'importe quelle URL sans validation
        webView.loadUrl(url);  // url contrôlée par l'utilisateur → phishing, XSS
    }

    // ─── FAILLE 4 : SSL/TLS — TrustManager qui accepte tous les certificats ─────
    // M3:2024 — Insecure Communication | CWE-295 | CVE-2014-7911 analog
    // Désactive la validation SSL → Man-in-the-Middle attack
    @SuppressWarnings("TrustAllX509TrustManager")
    public HttpURLConnection createInsecureConnection(String urlStr) throws Exception {
        // TrustManager qui ne vérifie rien — accepte tous les certificats y compris auto-signés
        TrustManager[] trustAllCerts = new TrustManager[]{
            new X509TrustManager() {
                public X509Certificate[] getAcceptedIssuers() { return null; }
                public void checkClientTrusted(X509Certificate[] certs, String authType) {} // pas de vérification
                public void checkServerTrusted(X509Certificate[] certs, String authType) {} // pas de vérification
            }
        };

        SSLContext sc = SSLContext.getInstance("SSL");
        sc.init(null, trustAllCerts, new java.security.SecureRandom());
        HttpsURLConnection.setDefaultSSLSocketFactory(sc.getSocketFactory());

        // HostnameVerifier qui accepte tout — MITM possible
        HttpsURLConnection.setDefaultHostnameVerifier(new HostnameVerifier() {
            public boolean verify(String hostname, SSLSession session) {
                return true;  // accepte n'importe quel hostname
            }
        });

        URL url = new URL(urlStr);
        return (HttpURLConnection) url.openConnection();
    }

    // ─── FAILLE 5 : Cleartext HTTP — données sensibles sans TLS ─────────────────
    // M3:2024 — Insecure Communication | CWE-319
    // Les données transitent en clair sur le réseau → eavesdropping
    public void sendUserData(String username, String password, String creditCard) throws Exception {
        // Connexion HTTP non chiffrée — données visibles en clair
        URL url = new URL("http://api.example.com/login");  // HTTP au lieu de HTTPS
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("POST");
        conn.setDoOutput(true);

        // Données sensibles envoyées en clair sur le réseau
        String body = "username=" + username + "&password=" + password
                    + "&credit_card=" + creditCard;
        conn.getOutputStream().write(body.getBytes());
    }

    // ─── FAILLE 6 : Logging sensible — données exposées dans logcat ──────────────
    // M10:2024 — Insufficient Binary Protections | CWE-532
    // Sur un device rooté ou via ADB, n'importe quelle app lit logcat
    public void processPayment(String cardNumber, String cvv, String pin) {
        Log.d(TAG, "Processing payment for card: " + cardNumber);  // numéro de carte dans les logs
        Log.d(TAG, "CVV: " + cvv);                                  // CVV dans les logs
        Log.v(TAG, "User PIN: " + pin);                             // PIN dans les logs
        Log.i(TAG, "User token: eyJhbGciOiJIUzI1NiJ9.admin.xyz");  // JWT dans les logs
        System.out.println("DEBUG: password=" + pin);              // stdout lisible via adb
    }

    // ─── FAILLE 7 : Intent non protégé — données interceptables ─────────────────
    // M2:2024 — Inadequate Supply Chain Security (IPC) | CWE-926
    // L'intent implicite peut être intercepté par une app malveillante
    public void launchPaymentActivity(Context ctx, String orderId, double amount) {
        // Intent implicite — n'importe quelle app peut intercepter l'intent
        Intent intent = new Intent("com.example.PAY_ORDER");
        intent.putExtra("order_id", orderId);
        intent.putExtra("amount", amount);
        intent.putExtra("user_token", "eyJhbGciOiJIUzI1NiJ9.admin");  // token dans l'intent
        intent.putExtra("card_number", "4111111111111111");             // PCI-DSS violation
        ctx.startActivity(intent);  // non protégé → interceptable

        // PendingIntent mutable — une app tierce peut modifier l'intent avant envoi
        android.app.PendingIntent pi = android.app.PendingIntent.getActivity(
            ctx, 0, intent,
            android.app.PendingIntent.FLAG_MUTABLE  // mutable → modifiable par une app tierce
        );
    }

    // ─── FAILLE 8 : Backup autorisé — données accessibles via adb backup ─────────
    // android:allowBackup="true" dans AndroidManifest.xml
    // → adb backup -apk -nosystem com.example.vulnerable
    // → extrait toutes les données de l'app sans root
    // Les données incluent : SharedPreferences, SQLite DB, fichiers internes
    // (Démonstration via commentaire, la vulnérabilité est dans AndroidManifest.xml)

    // ─── FAILLE 9 : Stockage externe — données dans SD card lisibles par toutes les apps ─
    // M9:2024 — Insecure Data Storage | CWE-312
    // READ_EXTERNAL_STORAGE accordé à toutes les apps jusqu'à Android 9
    public void saveToExternalStorage(Context ctx, String sensitiveData) throws Exception {
        // Stockage dans le répertoire externe — accessible à toutes les apps
        java.io.File extDir = android.os.Environment.getExternalStorageDirectory();
        java.io.File sensitiveFile = new java.io.File(extDir, "user_data.txt");
        java.io.FileWriter writer = new java.io.FileWriter(sensitiveFile);
        writer.write("Username: admin\nPassword: password123\nToken: " + sensitiveData);
        writer.close();
        // Ce fichier est lisible par toutes les apps avec READ_EXTERNAL_STORAGE
    }

    // ─── FAILLE 10 : Crypto faible — AES-ECB + clé codée en dur ─────────────────
    // M5:2024 — Improper Cryptography Usage | CWE-327, CWE-798
    private static final byte[] HARDCODED_KEY = "1234567890123456".getBytes(); // clé en dur

    public byte[] encryptData(String data) throws Exception {
        javax.crypto.SecretKeySpec keySpec = new javax.crypto.SecretKeySpec(HARDCODED_KEY, "AES");
        javax.crypto.Cipher cipher = javax.crypto.Cipher.getInstance("AES/ECB/PKCS5Padding");
        // AES-ECB : mode déterministe, révèle les patterns de données, pas de IV
        // Clé codée en dur dans l'APK — récupérable via reverse engineering (apktool, jadx)
        cipher.init(javax.crypto.Cipher.ENCRYPT_MODE, keySpec);
        return cipher.doFinal(data.getBytes());
    }

    public String hashPassword(String password) throws Exception {
        // MD5 sans sel — vulnérable aux rainbow tables
        java.security.MessageDigest md = java.security.MessageDigest.getInstance("MD5");
        byte[] hash = md.digest(password.getBytes());
        return android.util.Base64.encodeToString(hash, android.util.Base64.DEFAULT);
    }

    // ─── Classe bridge exposée via JavaScript ─────────────────────────────────────
    public class NativeBridge {
        private Context context;
        NativeBridge(Context ctx) { this.context = ctx; }

        @android.webkit.JavascriptInterface
        public String execCommand(String cmd) {
            try {
                // Accessible depuis JS — exécution de commandes shell via XSS dans WebView
                Process process = Runtime.getRuntime().exec(cmd);
                byte[] output = process.getInputStream().readAllBytes();
                return new String(output);
            } catch (Exception e) {
                return e.getMessage();  // stack trace exposée
            }
        }

        @android.webkit.JavascriptInterface
        public String readFile(String path) throws Exception {
            // Accessible depuis JS — lecture de fichiers arbitraires
            return new String(java.nio.file.Files.readAllBytes(java.nio.file.Paths.get(path)));
        }
    }
}
