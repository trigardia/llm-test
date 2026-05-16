/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection injection NoSQL / MongoDB
 * Couverture : OWASP A05:2025 (Injection), CWE-943, OWASP API3:2023
 * NE PAS déployer en production.
 */

const express = require('express');
const { MongoClient, ObjectId } = require('mongodb');
const mongoose = require('mongoose');
const redis = require('redis');
const app = express();

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

const MONGO_URI = 'mongodb://localhost:27017/appdb';
let db;
MongoClient.connect(MONGO_URI).then(client => { db = client.db('appdb'); });

// ─── FAILLE 1 : Injection d'opérateur MongoDB — authentification bypass ────────
// Payload JSON : {"username": {"$ne": ""}, "password": {"$ne": ""}}
// → la requête devient : WHERE username != '' AND password != '' → tous les users
app.post('/api/auth/login', async (req, res) => {
    const { username, password } = req.body;

    // L'objet req.body est passé directement — l'opérateur $ne bypass l'auth
    const user = await db.collection('users').findOne({
        username: username,   // si username = {"$ne": ""} → filtre sur != ""
        password: password    // si password = {"$ne": ""} → match n'importe quoi
    });

    if (user) {
        res.json({ success: true, token: generateToken(user), user });
    } else {
        res.status(401).json({ error: 'Invalid credentials' });
    }
});

// ─── FAILLE 2 : Injection $regex — enumération de contenu ────────────────────
// Payload : {"email": {"$regex": "^admin"}} → enumère les emails commençant par admin
app.get('/api/users/search', async (req, res) => {
    const { email, name } = req.query;

    // L'objet query passé directement à find() → injection d'opérateurs MongoDB
    const filter = {};
    if (email) filter.email = email;  // email={"$regex":".*"} → retourne tous les users
    if (name)  filter.name  = name;

    const users = await db.collection('users').find(filter).toArray();
    res.json({ users, count: users.length });
});

// ─── FAILLE 3 : $where — injection JavaScript Server-Side ────────────────────
// Payload : {"$where": "sleep(5000) || true"} → DoS, timing attack, exécution JS
// MongoDB >= 4.4 désactive $where par défaut, mais beaucoup d'apps anciennes vulnérables
app.post('/api/users/filter', async (req, res) => {
    const { filter } = req.body;

    // filter peut contenir {"$where": "function(){return true;}"} → RCE JS côté serveur
    const users = await db.collection('users').find(filter).toArray();
    res.json({ users });
});

// ─── FAILLE 4 : Injection via paramètre URL — query string MongoDB ────────────
// URL : /api/products?price[$gt]=0&category[$ne]=hidden
// → Express parse les [] comme objets → injection d'opérateurs
app.get('/api/products', async (req, res) => {
    // req.query parsé par Express : ?price[$lt]=100 → { price: { '$lt': '100' } }
    const products = await db.collection('products').find(req.query).toArray();
    res.json({ products });
});

// ─── FAILLE 5 : Injection via ObjectId — IDOR sans validation ────────────────
// L'attaquant peut passer des opérateurs au lieu d'un ID valide
// {"_id": {"$gt": ObjectId("000000000000000000000000")}} → retourne tous les docs
app.get('/api/orders/:id', async (req, res) => {
    const { id } = req.params;
    try {
        // Pas de validation que id est un ObjectId valide
        const query = id.startsWith('{') ? JSON.parse(id) : { _id: new ObjectId(id) };
        const order = await db.collection('orders').findOne(query);
        res.json({ order });
    } catch (e) {
        res.status(400).json({ error: e.message });  // fuite de message d'erreur MongoDB
    }
});

// ─── FAILLE 6 : Injection dans aggregation pipeline ──────────────────────────
// Payload : {"$lookup":{"from":"admin_secrets","localField":"_id","foreignField":"user_id","as":"secrets"}}
// L'attaquant injecte un $lookup pour exfiltrer des collections protégées
app.post('/api/reports/aggregate', async (req, res) => {
    const { pipeline } = req.body;

    // Pipeline MongoDB directement fourni par l'utilisateur → accès à toutes les collections
    const results = await db.collection('orders').aggregate(pipeline).toArray();
    res.json({ results });
});

// ─── FAILLE 7 : Injection Mongoose — contournement de schéma ─────────────────
// Mongoose ne protège pas contre $ne/$gt passés dans les requêtes find()
const User = mongoose.model('User', new mongoose.Schema({
    username: String,
    password: String,
    role: String,
    isAdmin: Boolean
}));

app.post('/api/mongoose/login', async (req, res) => {
    const { username, password } = req.body;

    // Mongoose : si req.body.password = {"$gt": ""} → trouve user même sans mot de passe
    const user = await User.findOne({ username, password });
    if (user) {
        res.json({ authenticated: true, role: user.role });
    } else {
        res.status(401).json({ error: 'Invalid credentials' });
    }
});

// ─── FAILLE 8 : Redis injection via CRLF ────────────────────────────────────
// Payload : "username\r\nSET admin_token hacked\r\n"
// CRLF dans la clé → injection de commandes Redis arbitraires
const redisClient = redis.createClient();

app.post('/api/session/store', async (req, res) => {
    const { sessionId, userId } = req.body;

    // CRLF injection dans la clé Redis — exécute des commandes Redis arbitraires
    await redisClient.set(`session:${sessionId}`, JSON.stringify({ userId }));
    res.json({ stored: true });
});

// ─── FAILLE 9 : Exposition de masse — retourne tous les champs MongoDB ────────
// L'attaquant récupère password_hash, tokens, données sensibles via projection manquante
app.get('/api/user/:id', async (req, res) => {
    const user = await db.collection('users').findOne(
        { _id: new ObjectId(req.params.id) }
        // pas de projection : { password: 0, token: 0, secret: 0 }
        // retourne password_hash, session_token, MFA_secret, etc.
    );
    res.json({ user });  // données sensibles exposées intégralement
});

// ─── FAILLE 10 : Time-based blind — enumération par timing ───────────────────
// Payload $where : "function(){ var start = new Date(); while(new Date()-start<5000){}; return this.username=='admin'; }"
// Timing différent selon si la condition est vraie → énumération blindée
app.post('/api/users/exists', async (req, res) => {
    const { query } = req.body;
    const start = Date.now();

    // $where avec fonction de timing → blind NoSQL injection
    const exists = await db.collection('users').findOne(query);
    const elapsed = Date.now() - start;

    res.json({ exists: !!exists, time: elapsed });  // temps de réponse exposé → timing attack
});

function generateToken(user) {
    return require('crypto').randomBytes(16).toString('hex');
}

app.listen(3001);
