package lab;

import com.github.junrar.Junrar;

import java.io.File;

public class Unpack {
    public static void main(String[] args) throws Exception {
        // Extracting an untrusted archive: exactly the CVE-2026-28208 path traversal sink.
        Junrar.extract(new File(args[0]), new File(args[1]));
    }
}
