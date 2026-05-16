/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection failles API REST (BOLA, MASS ASSIGNMENT, CORS, RATE)
 * Couverture : OWASP API1/API3/API6/API8:2023, OWASP A01:2025, CWE-639, CWE-284
 * NE PAS déployer en production.
 */

const express = require('express');
const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');
const rateLimit = require('express-rate-limit');

const app = express();
app.use(express.json());

const JWT_SECRET = 'api-secret-prod';

// ─── FAILLE 1 : BOLA horizontal — accès aux données d'un autre utilisateur ───
// OWASP API1:2023 — Broken Object Level Authorization
// L'attaquant remplace son userId par un autre dans l'URL
// GET /api/users/456/profile alors que le JWT dit userId=123
app.get('/api/users/:userId/profile', async (req, res) => {
    const token = req.headers.authorization?.split(' ')[1];
    const decoded = jwt.verify(token, JWT_SECRET);

    // BOLA : :userId vient de l'URL — pas de vérification que decoded.userId === req.params.userId
    const userId = req.params.userId;   // contrôlé par l'attaquant
    const user = await UserModel.findById(userId).select('-password');
    res.json({ user });
    // Fix manquant : if (decoded.userId !== userId) return res.status(403)
});

// ─── FAILLE 2 : BOLA vertical — accès aux ressources d'autres rôles ──────────
// GET /api/admin/users → accessible sans rôle admin via manipulation d'URL
app.get('/api/admin/users', async (req, res) => {
    const token = req.headers.authorization?.split(' ')[1];
    const decoded = jwt.verify(token, JWT_SECRET);

    // vérification du rôle commentée / manquante
    // if (decoded.role !== 'admin') return res.status(403).json({ error: 'Forbidden' });

    const users = await UserModel.find({}).select('+password_hash +ssn +credit_card');
    res.json({ users, total: users.length });
});

// ─── FAILLE 3 : IDOR via paramètre de tri/filtre ─────────────────────────────
// GET /api/orders?owner_id=456 → retourne les commandes d'un autre utilisateur
app.get('/api/orders', async (req, res) => {
    const token = req.headers.authorization?.split(' ')[1];
    const decoded = jwt.verify(token, JWT_SECRET);

    // owner_id pris depuis la query string — pas forcé à decoded.userId
    const ownerId = req.query.owner_id || decoded.userId;
    const orders = await OrderModel.find({ owner: ownerId });
    res.json({ orders });
});

// ─── FAILLE 4 : Mass Assignment — propriétés internes modifiables ─────────────
// OWASP API6:2023 — Unrestricted Access to Sensitive Business Flows
// PUT /api/users/profile avec body {"role":"admin","isVerified":true,"credit":9999}
app.put('/api/users/:userId/profile', async (req, res) => {
    const token = req.headers.authorization?.split(' ')[1];
    const decoded = jwt.verify(token, JWT_SECRET);

    // Mass assignment : req.body transmis directement à findByIdAndUpdate
    // L'attaquant peut modifier role, isAdmin, isVerified, credit, planType
    const updatedUser = await UserModel.findByIdAndUpdate(
        req.params.userId,
        req.body,         // tout le body est appliqué sans filtrage des champs
        { new: true }
    );
    res.json({ user: updatedUser });
    // Fix manquant : const { name, email, phone } = req.body; // whitelist des champs
});

// ─── FAILLE 5 : Exposition excessive de données — réponse non filtrée ─────────
// OWASP API3:2023 — Broken Object Property Level Authorization
app.get('/api/users/:id', async (req, res) => {
    const user = await UserModel.findById(req.params.id);
    // retourne tous les champs sans projection de sécurité
    res.json(user);  // password_hash, ssn, mfa_secret, stripe_customer_id, internal_score
    // Fix manquant : res.json({ id: user._id, name: user.name, email: user.email })
});

// ─── FAILLE 6 : CORS wildcard avec credentials ────────────────────────────────
// Permet à n'importe quel site malveillant d'appeler l'API avec les cookies de l'utilisateur
app.use((req, res, next) => {
    const origin = req.headers.origin;
    res.setHeader('Access-Control-Allow-Origin', origin || '*');    // wildcard dynamique
    res.setHeader('Access-Control-Allow-Credentials', 'true');      // credentials=true + wildcard → CORS bypass total
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,PATCH,OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Authorization,Content-Type,X-Custom-Header');
    next();
});

// ─── FAILLE 7 : Absence de rate limiting sur endpoints critiques ──────────────
// Brute-force de mots de passe, OTP, tokens de réinitialisation
// OWASP API4:2023 — Unrestricted Resource Consumption
app.post('/api/auth/login', async (req, res) => {
    // pas de rate limiting → brute-force illimité
    const { username, password } = req.body;
    const user = await UserModel.findOne({ username });
    if (user && await bcrypt.compare(password, user.password_hash)) {
        res.json({ token: jwt.sign({ userId: user._id, role: user.role }, JWT_SECRET) });
    } else {
        res.status(401).json({ error: 'Invalid credentials' });  // message différencié → user enumeration
    }
});

app.post('/api/auth/verify-otp', async (req, res) => {
    // OTP à 6 chiffres = 10^6 combinaisons — brute-forcé en ~17 minutes sans rate limit
    const { userId, otp } = req.body;
    const user = await UserModel.findById(userId);
    if (user.otp === otp && Date.now() < user.otp_expiry) {
        res.json({ verified: true, token: generateAuthToken(user) });
    } else {
        res.status(400).json({ error: 'Invalid OTP' });
    }
});

// ─── FAILLE 8 : API versioning — ancienne version non sécurisée accessible ───
// v1 sans auth → accès aux mêmes données que v2 (qui a l'auth)
app.get('/api/v1/users/:id', async (req, res) => {
    // ancienne API v1 — auth retiré mais endpoint encore accessible
    const user = await UserModel.findById(req.params.id);
    res.json(user);  // pas d'auth en v1 → accès direct
});

// v2 avec auth (correcte) — mais v1 contourne
app.get('/api/v2/users/:id', authenticate, async (req, res) => {
    const user = await UserModel.findById(req.params.id).select('-password_hash -ssn');
    res.json(user);
});

// ─── FAILLE 9 : Injection HTTP Parameter Pollution ────────────────────────────
// GET /api/transfer?amount=100&amount=0.01
// Express prend le dernier, certains middleware prennent le premier
// Contourne des validations de montant, de rôle, de permissions
app.post('/api/transfer', async (req, res) => {
    // Pas de vérification de pollution : req.body.amount peut être un tableau
    const amount = req.body.amount;  // si ["0.01","100000"] → comportement indéterminé
    const toUserId = req.body.to;

    // Pas de vérification que le compte source appartient à l'utilisateur connecté
    await transfer(req.user.id, toUserId, amount);
    res.json({ success: true, amount });
});

// ─── FAILLE 10 : Business logic bypass — prix modifiable côté client ──────────
// L'API accepte le prix final calculé côté client
app.post('/api/checkout', async (req, res) => {
    const { cartId, finalPrice, discountCode } = req.body;
    const cart = await CartModel.findById(cartId);

    // Le prix est fourni par le client — pas de recalcul côté serveur
    // L'attaquant envoie finalPrice=0.01 pour n'importe quel panier
    await Order.create({
        cart: cartId,
        amount: finalPrice,       // prix contrôlé par l'attaquant
        discount: discountCode,
        status: 'pending'
    });

    // Traite le paiement avec le montant fourni par le client
    await processPayment(req.user.stripeId, finalPrice);
    res.json({ success: true, charged: finalPrice });
});

function authenticate(req, res, next) {
    const token = req.headers.authorization?.split(' ')[1];
    try {
        req.user = jwt.verify(token, JWT_SECRET);
        next();
    } catch (e) {
        res.status(401).json({ error: 'Unauthorized' });
    }
}

async function transfer(from, to, amount) { /* stub */ }
async function processPayment(customerId, amount) { /* stub */ }
function generateAuthToken(user) {
    return jwt.sign({ userId: user._id, role: user.role }, JWT_SECRET, { expiresIn: '1h' });
}

const UserModel = mongoose.model('User', new mongoose.Schema({
    username: String, password_hash: String, role: String, isAdmin: Boolean,
    ssn: String, credit_card: String, mfa_secret: String, otp: String, otp_expiry: Number,
    isVerified: Boolean, credit: Number, internal_score: Number, stripe_customer_id: String
}));
const OrderModel  = mongoose.model('Order',  new mongoose.Schema({ owner: String, items: Array, amount: Number }));
const CartModel   = mongoose.model('Cart',   new mongoose.Schema({ items: Array, total: Number }));
const Order       = mongoose.model('Order2', new mongoose.Schema({ cart: String, amount: Number, status: String }));

app.listen(3002);
