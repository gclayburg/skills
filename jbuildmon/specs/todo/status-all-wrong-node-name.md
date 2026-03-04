When I run a buildgit status, I am looking at the agent information. The output here doesn't quite match what I see on the Jenkins UI console what I see in the Jenkins UI console is other agents running not agent six I see agent seven and agent hate running, but I don't see agent six but the problem is that this file of this building gets command what it wants to do is show me that we're running on agent six and running on agent six for several of these parallel test that are running like unit test a unit test B unit test C and unit test D it says that all of these are running on age 6, but in reality they're not they're running on agent seven and agent eight so we need to do a thorough look how were coming up with this information? Is it correct? I think it needs to be changed because it's not matching what reality is we're not doing enough investigation here now also what I found is it says age of six but really that's not the name of the agent the name of the agent in Jenkins agent six space Guthrie so there's more stuff in there that's not being captured by whatever we're doing now to name the agents being running or that is running so we need to find out make the agent name, capture mechanism more robust so let's look at the API and find a better way to capture the exact name of the age of running each individual stage and display it to the user I wanna be able to show what exact stage i being run and what agent is being run on



```
$ ./buildgit status -f
[12:13:27] ℹ Waiting for Jenkins build ralph1/main to start...
[12:13:27] ℹ Prior 3 Jobs
SUCCESS     #11 id=e9be110 Tests=673/0/0 Took 2m 41s on 2026-03-04T10:49:57-0700 (1 hour ago)
SUCCESS     #12 id=02cf928 Tests=673/0/0 Took 2m 40s on 2026-03-04T11:17:10-0700 (56 minutes ago)
SUCCESS     #13 id=7d21476 Tests=676/0/0 Took 2m 26s on 2026-03-04T11:54:47-0700 (18 minutes ago)
[12:13:28] ℹ Estimated build time = 2m 26s

[12:13:28] ℹ Waiting for next build of ralph1/main...
[14:28:54] ℹ Starting

╔════════════════════════════════════════╗
║          BUILD IN PROGRESS             ║
╚════════════════════════════════════════╝

Job ralph1/main #14 has been running for 2s

Job:        ralph1/main
Build:      #14
Status:     BUILDING
Trigger:    Unknown
Started:    2026-03-04 14:28:51

=== Build Info ===
  Agent:       agent6
==================

Commit:     31de317 - "Handle test-report communication failures explicitly"
            ✓ Your commit (HEAD)

Console:    http://palmer.garyclayburg.com:18080/job/ralph1/job/main/14/console
[14:29:01] ℹ   Stage: [agent6        ] Build (4s)
[14:29:01] ℹ   Stage:   ║3 [agent6        ] Unit Tests C (<1s)
[14:30:15] ℹ   Stage:   ║1 [agent6        ] Unit Tests A (<1s)
[14:30:15] ℹ   Stage:   ║2 [agent6        ] Unit Tests B (1m 14s)
[14:30:15] ℹ   Stage: [agent6        ] Unit Tests (1m 14s)
[14:31:19] ℹ   Stage:   ║4 [agent6        ] Unit Tests D (2m 16s)
```
