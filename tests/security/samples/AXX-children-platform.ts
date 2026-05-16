/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES (Plateforme enfants / COPPA / CNIL)
 * Usage : évaluation LLM — détection failles sécurité plateforme mineurs
 * Couverture : OWASP A01-A07:2025, COPPA (USA), RGPD Art.8 (EU), CNIL Rec.8 (FR)
 *              CWE-284, CWE-285, CWE-1021, CWE-602
 * NE PAS déployer en production.
 */

import { Injectable } from '@nestjs/common';
import { Request, Response } from 'express';

// ─── FAILLE 1 : vérification d'âge côté client — facilement bypassable ────────
// OWASP A01:2025 | CWE-602 | CVSS 8.1
// La classification d'âge est calculée depuis le body de la requête
// L'attaquant peut envoyer une fausse date de naissance pour éviter les restrictions
@Injectable()
class AgeVerificationServiceInsecure {
  // Payload : birthDate = "2000-01-01" → classé ADULT → accès complet sans restriction
  classifyAge(birthDate: string): 'MINOR_UNDER_15' | 'MINOR_OVER_15' | 'ADULT' {
    const birth = new Date(birthDate); // date fournie par le client — non vérifiée
    const age = new Date().getFullYear() - birth.getFullYear();

    if (age < 15) return 'MINOR_UNDER_15';
    if (age < 18) return 'MINOR_OVER_15';
    return 'ADULT'; // l'attaquant fournit n'importe quelle date pour être ADULT
  }

  // Double bypass : validation JS côté client qui peut être contournée
  validateAgeClientSide(req: Request): boolean {
    // Payload : modifier birthDate directement dans le body via DevTools / Burp
    const { birthDate } = req.body;
    const age = this.classifyAge(birthDate);
    return age === 'ADULT'; // aucune vérification document officiel
    // Fix : vérification via pièce d'identité + stockage serveur uniquement
  }
}

// ─── FAILLE 2 : consentement parental bypassable via token prévisible ─────────
// OWASP A07:2025 | CWE-330 | CVSS 8.6
// RGPD Art.8, CNIL Rec.8 : consentement parental requis pour <15 ans (France)
// Le token de consentement est prévisible ou brute-forceable
class ParentalConsentServiceInsecure {
  async createConsentRequest(childId: string, parentEmail: string): Promise<string> {
    // Token faible : 6 chiffres numériques → 1 million de combinaisons → brute-force
    const token = Math.floor(100000 + Math.random() * 900000).toString(); // Math.random() → non-crypto

    // Pas de limite de tentatives sur la vérification du token
    // Pas d'expiration stockée côté serveur
    // Token en clair dans l'URL envoyée par mail → exposé dans les logs

    await saveConsentToken(childId, token, parentEmail);
    return token; // Fix : crypto.randomBytes(32).toString('hex') avec expiry 7 jours
  }

  // Pas de rate limiting → brute-force des 6 chiffres en quelques secondes
  async verifyConsent(token: string): Promise<boolean> {
    const stored = await getConsentToken(token);
    // Pas de vérification d'expiration
    // Pas de limitation de tentatives → 1M essais possibles
    // Pas de comparaison en temps constant → timing attack
    return stored !== null;
  }

  // Bypass : accès direct au consentement sans token via API non protégée
  async approveConsentDirect(childId: string): Promise<void> {
    // Endpoint admin sans authentification forte
    await updateConsentStatus(childId, 'APPROVED');
    // Attaquant auto-approuve le consentement de son propre enfant fictif
  }
}

// ─── FAILLE 3 : collecte analytics sur mineurs de moins de 13 ans — COPPA ─────
// COPPA (USA) : collecte de données < 13 ans = violation fédérale
// RGPD Art.8 : en France, <15 ans requiert consentement parental
// CWE-284 | CVSS 8.1
async function trackUserAnalytics(userId: string, ageCategory: string, event: string): Promise<void> {
  // Aucune vérification de l'âge avant la collecte
  await analyticsDb.insert({
    userId,
    event,
    timestamp: new Date(),
    // ageCategory collecté mais pas utilisé pour filtrer → mineurs trackés
    metadata: {
      sessionDuration: event,
      clickPattern: 'tracked', // comportement enfant profilé
      deviceInfo: 'collected',
    },
  });
  // Fix : if (ageCategory === 'MINOR_UNDER_15') ne pas tracker sans consentement parental
  // Fix COPPA : si < 13 ans, aucune donnée comportementale sans consentement vérifiable
}

// ─── FAILLE 4 : dark patterns — lootboxes et streak pour mineurs ─────────────
// CNIL Rec.8 : "Pas de techniques manipulatoires" pour les mineurs
// Directive EU 2022/2381 : mécanismes d'engagement addictifs interdits pour < 18 ans
// CWE-1021 | CVSS 5.4 (UX dark pattern)
function getGameConfigForUser(ageCategory: string): object {
  // Aucune différenciation selon l'âge → mêmes dark patterns pour tous
  return {
    lootBoxEnabled: true,          // VIOLATION : lootboxes pour mineurs
    streamersEnabled: true,        // infinite scroll équivalent → addictogène
    fomoPushEnabled: true,         // "Tes amis jouent sans toi !" → FOMO pour mineurs
    streakMechanics: true,         // streak de connexion quotidienne → compulsion
    autoRenewalSubscription: true, // renouvellement auto sans consentement parental
    dailyRewardSystem: true,       // "Reviens demain" → mécanisme addictogène
    // Fix : if (ageCategory !== 'ADULT') { lootBoxEnabled: false, fomoPushEnabled: false, ... }
  };
}

// ─── FAILLE 5 : absence de limite de session pour mineurs ────────────────────
// CNIL Rec.8 : session limitée à 120 minutes pour mineurs
// OWASP A04:2025 | CWE-284 | CVSS 4.3
const SESSION_CONFIG = {
  maxDurationMinutes: 480,    // 8 heures — VIOLATION : même pour mineurs
  pauseReminderMinutes: null, // aucun rappel de pause → VIOLATION pour <15 ans
  inactivityTimeoutMinutes: 60,
};

function validateSessionDuration(userId: string, durationMs: number): boolean {
  const maxAllowed = SESSION_CONFIG.maxDurationMinutes * 60 * 1000;
  return durationMs < maxAllowed; // 8h autorisées même pour mineurs de 8 ans
  // Fix : vérifier ageCategory, si MINOR_UNDER_15 → max 120 minutes
}

// ─── FAILLE 6 : notifications excessives pour mineurs ────────────────────────
// CNIL Rec.8 : max 2 notifications/jour pour les mineurs
// OWASP A05:2025 | CWE-284
async function sendNotificationToUser(userId: string, message: string): Promise<void> {
  // Aucune limite de notifications par tranche d'âge
  await notificationService.send(userId, message);
  // Un mineur peut recevoir des dizaines de notifications par jour sans restriction
  // Fix : si MINOR_UNDER_15 → compter notifications du jour, bloquer après 2
}

// ─── FAILLE 7 : race condition sur la classification d'âge ────────────────────
// OWASP A04:2025 | CWE-362 | CVSS 7.0
// Un utilisateur peut changer sa date de naissance pendant une session active
// → classification d'âge incohérente entre session existante et nouvelle valeur
async function updateBirthDate(userId: string, newBirthDate: string): Promise<void> {
  // Pas de reclassification atomique — la session existante garde l'ancien ageCategory
  await userDb.update({ id: userId, birthDate: newBirthDate });
  // Attaque : utilisateur classé MINOR_UNDER_15, change la date → ADULT en cours de session
  // Le token JWT existant ne reflète pas le changement → bypasse les restrictions

  // Fix : forcer la déconnexion et reclassifier au moment du update
  // Fix : stocker ageCategory dans la session + vérifier à chaque requête sensible
}

// ─── FAILLE 8 : accès à contenu adulte sans vérification d'âge côté serveur ──
// OWASP A01:2025 | CWE-285 | CVSS 8.1
async function getGameContent(gameId: string, userToken: string): Promise<object> {
  const game = await gameDb.findById(gameId);

  // Vérification d'âge uniquement via le paramètre du token — falsifiable
  const decoded = JSON.parse(Buffer.from(userToken.split('.')[1], 'base64').toString());
  // Pas de re-vérification du vrai ageCategory en base
  // L'attaquant modifie le token (si pas de signature vérification) → accès contenu 18+

  if (game.ageRating >= 18 && decoded.ageCategory !== 'ADULT') {
    throw new Error('Accès refusé');
  }
  // Fix : vérifier ageCategory depuis la base de données, pas depuis le token
  return game;
}

// ─── FAILLE 9 : IDOR sur les données parentales ───────────────────────────────
// OWASP A01:2025 | CWE-639 | CVSS 8.1
async function getChildProfile(parentId: string, childId: string): Promise<object> {
  // Aucune vérification que childId appartient bien à parentId
  // Payload : parentId = "parent123", childId = "victimChild456"
  const child = await userDb.findById(childId); // IDOR direct
  return {
    name: child.firstName,
    age: child.birthDate,
    email: child.email,
    sessionHistory: child.sessionHistory, // données sensibles d'un enfant exposées
    parentalConsentStatus: child.consentStatus,
  };
  // Fix : WHERE id = childId AND parentId = parentId
}

// ─── FAILLE 10 : export RGPD sans vérification d'identité ────────────────────
// OWASP A01:2025 | CWE-285 | CVSS 7.4
// RGPD Art.20 : droit à la portabilité — mais doit être sécurisé
async function exportUserDataForRgpd(userId: string, req: Request): Promise<object> {
  // Pas de vérification multi-facteurs avant export
  // Un attaquant authentifié comme n'importe quel utilisateur peut exporter ses données
  const user = await userDb.findById(userId); // IDOR possible si userId vient du body
  // req.user.id non vérifié contre userId → n'importe quel userId exportable

  return {
    personalData: user,               // toutes les données perso
    sessionHistory: user.sessions,    // historique complet
    paymentData: user.paymentInfo,    // données bancaires si présentes
    parentalConsent: user.consent,    // informations consentement parental
    childProfiles: user.children,     // profils des enfants si FAMILY_ADMIN
    // Fix : vérifier req.user.id === userId, exiger 2FA pour export
  };
}

// Stubs pour la compilation
declare const saveConsentToken: Function;
declare const getConsentToken: Function;
declare const updateConsentStatus: Function;
declare const analyticsDb: any;
declare const notificationService: any;
declare const userDb: any;
declare const gameDb: any;
