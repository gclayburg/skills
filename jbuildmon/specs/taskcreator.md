Use these instructions for breaking down a large specification.  The main objective is to create an implementation plan markdown file that can be used later by the implementer to build the software.  

## Goals
- Break down a large spec into smaller, independant chunks of work
- Each chunk must refer to the detailed spec document for clarifying detail
- Each chunk of work must be buildable and runnable on its own
- Each chunk of work must be able to be executed to verify that it does what it claims
- Try to minimize tight coupling between different chunks.
- Each chunk needs to have a test plan to verify it does what it says it does
- The test plan must have steps that can be executed by an automated agent.  For scripts, this means that the script must be executable so elemets of the test plan can run the script to verify certain code paths are working as intended.
- For scripts, the test plan should include manual steps to run the script and verify the output
- Each chunk in the implementation plan must be a checklist item.  These will be checked off by the implementer when there are complete.

## Size and Scope
- Each chunk should be large enough to be a meaningful part of the whole
- Each chunk should be small enough so that it can be implemented within the context window of any standard LLM, avoiding compaction.  

## Output format.  
- The name of this file will be based on the name of the spec being analyzed.  e.g. if we start with  a spec named majorfeature47-spec.md we will generate the file majorfeature47-plan.md
- checklist items should have a title.  sub-items of the checklist would have references to the spec and testing plain

## Ordering and dependence
- The plan will not specify an order as to which chunks should be built first.  This decision is deferred to implementation time.



## For the implementer
- The implementer of the chunk will create all the code necessary for the chunk
- The implementer will also use the test plan to exeucte the code to verify it