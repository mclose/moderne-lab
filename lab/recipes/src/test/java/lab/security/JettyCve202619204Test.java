package lab.security;

import org.junit.jupiter.api.Test;
import org.openrewrite.test.RecipeSpec;
import org.openrewrite.test.RewriteTest;

import static org.assertj.core.api.Assertions.assertThat;
import static org.openrewrite.maven.Assertions.pomXml;

class JettyCve202619204Test implements RewriteTest {

    @Override
    public void defaults(RecipeSpec spec) {
        spec.recipeFromResources("lab.security.JettyCve202619204");
    }

    @Test
    void upgradesVulnerableJetty121() {
        rewriteRun(
          pomXml(
            pom("12.1.11"),
            // "12.1.x" resolves to the newest patch on Maven Central, so assert the floor, not an exact version.
            spec -> spec.after(actual -> {
                String v = actual.replaceAll("(?s).*<version>(12\\.1\\.\\d+)</version>.*", "$1");
                assertThat(Integer.parseInt(v.substring("12.1.".length()))).isGreaterThanOrEqualTo(12);
                return actual;
            })
          )
        );
    }

    @Test
    void cannotFixJetty11() {
        // Jetty 11's fix (11.0.32) is commercial-only; Maven Central stops at 11.0.26.
        // The recipe must not "fix" this by jumping majors: no change expected.
        rewriteRun(pomXml(pom("11.0.26").replace("jetty-websocket-core-common", "websocket-core-common")));
    }

    private static String pom(String jettyVersion) {
        return """
          <project>
            <groupId>lab</groupId>
            <artifactId>demo</artifactId>
            <version>1</version>
            <dependencies>
              <dependency>
                <groupId>org.eclipse.jetty.websocket</groupId>
                <artifactId>jetty-websocket-core-common</artifactId>
                <version>%s</version>
              </dependency>
            </dependencies>
          </project>
          """.formatted(jettyVersion);
    }
}
