

# Ralph Wiggum process
1. brainstorm and write down some ideas for a new feature, a bug fix, or a new user story .  include as much clarifying detail as possible
2. write this to a file like specs/some-new-feature-raw.md

3. Use claude Opus to read about your idea then force it to ask you clarifying questions about what exactly you want.  when satisfied, have claude code write a specification document in the specs folder using the name standard specs/some-new-feature-spec.md

Do it with this script

```bash
./raw-to-spec.sh specs/some-new-feature-raw.md 
```

4. human verifies the spec has everything needed
5. use claude to break down specs into a plan according to instructions:

```bash
$ ./createchunks.sh specs/some-new-feature-spec.md
```

6. Human verifies the plan.

7. implement one task with unit test

```bash
$ ./executeplan.sh specs/some-new-feature-plan.md
```

repeat 7 until all tasks marked complete.


## use claude opus for creating taskcreator.md:

```bash
claude 'study AGENTS.md README.md and specs/taskcreator.md  is there anything in specs/taskcreator.md that is not clear or needs further explanation.  at some point, I will ask you to use this to generate a plan.  '
```

repeat this prompt again after making edits.



# Bugs

1. describe bug in claude prompt with all the detail we know.  ask claude to create a bug report with root cause analysis and save file in specs/bug#-thingthatbroke.md

2. review document
3. have claude create implementation plan, just like a spec:

```bash
claude 'use taskcreator.md to create an implementation plan for specs/build-tools-enhancement-spec.md'
```

4. run this as many times as it takes to build all chunks:

```bash
claude 'study  specs/bug1-jenkins-log-truncated-plan.md . use your judgement to pick the highest priority task or chunk and build that.  do not ask questions, just do it.  When finished mark the chunk as completed in  specs/bug1-jenkins-log-truncated-plan.md '
```
