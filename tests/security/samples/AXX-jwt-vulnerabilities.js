/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection failles JWT (JSON Web Tokens)
 * Couverture : OWASP A07:2025 (Auth), OWASP API2:2023, OWASP LLM02
 * NE PAS déployer en production.
 */

const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const express = require('express');
const fs = require('fs');
const axios = require('axios');

const app = express();
app.use(express.json());

// ─── FAILLE 1 : Algorithm "none" — signature ignorée ─────────────────────────
// Payload : header {"alg":"none","typ":"JWT"} → aucune vérification de signature
// L'attaquant forge un token admin sans connaître le secret
app.post('/api/auth/token-none', (req, res) => {
    const { token } = req.body;
    try {
        // algorithms non restreint → accepte "none"
        const decoded = jwt.verify(token, '', { algorithms: ['HS256', 'RS256', 'none'] });
        res.json({ user: decoded, authenticated: true });
    } catch (e) {
        res.status(401).json({ error: e.message });
    }
});

// ─── FAILLE 2 : Secret faible (dictionary word) — force brutable ─────────────
// Secret "secret" ou "password123" → hashcat/jwt_tool crackent en secondes
const WEAK_SECRET = 'secret';

app.post('/api/auth/login', (req, res) => {
    const { username, password } = req.body;
    if (username === 'admin' && password === 'admin') {
        const token = jwt.sign(
            { userId: 1, role: 'admin', username },
            WEAK_SECRET,            // secret trivial
            { expiresIn: '365d' }   // expiration très longue
        );
        res.json({ token });
    }
});

// ─── FAILLE 3 : kid (Key ID) — injection SQL via paramètre kid ────────────────
// Payload header : {"alg":"HS256","kid":"1' UNION SELECT 'attacker_secret'-- -"}
// Le kid est injecté dans une requête SQL → signe le token avec un secret contrôlé
const db = require('sqlite3');
const sqlite = new db.Database(':memory:');

function getKeyById(kid) {
    return new Promise((resolve, reject) => {
        // injection SQL directe dans kid — pas de paramètre lié
        sqlite.get(`SELECT secret_key FROM api_keys WHERE id = '${kid}'`, (err, row) => {
            if (err) reject(err);
            else resolve(row ? row.secret_key : null);
        });
    });
}

app.post('/api/auth/verify-kid', async (req, res) => {
    const { token } = req.body;
    const header = JSON.parse(Buffer.from(token.split('.')[0], 'base64').toString());
    const kid = header.kid;                  // non sanitisé
    const secret = await getKeyById(kid);    // SQLi via kid
    try {
        const decoded = jwt.verify(token, secret);
        res.json({ decoded, authenticated: true });
    } catch (e) {
        res.status(401).json({ error: e.message });
    }
});

// ─── FAILLE 4 : kid — Path Traversal vers /dev/null ──────────────────────────
// Payload header : {"alg":"HS256","kid":"../../../../dev/null"}
// La clé lue depuis /dev/null est vide → token signé avec ''
function getKeyFromFile(kid) {
    // path traversal non vérifié
    const keyPath = `/var/app/keys/${kid}.pem`;
    return fs.readFileSync(keyPath, 'utf8');   // lecture arbitraire de fichier
}

app.post('/api/auth/verify-file-key', (req, res) => {
    const { token } = req.body;
    const header = JSON.parse(Buffer.from(token.split('.')[0], 'base64').toString());
    try {
        const secret = getKeyFromFile(header.kid);  // path traversal
        const decoded = jwt.verify(token, secret);
        res.json({ decoded });
    } catch (e) {
        res.status(401).json({ error: e.message });
    }
});

// ─── FAILLE 5 : JWK (JSON Web Key) — injection de clé dans le header ─────────
// Payload : header inclut "jwk":{...RSA key publique de l'attaquant...}
// Le serveur utilise la clé fournie par l'attaquant pour vérifier → self-signed token
app.post('/api/auth/verify-jwk', (req, res) => {
    const { token } = req.body;
    const header = JSON.parse(Buffer.from(token.split('.')[0], 'base64').toString());

    let publicKey;
    if (header.jwk) {
        // utilise la JWK fournie dans le header sans whitelist → attaquant injecte sa propre clé
        publicKey = crypto.createPublicKey({ key: header.jwk, format: 'jwk' });
    } else {
        publicKey = fs.readFileSync('/var/app/keys/public.pem');
    }

    try {
        const decoded = jwt.verify(token, publicKey, { algorithms: ['RS256'] });
        res.json({ decoded, authenticated: true });
    } catch (e) {
        res.status(401).json({ error: e.message });
    }
});

// ─── FAILLE 6 : jku (JWK Set URL) — SSRF + injection de clé externe ──────────
// Payload header : {"alg":"RS256","jku":"https://attacker.com/evil-jwks.json"}
// Le serveur fetch l'URL fournie → SSRF + le set de clés JWK est contrôlé par l'attaquant
app.post('/api/auth/verify-jku', async (req, res) => {
    const { token } = req.body;
    const header = JSON.parse(Buffer.from(token.split('.')[0], 'base64').toString());

    try {
        // fetch SSRF : l'URL jku est fournie par l'attaquant dans le header JWT
        const jwksResponse = await axios.get(header.jku, { timeout: 5000 });
        const jwks = jwksResponse.data;
        const key = jwks.keys.find(k => k.kid === header.kid);
        const publicKey = crypto.createPublicKey({ key, format: 'jwk' });
        const decoded = jwt.verify(token, publicKey, { algorithms: ['RS256'] });
        res.json({ decoded });
    } catch (e) {
        res.status(401).json({ error: e.message });
    }
});

// ─── FAILLE 7 : RS256 → HS256 — Algorithm Confusion Attack ──────────────────
// Clé publique RSA exposée → l'attaquant l'utilise comme secret HMAC
// Signe avec HS256 + clé_publique_RSA → serveur vérifie avec cette même "clé" en HMAC
const PUBLIC_KEY = fs.readFileSync('/var/app/keys/public.pem', 'utf8');  // clé publique exposée dans /api/public-key

app.post('/api/auth/verify-asymmetric', (req, res) => {
    const { token } = req.body;
    try {
        // jwt.verify sans restriction d'algorithme → accepte HS256 signé avec la clé publique RSA
        const decoded = jwt.verify(token, PUBLIC_KEY);  // vulnérable à algorithm confusion
        res.json({ decoded, authenticated: true });
    } catch (e) {
        res.status(401).json({ error: e.message });
    }
});

// ─── FAILLE 8 : Token expiré accepté — vérification manuelle non sécurisée ───
// L'application vérifie manuellement exp mais ignore nbf, iat
app.post('/api/auth/verify-manual', (req, res) => {
    const { token } = req.body;
    try {
        // ignoreExpiration: true → les tokens expirés depuis des années sont acceptés
        const decoded = jwt.verify(token, WEAK_SECRET, { ignoreExpiration: true });
        res.json({ decoded, authenticated: true });
    } catch (e) {
        res.status(401).json({ error: e.message });
    }
});

// ─── FAILLE 9 : JWT stocké dans localStorage + XSS → vol de token ─────────────
// Côté client : localStorage.setItem('auth_token', token)
// Toute XSS peut voler le token : document.cookie vs localStorage
// Combined with lack of token revocation
app.get('/api/user/profile', (req, res) => {
    const token = req.headers['authorization']?.split(' ')[1];
    if (!token) return res.status(401).json({ error: 'No token' });

    // Pas de vérification de révocation — token révoqué reste valide jusqu'à expiration
    const decoded = jwt.verify(token, WEAK_SECRET);
    const sql = `SELECT * FROM users WHERE id = ${decoded.userId}`;  // SQLi post-auth
    res.json({ user: decoded });
});

// ─── FAILLE 10 : Divulgation d'informations sensibles dans le payload JWT ─────
// Le payload contient des données sensibles non chiffrées (JWT = encodé, non chiffré)
function generateTokenWithSensitiveData(user) {
    return jwt.sign({
        userId: user.id,
        email: user.email,
        password_hash: user.password_hash,    // hash du mot de passe dans le token !
        ssn: user.ssn,                         // numéro de sécurité sociale
        credit_card: user.credit_card,         // PCI-DSS violation
        role: user.role,
        internal_ip: '10.0.1.45',             // IP interne exposée
        db_connection: 'mysql://prod-db:3306'  // info infrastructure
    }, WEAK_SECRET, { expiresIn: '365d' });
}

app.listen(3000);
