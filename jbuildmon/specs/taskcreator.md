# taskcreator

Use these instructions for breaking down a large specification.  The main objective is to create an implementation plan markdown file that can be used later by the implementer to build the software.  You are a software architect. Decompose the feature specification into LLM-sized implementation chunks.

## implementation plan
- Any file named `*-plan.md` or `*_plan.md` is an implementation plan that have rules for how they are updated
- us `chunk_template.md` for template of sample chunk of implementation plan
- Each chunk has a brief description, which has backing documentation in the referenced spec section
- Each chunk starts as an un marked checkbox, meaning the task has not been completed.
- When a task or 'chunk' in the plan has been implemented, it is marked as completed.
- Once all chunks in a plan have been implemented, the corresponding plan.md file is not useful and can be considered archival status

## Goals
- Break down a large spec into smaller, independently runnable chunks or tasks of work.  Chunk and task terms are used interchangeably.
- Each chunk must refer to the detailed spec document for clarifying detail
- Each chunk of work must be buildable and testable on its own.  See unit testing section below
- Each chunk of work must be able to be executed to verify that it does what it claims
- Try to minimize tight coupling between different chunks.
- Each chunk in the implementation plan must be a checklist item.  These will be checked off by the implementer when there are complete.
- Each chunk when implemented should result in new implementation code, not just documentation updates, or spec or planning updates.
- It is ok for the chunk to be new library code that is not reachable by the main entrypoint just yet.
- Dependencies between chunks should be well documented. e.g. If chunk B calls function from chunk A, that needs to be documented inside chunk B
- An implemented chunk that changes how and end user will use it needs to have documentation delivered along with it.  For example, if you add a new option, flag or env setting to a shell script the usage section must also be changed to match.

## Agent Executability
- **Every chunk must be executable by an AI agent.** Chunks are not suggestions or optional guidance—they are concrete tasks that an agent will perform.
- Do not create chunks labeled as "investigation" or "manual" tasks that an agent might interpret as something to skip. If data gathering or API queries are needed, write the chunk with explicit instructions for how the agent should perform them (e.g., specific curl commands, API endpoints, environment variables to use).
- If a chunk requires querying an external system (e.g., Jenkins API, database), include the exact commands or code the agent should execute. Reference any required credentials by environment variable name.
- Chunks should not rely on assumptions about system state. If a chunk needs to verify something before proceeding, include that verification step explicitly.
- If a chunk produces artifacts (e.g., fixture files, captured API responses), specify the exact output file path and format expected.

## Unit Testing
- Each chunk needs to have unit tests created alongside it to verify the code is working.
- Unit tests must be repeatable.  
- Running a unit test should not create any side effects.
- A unit test should not use external systems or network communication to run.
- Implementation code must be a testable design.  The code can be invoked from a unit test, not just the normal frontend entrypoint.
- Unit tests must be written with a goal of 80% test coverage
- Each test case written should document within the test itself the name of the spec and the section from which it was derived
- Implementation code must use a unit testing framework that is appropriate for the language used
  - Bash shell scripts should use bats-core
  - Java should use Junit 5 or Spock tests in Groovy
  - Typescript should use Jest
  - Groovy should use Spock

## Definition of done
- all unit tests written as a part of this task have been executed and they pass
- all unit tests of the entire project also are still passing
- if you find that this new feature starts to cause the test failure of an existing test, use your judgement to examine and fix either the implementation code or the test code


## Size and Scope
- Decompose this specification into LLM-sized implementation chunks.
- Each chunk must be implementable end-to-end within a single LLM session with a 200k-token context window, including any necessary code, tests, and documentation updates.
- A chunk may produce one or more files, but should be small enough that the full diff plus reasoning fits comfortably inside the context budget.
- Define explicit interfaces/contracts between packages (APIs, types, schemas, events), so packages can be implemented independently.

## Output format.  
- The name of this file will be based on the name of the spec being analyzed.  e.g. if we start with  a spec named majorfeature47-spec.md we will generate the file majorfeature47-plan.md
- checklist items should have a title.  sub-items of the checklist would have references to the spec
- see chunk_template.md for a format example of a system for bash shell scripts using the bats-core unit testing framework


## Ordering and dependence
- The plan will not specify an order as to which chunks should be built first.  
- The dependencies are documented so this decision of which chunk to build next can be deferred to implementation time.

### Chunk Execution Rules
- **All chunks are designed to be executed by an AI agent.** There are no "manual-only" or "investigation-only" chunks that should be skipped.
- Agents must attempt each chunk before concluding it cannot be done. If a chunk requires data gathering (API calls, file reads, etc.), the agent should execute those operations.
