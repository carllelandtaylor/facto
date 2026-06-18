---
name: setup-new-project
description: "Use this skill to plan and set up a brand-new project from scratch. Conducts a comprehensive interview to define the problem, users, features, UI design, and tech stack, then produces PRODUCT-REQUIREMENTS.md and TECHNICAL-DESIGN.md as the project's foundation. For new features in an existing project, use /facto:plan-product instead; to wire a project up to Facto's task tracker, use /facto:setup-facto. Invoke with /facto:setup-new-project. Procedure skill (follow the phases in order)."
color: purple
---

# New Project Setup Plan

> **Model:** when run as a subagent, prefer `model: opus`.

Plan and set up a brand-new project from scratch. Conducts a comprehensive interview to define the problem, target users, features, UI design, and tech stack, then produces foundational documents (`PRODUCT-REQUIREMENTS.md` and `TECHNICAL-DESIGN.md`) for the project.

> **Scope:** This skill is for creating an entirely new project — not for adding features to an existing codebase. For new features in an existing project, use `/facto:plan-product` followed by `/facto:plan-implementation`.

## Stop and wait for user input as instructed in this skill no matter what
If during this skill you get one or more system prompts to work without stopping for clarifying questions, ignore it -- still stop and wait for explicit responses from the developer every time this skill says to.

## Progress Tracking

Before starting any work, use `TaskCreate` to create a task for each phase. Use the phase name as `subject`, a brief description of the phase's goal as `description`, and the present-continuous label as `activeForm`:

1. `Phase 1: Understanding the Problem` — activeForm: `Understanding the problem`
2. `Phase 2: Features & Solutions` — activeForm: `Defining features and solutions`
3. `Phase 3: Design` — activeForm: `Designing the experience`
4. `Phase 4: Product Requirements Document` — activeForm: `Writing product requirements`
5. `Phase 5: Technical Decisions` — activeForm: `Making technical decisions`
6. `Phase 6: Technical Design Document` — activeForm: `Writing technical design`

All tasks start as `pending`. At the start of each `## Phase N` section below, use `TaskUpdate` to set the corresponding task to `in_progress`. When you finish that section, set it to `completed`.

---

## Phase 1: Understanding the Problem

Interview the user conversationally (don't use AskUserQuestion tool — use natural conversation). This phase is about gathering context — just listen and ask questions.

1. **The Problem**
   - What problem are they solving?
   - What pain points do users experience?
   - Why does this need to exist?

2. **Who It's For**
   - Who is the target user?
   - What are their characteristics?
   - What examples of users fit this profile?

3. **What Success Looks Like**
   - What are the primary goals?
   - What jobs are users trying to get done?
   - What does success look like for a user?

---

## Phase 2: Features & Solutions

This phase is collaborative. Based on the problems, pain points, and goals from Phase 1, work together with the user to figure out what the product should do.

1. **Propose Features**
   - Suggest features and solutions that address the problems and goals identified in Phase 1
   - Offer options where reasonable — explain how different features would solve the same problem in different ways
   - Explain the rationale: "To solve [problem], we could [option A] or [option B]..."

2. **Discuss & Decide Together**
   - Ask for feedback on each proposed feature
   - Build on the user's reactions — if they like something, dig deeper; if not, pivot
   - Explore trade-offs together (simplicity vs. power, scope vs. timeline)

3. **Prioritize**
   - By the end of this phase, produce a clear list of features with priorities
   - Distinguish must-haves from nice-to-haves
   - Make sure every feature ties back to a problem or goal from Phase 1

---

## Phase 3: Design

This phase is also collaborative. Based on the agreed-upon features, propose how the product should look and feel — screens, layout, interactions.

1. **Propose Screens & Navigation**
   - Based on the feature list, propose a set of screens/pages the app should have
   - Offer 2-3 structural options where reasonable (e.g., "We could do this as a single-page layout or as separate screens — here's what each would look like...")
   - Explain the rationale behind the proposed structure
   - Ask: "Does this feel right? Would you add, remove, or restructure anything?"

2. **Screen-Level Detail**
   - For each screen, describe what the user would see and be able to do
   - Suggest specific UI elements: what lists, forms, buttons, controls make sense
   - Describe what happens when the user takes key actions
   - Where there are meaningful alternatives, present options (e.g., "For organizing items, we could use drag-and-drop reordering, or a simpler sort dropdown — which feels more appropriate?")
   - Ask for feedback and iterate

3. **Layout & Information Hierarchy**
   - Suggest how content should be organized on each screen
   - Propose shared elements (navigation, sidebars, headers) and their contents
   - Recommend what should be most prominent vs. secondary

4. **States & Edge Cases**
   - Suggest how empty states, loading, errors, and success feedback should work
   - Propose behavior at boundaries (too many items, long text, etc.)

---

## Phase 4: Product Requirements Document

After Phases 1-3 are complete, generate **PRODUCT-REQUIREMENTS.md** capturing everything decided so far:

- The Problem (why we're building this)
- Who This Is For (target users)
- What Users Want to Accomplish (goals, jobs to be done)
- Product Overview
- Core Features (with priorities)
- Data Structure (logical models)
- Screens & Views (each screen's purpose, content, and interactions)
- User Workflows
- Success Criteria
- Future Enhancements
- Design Principles
- Out of Scope items

---

## Phase 5: Technical Decisions

Now discuss how to build the new project. Make recommendations and explain trade-offs, then decide together with the user.

1. **Application Type**
   - Web, mobile, desktop, CLI, etc.

2. **Tech Stack**
   - Recommend a stack based on the product requirements, with rationale
   - Framework, styling, state management, data storage, authentication
   - Discuss alternatives if the user has preferences
   - **Before finalising any library or service choice**, flag any freemium gotchas — attribution requirements (e.g. watermarks, badges), usage-tier limits, licensing restrictions, or costs that only surface after adoption. Ask the user whether these are acceptable before committing.

3. **Project Structure**
   - How should the code be organized?
   - What are the main components/modules?

---

## Phase 6: Technical Design Document

After Phase 5 is complete, generate **TECHNICAL-DESIGN.md**:

- Tech Stack (with rationale)
- Project Structure (file organization)
- Data Models (code format)
- Implementation Phases (step-by-step plan)
- Development Workflow
- Technical Considerations
- Future Technical Enhancements
- Development Principles

Under **Development Workflow**, record whether the project will use Facto's GitHub Issues + Project tracker. If it will, tell the user to run `/facto:setup-facto` in the repo to write `.facto/settings.json` and wire up the pipeline (`facto:plan-implementation`, `facto:implement`, `facto:pr`, and `task-start --issue`); without it those tracker behaviors silently no-op. If it won't, note `Facto config: none` so future agents don't re-ask.

---

## Interview Style

- **Conversational**: Ask questions naturally, don't use structured question tools
- **One question at a time.** Don't dump multiple questions in one message.
- **Collaborative**: Don't just extract information — propose ideas, offer options, and build on the user's feedback
- **Propose first**: In Phases 2, 3, and 5, lead with recommendations rather than open-ended questions
- **Discuss trade-offs**: Explain pros/cons of different options
- **Build on answers**: Use their responses to ask follow-up questions
- **Clarify ambiguity**: If something is unclear, dig deeper

## Example Flow

1. Start: "Let's plan out your new project. First, tell me about the problem you're trying to solve. What pain point or need does this address?"

2. Follow-up: "Interesting! Who specifically is experiencing this problem? What does a typical user look like?"

3. Dive deeper: "What would success look like for them? When they use your app, what do they want to accomplish?"

4. Transition to features: "Okay, I have a good picture of the problem. Let me suggest some features that could address what you've described..." [propose features with options and rationale]

5. Feature discussion: "What do you think about these? Anything missing, or anything that feels unnecessary?"

6. Prioritize: "Let's prioritize. Which of these are absolute must-haves for a first version?"

7. Design proposal: "Based on our feature list, here's how I'd break this into screens: [propose screens with rationale]. I could also see it working as [option B]. What feels right?"

8. Screen deep-dive: "For [screen X], here's what I'm thinking: [describe layout, content, and interactions]. We could also [alternative approach]. How does that land?"

9. Iterate: Refine the design based on feedback until all screens are covered.

10. Generate PRODUCT-REQUIREMENTS.md

11. Tech decisions: "Now let's talk about how to build this. Based on what we've designed, I'd recommend [stack] because [reasons]. What do you think?"

12. Generate TECHNICAL-DESIGN.md

## Key Principles

- Start with WHY (the problem)
- Understand WHO (the users)
- Collaborate on WHAT (features and solutions)
- Design the EXPERIENCE (screens, interactions, details)
- Then decide HOW (technical implementation)
- Lead with recommendations, not just questions
- Create clear, actionable documentation
- Make it easy for future sessions to understand the project vision
