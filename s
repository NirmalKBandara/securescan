[1mdiff --git a/README.md b/README.md[m
[1mindex 7e3f96a..2614e6e 100644[m
[1m--- a/README.md[m
[1m+++ b/README.md[m
[36m@@ -52,14 +52,15 @@[m [mPostgreSQL[m
 [m
 ## Current Status[m
 [m
[31m-The Go scanner engine now runs as an internal HTTP service. It provides a[m
[31m-health check, accepts validated scan jobs, generates UUID job identifiers,[m
[31m-runs scans asynchronously and exposes job status and results through JSON.[m
[31m-Day 3 target safety, port limits and concurrency controls remain enforced.[m
[32m+[m[32mThe Ballerina integration API has also been initialized. It provides a[m
[32m+[m[32mconfigurable HTTP listener, a typed `GET /health` endpoint, consistent public[m
[32m+[m[32mJSON response envelopes, and an automated health endpoint test. Public scan[m
[32m+[m[32mendpoints and Go scanner integration will be added during Days 6–9.[m
 [m
 ## Security Notice[m
 [m
[31m-SecureScan is intended only for systems that the user owns or has explicit permission to test. Unauthorized scanning is prohibited.[m
[32m+[m[32mSecureScan is intended only for systems that the user owns or has explicit permission to test.[m[41m [m
[32m+[m[32mUnauthorized scanning is prohibited.[m
 [m
 ## Roadmap[m
 [m
