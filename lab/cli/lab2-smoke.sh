#!/bin/bash
# Non-interactive replay of 03-lab2-moderne-cli.md, used to verify the lab.
f(){ grep -v "▛\|▌\|▀\|^\s*$" | grep -vE "^\s+[0-9]+% \(" ; }
step(){ echo; echo "######## $* ($(date +%T))"; }
cd /ws
step clone;   mod git sync csv ./repos /lab/repos.csv --with-sources 2>&1 | f | tail -3
step recipes; mod config recipes jar install org.openrewrite:rewrite-java:RELEASE org.openrewrite.recipe:rewrite-java-security:RELEASE org.openrewrite.recipe:rewrite-migrate-java:RELEASE org.openrewrite.recipe:rewrite-static-analysis:RELEASE 2>&1 | f | tail -2
step build;   mod build ./repos 2>&1 | f | grep -E "Built|✗|SUCC|FAIL"
step vuln;    mod run ./repos --recipe org.openrewrite.java.dependencies.DependencyVulnerabilityCheck 2>&1 | f | grep -E "Produced|SUCC|FAIL"
              mod study ./repos --last-recipe-run --data-table VulnerabilityReport 2>&1 | f | tail -2
step find;    mod run ./repos --recipe org.openrewrite.java.search.FindMethods -PmethodPattern="java.sql.Statement execute*(..)" 2>&1 | f | grep -E "Produced|SUCC|FAIL"
              mod study ./repos --last-recipe-run --data-table MethodCalls --json sourceFile,method 2>&1 | grep -c '"sourceFile"'
step java21;  mod run ./repos --recipe org.openrewrite.java.migrate.UpgradeToJava21 2>&1 | f | grep -E "Produced|saved|SUCC|FAIL"
              mod git apply ./repos --last-recipe-run 2>&1 | f | grep -E "Applied|FAIL"
              mod git status ./repos 2>&1 | f | tail -6
step search;  mod search ./repos implements:Serializable 2>&1 | f | grep -E "license|FAIL|SUCC"
step done
