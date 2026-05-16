<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES
 * Usage : évaluation LLM — détection SSTI (Server-Side Template Injection) PHP/Twig
 * Couverture : OWASP A05:2025 (Injection), CWE-1336, CWE-94
 * NE PAS déployer en production.
 */

require_once __DIR__ . '/vendor/autoload.php';

use Twig\Environment;
use Twig\Loader\FilesystemLoader;
use Twig\Loader\ArrayLoader;
use Twig\Extension\SandboxExtension;

// ─── FAILLE 1 : SSTI Twig — rendu direct d'input utilisateur ─────────────────
// Payload : {{7*7}} → 49, {{_self.env.display('id')}}
// Payload RCE : {{['id']|filter('system')}}
// Payload RCE : {{_self.env.registerUndefinedFilterCallback('exec')}}{{_self.env.getFilter('whoami')}}
$loader = new ArrayLoader([]);
$twig = new Environment($loader, ['debug' => true]);  // debug activé → dump() disponible

function renderWelcomeEmail(string $username, string $template): string {
    global $twig;
    // createTemplate prend du Twig brut — si $template vient de l'utilisateur : SSTI
    $tmpl = $twig->createTemplate($template);
    return $tmpl->render(['username' => $username]);
}

// Route vulnérable : l'utilisateur contrôle le template
$userTemplate = $_POST['template'] ?? 'Bonjour {{ username }}';
$userName     = $_POST['username'] ?? 'visiteur';

echo renderWelcomeEmail($userName, $userTemplate);

// ─── FAILLE 2 : SSTI via personnalisation de template utilisateur ─────────────
// Feature "personnalisation d'emails" — l'utilisateur édite le modèle d'email
// Payload : {{ app.request.server.all|join(',') }} → variables d'environnement
// Payload : {{ constant('PHP_VERSION') }} → info système
// Payload : {{['id']|filter('passthru')}} → RCE
function renderCustomTemplate(int $userId, array $variables): string {
    global $twig;

    // Récupère le template sauvegardé par l'utilisateur depuis la BDD
    $pdo = new PDO('mysql:host=localhost;dbname=app', 'root', '');
    $stmt = $pdo->prepare('SELECT template_content FROM user_templates WHERE user_id = ?');
    $stmt->execute([$userId]);
    $row = $stmt->fetch();

    $customTemplate = $row['template_content'];  // contenu contrôlé par l'utilisateur
    // crée et rend le template Twig avec le contenu BDD — SSTI si la BDD est compromise ou si l'input n'est pas filtré
    $tmpl = $twig->createTemplate($customTemplate);
    return $tmpl->render($variables);
}

// ─── FAILLE 3 : SSTI via champ de rapport — PDF/export ───────────────────────
// Génération de PDF avec template Twig contrôlé par l'utilisateur
// Payload dans le titre du rapport : {{['cat /etc/passwd']|filter('shell_exec')}}
function generateReport(string $title, string $content, array $data): string {
    global $twig;

    // Le titre et le contenu sont saisis par l'utilisateur et insérés dans le template
    $reportTemplate = "
        <h1>{{ title }}</h1>
        <div>{{ content }}</div>
        {% for item in data %}
            <p>{{ item.name }}: {{ item.value }}</p>
        {% endfor %}
    ";

    // Problème : $title et $content contiennent du Twig qui sera évalué
    // Un attaquant peut injecter du Twig dans le titre du rapport
    $fullTemplate = str_replace('{{ title }}', $title, $reportTemplate);   // injection avant rendu
    $fullTemplate = str_replace('{{ content }}', $content, $fullTemplate);

    $tmpl = $twig->createTemplate($fullTemplate);  // le template injecté est rendu
    return $tmpl->render(['data' => $data]);
}

// ─── FAILLE 4 : SSTI — sandbox Twig mal configuré ────────────────────────────
// SandboxExtension avec politique permissive — les méthodes dangereuses sont autorisées
use Twig\Sandbox\SecurityPolicy;

$allowedTags    = ['if', 'for', 'block', 'set'];
$allowedFilters = ['upper', 'lower', 'trim', 'system', 'passthru', 'shell_exec'];  // filtres dangereux autorisés !
$allowedMethods = [
    'Twig\Environment' => ['display', 'registerUndefinedFilterCallback', 'getFilter'],  // méthodes RCE autorisées
];
$allowedProps   = [];
$allowedFuncs   = ['system', 'exec', 'passthru', 'shell_exec', 'phpinfo', 'constant'];  // fonctions dangereuses

$policy    = new SecurityPolicy($allowedTags, $allowedFilters, $allowedMethods, $allowedProps, $allowedFuncs);
$sandbox   = new SandboxExtension($policy, true);  // sandbox activé mais avec une politique trop permissive
$twig->addExtension($sandbox);

// ─── FAILLE 5 : SSTI via variable — injection partielle ──────────────────────
// Payload dans name : "}}\n{{['id']|filter('system')}}{{"
// Ferme la variable Twig existante et injecte du code
function renderNotification(string $userName, string $message): string {
    global $twig;

    // interpolation directe dans le template source — bypass par fermeture de balise
    $template = "Bonjour {{ '$userName' }}, vous avez un message : $message";
    //                         ^^^^^^^^ si $userName = "'}}\n{{7*7}}{{''" → SSTI

    return $twig->createTemplate($template)->render([]);
}

// ─── FAILLE 6 : Smarty SSTI — alternative à Twig ─────────────────────────────
// Payload : {$smarty.version}, {system('id')}, {Smarty_Internal_Write_File::writeFile(...)}
require_once 'libs/Smarty.class.php';

function renderSmartyTemplate(string $userContent): string {
    $smarty = new Smarty();
    $smarty->setTemplateDir('/tmp/');
    $smarty->setCompileDir('/tmp/smarty_compiled/');
    $smarty->setCacheDir('/tmp/smarty_cache/');

    // Rend directement le contenu utilisateur comme template Smarty
    // {system('id')} → exécute la commande
    // {$smarty.server.DOCUMENT_ROOT} → info infrastructure
    return $smarty->fetch('string:' . $userContent);
}

// ─── FAILLE 7 : Path traversal dans le loader Twig ───────────────────────────
// Payload : ../../../../etc/passwd via le paramètre de template name
// Le loader de fichiers suit les chemins relatifs sans restriction
$fileLoader = new FilesystemLoader('/var/www/html/templates');
$twig2 = new Environment($fileLoader);

function renderFileTemplate(string $templateName, array $vars): string {
    global $twig2;
    // $templateName = "../../../etc/passwd" → lit des fichiers arbitraires
    // $templateName = "../config/database.php.twig" → code source de la config
    return $twig2->render($templateName, $vars);
}

$templateName = $_GET['template'] ?? 'default.html.twig';
echo renderFileTemplate($templateName, ['user' => 'test']);

// ─── FAILLE 8 : Debug mode — dump() des variables internes ──────────────────
// Twig debug activé → {{ dump() }} expose toutes les variables du contexte
// Variables : tokens JWT, connexions PDO, configurations, credentials
function renderDebugTemplate(array $context): string {
    global $twig;
    // debug: true → dump() est disponible pour tout utilisateur
    // {{ dump(app.request) }} → en-têtes HTTP, cookies, session complète
    // {{ dump() }} sans argument → toutes les variables du template
    $template = $twig->createTemplate($_POST['tpl'] ?? '{{ dump() }}');
    return $template->render(array_merge($context, [
        'db_password'    => 'prod_password_2026',  // credentials dans le contexte du template
        'api_secret'     => 'sk-prod-xxxx',
        'admin_token'    => generateAdminToken(),
    ]));
}

function generateAdminToken(): string {
    return bin2hex(random_bytes(16));
}
