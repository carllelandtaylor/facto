# Technical Architecture Plan: [Short Title]

---

## 1. Summary

[2–4 sentences. What problem or opportunity is this addressing? Why does it matter? What is the proposed solution at a high level?]

---

## 2. Existing System

[Describe what already exists that is relevant to this work: tech stack, data models, infrastructure, integrations, and rough scale. If this is greenfield, state that clearly and describe the blank-slate context instead: team constraints, target environment, any pre-decided technology choices.]

---

## 3. Requirements

### 3.1 Functional Requirements

**FR-1: [Short name]**
[Description of what the system must do.]

**FR-2: [Short name]**
[Description.]

<!-- Add as many FRs as needed -->

### 3.2 Non-Functional Requirements

**NFR-1: [Short name]**
[Description — include concrete targets where relevant, e.g. "under 200ms p95 latency", "no new managed services", "must work in last 2 versions of Safari".]

**NFR-2: [Short name]**
[Description.]

<!-- Add as many NFRs as needed -->

---

## 4. Solution

### 4.1 [Component or Layer Name]

[Describe this part of the solution. What it is, how it works, key implementation notes. Be specific enough that a developer could start building from this description.]

**Addresses:** FR-1, NFR-2

### 4.2 [Next Component]

[Description.]

**Addresses:** FR-2, FR-3, NFR-1

<!-- Add as many solution sections as needed -->

---

## 5. Basic Implementation Plan

<!-- Keep this at the phase level: sequencing, goals, dependencies, and concrete steps.
     Do not include file-level detail, specific commands, or commit-sized breakdowns.
     This basic plan needs to be expanded into a detailed implementation plan before
     execution — use /facto:plan-implementation for that. -->

> **Note:** This is a basic implementation plan covering sequencing, goals, and dependencies. It needs to be expanded into a detailed implementation plan (with file-level changes, validation steps, and commit messages) before execution. Use `/facto:plan-implementation` to do that.

### Phase 1: [Name]
*[One sentence: why this comes first / what this phase unlocks.]*
- [Concrete step]
- [Concrete step]

### Phase 2: [Name]
*[One sentence goal or rationale.]*
- [Concrete step]
- [Concrete step]

<!-- Add or remove phases as needed -->

---

## Appendix: Key Decisions

---

### Decision 1: [Short name for the decision]

**What's needed:** [One sentence: what choice had to be made and why it mattered.]

**Options considered:**

**Option A: [Name]**
- Pro: [...]
- Con: [...]

**Option B: [Name]**
- Pro: [...]
- Con: [...]

**Option C: [Name]** ✓ *Selected*
- Pro: [...]
- Con: [...]

**Decision:** [Paragraph explaining why the selected option was chosen. Reference specific requirements (e.g. NFR-3 ruled out Option A because...). Be direct about trade-offs made.]

---

### Decision 2: [Short name]

<!-- Repeat structure above for each key decision -->
