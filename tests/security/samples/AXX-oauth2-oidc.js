/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection failles OAuth2 / OIDC / SSO
 * Couverture : OWASP A07:2025, OWASP API2:2023, RFC 6749 attack surface
 * NE PAS déployer en production.
 */

const express = require('express');
const axios = require('axios');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const session = require('express-session');

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(session({ secret: 'session-secret', resave: false, saveUninitialized: true }));

const CLIENT_ID     = 'my-app-client-id';
const CLIENT_SECRET = 'super-secret-client-secret';  // secret codé en dur
const JWT_SECRET    = 'oauth-jwt-secret-2024';        // secret JWT faible

// ─── FAILLE 1 : state manquant — CSRF sur le flux OAuth2 ─────────────────────
// RFC 6749 §10.12 : le paramètre state est obligatoire pour prévenir le CSRF
// Payload : l'attaquant forge un lien d'autorisation → vole la session OAuth de la victime
app.get('/oauth/authorize-initiate', (req, res) => {
    const redirectUri = 'https://myapp.com/oauth/callback';

    // Pas de paramètre state — vulnérable au CSRF sur OAuth
    // Un attaquant peut forcer la victime à lier son compte à un token contrôlé par l'attaquant
    const authUrl = `https://auth.example.com/oauth/authorize?` +
        `client_id=${CLIENT_ID}&` +
        `redirect_uri=${redirectUri}&` +
        `response_type=code&` +
        `scope=openid profile email`;
    // state absent → pas de vérification d'intégrité de la réponse
    res.redirect(authUrl);
});

// ─── FAILLE 2 : redirect_uri non validée — token interception ─────────────────
// RFC 6749 §10.6 : la redirect_uri doit être strictement comparée
// Payload : https://myapp.com/callback%2F..%2F → redirige vers un path contrôlé
// Payload : https://myapp.com.evil.com/callback → sous-domaine attaquant
app.post('/oauth/token-exchange', async (req, res) => {
    const { code, redirect_uri } = req.body;

    // Validation partielle de redirect_uri — substring match seulement
    if (!redirect_uri.includes('myapp.com')) {
        return res.status(400).json({ error: 'Invalid redirect_uri' });
    }
    // Bypass : "https://myapp.com.evil.com/steal" → contient "myapp.com" mais est malicieux
    // Bypass : "https://myapp.com%40evil.com/steal" → URL encoding bypass

    const tokenResponse = await axios.post('https://auth.example.com/oauth/token', {
        grant_type: 'authorization_code',
        code,
        redirect_uri,  // redirect_uri non validée strictement → interception du code
        client_id: CLIENT_ID,
        client_secret: CLIENT_SECRET
    });

    const { access_token, refresh_token } = tokenResponse.data;
    // Token exposé dans la réponse sans sécurisation du transport
    res.json({ access_token, refresh_token, client_secret: CLIENT_SECRET });  // client_secret exposé !
});

// ─── FAILLE 3 : authorization code interception — code réutilisable ──────────
// Le code d'autorisation OAuth2 doit être à usage unique
// Un attaquant qui capture le code (via Referer, logs) peut l'échanger plusieurs fois
app.get('/oauth/callback', async (req, res) => {
    const { code, state } = req.query;

    // Pas de vérification du state (déjà vulnerable faille 1)
    // Le code n'est pas marqué comme utilisé → réutilisable si le serveur OAuth le permet

    // Le code apparaît dans l'URL → exposé dans les logs nginx, Referer headers, historique navigateur
    console.log(`OAuth callback received: code=${code}`);  // code dans les logs !

    // Token exchange sans PKCE (Proof Key for Code Exchange) → susceptible d'interception
    const tokens = await exchangeCode(code);
    req.session.tokens = tokens;

    // Stockage du token dans un cookie sans HttpOnly ni Secure
    res.cookie('access_token', tokens.access_token, {
        // httpOnly: false → accessible via JavaScript → vol via XSS
        // secure: false → envoyé sur HTTP → eavesdropping
        // sameSite: none → CSRF possible
    });
    res.redirect('/dashboard');
});

// ─── FAILLE 4 : scope escalation — demande de permissions supplémentaires ─────
// Un client ne peut pas demander plus de permissions que celles configurées
// Mais une validation insuffisante côté serveur permet l'escalade
app.post('/oauth/request-token', async (req, res) => {
    const { requested_scope } = req.body;

    // Pas de validation que les scopes demandés sont un sous-ensemble des scopes autorisés
    // L'attaquant peut demander scope=admin:all ou scope=user:delete
    const tokenResponse = await axios.post('https://auth.example.com/oauth/token', {
        grant_type: 'client_credentials',
        client_id: CLIENT_ID,
        client_secret: CLIENT_SECRET,
        scope: requested_scope  // scope fourni par l'attaquant — non filtré
    });

    res.json(tokenResponse.data);
});

// ─── FAILLE 5 : token leakage via Referer header ─────────────────────────────
// Implicit flow expose le token dans l'URL fragment → Referer header le divulgue
app.get('/implicit-flow-redirect', (req, res) => {
    // Implicit flow (déprécié dans OAuth 2.1 mais encore utilisé)
    // response_type=token → access_token dans l'URL fragment
    // Exemple : https://myapp.com/callback#access_token=eyJhbG...&token_type=bearer
    // Si la page contient des ressources externes (CDN, analytics), le token fuit dans Referer
    const authUrl = `https://auth.example.com/oauth/authorize?` +
        `client_id=${CLIENT_ID}&` +
        `redirect_uri=https://myapp.com/callback&` +
        `response_type=token&`  // implicit flow → token dans l'URL
        `scope=openid profile`;
    res.redirect(authUrl);
});

// ─── FAILLE 6 : refresh token — rotation non implémentée ─────────────────────
// Un refresh token volé reste valide indéfiniment sans rotation
const refreshTokens = new Map();  // stockage en mémoire — perdu au redémarrage

app.post('/oauth/refresh', async (req, res) => {
    const { refresh_token } = req.body;

    // Pas de rotation du refresh token → token volé utilisable indéfiniment
    // Pas d'invalidation de l'ancien token après rotation
    // Pas de détection de réutilisation (refresh token replay attack)
    if (refreshTokens.has(refresh_token)) {
        const userId = refreshTokens.get(refresh_token);
        const newAccessToken = jwt.sign({ userId, role: 'user' }, JWT_SECRET, { expiresIn: '1h' });
        // L'ancien refresh_token n'est pas invalidé → réutilisable
        res.json({ access_token: newAccessToken, refresh_token });  // même refresh token retourné
    } else {
        res.status(401).json({ error: 'Invalid refresh token' });
    }
});

// ─── FAILLE 7 : ID token validation manquante — JWT non vérifié ──────────────
// L'ID token OIDC doit être validé (signature, issuer, audience, expiration)
app.post('/oidc/login', async (req, res) => {
    const { id_token } = req.body;

    // Décodage sans vérification de signature — susceptible de falsification
    const decoded = jwt.decode(id_token);  // decode() ≠ verify() — pas de vérif signature

    // Pas de vérification de l'issuer (iss)
    // Pas de vérification de l'audience (aud)
    // Pas de vérification de l'expiration (exp)
    // Pas de vérification du nonce (replay attack)

    if (decoded && decoded.sub) {
        // Crée une session basée sur un token non vérifié
        req.session.userId = decoded.sub;
        req.session.role = decoded.role || 'user';  // role non vérifié → escalade
        res.json({ authenticated: true, user: decoded });
    } else {
        res.status(401).json({ error: 'Invalid token' });
    }
});

// ─── FAILLE 8 : open redirect via post_logout_redirect_uri ───────────────────
// Après déconnexion OIDC, la redirection peut pointer vers un site malveillant
app.get('/oidc/logout', (req, res) => {
    const redirectAfterLogout = req.query.post_logout_redirect_uri;

    // Pas de validation de l'URI de redirection post-logout
    // Payload : post_logout_redirect_uri=https://evil.com/phishing
    req.session.destroy(() => {
        // Redirection open redirect vers un site externe non validé
        res.redirect(
            `https://auth.example.com/logout?post_logout_redirect_uri=${redirectAfterLogout}`
        );
    });
});

// ─── FAILLE 9 : client_secret exposé côté client (SPA) ───────────────────────
// Un SPA (Single Page App) ne peut pas garder un secret confidentiel
// Le client_secret est visible dans le bundle JavaScript — ne doit pas exister pour les SPAs
const publicClientConfig = {
    client_id: 'spa-public-client',
    client_secret: 'SPA_SECRET_WHICH_IS_NOT_SECRET',  // exposé dans le bundle JS
    auth_endpoint: 'https://auth.example.com/oauth/authorize',
    token_endpoint: 'https://auth.example.com/oauth/token',
    // PKCE non implémenté → interception du code possible
};

// ─── FAILLE 10 : token storage insécurisé côté client ─────────────────────────
// Les tokens OAuth ne doivent pas être dans localStorage (XSS) ni dans des cookies non sécurisés
app.get('/oauth/success', (req, res) => {
    const { access_token, refresh_token } = req.query;

    // Token renvoyé au client pour stockage dans localStorage (via JavaScript)
    // Toute XSS peut voler le token
    res.send(`
        <script>
            // Stockage des tokens dans localStorage — accessible via XSS
            localStorage.setItem('access_token', '${access_token}');
            localStorage.setItem('refresh_token', '${refresh_token}');
            // Les tokens JWT ont une longue durée de vie (365 jours)
            // Pas de détection de vol de token
            // Pas de binding d'IP ou de device fingerprint
            window.location.href = '/dashboard';
        </script>
    `);
});

async function exchangeCode(code) {
    const response = await axios.post('https://auth.example.com/oauth/token', {
        grant_type: 'authorization_code',
        code,
        client_id: CLIENT_ID,
        client_secret: CLIENT_SECRET
    });
    return response.data;
}

app.listen(3003);
