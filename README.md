

# Ralph Wiggum process
1. brainstorm and write down some ideas for a new feature, a bug fix, or a new user story .  include as much clarifying detail as possible
2. Use Claude Opus to read the idea, and ask you questions about it to further clarify.
3. Use claude Opus to read about your idea then force it to ask you clarifying questions about what exactly you want.  when satisfied, have claude code write a specification document in the specs folder using the name standard specs/something-spec.md
4. human verifies the spec has everything needed
5. use claude to create plan according to instructions

```bash
claude 'use taskcreator.md to create an implementation plan for specs/build-tools-enhancement-spec.md'
```

6. Human verifies the plan.

7. implement one task with unit test

```bash
claude 'study  specs/build-tools-enhancements-plan.md . use your judgement to pick the highest priority task or chunk and build that.  do not ask questions, just do it.  When finished mark the chunk as completed in  specs/build-tools-enhancements-plan.md '
```

todo: figure out good sandbox to use unattended

repeat 7 until all tasks marked complete.


## use claude opus for creating taskcreator.md:

```bash
claude 'study AGENTS.md README.md and specs/taskcreator.md  is there anything in specs/taskcreator.md that is not clear or needs further explanation.  at some point, I will ask you to use this to generate a plan.  '
```

repeat this prompt again after making edits.
