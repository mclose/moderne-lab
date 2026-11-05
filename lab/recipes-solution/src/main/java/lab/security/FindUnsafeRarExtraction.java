package lab.security;

import org.openrewrite.ExecutionContext;
import org.openrewrite.Recipe;
import org.openrewrite.TreeVisitor;
import org.openrewrite.java.JavaIsoVisitor;
import org.openrewrite.java.MethodMatcher;
import org.openrewrite.java.tree.J;
import org.openrewrite.marker.SearchResult;

/**
 * Reference solution for Lab 5. Marks every call to junrar's archive extraction API,
 * the sink for CVE-2026-28208 (path traversal). A search recipe: it changes nothing,
 * it just marks call sites so a human or an agent can review them.
 */
public class FindUnsafeRarExtraction extends Recipe {

    private static final MethodMatcher EXTRACT = new MethodMatcher("com.github.junrar.Junrar extract(..)");

    @Override
    public String getDisplayName() {
        return "Find RAR extraction call sites (CVE-2026-28208 sink)";
    }

    @Override
    public String getDescription() {
        return "Marks calls to `Junrar.extract(..)`. Versions below 7.5.8 allow path traversal (CVE-2026-28208); "
               + "even patched, extracting untrusted archives deserves review.";
    }

    @Override
    public TreeVisitor<?, ExecutionContext> getVisitor() {
        return new JavaIsoVisitor<ExecutionContext>() {
            @Override
            public J.MethodInvocation visitMethodInvocation(J.MethodInvocation method, ExecutionContext ctx) {
                J.MethodInvocation m = super.visitMethodInvocation(method, ctx);
                if (EXTRACT.matches(m)) {
                    return SearchResult.found(m, "RAR extraction: check archive source and junrar >= 7.5.10");
                }
                return m;
            }
        };
    }
}
