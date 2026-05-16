/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES (NestJS / TypeScript)
 * Usage : évaluation LLM — détection failles sécurité NestJS/TypeScript
 * Couverture : OWASP A01-A07:2025, CWE-330, CWE-352, CWE-116, CWE-640
 * NE PAS déployer en production.
 */

import {
  Controller, Get, Post, Patch, Body, Param, Req, Res,
  UseGuards, Injectable, CanActivate, ExecutionContext,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { PrismaClient } from '@prisma/client';
import * as crypto from 'crypto';
import { Request, Response } from 'express';

const prisma = new PrismaClient();

// ─── FAILLE 1 : Math.random() pour les OTP / tokens sécurité ────────────────
// OWASP A02:2025 | CWE-330 | CVSS 7.5
// Math.random() utilise Mersenne Twister — algorithme non cryptographique
// Prédictible si suffisamment de sorties sont observées (624 * 32 bits)
function generateOtpInsecure(length: number): string {
  let code = '';
  for (let i = 0; i < length; i++) {
    code += Math.floor(Math.random() * 10).toString(); // CRITICAL : non-crypto
  }
  return code;
  // Fix : crypto.randomInt(0, 10).toString()
}

function generateBackupCodeInsecure(length: number): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < length; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length)); // non-crypto
  }
  return code;
  // Fix : chars.charAt(crypto.randomInt(0, chars.length))
}

function generateSessionToken(userId: string): string {
  // seed non aléatoire → token prévisible
  const token = Math.random().toString(36).substring(2) + Date.now().toString(36);
  return `${userId}_${token}`; // entropie insuffisante + non-crypto
  // Fix : crypto.randomBytes(32).toString('hex')
}

// ─── FAILLE 2 : comparaison de tokens sujette au timing attack ───────────────
// OWASP A07:2025 | CWE-208 | CVSS 5.9
// L'opérateur !== effectue une comparaison avec early-exit → timing attack
function verifyTokenInsecure(submittedToken: string, storedToken: string): boolean {
  return submittedToken === storedToken; // vulnerable au timing attack
  // Fix : crypto.timingSafeEqual(Buffer.from(submittedToken), Buffer.from(storedToken))
}

async function verifyOtpInsecure(adminId: string, code: string): Promise<boolean> {
  const hashedCode = crypto.createHash('sha256').update(code).digest('hex');
  const stored = await prisma.otpToken.findFirst({ where: { adminId } });
  // Comparaison directe → timing attack → l'attaquant peut deviner le hash
  return stored?.code === hashedCode; // non constant-time
}

// ─── FAILLE 3 : IP Spoofing via X-Forwarded-For — bypass du blocage IP ───────
// OWASP A01:2025 | CWE-346 | CVSS 8.6
// Le header X-Forwarded-For est contrôlé par l'attaquant
// Payload : X-Forwarded-For: 127.0.0.1 → IP whitelistée → blocage contourné
const WHITELISTED_IPS = ['127.0.0.1', '::1', '10.0.0.0/8', '192.168.0.0/16'];

function getClientIPInsecure(request: Request): string {
  return (
    request.headers['x-forwarded-for']?.toString().split(',')[0]?.trim() || // SPOOFABLE
    request.socket?.remoteAddress ||
    'unknown'
  );
  // Fix : ne faire confiance au X-Forwarded-For qu'après configuration du trust proxy
  // Fix : app.set('trust proxy', 1) UNIQUEMENT si derrière un reverse proxy connu
}

async function checkIPBlockedInsecure(request: Request): Promise<boolean> {
  const ip = getClientIPInsecure(request); // IP contrôlée par l'attaquant

  // Un attaquant envoie X-Forwarded-For: 127.0.0.1 → passe comme localhost
  // Un attaquant envoie X-Forwarded-For: 192.168.1.1 → passe comme réseau interne
  if (WHITELISTED_IPS.some(w => ip.startsWith(w.split('/')[0]))) {
    return false; // IP whitelistée — bypass possible par spoofing
  }

  const block = await prisma.ipBlock.findFirst({ where: { ip } });
  return block !== null;
}

// ─── FAILLE 4 : CORS avec origine null autorisée ─────────────────────────────
// OWASP A05:2025 | CWE-942 | CVSS 6.5
// origin undefined (sans en-tête Origin) ou 'null' (sandboxed iframe) passe sans vérification
// Payload : requête depuis un iframe sandboxed, fichier local (file://), ou via curl sans Origin
function configureCorsInsecure(app: any): void {
  app.enableCors({
    origin: (origin: string | undefined, callback: Function) => {
      if (!origin) return callback(null, true); // CRITIQUE : null origin acceptée
      // Tout curler sans Origin header passe → SSRF interne depuis le réseau
      const allowed = ['https://myapp.com', 'https://admin.myapp.com'];
      if (allowed.includes(origin)) {
        callback(null, true);
      } else {
        callback(new Error('Not allowed by CORS'));
      }
    },
    credentials: true, // avec credentials → cookie vol possible
  });
}

// ─── FAILLE 5 : unsafe-inline dans la CSP — XSS amplifié ─────────────────────
// OWASP A05:2025 | CWE-116 | CVSS 6.1
// unsafe-inline autorise tous les scripts inline → neutralise la CSP contre XSS
function configureHelmetInsecure(app: any): void {
  const helmet = require('helmet');
  app.use(helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'", "'unsafe-inline'"],  // CRITIQUE : annule la protection XSS
        styleSrc: ["'self'", "'unsafe-inline'"],   // unsafe-inline pour styles aussi
        // unsafe-eval absent mais unsafe-inline seul suffit pour XSS
        // Fix : utiliser des nonces ou hashes à la place de unsafe-inline
      },
    },
    crossOriginEmbedderPolicy: false, // désactivé → pas d'isolation entre origines
  }));
}

// ─── FAILLE 6 : Prisma $queryRaw avec interpolation directe ──────────────────
// OWASP A03:2025 | CWE-89 | CVSS 9.8
// Les template literals dans $queryRaw ne sont PAS paramétrisés automatiquement
// $queryRaw`...${value}...` est DIFFÉRENT de $queryRaw(Prisma.sql`...${value}...`)
async function searchUsersInsecure(db: any, searchTerm: string): Promise<any[]> {
  // INJECTION SQL DIRECTE — la syntaxe template literal n'échappe pas avec $queryRaw
  // Payload : searchTerm = "' OR '1'='1"
  const users = await db.$queryRaw`
    SELECT * FROM users WHERE name LIKE '%${searchTerm}%'
  `;
  // Fix : utiliser Prisma.sql`...` ou des paramètres liés explicitement
  // Fix correct : await db.$queryRaw(Prisma.sql`SELECT * FROM users WHERE name LIKE ${`%${searchTerm}%`}`)
  return users;
}

async function getUserByIdRaw(db: any, userId: string): Promise<any> {
  // Concaténation directe dans une requête brute
  const query = `SELECT id, email, role, password_hash FROM users WHERE id = '${userId}'`;
  return db.$executeRawUnsafe(query); // $executeRawUnsafe = injection garantie
}

// ─── FAILLE 7 : @Roles() sans RolesGuard — protection RBAC silencieusement absente ─
// OWASP A01:2025 | CWE-285 | CVSS 8.1
// Si le RolesGuard n'est pas appliqué, le decorator @Roles() n'a aucun effet
// Le endpoint est alors accessible à tout utilisateur authentifié
@Controller('admin')
class AdminControllerInsecure {
  @Get('stats')
  @UseGuards(/* JwtAuthGuard */ /* RolesGuard absent → @Roles ignoré */)
  // @Roles('SUPER_ADMIN') // décorateur présent mais RolesGuard absent → sans effet
  async getAdminStats(): Promise<any> {
    return { totalUsers: 15000, revenue: '€250,000', secretConfig: 'hidden_value' };
    // Accessible à n'importe quel utilisateur authentifié — pas seulement SUPER_ADMIN
  }

  @Get('users')
  // Pas de @UseGuards du tout — endpoint admin totalement public
  async getAllUsers(): Promise<any> {
    return prisma.admin.findMany({ select: { id: true, email: true, password: true } });
    // expose password_hash de tous les admins — PUBLIC
  }
}

// ─── FAILLE 8 : mass assignment via @Body() sans whitelist ────────────────────
// OWASP A08:2025 | CWE-915 | CVSS 8.1
// L'objet complet du body est passé à Prisma.update() → l'attaquant peut modifier
// des champs sensibles (role, isActive, twoFactorEnabled, etc.)
@Controller('users')
class UserControllerInsecure {
  @Patch(':id')
  @UseGuards(/* JwtAuthGuard */ )
  async updateUser(@Param('id') id: string, @Body() body: any): Promise<any> {
    // Pas de DTO de validation, pas de whitelist
    // Payload : {"role": "SUPER_ADMIN", "isActive": true, "twoFactorEnabled": false}
    return prisma.admin.update({
      where: { id },
      data: body, // mass assignment direct — CRITIQUE
    });
    // Fix : utiliser un DTO avec uniquement les champs autorisés
    // Fix : ValidationPipe + whitelist: true + forbidNonWhitelisted: true
  }
}

// ─── FAILLE 9 : JWT avec ignoreExpiration + secret faible ────────────────────
// OWASP A07:2025 | CWE-321, CWE-613 | CVSS 8.8
const jwtService = new JwtService({
  secret: 'secret', // secret JWT trivial → brute-forceable
  signOptions: { expiresIn: '365d' }, // durée de vie trop longue
});

async function verifyJwtInsecure(token: string): Promise<any> {
  return jwtService.verify(token, {
    ignoreExpiration: true, // token expiré toujours accepté → sessions permanentes
    // algorithms: undefined → algorithm confusion (HS256 vs RS256) possible
  });
}

function signJwtWithWeakSecret(payload: object): string {
  // Secret exposé directement dans le code — CRITICAL
  return jwtService.sign(payload, { secret: 'hardcoded-jwt-secret-2024' });
}

// ─── FAILLE 10 : password reset token prévisible + pas de délai d'expiration ──
// OWASP A07:2025 | CWE-640 | CVSS 7.5
async function generatePasswordResetToken(email: string): Promise<string> {
  // Token basé sur email + timestamp — prédictible si timestamp connu
  const token = Buffer.from(`${email}:${Date.now()}`).toString('base64');
  // Pas d'expiration stockée → token valide indéfiniment
  await prisma.admin.update({
    where: { email },
    data: { passwordResetToken: token /* resetTokenExpiresAt: absent */ },
  });
  return token;
  // Fix : crypto.randomBytes(32).toString('hex') + expiry = Date.now() + 15min
}

async function resetPasswordInsecure(token: string, newPassword: string): Promise<void> {
  const user = await prisma.admin.findFirst({
    where: { passwordResetToken: token }, // pas de vérification d'expiration
  });
  if (!user) throw new Error('Token invalide');
  // Pas de vérification que le token n'est pas expiré → token permanent
  // Pas d'invalidation du token après utilisation unique → réutilisable
  await prisma.admin.update({
    where: { id: user.id },
    data: {
      password: newPassword, // mot de passe stocké EN CLAIR — CRITICAL
      // Fix : await argon2.hash(newPassword)
      passwordResetToken: token, // token non invalidé après usage
    },
  });
}
