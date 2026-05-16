/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection failles GraphQL
 * Couverture : OWASP A01/A05/A09:2025, OWASP API4/API8:2023, CWE-200, CWE-770
 * NE PAS déployer en production.
 */

const { ApolloServer, gql } = require('@apollo/server');
const { startStandaloneServer } = require('@apollo/server/standalone');
const { GraphQLError } = require('graphql');
const mysql = require('mysql2/promise');
const jwt = require('jsonwebtoken');

const JWT_SECRET = 'graphql-secret-2024';  // secret faible et en dur

const pool = mysql.createPool({ host: 'localhost', user: 'root', password: '', database: 'appdb' });

// ─── FAILLE 1 : Introspection activée en production ──────────────────────────
// Un attaquant peut cartographier tout le schéma GraphQL :
// query { __schema { types { name fields { name type { name } } } } }
// Révèle tous les types, champs, mutations, directives → roadmap d'attaque complète
const typeDefs = gql`
    type Query {
        user(id: ID!): User
        users(filter: UserFilter): [User]
        adminPanel: AdminData
        internalMetrics: Metrics
        searchLogs(query: String): [Log]
    }
    type Mutation {
        deleteUser(id: ID!): Boolean
        updateUserRole(id: ID!, role: String!): User
        createAdminToken: String
    }
    type User {
        id: ID
        username: String
        email: String
        password_hash: String    # champ sensible exposé dans le schéma
        role: String
        ssn: String              # données PII exposées
        credit_card: String      # PCI-DSS
        internal_notes: String   # notes internes exposées
    }
    type AdminData { secret_key: String; db_connection: String }
    type Metrics { query_count: Int; error_details: String }
    type Log { timestamp: String; query: String; user_id: ID; ip: String }
    input UserFilter { username: String; email: String; role: String }
`;

// ─── FAILLE 2 : SQL injection via argument GraphQL ────────────────────────────
// query { user(id: "1 OR 1=1") { username email } }
// query { users(filter: {username: "admin'--"}) { password_hash } }
const resolvers = {
    Query: {
        user: async (_, { id }, context) => {
            // injection SQL directe — id non échappé
            const [rows] = await pool.execute(`SELECT * FROM users WHERE id = ${id}`);
            return rows[0];
        },

        users: async (_, { filter }) => {
            let query = 'SELECT * FROM users WHERE 1=1';
            // concaténation de chaîne directe — injection SQL via filter.username
            if (filter?.username) query += ` AND username LIKE '%${filter.username}%'`;
            if (filter?.email)    query += ` AND email = '${filter.email}'`;
            if (filter?.role)     query += ` AND role = '${filter.role}'`;
            const [rows] = await pool.execute(query);
            return rows;
        },

        // ─── FAILLE 3 : Absence de contrôle d'accès sur les resolvers ────────────
        // Pas de vérification de rôle → n'importe qui peut accéder à adminPanel
        adminPanel: async (_, __, context) => {
            // aucun check context.user.role === 'admin'
            const [rows] = await pool.execute('SELECT secret_key, db_connection FROM admin_config');
            return rows[0];
        },

        // ─── FAILLE 4 : Exposition de logs avec données sensibles ─────────────────
        searchLogs: async (_, { query }) => {
            // 'query' est la chaîne de recherche dans les logs
            // injection SQL + exposition de requêtes SQL internes et IPs
            const [rows] = await pool.execute(
                `SELECT * FROM query_logs WHERE query LIKE '%${query}%' ORDER BY timestamp DESC`
            );
            return rows;  // retourne les requêtes SQL complètes + IPs des utilisateurs
        },

        internalMetrics: async (_, __, context) => {
            // pas d'auth — retourne des métriques internes avec détails d'erreurs SQL
            const [rows] = await pool.execute('SELECT COUNT(*) as cnt, last_error FROM metrics');
            return { query_count: rows[0].cnt, error_details: rows[0].last_error };
        }
    },

    Mutation: {
        // ─── FAILLE 5 : Mutation destructive sans authentification ────────────────
        deleteUser: async (_, { id }, context) => {
            // pas de vérification du token JWT → n'importe qui peut supprimer un user
            await pool.execute(`DELETE FROM users WHERE id = ${id}`);
            return true;
        },

        updateUserRole: async (_, { id, role }, context) => {
            // injection SQL dans role + pas de validation des rôles autorisés
            // mutation { updateUserRole(id: "1", role: "admin") { role } }
            await pool.execute(`UPDATE users SET role = '${role}' WHERE id = ${id}`);
            const [rows] = await pool.execute(`SELECT * FROM users WHERE id = ${id}`);
            return rows[0];
        },

        createAdminToken: async (_, __, context) => {
            // génère un token admin sans aucune vérification d'identité
            return jwt.sign({ userId: 1, role: 'admin' }, JWT_SECRET, { expiresIn: '365d' });
        }
    }
};

// ─── FAILLE 6 : Batching attack — amplification de requêtes ─────────────────
// Un seul POST contenant un tableau de queries → bypass rate limiting
// [{"query":"{ user(id:1) {...} }"},{"query":"{ user(id:2) {...} }"},...]
// 1000 requêtes en un seul appel HTTP → DoS, brute-force de tokens
// Apollo Server active le batching par défaut sans protection
const server = new ApolloServer({
    typeDefs,
    resolvers,
    // introspection: true (défaut en mode production dans certaines versions)
    // pas de limite sur la profondeur des requêtes
    // pas de limite sur la complexité des requêtes
    // pas de désactivation du batching
    formatError: (formattedError, error) => {
        // ─── FAILLE 7 : Stack traces dans les erreurs GraphQL ─────────────────────
        // En production, les stack traces révèlent le code source et les chemins de fichiers
        console.error(error);
        return {
            ...formattedError,
            extensions: {
                ...formattedError.extensions,
                stacktrace: error.stack,          // stack trace exposée
                originalError: error.originalError // erreur originale avec détails SQL
            }
        };
    }
});

// ─── FAILLE 8 : Query depth attack — requêtes récursives ─────────────────────
// GraphQL permet des requêtes infiniment imbriquées par défaut
// { user { friends { friends { friends { friends { ... } } } } } }
// Sans limite de profondeur : parse d'une requête récursive → CPU/RAM épuisés
// Pas de graphql-depth-limit ou graphql-validation-complexity configuré

// ─── FAILLE 9 : Field duplication attack — amplification via fragments ────────
// { user(id:1) { id id id id id id id id id id email email email email ... } }
// Demander 10000 fois le même champ → charge base de données
// Pas de limite sur le nombre de champs par requête

// ─── FAILLE 10 : Authorization bypass via fragments et inline fragments ───────
// Un utilisateur normal peut accéder aux champs admin via fragments
// query { user(id: 1) { ...AdminFields } }
// fragment AdminFields on User { password_hash ssn credit_card internal_notes }
// Sans field-level authorization → les fragments héritent de l'objet parent autorisé
// mais accèdent à des sous-champs qui auraient dû être restreints

startStandaloneServer(server, {
    context: async ({ req }) => {
        const token = req.headers.authorization?.split(' ')[1];
        if (token) {
            try {
                const user = jwt.verify(token, JWT_SECRET);
                return { user };
            } catch (e) {
                // token invalide → contexte user null, mais les resolvers n'y vérifient pas
                return { user: null };
            }
        }
        return { user: null };
    },
    listen: { port: 4000 }
});
