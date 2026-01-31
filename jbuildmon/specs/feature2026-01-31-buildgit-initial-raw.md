# buildgit

create combined bash script called buildgit

buildgit is a bash shell script that will combine functionality from the regular git executable and selected functionality from our bash scripts checkbuild.sh, pushmon.sh and jenkins-common.sh.  
This would closely mirror what the git  does, but also assume this git repo is tied to a jenkins job that we can also control and monitor much like checkbuild.sh does now.


## example buildgit usage
- buildgit is normally invoked with a command such as status, push, or build.  

buildgit status

This is a combined status report of git and the jenkins build.  We want to show the current state of our local repository with 'git status' and the overal state of
the jenkins build, similar to checkbuild.sh
- show output of 'git status'
- show output identical to what 'checkbuild.sh' does 

buildgit --job visualsync status
- show the git status of the current directory as well as the visualsync job. See checkbuild.sh for the --job argument implementation.

buildgit --job visualsync status --json
- this is the same as 'buildgit --job visualsync status' with the additional constraint that the output will be displayed as JSON format, just like checkbuild.sh does
- note here '--job visualsync' is a direct option to buildgit and will apply to any command such as status or push or build. 
- The --json argument only applies to the status command of buildgit

buildgit status -f
- show all of "buildgit status" but also follow a build if it is currently in progres OR wait until the next build starts.  once the build starts, it should monitor the build and report on its progress, just like pushmon.sh does now.  Since the -f option is used, the script should also keep waiting for the next build once the build completes.  The console should say "Waiting for next build of <job>..."

buildgit status -s
- the -s option is a git option so it would be passed to the regular git command to produce a status in a short form

The overall goal here is to have some options to the status comand that are interpreted directly by buildgit command, like -f (--follow).  Any unrecognized options are passed directly to the git command, like the -s (--short) git option

buildgit push
- essentially does what ./pushmon.sh does now if there is a committed change not yet pushed
- also honor all git push flags.  if buildgit itself doesn't understand the flag, pass it to git
- does not try to commit AND push.  That is too many concerns at once.  Instead the user is expected to do this to get that kind of behavior:
  - git commit -m 'new thing' && buildgit push


buildgit push origin featurebranch
- do the same thing that 'buildgit push' does but also pass the extra arguments of 'origin featurebranch' to the git command

buildgit build
- this will force a build for the job. This should behave very similar to what would happen if a user pressed the 'build now' button in Jenkins.  Just schedule a build start.  However, this script will also watch the build being started and report its progress, just like pushmon.sh does today.
- one a build has finished the script will finish

## options
buildgit will take options similar to what pushmon.sh and checkbuild.sh do today at the root level
- also honors these options just like pushmon.sh does: -j,--job, -h, --help
- For example 
  - buildgit --job visualsync build
  - buildgit --help

## notes
- If buildgit is used in a directory that is not a git directory, The git command that buildgit calls will likely produce an output to stderr and return with a non-zero exit code.  This message needs to be printed and buildgit still needs to attempt to show the build information.  For example, it may also be givin a --job argument with a valid build job name.
- None of these features should change how checkbuild.sh or pushmon.sh behaves today.
