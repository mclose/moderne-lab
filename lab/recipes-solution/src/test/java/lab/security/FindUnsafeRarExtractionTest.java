package lab.security;

import org.junit.jupiter.api.Test;
import org.openrewrite.java.JavaParser;
import org.openrewrite.test.RecipeSpec;
import org.openrewrite.test.RewriteTest;

import static org.openrewrite.java.Assertions.java;

class FindUnsafeRarExtractionTest implements RewriteTest {

    @Override
    public void defaults(RecipeSpec spec) {
        spec.recipe(new FindUnsafeRarExtraction())
          .parser(JavaParser.fromJavaVersion().classpath("junrar"));
    }

    @Test
    void marksExtract() {
        rewriteRun(
          java(
            """
              import com.github.junrar.Junrar;
              import java.io.File;
              class Unpack {
                  void go(String a, String b) throws Exception {
                      Junrar.extract(new File(a), new File(b));
                  }
              }
              """,
            """
              import com.github.junrar.Junrar;
              import java.io.File;
              class Unpack {
                  void go(String a, String b) throws Exception {
                      /*~~(RAR extraction: check archive source and junrar >= 7.5.10)~~>*/Junrar.extract(new File(a), new File(b));
                  }
              }
              """
          )
        );
    }

    @Test
    void ignoresLookalikeMethod() {
        // Same method name on a different type: a regex would flag this, a type-aware recipe doesn't.
        rewriteRun(
          java(
            """
              class Junrar {
                  static void extract(java.io.File a, java.io.File b) {}
              }
              class Other {
                  void go() { Junrar.extract(null, null); }
              }
              """
          )
        );
    }
}
