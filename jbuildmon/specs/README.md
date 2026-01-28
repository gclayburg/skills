# 

## specs for the project
Individual *-spec.md files are considered the specification for what a feature is and what it needs to do.  These specifications represent the canonical view
of what the corresponding parts of the application should do.  All new specs being created will never invalidate the older specs.  If there is a conflict, the specs must be updated so that no conflicts remain.

- checkbuild-spec.md  checkbuild.sh shell script to check the current build status of git/Jenkins project from working directory
- jenkins-build-monitor-spec.md  pushmon.sh shell script to push staged git changes to origin and monitor build status until complete.
- install-bats-core-spec.md  install bats-core as unit testing framework

## helper prompts
- taskcreator.md  instructions to create individual tasks from a spec file
- chunk_template.md template chunk of implementation plan

## implementaiton plan 
- Any file named *-plan.md or *_plan.md is an implementation plan that have rules for how they are updated
- These files are created from a spec file using taskcreator.md
- Each chunk has a brief description, which has backing documentation in the referenced spec section
- Each chunk starts as an un marked checkbox, meaning the task has not been completed.
- When a task or 'chunk' in the plan has been implemented, it is marked as completed.
- Once a plan is implemented, the corresponding plan.md file is not useful and can be considered archival status

