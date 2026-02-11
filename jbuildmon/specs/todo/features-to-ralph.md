
# features

## future version - more complicated - needs more detailed spec
buildgit log
- show git log with build status matched to each git commit

all commands:
- new verbose option -vv --debug to show the verbose steps.  things like connecting to jenkins, finding job name, etc.

## total time for build
- at the end of the build it should say:
Elapsed: 3m 42s  or whatever time it took


buildgit push AND buildgit build should also show a brief summary of the last build job.  Things like:
- how long did each stage take?
- how many tests passed? skipped? failed?
- overall success/fail


commit repo to github then make sure skill install works like this:

npx skills add https://github.com/gclayburg/buildgit --skill buildgit
npx skills add https://github.com/gclayburg/buildgit/tree/main/jbuildmon/buildgit --skill buildgit


--json flag should mean no other ouput like status messages or 'git status' of any kind (LLMs need to use this and parse the result with tools)

./buildgit --verbose status --json