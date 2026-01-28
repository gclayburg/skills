# Specs/ directory: Specifications, Implementation Plans, and Bug fixes workflow

## Project Specs
Individual *-spec.md files are considered the specification for what a feature is and what it needs to do.  These specifications represent the canonical view of what the corresponding parts of the application should do.  If there is a conflict between specs, they must be analyzed and updated so that no conflicts remain.

### Spec and Bug index
These files represent completed specifications in the specs/ directory.  This list should be updated when the specs are completed.
- checkbuild-spec.md  checkbuild.sh shell script to check the current build status of git/Jenkins project from working directory
- jenkins-build-monitor-spec.md  pushmon.sh shell script to push staged git changes to origin and monitor build status until complete.
- install-bats-core-spec.md  install bats-core as unit testing framework
- bug2026-01-28-jenkins-log-truncated-spec.md  fix for stage log truncation when displaying failure analysis


## Helper Prompts
Helper prompts are used by AI to automatically generate other documents
- taskcreator.md  instructions to create individual chunks (implementation tasks) from a spec file
- chunk_template.md template of sample chunk of implementation plan

## implementation plan 
- Any file named *-plan.md or *_plan.md is an implementation plan that have rules for how they are updated
- These files are created from a spec file using taskcreator.md
- Each chunk has a brief description, which has backing documentation in the referenced spec section
- Each chunk starts as an un marked checkbox, meaning the task has not been completed.
- When a task or 'chunk' in the plan has been implemented, it is marked as completed.
- Once a plan is implemented, the corresponding plan.md file is not useful and can be considered archival status


## Bug reports
### Bug Report File Naming Conventions
Bug reports go through these phases

raw bug report -> root cause analysis spec -> implementation plan -> code fix
Each arrow here goes through a documented process to create the next phase

- **Raw bug reports:**  
  Use the following naming pattern for raw, unprocessed bug reports:  
  ```
  specs/bug<YYYY-MM-DD>-<title>-raw-bugreport.md
  ```
  Example: `specs/bug2026-01-28-stage-log-truncated-raw-bugreport.md`
- **Analyzed bug reports:**  
  Once a bug report has been analyzed for its root cause, name the file as:  
  ```
  specs/bug<YYYY-MM-DD>-<title>-spec.md
  ```
  Example: `specs/bug2026-01-28-stage-log-truncated-spec.md`
- **Implementation plans for bug fixes:**  
  After a bug spec has been broken down into an implementation plan, use the following naming pattern:  
  ```
  specs/bug<YYYY-MM-DD>-<title>-plan.md
  ```
  Example: `specs/bug2026-01-28-stage-log-truncated-plan.md`

