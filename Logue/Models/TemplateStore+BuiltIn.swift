// swiftlint:disable file_length force_unwrapping function_body_length
// Note: force_unwrapping is disabled because this file uses 38+ UUID(uuidString:)! calls
// with compile-time constant strings that are guaranteed to be valid UUID format.
import Foundation

extension TemplateStore {
    static func makeBuiltInTemplates() -> [DocumentTemplate] {
        [
            // MARK: Meeting Notes

            meetingNotes(), oneOnOne(), standupNotes(), boardMeetingMinutes(), brainstormingSession(), retrospective(),

            // MARK: Project Management

            projectBrief(), projectPlan(), statusReport(), postMortem(), prd(), sprintPlanning(), releaseNotes(),

            // MARK: Business

            businessProposal(), businessPlan(), swotAnalysis(), competitiveAnalysis(), quarterlyBusinessReview(), executiveSummary(),

            // MARK: Marketing

            contentBrief(), marketingCampaignPlan(), socialMediaPlan(), pressRelease(), brandGuidelines(),

            // MARK: Engineering

            technicalDesignDocument(), bugReport(), rfc(), apiDocumentation(), incidentReport(),

            // MARK: HR & People

            jobDescription(), performanceReview(), onboardingChecklist(), interviewScorecard(), teamCharter(),

            // MARK: Finance

            budgetProposal(), expenseReport(), investmentMemo(),

            // MARK: Academic

            lectureNotes(), researchPaperOutline(), studyGuide(), essayOutline(), labReport(), readingNotes(), groupProjectPlan(), thesisOutline(),

            // MARK: Personal

            weeklyPlanner(), goalTracker(), dailyJournal(), decisionLog(), habitTracker(), travelPlanner(), personalOKRs(),

            // MARK: Communication

            memo(), presentationOutline(), newsletter(),
        ]
    }

    // MARK: - Meeting Notes

    private static func meetingNotes() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000001")!,
            name: "Meeting Notes",
            category: .meetingNotes,
            icon: "note.text",
            description: "Standard meeting notes with agenda, attendees, discussion, and action items.",
            body: """
            ## Meeting Notes

            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Time:** Start — End
            **Location:** Conference Room / Video Call Link
            **Facilitator:**

            ---

            ### Attendees

            | Name | Role |
            |------|------|
            |      |      |
            |      |      |
            |      |      |

            ---

            ### Agenda

            1.
            2.
            3.

            ---

            ### Discussion Notes

            #### Topic 1
            - Key points discussed
            - Decisions made
            - Open questions

            #### Topic 2
            - Key points discussed
            - Decisions made
            - Open questions

            ---

            ### Action Items

            - [ ] **[Owner]** — Task description (Due: )
            - [ ] **[Owner]** — Task description (Due: )
            - [ ] **[Owner]** — Task description (Due: )

            ---

            ### Next Meeting
            **Date:** TBD
            **Agenda preview:**
            """,
            isBuiltIn: true
        )
    }

    private static func oneOnOne() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000002")!,
            name: "One-on-One Meeting",
            category: .meetingNotes,
            icon: "person.2",
            description: "Recurring 1:1 meeting with talking points, feedback, and action items.",
            body: """
            ## One-on-One Meeting

            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Manager:**
            **Direct Report:**

            ---

            ### Check-In
            - How are you doing this week?
            - Any wins or highlights to celebrate?
            - Anything on your mind?

            ---

            ### Talking Points (Direct Report)

            1.
            2.
            3.

            ### Talking Points (Manager)

            1.
            2.
            3.

            ---

            ### Progress on Goals
            - **Goal 1:** Status update
            - **Goal 2:** Status update
            - **Goal 3:** Status update

            ---

            ### Feedback

            **Positive feedback:**
            -

            **Constructive feedback:**
            -

            ---

            ### Career Development
            - Skills to develop
            - Upcoming opportunities
            - Support needed

            ---

            ### Action Items

            - [ ] **[Name]** — Task (Due: )
            - [ ] **[Name]** — Task (Due: )

            ---

            ### Notes for Next Time
            -
            """,
            isBuiltIn: true
        )
    }

    private static func standupNotes() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000003")!,
            name: "Standup Notes",
            category: .meetingNotes,
            icon: "figure.stand",
            description: "Daily standup format covering yesterday, today, and blockers.",
            body: """
            ## Daily Standup

            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Team:**

            ---

            ### Team Member 1: [Name]

            **Yesterday:**
            - Completed task
            - Worked on feature

            **Today:**
            - Will continue working on
            - Plan to start

            **Blockers:**
            - None / Describe blocker

            ---

            ### Team Member 2: [Name]

            **Yesterday:**
            -

            **Today:**
            -

            **Blockers:**
            -

            ---

            ### Team Member 3: [Name]

            **Yesterday:**
            -

            **Today:**
            -

            **Blockers:**
            -

            ---

            ### Parking Lot
            Items that need further discussion outside standup:
            -

            ### Key Dates & Reminders
            -
            """,
            isBuiltIn: true
        )
    }

    private static func boardMeetingMinutes() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000004")!,
            name: "Board Meeting Minutes",
            category: .meetingNotes,
            icon: "building.columns",
            description: "Formal board meeting minutes with motions, votes, and resolutions.",
            body: """
            ## Board Meeting Minutes

            **Organization:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Time:** Start — End
            **Location:**
            **Meeting called to order by:**

            ---

            ### Attendance

            | Name | Title | Present |
            |------|-------|---------|
            |      | Chair | Yes/No  |
            |      | Director | Yes/No  |
            |      | Secretary | Yes/No  |
            |      | Treasurer | Yes/No  |

            **Quorum:** Yes / No

            ---

            ### Approval of Previous Minutes
            - Motion to approve minutes from [date] by [name]
            - Seconded by [name]
            - **Vote:** Approved / Not Approved (For: , Against: , Abstain: )

            ---

            ### Reports

            #### Chair's Report
            -

            #### Treasurer's Report
            - Revenue:
            - Expenses:
            - Net position:

            ---

            ### Old Business
            1. Status of [item from previous meeting]

            ### New Business

            #### Motion 1: [Title]
            - **Moved by:** [name]
            - **Seconded by:** [name]
            - **Discussion:**
            - **Vote:** Approved / Not Approved (For: , Against: , Abstain: )

            #### Motion 2: [Title]
            - **Moved by:** [name]
            - **Seconded by:** [name]
            - **Discussion:**
            - **Vote:** Approved / Not Approved (For: , Against: , Abstain: )

            ---

            ### Resolutions
            1.
            2.

            ### Action Items
            - [ ] **[Owner]** — Task (Due: )

            ### Next Meeting
            **Date:**

            **Meeting adjourned at:** [time]
            **Minutes recorded by:** [name]
            """,
            isBuiltIn: true
        )
    }

    private static func brainstormingSession() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000005")!,
            name: "Brainstorming Session",
            category: .meetingNotes,
            icon: "lightbulb",
            description: "Ideation capture with problem statement, ideas, and evaluation matrix.",
            body: """
            ## Brainstorming Session

            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Facilitator:**
            **Participants:**
            **Time-box:** 60 minutes

            ---

            ### Problem Statement
            What challenge are we trying to solve?

            > Clearly state the problem or opportunity here.

            ### Constraints
            - Budget:
            - Timeline:
            - Technical:
            - Other:

            ---

            ### Ground Rules
            1. No idea is a bad idea
            2. Build on others' ideas
            3. Stay focused on the problem
            4. One conversation at a time

            ---

            ### Ideas

            | # | Idea | Proposed By | Notes |
            |---|------|-------------|-------|
            | 1 |      |             |       |
            | 2 |      |             |       |
            | 3 |      |             |       |
            | 4 |      |             |       |
            | 5 |      |             |       |

            ---

            ### Evaluation Matrix

            | Idea | Impact (1-5) | Feasibility (1-5) | Effort (1-5) | Total |
            |------|--------------|--------------------|--------------|-------|
            |      |              |                    |              |       |
            |      |              |                    |              |       |
            |      |              |                    |              |       |

            ---

            ### Top 3 Ideas to Explore
            1. **Idea:** — Next step:
            2. **Idea:** — Next step:
            3. **Idea:** — Next step:

            ### Action Items
            - [ ] **[Owner]** — Research / prototype idea (Due: )
            - [ ] **[Owner]** — Schedule follow-up session (Due: )
            """,
            isBuiltIn: true
        )
    }

    private static func retrospective() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000006")!,
            name: "Retrospective",
            category: .meetingNotes,
            icon: "arrow.trianglehead.2.clockwise",
            description: "Sprint retrospective covering what went well, what didn't, and improvements.",
            body: """
            ## Sprint Retrospective

            **Sprint:** Sprint [#]
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Facilitator:**
            **Team:**

            ---

            ### What Went Well
            Things we should keep doing:
            -
            -
            -

            ---

            ### What Didn't Go Well
            Things that caused friction or problems:
            -
            -
            -

            ---

            ### What We Learned
            New insights or discoveries:
            -
            -

            ---

            ### Improvement Ideas

            | Improvement | Priority | Owner |
            |------------|----------|-------|
            |            | High/Med/Low |   |
            |            | High/Med/Low |   |
            |            | High/Med/Low |   |

            ---

            ### Action Items for Next Sprint
            - [ ] **[Owner]** — Improvement action (Due: )
            - [ ] **[Owner]** — Improvement action (Due: )
            - [ ] **[Owner]** — Improvement action (Due: )

            ---

            ### Team Happiness Score
            Rate the sprint 1-5: ⭐️

            ### Follow-Up from Previous Retro
            - [ ] Action item from last retro — Status
            """,
            isBuiltIn: true
        )
    }

    // MARK: - Project Management

    private static func projectBrief() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000007")!,
            name: "Project Brief",
            category: .projectManagement,
            icon: "doc.text",
            description: "Project overview with goals, scope, timeline, and stakeholders.",
            body: """
            ## Project Brief

            **Project Name:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Project Lead:**
            **Sponsor:**

            ---

            ### Project Overview
            A concise description of the project and why it matters.

            ### Business Objective
            What business goal does this project serve?

            ---

            ### Goals & Success Criteria

            | Goal | Success Metric | Target |
            |------|---------------|--------|
            |      |               |        |
            |      |               |        |

            ---

            ### Scope

            **In Scope:**
            -
            -

            **Out of Scope:**
            -
            -

            ---

            ### Stakeholders

            | Name | Role | Responsibility |
            |------|------|---------------|
            |      |      | Decision maker |
            |      |      | Contributor    |
            |      |      | Reviewer       |

            ---

            ### Timeline

            | Phase | Start | End | Deliverable |
            |-------|-------|-----|-------------|
            | Discovery |  |  |             |
            | Design    |  |  |             |
            | Build     |  |  |             |
            | Launch    |  |  |             |

            ---

            ### Budget
            - Estimated cost:
            - Funding source:

            ### Risks & Assumptions
            - **Risk:** Mitigation plan
            - **Assumption:**

            ### Approval
            - [ ] Sponsor approval
            - [ ] Stakeholder sign-off
            """,
            isBuiltIn: true
        )
    }

    private static func projectPlan() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000008")!,
            name: "Project Plan",
            category: .projectManagement,
            icon: "list.clipboard",
            description: "Detailed project plan with milestones, deliverables, dependencies, and owners.",
            body: """
            ## Project Plan

            **Project Name:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Project Manager:**
            **Version:** 1.0

            ---

            ### Objectives
            1.
            2.
            3.

            ---

            ### Milestones

            | Milestone | Target Date | Status | Owner |
            |-----------|-------------|--------|-------|
            | Kickoff   |             | Not Started |  |
            | Milestone 1 |           | Not Started |  |
            | Milestone 2 |           | Not Started |  |
            | Milestone 3 |           | Not Started |  |
            | Launch    |             | Not Started |  |

            ---

            ### Deliverables

            | Deliverable | Description | Owner | Due Date | Status |
            |------------|-------------|-------|----------|--------|
            |            |             |       |          | Not Started |
            |            |             |       |          | Not Started |
            |            |             |       |          | Not Started |

            ---

            ### Dependencies

            | Dependency | Depends On | Impact if Delayed | Owner |
            |-----------|-----------|-------------------|-------|
            |           |           |                   |       |
            |           |           |                   |       |

            ---

            ### Team & Roles

            | Name | Role | Allocation (%) |
            |------|------|---------------|
            |      |      |               |
            |      |      |               |

            ---

            ### Communication Plan
            - **Weekly status:** Every [day] at [time]
            - **Stakeholder updates:** Bi-weekly
            - **Escalation path:**

            ### Risk Register

            | Risk | Likelihood | Impact | Mitigation |
            |------|-----------|--------|------------|
            |      | High/Med/Low | High/Med/Low |    |
            |      | High/Med/Low | High/Med/Low |    |
            """,
            isBuiltIn: true
        )
    }

    private static func statusReport() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000009")!,
            name: "Status Report",
            category: .projectManagement,
            icon: "chart.bar",
            description: "Weekly status report with progress, risks, blockers, and next steps.",
            body: """
            ## Status Report

            **Project:**
            **Reporting Period:** Week of \(Date.now.formatted(date: .long, time: .omitted))
            **Author:**
            **Overall Status:** 🟢 On Track / 🟡 At Risk / 🔴 Off Track

            ---

            ### Summary
            Brief overview of progress this period.

            ---

            ### Progress

            | Task / Deliverable | Status | % Complete | Notes |
            |-------------------|--------|-----------|-------|
            |                   | Done   | 100%      |       |
            |                   | In Progress | 60%  |       |
            |                   | Not Started | 0%   |       |

            ---

            ### Key Accomplishments
            -
            -
            -

            ### Risks & Issues

            | Risk / Issue | Severity | Status | Mitigation / Resolution |
            |-------------|----------|--------|------------------------|
            |             | High     | Open   |                        |
            |             | Medium   | Open   |                        |

            ---

            ### Blockers
            - [ ] Blocker description — Assigned to [name], needs resolution by [date]

            ---

            ### Next Steps (Upcoming Week)
            - [ ] Task 1 — Owner
            - [ ] Task 2 — Owner
            - [ ] Task 3 — Owner

            ### Decisions Needed
            1. Decision description — needed by [date]

            ### Budget / Resource Update
            - Budget consumed: $X / $Y
            - Resources: On plan / Additional needed
            """,
            isBuiltIn: true
        )
    }

    private static func postMortem() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000010")!,
            name: "Post-Mortem",
            category: .projectManagement,
            icon: "flag.checkered",
            description: "Project post-mortem with outcomes, lessons learned, and recommendations.",
            body: """
            ## Post-Mortem

            **Project:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Author:**
            **Participants:**

            ---

            ### Project Summary
            Brief description of the project, its goals, and intended outcomes.

            ---

            ### Outcomes

            | Goal | Target | Actual | Met? |
            |------|--------|--------|------|
            |      |        |        | Yes/No |
            |      |        |        | Yes/No |
            |      |        |        | Yes/No |

            **Overall Outcome:** Successful / Partially Successful / Unsuccessful

            ---

            ### Timeline Review

            | Milestone | Planned Date | Actual Date | Delta |
            |-----------|-------------|-------------|-------|
            |           |             |             |       |
            |           |             |             |       |

            ---

            ### What Went Well
            -
            -
            -

            ### What Could Have Gone Better
            -
            -
            -

            ---

            ### Root Causes of Issues
            1. **Issue:** Root cause and contributing factors
            2. **Issue:** Root cause and contributing factors

            ### Lessons Learned
            1.
            2.
            3.

            ---

            ### Recommendations for Future Projects
            - [ ] Process improvement
            - [ ] Tool or resource change
            - [ ] Communication improvement

            ### Acknowledgments
            Recognize team members and contributions.
            """,
            isBuiltIn: true
        )
    }

    private static func prd() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000011")!,
            name: "Product Requirements Document",
            category: .projectManagement,
            icon: "doc.richtext",
            description: "PRD with user stories, acceptance criteria, and technical requirements.",
            body: """
            ## Product Requirements Document

            **Product:**
            **Version:** 1.0
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Author:**
            **Status:** Draft / In Review / Approved

            ---

            ### Overview
            What is this product or feature, and why are we building it?

            ### Problem Statement
            Describe the user pain point or business need.

            ### Target Users
            - **Primary:** Description of main user persona
            - **Secondary:** Description of secondary persona

            ---

            ### User Stories

            | ID | As a... | I want to... | So that... | Priority |
            |----|---------|-------------|-----------|----------|
            | US-1 |       |             |           | Must Have |
            | US-2 |       |             |           | Should Have |
            | US-3 |       |             |           | Nice to Have |

            ---

            ### Acceptance Criteria

            #### US-1: [Story Title]
            - [ ] Given [context], when [action], then [outcome]
            - [ ] Given [context], when [action], then [outcome]

            #### US-2: [Story Title]
            - [ ] Given [context], when [action], then [outcome]

            ---

            ### Technical Requirements
            - Performance: Response time under X ms
            - Scalability: Support up to N concurrent users
            - Security: Authentication, data encryption
            - Compatibility: Platforms and versions supported

            ### Non-Functional Requirements
            - Accessibility:
            - Localization:
            - Analytics:

            ---

            ### Design & Wireframes
            Link to designs or embed screenshots.

            ### Dependencies
            - External services:
            - Internal teams:

            ### Release Criteria
            - [ ] All must-have stories complete
            - [ ] QA sign-off
            - [ ] Performance benchmarks met
            - [ ] Documentation updated
            """,
            isBuiltIn: true
        )
    }

    private static func sprintPlanning() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000012")!,
            name: "Sprint Planning",
            category: .projectManagement,
            icon: "calendar.badge.clock",
            description: "Sprint planning with goals, capacity planning, and committed backlog.",
            body: """
            ## Sprint Planning

            **Sprint:** Sprint [#]
            **Dates:** Start — End
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Scrum Master:**
            **Product Owner:**

            ---

            ### Sprint Goal
            What is the single most important outcome for this sprint?

            > State the sprint goal here.

            ---

            ### Team Capacity

            | Team Member | Available Days | Notes |
            |------------|---------------|-------|
            |            |               | PTO / partial |
            |            |               |       |
            |            |               |       |
            | **Total**  | **X days**    |       |

            ---

            ### Committed Backlog

            | Ticket | Title | Points | Assignee | Priority |
            |--------|-------|--------|----------|----------|
            |        |       |        |          | High     |
            |        |       |        |          | High     |
            |        |       |        |          | Medium   |
            |        |       |        |          | Medium   |
            |        |       |        |          | Low      |

            **Total Points Committed:**
            **Velocity (last 3 sprints):**

            ---

            ### Stretch Goals
            Items to pull in if capacity allows:
            1.
            2.

            ---

            ### Dependencies & Risks
            - **Dependency:** Description — Status
            - **Risk:** Description — Mitigation

            ### Carry-Over from Previous Sprint
            - Ticket — Reason for carry-over

            ### Definition of Done
            - [ ] Code reviewed
            - [ ] Tests passing
            - [ ] Documentation updated
            - [ ] Deployed to staging
            """,
            isBuiltIn: true
        )
    }

    private static func releaseNotes() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000013")!,
            name: "Release Notes",
            category: .projectManagement,
            icon: "shippingbox",
            description: "Release notes documenting new features, bug fixes, and known issues.",
            body: """
            ## Release Notes

            **Product:**
            **Version:**
            **Release Date:** \(Date.now.formatted(date: .long, time: .omitted))

            ---

            ### Highlights
            A brief summary of the most important changes in this release.

            ---

            ### New Features

            - **Feature Name** — Description of the feature and how to use it.
            - **Feature Name** — Description of the feature and how to use it.
            - **Feature Name** — Description of the feature and how to use it.

            ---

            ### Improvements

            - **Area** — Description of improvement.
            - **Area** — Description of improvement.

            ---

            ### Bug Fixes

            - **Fixed:** Description of the bug that was resolved.
            - **Fixed:** Description of the bug that was resolved.
            - **Fixed:** Description of the bug that was resolved.

            ---

            ### Known Issues

            | Issue | Severity | Workaround |
            |-------|----------|------------|
            |       | High     |            |
            |       | Medium   | Use [alternative] |

            ---

            ### Breaking Changes
            - Description of any breaking changes and migration steps.

            ### Deprecations
            - Feature/API deprecated — will be removed in version X.

            ### Upgrade Instructions
            1. Step one
            2. Step two
            3. Step three

            ---

            ### Contributors
            Thanks to everyone who contributed to this release.
            """,
            isBuiltIn: true
        )
    }

    // MARK: - Business

    private static func businessProposal() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000014")!,
            name: "Business Proposal",
            category: .business,
            icon: "briefcase",
            description: "Professional proposal with executive summary, approach, pricing, and timeline.",
            body: """
            ## Business Proposal

            **Prepared for:** [Client / Organization]
            **Prepared by:** [Your Name / Company]
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Valid until:**

            ---

            ### Executive Summary
            Briefly describe the opportunity, your proposed solution, and the expected value delivered.

            ---

            ### Understanding of Needs
            Demonstrate your understanding of the client's challenges and requirements.

            - Challenge 1:
            - Challenge 2:
            - Challenge 3:

            ---

            ### Proposed Approach

            #### Phase 1: Discovery
            - Activities and deliverables

            #### Phase 2: Implementation
            - Activities and deliverables

            #### Phase 3: Delivery & Support
            - Activities and deliverables

            ---

            ### Timeline

            | Phase | Duration | Start | End |
            |-------|----------|-------|-----|
            | Discovery | 2 weeks |   |     |
            | Implementation | 6 weeks | | |
            | Delivery | 2 weeks |     |     |

            ---

            ### Pricing

            | Item | Description | Cost |
            |------|-------------|------|
            |      |             | $    |
            |      |             | $    |
            |      |             | $    |
            | **Total** |       | **$** |

            **Payment terms:**

            ---

            ### Why Us
            - Differentiator 1
            - Differentiator 2
            - Relevant experience

            ### Terms & Conditions
            - Scope boundaries
            - Change request process
            - Intellectual property

            ### Next Steps
            1. Review proposal
            2. Schedule Q&A call
            3. Sign agreement
            """,
            isBuiltIn: true
        )
    }

    private static func businessPlan() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000015")!,
            name: "Business Plan",
            category: .business,
            icon: "chart.line.uptrend.xyaxis",
            description: "Comprehensive business plan with market analysis, strategy, and financials.",
            body: """
            ## Business Plan

            **Company Name:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Author:**

            ---

            ### Executive Summary
            One-paragraph overview of the business, its mission, and key financial projections.

            ### Company Description
            - **Mission:**
            - **Vision:**
            - **Legal structure:**
            - **Location:**

            ---

            ### Market Analysis

            #### Industry Overview
            Describe the industry, trends, and growth outlook.

            #### Target Market
            - **Demographics:**
            - **Market size:**
            - **Growth rate:**

            #### Competitive Landscape

            | Competitor | Strengths | Weaknesses | Market Share |
            |-----------|-----------|------------|-------------|
            |           |           |            |             |
            |           |           |            |             |

            ---

            ### Products & Services
            - Description of offerings
            - Value proposition
            - Pricing model

            ### Marketing & Sales Strategy
            - Customer acquisition channels
            - Sales process
            - Key partnerships

            ---

            ### Financial Projections

            | Year | Revenue | Expenses | Net Income |
            |------|---------|----------|-----------|
            | Y1   | $       | $        | $         |
            | Y2   | $       | $        | $         |
            | Y3   | $       | $        | $         |

            ### Funding Requirements
            - Amount needed: $
            - Use of funds:
            - Expected ROI:

            ---

            ### Team

            | Name | Role | Background |
            |------|------|-----------|
            |      | CEO  |           |
            |      | CTO  |           |

            ### Milestones
            - [ ] Milestone 1 — Target date
            - [ ] Milestone 2 — Target date
            """,
            isBuiltIn: true
        )
    }

    private static func swotAnalysis() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000016")!,
            name: "SWOT Analysis",
            category: .business,
            icon: "square.grid.2x2",
            description: "Strategic SWOT analysis covering strengths, weaknesses, opportunities, and threats.",
            body: """
            ## SWOT Analysis

            **Subject:** [Company / Product / Initiative]
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Prepared by:**

            ---

            ### Strengths (Internal, Positive)
            What advantages do we have? What do we do well?

            -
            -
            -
            -

            ---

            ### Weaknesses (Internal, Negative)
            Where can we improve? What are we lacking?

            -
            -
            -
            -

            ---

            ### Opportunities (External, Positive)
            What trends or changes can we leverage?

            -
            -
            -
            -

            ---

            ### Threats (External, Negative)
            What obstacles do we face? What are competitors doing?

            -
            -
            -
            -

            ---

            ### Strategic Actions

            | SWOT Pair | Strategy | Priority |
            |-----------|----------|----------|
            | Strength + Opportunity | Leverage [strength] to capture [opportunity] | High |
            | Strength + Threat | Use [strength] to defend against [threat] | Medium |
            | Weakness + Opportunity | Address [weakness] to unlock [opportunity] | High |
            | Weakness + Threat | Mitigate [weakness] to reduce [threat] exposure | Critical |

            ---

            ### Key Takeaways
            1.
            2.
            3.

            ### Recommended Next Steps
            - [ ] Action item 1
            - [ ] Action item 2
            - [ ] Action item 3
            """,
            isBuiltIn: true
        )
    }

    private static func competitiveAnalysis() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000017")!,
            name: "Competitive Analysis",
            category: .business,
            icon: "person.3.sequence",
            description: "Competitor comparison with feature analysis and market positioning.",
            body: """
            ## Competitive Analysis

            **Market / Category:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Prepared by:**

            ---

            ### Market Overview
            Brief description of the market landscape and key trends.

            ---

            ### Competitor Profiles

            #### Competitor 1: [Name]
            - **Website:**
            - **Founded:**
            - **Funding / Revenue:**
            - **Target market:**
            - **Key differentiator:**

            #### Competitor 2: [Name]
            - **Website:**
            - **Founded:**
            - **Funding / Revenue:**
            - **Target market:**
            - **Key differentiator:**

            #### Competitor 3: [Name]
            - **Website:**
            - **Founded:**
            - **Funding / Revenue:**
            - **Target market:**
            - **Key differentiator:**

            ---

            ### Feature Comparison

            | Feature | Us | Competitor 1 | Competitor 2 | Competitor 3 |
            |---------|----|-------------|-------------|-------------|
            | Feature A | Yes | Yes | No | Partial |
            | Feature B | Yes | No | Yes | Yes |
            | Feature C | Planned | Yes | Yes | No |
            | Pricing | $X/mo | $Y/mo | $Z/mo | $W/mo |

            ---

            ### Positioning Map
            Describe where each competitor sits on key axes (e.g., price vs. features, enterprise vs. SMB).

            ### Strengths & Weaknesses vs. Competition
            - **Our advantages:**
            - **Their advantages:**
            - **Gaps to close:**

            ### Strategic Recommendations
            - [ ] Differentiation opportunity
            - [ ] Feature parity needed
            - [ ] Market positioning adjustment
            """,
            isBuiltIn: true
        )
    }

    private static func quarterlyBusinessReview() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000018")!,
            name: "Quarterly Business Review",
            category: .business,
            icon: "calendar.badge.checkmark",
            description: "QBR template with KPIs, achievements, challenges, and next-quarter goals.",
            body: """
            ## Quarterly Business Review

            **Quarter:** Q[1-4] [Year]
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Presenter:**

            ---

            ### Executive Summary
            High-level overview of quarterly performance and outlook.

            ---

            ### Key Performance Indicators

            | KPI | Target | Actual | Status |
            |-----|--------|--------|--------|
            | Revenue | $ | $ | 🟢/🟡/🔴 |
            | Active Users | | | 🟢/🟡/🔴 |
            | Churn Rate | % | % | 🟢/🟡/🔴 |
            | NPS Score | | | 🟢/🟡/🔴 |
            | Customer Acquisition Cost | $ | $ | 🟢/🟡/🔴 |

            ---

            ### Achievements
            -
            -
            -

            ### Challenges & Learnings
            -
            -
            -

            ---

            ### Product Updates
            - Feature launches:
            - Roadmap progress:

            ### Customer Highlights
            - New logos:
            - Expansion:
            - Churn:

            ---

            ### Next Quarter Goals

            | Goal | Owner | Target | Priority |
            |------|-------|--------|----------|
            |      |       |        | High     |
            |      |       |        | Medium   |
            |      |       |        | Medium   |

            ### Resource Requests
            -
            -

            ### Open Discussion
            Topics for team feedback and alignment.
            """,
            isBuiltIn: true
        )
    }

    private static func executiveSummary() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000019")!,
            name: "Executive Summary",
            category: .business,
            icon: "star.square.on.square",
            description: "Concise executive summary with key findings and recommendations.",
            body: """
            ## Executive Summary

            **Subject:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Prepared by:**
            **Audience:**

            ---

            ### Purpose
            Why this document exists and what decision it supports.

            ---

            ### Background
            Brief context necessary to understand the findings.

            ---

            ### Key Findings

            1. **Finding 1:** Description with supporting data
            2. **Finding 2:** Description with supporting data
            3. **Finding 3:** Description with supporting data

            ---

            ### Analysis Summary

            | Factor | Current State | Impact | Urgency |
            |--------|--------------|--------|---------|
            |        |              | High   | Immediate |
            |        |              | Medium | Short-term |
            |        |              | Low    | Long-term |

            ---

            ### Recommendations

            1. **Recommendation 1:** Rationale and expected outcome
            2. **Recommendation 2:** Rationale and expected outcome
            3. **Recommendation 3:** Rationale and expected outcome

            ---

            ### Financial Impact
            - Estimated cost:
            - Expected benefit:
            - ROI timeline:

            ### Next Steps
            - [ ] Decision needed by [date]
            - [ ] Implementation begins [date]
            - [ ] Follow-up review on [date]

            ### Appendix
            Reference to detailed supporting documents.
            """,
            isBuiltIn: true
        )
    }

    // MARK: - Marketing

    private static func contentBrief() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000020")!,
            name: "Content Brief",
            category: .marketing,
            icon: "pencil.and.outline",
            description: "Content brief with audience, goals, key messages, and SEO keywords.",
            body: """
            ## Content Brief

            **Content Title:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Author:**
            **Content Type:** Blog / White Paper / Video / Social Post
            **Target Publish Date:**

            ---

            ### Objective
            What is the purpose of this content? What action should the reader take?

            ### Target Audience
            - **Primary persona:**
            - **Pain points:**
            - **Stage in funnel:** Awareness / Consideration / Decision

            ---

            ### Key Messages
            1. Main message to convey
            2. Supporting message
            3. Supporting message

            ### SEO Keywords

            | Keyword | Search Volume | Difficulty | Priority |
            |---------|--------------|------------|----------|
            |         |              |            | Primary  |
            |         |              |            | Secondary |
            |         |              |            | Secondary |

            ---

            ### Content Outline
            1. **Introduction** — Hook and context
            2. **Section 1** — Key point with supporting evidence
            3. **Section 2** — Key point with supporting evidence
            4. **Section 3** — Key point with supporting evidence
            5. **Conclusion** — Summary and call to action

            ---

            ### Tone & Style
            - Voice: Professional / Conversational / Technical
            - Length: Word count target
            - References / Sources:

            ### Distribution Channels
            - [ ] Blog
            - [ ] Email newsletter
            - [ ] Social media
            - [ ] Paid promotion

            ### Success Metrics
            - Target views:
            - Target engagement:
            - Conversion goal:
            """,
            isBuiltIn: true
        )
    }

    private static func marketingCampaignPlan() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000021")!,
            name: "Marketing Campaign Plan",
            category: .marketing,
            icon: "megaphone",
            description: "Campaign plan with objectives, channels, budget, timeline, and metrics.",
            body: """
            ## Marketing Campaign Plan

            **Campaign Name:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Campaign Lead:**
            **Duration:** Start — End

            ---

            ### Campaign Objective
            What specific outcome are we driving? Be measurable.

            ### Target Audience
            - **Demographics:**
            - **Psychographics:**
            - **Segments:**

            ---

            ### Key Messages
            - **Headline:**
            - **Value proposition:**
            - **Call to action:**

            ---

            ### Channel Strategy

            | Channel | Tactic | Budget | Owner | Timeline |
            |---------|--------|--------|-------|----------|
            | Email   |        | $      |       |          |
            | Social  |        | $      |       |          |
            | Paid Ads |       | $      |       |          |
            | Content |        | $      |       |          |
            | Events  |        | $      |       |          |

            ---

            ### Budget

            | Category | Planned | Actual |
            |----------|---------|--------|
            | Creative | $       | $      |
            | Media    | $       | $      |
            | Tools    | $       | $      |
            | **Total** | **$**  | **$**  |

            ---

            ### Timeline

            | Week | Activity | Status |
            |------|----------|--------|
            | 1    | Campaign prep & asset creation | |
            | 2    | Soft launch | |
            | 3-4  | Full launch | |
            | 5    | Optimization | |
            | 6    | Wrap-up & reporting | |

            ### Success Metrics

            | Metric | Target | Actual |
            |--------|--------|--------|
            | Impressions | | |
            | Click-through rate | | |
            | Conversions | | |
            | Cost per acquisition | | |
            | ROI | | |
            """,
            isBuiltIn: true
        )
    }

    private static func socialMediaPlan() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000022")!,
            name: "Social Media Plan",
            category: .marketing,
            icon: "bubble.left.and.bubble.right",
            description: "Social media strategy with platform plan and content calendar.",
            body: """
            ## Social Media Plan

            **Brand / Product:**
            **Period:** Month / Quarter
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Owner:**

            ---

            ### Goals
            1. Increase engagement by X%
            2. Grow followers by X
            3. Drive X visits to website

            ---

            ### Platform Strategy

            | Platform | Audience | Post Frequency | Content Focus |
            |----------|----------|---------------|---------------|
            | X (Twitter) | | 3-5x/week | Industry insights, engagement |
            | LinkedIn | | 2-3x/week | Thought leadership, company news |
            | Instagram | | 3-4x/week | Visual content, behind-the-scenes |
            | TikTok | | 2-3x/week | Short-form video, trends |

            ---

            ### Content Pillars
            1. **Educational** — Tips, how-tos, industry insights
            2. **Promotional** — Product features, launches, offers
            3. **Community** — User stories, behind-the-scenes, team highlights
            4. **Engagement** — Polls, questions, trending topics

            ---

            ### Weekly Content Calendar

            | Day | Platform | Content Type | Topic | Status |
            |-----|----------|-------------|-------|--------|
            | Mon |          |             |       | Draft  |
            | Tue |          |             |       | Draft  |
            | Wed |          |             |       | Draft  |
            | Thu |          |             |       | Draft  |
            | Fri |          |             |       | Draft  |

            ---

            ### Hashtag Strategy
            - Branded:
            - Industry:
            - Trending:

            ### Metrics to Track
            - Engagement rate
            - Follower growth
            - Click-through rate
            - Reach and impressions
            """,
            isBuiltIn: true
        )
    }

    private static func pressRelease() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000023")!,
            name: "Press Release",
            category: .marketing,
            icon: "newspaper",
            description: "Standard press release format with headline, dateline, body, and boilerplate.",
            body: """
            ## Press Release

            **FOR IMMEDIATE RELEASE**

            ---

            ### [Headline: Clear, Newsworthy Statement in Title Case]

            #### [Subheadline providing additional context]

            **[City, State]** — **\(Date.now.formatted(
                date: .long,
                time: .omitted
            ))** — [Company Name], [brief descriptor], today announced \
            [what is being announced]. This [product/initiative/partnership] \
            will [key benefit or impact].

            ---

            ### The News
            Expand on the announcement. What is it? Why does it matter? Include specific details, numbers, and dates.

            ### Supporting Quote
            "[Quote from executive or stakeholder about the significance \
            of the announcement]," said [Full Name], [Title] of \
            [Company Name]. "[Additional context or forward-looking statement]."

            ### Details & Context
            Provide background information, how it works, who benefits, \
            and any relevant industry context. Include data points or \
            statistics that support the story.

            ### Availability
            [When and where the product/service/initiative will be available. Include pricing if applicable.]

            ---

            ### About [Company Name]
            [Standard boilerplate: 2-3 sentence company description including founding year, mission, key facts, and website.]

            ---

            **Media Contact:**
            [Name]
            [Title]
            [Email]
            [Phone]

            ###
            """,
            isBuiltIn: true
        )
    }

    private static func brandGuidelines() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000024")!,
            name: "Brand Guidelines",
            category: .marketing,
            icon: "paintpalette",
            description: "Brand guidelines covering voice, tone, colors, and usage rules.",
            body: """
            ## Brand Guidelines

            **Brand:**
            **Version:** 1.0
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Owner:**

            ---

            ### Brand Mission & Values
            - **Mission:**
            - **Vision:**
            - **Core values:**
              1.
              2.
              3.

            ---

            ### Brand Voice & Tone

            **Voice attributes:**
            - Professional yet approachable
            - Confident but not arrogant
            - Clear and concise

            | Context | Tone | Example |
            |---------|------|---------|
            | Marketing copy | Enthusiastic, inspiring | |
            | Support | Empathetic, helpful | |
            | Technical docs | Clear, precise | |
            | Social media | Conversational, friendly | |

            **Words we use:**
            -

            **Words we avoid:**
            -

            ---

            ### Visual Identity

            #### Logo
            - Primary logo usage
            - Minimum size: Xpx
            - Clear space: X around all sides
            - Do not: stretch, recolor, add effects

            #### Color Palette

            | Color | Hex | RGB | Usage |
            |-------|-----|-----|-------|
            | Primary |  |  | Headers, CTA buttons |
            | Secondary |  |  | Accents, links |
            | Neutral |  |  | Body text, backgrounds |
            | Success |  |  | Positive states |
            | Warning |  |  | Caution states |

            #### Typography
            - **Headings:** Font name, weight
            - **Body:** Font name, weight
            - **Code / Mono:** Font name

            ---

            ### Photography & Imagery
            - Style: Authentic, high-quality
            - Subjects: People, products, workspaces
            - Avoid: Stock-photo cliches

            ### Usage Rules
            - [ ] Always use approved logo files
            - [ ] Maintain minimum contrast ratios
            - [ ] Follow tone guidelines for audience context
            """,
            isBuiltIn: true
        )
    }

    // MARK: - Engineering

    private static func technicalDesignDocument() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000025")!,
            name: "Technical Design Document",
            category: .engineering,
            icon: "wrench.and.screwdriver",
            description: "Technical design document with problem statement, proposed solution, and trade-offs.",
            body: """
            ## Technical Design Document

            **Title:**
            **Author:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Status:** Draft / In Review / Approved
            **Reviewers:**

            ---

            ### Problem Statement
            What problem does this solve? Include context and motivation.

            ### Goals & Non-Goals

            **Goals:**
            -
            -

            **Non-Goals:**
            -
            -

            ---

            ### Background
            Relevant technical context, existing systems, and prior work.

            ---

            ### Proposed Solution

            #### Architecture Overview
            Describe the high-level architecture. Include a diagram if helpful.

            #### Key Components
            1. **Component A** — Responsibility and interface
            2. **Component B** — Responsibility and interface
            3. **Component C** — Responsibility and interface

            #### Data Model
            Describe new or modified data structures.

            #### API Changes
            Describe new or modified API endpoints / interfaces.

            ---

            ### Alternatives Considered

            | Option | Pros | Cons |
            |--------|------|------|
            | Option A (chosen) | | |
            | Option B | | |
            | Option C | | |

            **Rationale for chosen approach:**

            ---

            ### Trade-offs
            - Performance vs. complexity
            - Consistency vs. availability
            - Build vs. buy

            ### Security Considerations
            -

            ### Testing Strategy
            - Unit tests:
            - Integration tests:
            - Performance benchmarks:

            ### Rollout Plan
            1. Feature flag
            2. Canary deployment
            3. Full rollout

            ### Open Questions
            - [ ] Question 1
            - [ ] Question 2
            """,
            isBuiltIn: true
        )
    }

    private static func bugReport() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000026")!,
            name: "Bug Report",
            category: .engineering,
            icon: "ladybug",
            description: "Bug report with steps to reproduce, expected vs actual behavior, and environment.",
            body: """
            ## Bug Report

            **Title:**
            **Reported by:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Severity:** Critical / High / Medium / Low
            **Priority:** P0 / P1 / P2 / P3

            ---

            ### Summary
            One-sentence description of the bug.

            ---

            ### Steps to Reproduce
            1. Go to [page/screen]
            2. Click on [element]
            3. Enter [data]
            4. Observe the result

            ### Expected Behavior
            What should happen when following the steps above.

            ### Actual Behavior
            What actually happens. Include error messages if any.

            ---

            ### Environment

            | Property | Value |
            |----------|-------|
            | OS | macOS [version] |
            | App Version | |
            | Device / Hardware | |
            | Browser (if web) | |
            | Account / User | |

            ---

            ### Screenshots / Recordings
            Attach relevant screenshots or screen recordings.

            ### Logs
            ```
            Paste relevant log output here.
            ```

            ---

            ### Additional Context
            - Frequency: Always / Sometimes / Rare
            - Regression: Yes / No / Unknown
            - Workaround available: Yes / No
            - Related issues:

            ### Investigation Notes
            -
            """,
            isBuiltIn: true
        )
    }

    private static func rfc() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000027")!,
            name: "RFC",
            category: .engineering,
            icon: "text.bubble",
            description: "Request for Comments with context, options, and recommendation.",
            body: """
            ## RFC: [Title]

            **Author:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Status:** Open for Comments / Accepted / Rejected
            **Deadline for feedback:**

            ---

            ### Context
            Describe the background and motivation for this RFC. What problem or opportunity prompted this proposal?

            ---

            ### Current State
            How does the system work today? What are the limitations?

            ---

            ### Proposal
            Describe the proposed change in detail.

            #### Option A: [Name]
            - **Description:**
            - **Pros:**
              -
              -
            - **Cons:**
              -
              -
            - **Estimated effort:**

            #### Option B: [Name]
            - **Description:**
            - **Pros:**
              -
              -
            - **Cons:**
              -
              -
            - **Estimated effort:**

            #### Option C: [Name]
            - **Description:**
            - **Pros:**
              -
              -
            - **Cons:**
              -
              -
            - **Estimated effort:**

            ---

            ### Recommendation
            **Recommended option:** Option [X]
            **Rationale:** Explain why this option is preferred.

            ---

            ### Impact Assessment
            - **Systems affected:**
            - **Migration needed:**
            - **Backward compatibility:**

            ### Open Questions
            1.
            2.

            ### Feedback

            | Reviewer | Vote | Comments |
            |----------|------|----------|
            |          | +1/0/-1 |       |
            |          | +1/0/-1 |       |
            """,
            isBuiltIn: true
        )
    }

    private static func apiDocumentation() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000028")!,
            name: "API Documentation",
            category: .engineering,
            icon: "curlybraces",
            description: "API documentation with endpoints, parameters, examples, and error codes.",
            body: """
            ## API Documentation

            **API Name:**
            **Base URL:** `https://api.example.com/v1`
            **Version:** 1.0
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Author:**

            ---

            ### Authentication
            - **Method:** Bearer Token / API Key / OAuth 2.0
            - **Header:** `Authorization: Bearer <token>`

            ---

            ### Endpoints

            #### `GET /resource`
            Retrieve a list of resources.

            **Parameters:**

            | Name | Type | Required | Description |
            |------|------|----------|-------------|
            | `page` | integer | No | Page number (default: 1) |
            | `limit` | integer | No | Items per page (default: 20) |
            | `filter` | string | No | Filter expression |

            **Response (200 OK):**
            ```json
            {
              "data": [
                {
                  "id": "abc123",
                  "name": "Example",
                  "created_at": "2025-01-01T00:00:00Z"
                }
              ],
              "meta": {
                "page": 1,
                "total": 100
              }
            }
            ```

            ---

            #### `POST /resource`
            Create a new resource.

            **Request Body:**
            ```json
            {
              "name": "New Resource",
              "description": "Details about the resource"
            }
            ```

            **Response (201 Created):**
            ```json
            {
              "id": "def456",
              "name": "New Resource",
              "created_at": "2025-01-01T00:00:00Z"
            }
            ```

            ---

            ### Error Codes

            | Code | Message | Description |
            |------|---------|-------------|
            | 400 | Bad Request | Invalid parameters |
            | 401 | Unauthorized | Missing or invalid token |
            | 403 | Forbidden | Insufficient permissions |
            | 404 | Not Found | Resource does not exist |
            | 429 | Too Many Requests | Rate limit exceeded |
            | 500 | Internal Server Error | Unexpected server error |

            ### Rate Limits
            - **Default:** 100 requests per minute
            - **Authenticated:** 1000 requests per minute
            """,
            isBuiltIn: true
        )
    }

    private static func incidentReport() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000029")!,
            name: "Incident Report",
            category: .engineering,
            icon: "exclamationmark.triangle",
            description: "Incident report with timeline, root cause, impact, and remediation steps.",
            body: """
            ## Incident Report

            **Incident Title:**
            **Severity:** SEV-1 / SEV-2 / SEV-3 / SEV-4
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Duration:** Start — End (Total: X hours)
            **Incident Commander:**
            **Status:** Resolved / Monitoring / Ongoing

            ---

            ### Summary
            Brief description of the incident, what was affected, and the business impact.

            ---

            ### Timeline (All times in UTC)

            | Time | Event |
            |------|-------|
            | HH:MM | Issue first detected / alert fired |
            | HH:MM | Incident declared, team assembled |
            | HH:MM | Root cause identified |
            | HH:MM | Fix deployed |
            | HH:MM | Service restored, incident resolved |

            ---

            ### Impact

            | Metric | Value |
            |--------|-------|
            | Users affected | |
            | Duration of impact | |
            | Revenue impact | $ |
            | SLA breach | Yes / No |

            ---

            ### Root Cause
            Detailed explanation of what caused the incident. Dig into contributing factors, not just the trigger.

            ### Contributing Factors
            1.
            2.
            3.

            ---

            ### What Went Well
            -
            -

            ### What Went Poorly
            -
            -

            ---

            ### Remediation Actions

            | Action | Owner | Priority | Due Date | Status |
            |--------|-------|----------|----------|--------|
            | Immediate fix | | P0 | | Done |
            | Prevent recurrence | | P1 | | To Do |
            | Improve detection | | P2 | | To Do |
            | Update runbook | | P2 | | To Do |

            ### Lessons Learned
            1.
            2.
            """,
            isBuiltIn: true
        )
    }

    // MARK: - HR & People

    private static func jobDescription() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000030")!,
            name: "Job Description",
            category: .hr,
            icon: "person.badge.plus",
            description: "Job description with role summary, responsibilities, and qualifications.",
            body: """
            ## Job Description

            **Job Title:**
            **Department:**
            **Reports to:**
            **Location:** Remote / Hybrid / On-site
            **Employment Type:** Full-time / Part-time / Contract
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))

            ---

            ### About Us
            Brief company description and mission statement.

            ---

            ### Role Summary
            Describe the role in 2-3 sentences. What will this person do and why does it matter?

            ---

            ### Key Responsibilities
            - Responsibility 1
            - Responsibility 2
            - Responsibility 3
            - Responsibility 4
            - Responsibility 5

            ---

            ### Required Qualifications
            - X+ years of experience in [field]
            - Proficiency in [skills/tools]
            - Strong [soft skill]
            - Bachelor's degree in [field] or equivalent experience

            ### Preferred Qualifications
            - Experience with [specific technology or domain]
            - Familiarity with [methodology or framework]
            - Certification in [relevant area]

            ---

            ### What We Offer
            - Competitive salary range: $X — $Y
            - Health, dental, and vision insurance
            - Retirement plan with company match
            - Professional development budget
            - Flexible work arrangements
            - Paid time off

            ---

            ### How to Apply
            Submit your resume and a brief cover letter explaining why you are a great fit for this role.

            **Application deadline:**
            **Contact:**

            *[Company Name] is an equal opportunity employer.*
            """,
            isBuiltIn: true
        )
    }

    private static func performanceReview() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000031")!,
            name: "Performance Review",
            category: .hr,
            icon: "star",
            description: "Performance review covering goals, strengths, and development areas.",
            body: """
            ## Performance Review

            **Employee:**
            **Title:**
            **Manager:**
            **Review Period:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))

            ---

            ### Goals Assessment

            | Goal | Target | Result | Rating |
            |------|--------|--------|--------|
            |      |        |        | Exceeds / Meets / Below |
            |      |        |        | Exceeds / Meets / Below |
            |      |        |        | Exceeds / Meets / Below |

            **Overall Goal Rating:** Exceeds Expectations / Meets Expectations / Below Expectations

            ---

            ### Core Competencies

            | Competency | Rating (1-5) | Comments |
            |-----------|-------------|----------|
            | Technical Skills | | |
            | Communication | | |
            | Collaboration | | |
            | Problem Solving | | |
            | Leadership | | |
            | Initiative | | |

            ---

            ### Strengths
            -
            -
            -

            ### Areas for Development
            -
            -
            -

            ---

            ### Key Accomplishments
            Highlight notable achievements during the review period.
            1.
            2.
            3.

            ### Feedback from Peers
            Summary of peer feedback received.

            ---

            ### Development Plan

            | Skill / Area | Action | Timeline | Support Needed |
            |-------------|--------|----------|---------------|
            |             |        |          |               |
            |             |        |          |               |

            ### Goals for Next Period
            1.
            2.
            3.

            ---

            ### Overall Rating
            **Rating:** Outstanding / Exceeds Expectations / Meets Expectations / Needs Improvement

            **Employee signature:** _______________  **Date:**
            **Manager signature:** _______________  **Date:**
            """,
            isBuiltIn: true
        )
    }

    private static func onboardingChecklist() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000032")!,
            name: "Onboarding Checklist",
            category: .hr,
            icon: "checklist",
            description: "New hire onboarding checklist with first-day, first-week, and first-month tasks.",
            body: """
            ## Onboarding Checklist

            **New Hire:**
            **Start Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Role:**
            **Manager:**
            **Buddy/Mentor:**

            ---

            ### Pre-Start (Before Day 1)
            - [ ] Send welcome email with start details
            - [ ] Set up workstation / ship equipment
            - [ ] Create email and accounts
            - [ ] Add to team channels (Slack, Teams, etc.)
            - [ ] Prepare onboarding schedule
            - [ ] Assign buddy/mentor

            ---

            ### Day 1
            - [ ] Welcome meeting with manager
            - [ ] Office tour / virtual workspace walkthrough
            - [ ] IT setup: laptop, VPN, passwords
            - [ ] Review company handbook and policies
            - [ ] Complete HR paperwork and benefits enrollment
            - [ ] Meet the immediate team
            - [ ] Set up development environment (if engineering)
            - [ ] First lunch with buddy

            ---

            ### Week 1
            - [ ] Attend team standup / recurring meetings
            - [ ] Review team documentation and wikis
            - [ ] Complete required compliance training
            - [ ] 1:1 with manager — set initial expectations
            - [ ] Meet cross-functional stakeholders
            - [ ] Start first small task or project
            - [ ] End-of-week check-in with manager

            ---

            ### First Month
            - [ ] Complete all onboarding training modules
            - [ ] Deliver first meaningful contribution
            - [ ] Attend company all-hands / town hall
            - [ ] Set 30/60/90-day goals with manager
            - [ ] Schedule 1:1s with key collaborators
            - [ ] Provide feedback on onboarding experience
            - [ ] 30-day check-in with manager and HR

            ---

            ### First 90 Days
            - [ ] Complete 90-day review with manager
            - [ ] Demonstrate proficiency in core responsibilities
            - [ ] Build relationships across the organization
            - [ ] Identify areas for growth and development

            ### Notes
            -
            """,
            isBuiltIn: true
        )
    }

    private static func interviewScorecard() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000033")!,
            name: "Interview Scorecard",
            category: .hr,
            icon: "list.number",
            description: "Interview scorecard with competency ratings and structured notes.",
            body: """
            ## Interview Scorecard

            **Candidate:**
            **Position:**
            **Interviewer:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Interview Stage:** Phone Screen / Technical / Behavioral / Final

            ---

            ### Rating Scale
            - **1** — Does not meet requirements
            - **2** — Partially meets requirements
            - **3** — Meets requirements
            - **4** — Exceeds requirements
            - **5** — Strongly exceeds requirements

            ---

            ### Competency Assessment

            | Competency | Rating (1-5) | Notes / Evidence |
            |-----------|-------------|-----------------|
            | Technical Skills | | |
            | Problem Solving | | |
            | Communication | | |
            | Collaboration / Teamwork | | |
            | Leadership Potential | | |
            | Culture Fit / Values Alignment | | |
            | Domain Knowledge | | |
            | Adaptability | | |

            ---

            ### Key Questions Asked
            1. **Q:** — **A summary:**
            2. **Q:** — **A summary:**
            3. **Q:** — **A summary:**

            ---

            ### Strengths Observed
            -
            -
            -

            ### Concerns or Red Flags
            -
            -

            ---

            ### Overall Assessment
            **Rating:** Strong Hire / Hire / No Hire / Strong No Hire

            ### Recommendation
            Briefly explain your recommendation and any conditions.

            ### Additional Notes
            -
            """,
            isBuiltIn: true
        )
    }

    private static func teamCharter() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000034")!,
            name: "Team Charter",
            category: .hr,
            icon: "flag",
            description: "Team charter defining mission, values, roles, and working norms.",
            body: """
            ## Team Charter

            **Team Name:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Team Lead:**

            ---

            ### Mission Statement
            Why does this team exist? What is our purpose?

            > Our mission is to...

            ---

            ### Team Values
            1. **Value 1** — What it means in practice
            2. **Value 2** — What it means in practice
            3. **Value 3** — What it means in practice

            ---

            ### Team Members & Roles

            | Name | Role | Key Responsibilities |
            |------|------|---------------------|
            |      |      |                     |
            |      |      |                     |
            |      |      |                     |
            |      |      |                     |

            ---

            ### Goals & Success Metrics

            | Goal | Metric | Target |
            |------|--------|--------|
            |      |        |        |
            |      |        |        |

            ---

            ### Working Norms

            **Communication:**
            - Primary channel: Slack / Teams / Email
            - Response time expectation: Within X hours
            - Escalation path:

            **Meetings:**
            - Standup: [day/time]
            - Planning: [day/time]
            - Retro: [day/time]

            **Decision Making:**
            - Method: Consensus / Majority / Lead decides
            - Escalation: When and how to escalate

            **Work Hours:**
            - Core hours: X — Y
            - Flexibility:

            ---

            ### Conflict Resolution
            How we handle disagreements:
            1. Discuss directly with the person
            2. Involve a neutral mediator
            3. Escalate to team lead

            ### How We Celebrate Wins
            -

            ### Charter Review
            This charter will be reviewed and updated every [quarter / 6 months].
            """,
            isBuiltIn: true
        )
    }

    // MARK: - Finance

    private static func budgetProposal() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000035")!,
            name: "Budget Proposal",
            category: .finance,
            icon: "dollarsign.circle",
            description: "Budget proposal with line items, justifications, and projected ROI.",
            body: """
            ## Budget Proposal

            **Department / Project:**
            **Fiscal Period:**
            **Prepared by:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Approval required from:**

            ---

            ### Executive Summary
            Brief description of what this budget covers and why it is needed.

            ---

            ### Budget Overview

            | Category | Description | Amount |
            |----------|-------------|--------|
            | Personnel | Salaries, contractors | $ |
            | Software & Tools | Licenses, subscriptions | $ |
            | Hardware | Equipment, infrastructure | $ |
            | Marketing | Campaigns, events | $ |
            | Training | Professional development | $ |
            | Travel | Conferences, client visits | $ |
            | Contingency | Unexpected expenses (10%) | $ |
            | **Total** | | **$** |

            ---

            ### Detailed Line Items

            #### Personnel
            | Item | Quantity | Unit Cost | Total | Justification |
            |------|----------|-----------|-------|--------------|
            |      |          | $         | $     |              |
            |      |          | $         | $     |              |

            #### Software & Tools
            | Item | Quantity | Unit Cost | Total | Justification |
            |------|----------|-----------|-------|--------------|
            |      |          | $         | $     |              |
            |      |          | $         | $     |              |

            ---

            ### Comparison to Previous Period

            | Category | Previous | Proposed | Change (%) |
            |----------|----------|----------|-----------|
            |          | $        | $        |           |
            |          | $        | $        |           |

            ---

            ### Projected ROI
            - Expected revenue / savings: $
            - Investment: $
            - ROI: X%
            - Payback period:

            ### Risks if Not Approved
            -
            -

            ### Approval
            - [ ] Department head
            - [ ] Finance review
            - [ ] Executive approval
            """,
            isBuiltIn: true
        )
    }

    private static func expenseReport() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000036")!,
            name: "Expense Report",
            category: .finance,
            icon: "receipt",
            description: "Itemized expense report with categories and approval tracking.",
            body: """
            ## Expense Report

            **Employee:**
            **Department:**
            **Reporting Period:**
            **Date Submitted:** \(Date.now.formatted(date: .long, time: .omitted))

            ---

            ### Summary

            | Category | Total |
            |----------|-------|
            | Travel | $ |
            | Meals & Entertainment | $ |
            | Lodging | $ |
            | Transportation | $ |
            | Supplies | $ |
            | Other | $ |
            | **Grand Total** | **$** |

            ---

            ### Itemized Expenses

            | Date | Description | Category | Vendor | Amount | Receipt |
            |------|-------------|----------|--------|--------|---------|
            |      |             |          |        | $      | Yes/No  |
            |      |             |          |        | $      | Yes/No  |
            |      |             |          |        | $      | Yes/No  |
            |      |             |          |        | $      | Yes/No  |
            |      |             |          |        | $      | Yes/No  |

            ---

            ### Business Purpose
            Explain the business purpose for these expenses.

            ### Notes
            Any additional context or explanations for specific line items.

            ---

            ### Approval

            | Role | Name | Signature | Date |
            |------|------|-----------|------|
            | Employee | | | |
            | Manager | | | |
            | Finance | | | |

            ### Payment Method
            - [ ] Corporate card
            - [ ] Personal card (reimbursement)
            - [ ] Cash advance

            ### Attachments
            - [ ] All receipts attached
            - [ ] Mileage log (if applicable)
            """,
            isBuiltIn: true
        )
    }

    private static func investmentMemo() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000037")!,
            name: "Investment Memo",
            category: .finance,
            icon: "banknote",
            description: "Investment memo covering market opportunity, financials, and risk assessment.",
            body: """
            ## Investment Memo

            **Company / Opportunity:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Prepared by:**
            **Investment Stage:** Seed / Series A / Series B / Growth

            ---

            ### Executive Summary
            Brief overview of the investment opportunity and recommendation.

            ---

            ### Company Overview
            - **Founded:**
            - **Headquarters:**
            - **Team size:**
            - **Product / Service:**
            - **Business model:**

            ---

            ### Market Opportunity
            - **Total addressable market (TAM):** $
            - **Serviceable addressable market (SAM):** $
            - **Current market share:**
            - **Growth rate:**

            ### Competitive Landscape

            | Competitor | Stage | Funding | Differentiation |
            |-----------|-------|---------|----------------|
            |           |       | $       |                |
            |           |       | $       |                |

            ---

            ### Financial Overview

            | Metric | Current | Projected (12 mo) | Projected (24 mo) |
            |--------|---------|-------------------|-------------------|
            | Revenue | $ | $ | $ |
            | Burn Rate | $/mo | $/mo | $/mo |
            | Gross Margin | % | % | % |
            | Customers | | | |

            ---

            ### Investment Terms
            - **Amount:** $
            - **Valuation:** $
            - **Instrument:** SAFE / Convertible / Priced Round
            - **Key terms:**

            ---

            ### Risk Assessment

            | Risk | Likelihood | Impact | Mitigation |
            |------|-----------|--------|------------|
            | Market risk | | | |
            | Execution risk | | | |
            | Competitive risk | | | |
            | Regulatory risk | | | |

            ### Strengths of the Opportunity
            -
            -

            ### Concerns
            -
            -

            ---

            ### Recommendation
            **Invest / Pass / Further Diligence**

            Rationale for recommendation.
            """,
            isBuiltIn: true
        )
    }

    // MARK: - Academic

    private static func lectureNotes() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000038")!,
            name: "Lecture Notes",
            category: .academic,
            icon: "graduationcap",
            description: "Lecture notes with topic overview, key concepts, examples, and questions.",
            body: """
            ## Lecture Notes

            **Course:**
            **Lecture #:**
            **Topic:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Instructor:**

            ---

            ### Overview
            Brief summary of what this lecture covers and how it connects to previous material.

            ---

            ### Key Concepts

            #### Concept 1: [Name]
            - Definition:
            - Explanation:
            - Why it matters:

            #### Concept 2: [Name]
            - Definition:
            - Explanation:
            - Why it matters:

            #### Concept 3: [Name]
            - Definition:
            - Explanation:
            - Why it matters:

            ---

            ### Examples

            **Example 1:**
            - Problem:
            - Solution:

            **Example 2:**
            - Problem:
            - Solution:

            ---

            ### Important Formulas / Definitions

            | Term / Formula | Definition / Explanation |
            |---------------|------------------------|
            |               |                        |
            |               |                        |
            |               |                        |

            ---

            ### Diagrams & Visuals
            Sketch or describe key diagrams from the lecture.

            ### Connections to Other Topics
            - Related to [previous lecture topic]:
            - Builds foundation for [upcoming topic]:

            ---

            ### Questions to Review
            1.
            2.
            3.

            ### Reading / Homework
            - [ ] Textbook chapter:
            - [ ] Problem set:
            - [ ] Additional reading:
            """,
            isBuiltIn: true
        )
    }

    private static func researchPaperOutline() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000039")!,
            name: "Research Paper Outline",
            category: .academic,
            icon: "doc.text.magnifyingglass",
            description: "Research paper outline with abstract, methodology, results, and references.",
            body: """
            ## Research Paper Outline

            **Title:**
            **Author(s):**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Course / Journal:**
            **Advisor:**

            ---

            ### Abstract
            150-250 word summary covering purpose, methodology, key findings, and conclusions.

            ---

            ### 1. Introduction
            - Background and context
            - Problem statement
            - Research question(s)
            - Significance of the study
            - Thesis statement

            ---

            ### 2. Literature Review
            - **Theme 1:** Summary of existing research
            - **Theme 2:** Summary of existing research
            - **Theme 3:** Summary of existing research
            - Gaps in current literature
            - How this paper addresses those gaps

            ---

            ### 3. Methodology
            - **Research design:** Qualitative / Quantitative / Mixed
            - **Participants / Sample:**
            - **Data collection methods:**
            - **Data analysis approach:**
            - **Limitations:**

            ---

            ### 4. Results
            - **Finding 1:** Description with supporting data
            - **Finding 2:** Description with supporting data
            - **Finding 3:** Description with supporting data
            - Tables and figures to include

            ---

            ### 5. Discussion
            - Interpretation of results
            - Comparison with existing literature
            - Implications
            - Limitations
            - Future research directions

            ---

            ### 6. Conclusion
            - Summary of key findings
            - Contribution to the field
            - Final thoughts

            ---

            ### References
            1.
            2.
            3.

            ### Appendices
            - Supplementary data
            - Survey instruments
            - Additional tables
            """,
            isBuiltIn: true
        )
    }

    private static func studyGuide() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000040")!,
            name: "Study Guide",
            category: .academic,
            icon: "book",
            description: "Study guide with topics, key terms, summaries, and practice questions.",
            body: """
            ## Study Guide

            **Course:**
            **Exam:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Chapters / Topics Covered:**

            ---

            ### Topic 1: [Name]

            **Key Terms:**
            | Term | Definition |
            |------|-----------|
            |      |           |
            |      |           |
            |      |           |

            **Summary:**
            Main ideas and concepts in your own words.

            **Practice Questions:**
            1. Q:
               A:
            2. Q:
               A:

            ---

            ### Topic 2: [Name]

            **Key Terms:**
            | Term | Definition |
            |------|-----------|
            |      |           |
            |      |           |

            **Summary:**
            Main ideas and concepts in your own words.

            **Practice Questions:**
            1. Q:
               A:
            2. Q:
               A:

            ---

            ### Topic 3: [Name]

            **Key Terms:**
            | Term | Definition |
            |------|-----------|
            |      |           |
            |      |           |

            **Summary:**
            Main ideas and concepts in your own words.

            **Practice Questions:**
            1. Q:
               A:

            ---

            ### Important Formulas / Theorems
            -
            -
            -

            ### Common Mistakes to Avoid
            -
            -

            ### Study Checklist
            - [ ] Review all lecture notes
            - [ ] Complete practice problems
            - [ ] Review key terms and definitions
            - [ ] Re-do homework problems
            - [ ] Form study group session
            - [ ] Get a good night's sleep
            """,
            isBuiltIn: true
        )
    }

    private static func essayOutline() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000041")!,
            name: "Essay Outline",
            category: .academic,
            icon: "text.alignleft",
            description: "Essay outline with thesis statement, supporting arguments, and conclusion.",
            body: """
            ## Essay Outline

            **Title:**
            **Author:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Course:**
            **Word count target:**

            ---

            ### I. Introduction
            - **Hook:** Opening statement to grab the reader's attention
            - **Context:** Background information the reader needs
            - **Thesis Statement:** Your main argument or claim

            > Thesis: [State your thesis here]

            ---

            ### II. Body Paragraph 1
            - **Topic sentence:** First main point supporting the thesis
            - **Evidence:** Quote, data, or example
            - **Analysis:** Explain how the evidence supports the point
            - **Transition:** Connect to next paragraph

            ---

            ### III. Body Paragraph 2
            - **Topic sentence:** Second main point supporting the thesis
            - **Evidence:** Quote, data, or example
            - **Analysis:** Explain how the evidence supports the point
            - **Transition:** Connect to next paragraph

            ---

            ### IV. Body Paragraph 3
            - **Topic sentence:** Third main point supporting the thesis
            - **Evidence:** Quote, data, or example
            - **Analysis:** Explain how the evidence supports the point
            - **Transition:** Lead into conclusion

            ---

            ### V. Counterargument (Optional)
            - **Opposing view:** Present the strongest counterargument
            - **Rebuttal:** Explain why your position is stronger

            ---

            ### VI. Conclusion
            - **Restate thesis:** Rephrase in light of the evidence presented
            - **Summarize key points:** Briefly recap main arguments
            - **Closing thought:** Broader implication or call to action

            ---

            ### Sources
            1.
            2.
            3.

            ### Writing Checklist
            - [ ] Strong thesis statement
            - [ ] Each paragraph has evidence
            - [ ] Smooth transitions
            - [ ] Proofread for grammar and clarity
            """,
            isBuiltIn: true
        )
    }

    private static func labReport() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000042")!,
            name: "Lab Report",
            category: .academic,
            icon: "flask",
            description: "Lab report with hypothesis, procedure, data, analysis, and conclusion.",
            body: """
            ## Lab Report

            **Experiment Title:**
            **Course:**
            **Student:**
            **Lab Partner(s):**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Instructor:**

            ---

            ### Objective
            State the purpose of the experiment.

            ### Hypothesis
            If [independent variable is changed], then [dependent variable will...] because [reasoning].

            ---

            ### Materials
            -
            -
            -
            -

            ---

            ### Procedure
            1. Step one
            2. Step two
            3. Step three
            4. Step four
            5. Step five

            ---

            ### Data

            | Trial | Variable 1 | Variable 2 | Observation |
            |-------|-----------|-----------|-------------|
            | 1     |           |           |             |
            | 2     |           |           |             |
            | 3     |           |           |             |
            | 4     |           |           |             |
            | 5     |           |           |             |

            ### Calculations
            Show key calculations used to process the data.

            ---

            ### Analysis
            - What patterns or trends appear in the data?
            - Do the results support or refute the hypothesis?
            - What is the percent error or uncertainty?

            ---

            ### Discussion
            - Interpret the results in the context of the theory
            - Sources of error and how they affected results
            - How could the experiment be improved?

            ---

            ### Conclusion
            Summarize findings. Was the hypothesis supported? What was learned?

            ### References
            1.
            2.
            """,
            isBuiltIn: true
        )
    }

    private static func readingNotes() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000043")!,
            name: "Reading Notes",
            category: .academic,
            icon: "bookmark",
            description: "Reading notes with summary, key quotes, analysis, and discussion questions.",
            body: """
            ## Reading Notes

            **Title:**
            **Author:**
            **Date Read:** \(Date.now.formatted(date: .long, time: .omitted))
            **Course / Context:**
            **Pages / Chapters:**

            ---

            ### Summary
            Write a concise summary of the main argument or narrative.

            ---

            ### Key Themes
            1. **Theme 1:** Explanation
            2. **Theme 2:** Explanation
            3. **Theme 3:** Explanation

            ---

            ### Key Quotes

            > "Quote from the text" (p. X)
            - **Why it matters:**

            > "Quote from the text" (p. X)
            - **Why it matters:**

            > "Quote from the text" (p. X)
            - **Why it matters:**

            ---

            ### Important Terms / Concepts

            | Term | Definition / Context |
            |------|---------------------|
            |      |                     |
            |      |                     |
            |      |                     |

            ---

            ### Analysis & Reactions
            - What arguments are most convincing? Why?
            - What do you disagree with? Why?
            - How does this connect to other readings or concepts?

            ---

            ### Connections
            - **Related to [other text/concept]:**
            - **Builds on [previous reading]:**
            - **Contradicts [other source]:**

            ### Discussion Questions
            1.
            2.
            3.

            ### Vocabulary
            - Word:
            - Word:
            """,
            isBuiltIn: true
        )
    }

    private static func groupProjectPlan() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000044")!,
            name: "Group Project Plan",
            category: .academic,
            icon: "person.3",
            description: "Group project plan with member roles, deadlines, and collaboration norms.",
            body: """
            ## Group Project Plan

            **Project Title:**
            **Course:**
            **Due Date:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))

            ---

            ### Team Members

            | Name | Role | Contact | Strengths |
            |------|------|---------|-----------|
            |      | Lead |         |           |
            |      | Researcher |  |           |
            |      | Writer |     |           |
            |      | Editor |     |           |

            ---

            ### Project Overview
            Brief description of the assignment and deliverables.

            ### Project Goals
            1.
            2.
            3.

            ---

            ### Task Breakdown

            | Task | Assignee | Start | Due | Status |
            |------|----------|-------|-----|--------|
            | Research |  |  |  | Not Started |
            | Outline |  |  |  | Not Started |
            | Draft Section 1 |  |  |  | Not Started |
            | Draft Section 2 |  |  |  | Not Started |
            | Draft Section 3 |  |  |  | Not Started |
            | Compile & Edit |  |  |  | Not Started |
            | Final Review |  |  |  | Not Started |
            | Submit |  |  |  | Not Started |

            ---

            ### Communication Plan
            - **Primary tool:** Slack / Discord / Group Chat
            - **Meeting schedule:** Weekly on [day] at [time]
            - **File sharing:** Google Drive / Dropbox / GitHub

            ---

            ### Ground Rules
            - Respond to messages within 24 hours
            - Notify the group immediately if you cannot meet a deadline
            - Review each other's work constructively
            - Attend all scheduled meetings or notify in advance

            ---

            ### Milestones
            - [ ] Research complete — [date]
            - [ ] First draft — [date]
            - [ ] Peer review — [date]
            - [ ] Final submission — [date]

            ### Contingency Plan
            What happens if someone falls behind or drops out.
            """,
            isBuiltIn: true
        )
    }

    private static func thesisOutline() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000045")!,
            name: "Thesis Outline",
            category: .academic,
            icon: "text.book.closed",
            description: "Thesis outline with chapters, literature review, methodology, and timeline.",
            body: """
            ## Thesis Outline

            **Title:**
            **Author:**
            **Degree:** M.A. / M.S. / Ph.D.
            **Department:**
            **Advisor:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))

            ---

            ### Research Question
            State the central question your thesis will address.

            ### Thesis Statement
            Your main argument or hypothesis.

            ---

            ### Chapter 1: Introduction
            - Background and motivation
            - Problem statement
            - Research objectives
            - Scope and limitations
            - Structure of the thesis

            ---

            ### Chapter 2: Literature Review
            - **Section 2.1:** Historical context and foundational work
            - **Section 2.2:** Current state of research
            - **Section 2.3:** Gaps in the literature
            - **Section 2.4:** Theoretical framework

            ---

            ### Chapter 3: Methodology
            - Research design
            - Data sources and collection
            - Analysis methods
            - Ethical considerations
            - Validity and reliability

            ---

            ### Chapter 4: Results / Findings
            - Presentation of data
            - Key findings organized by research question
            - Tables and figures

            ---

            ### Chapter 5: Discussion
            - Interpretation of findings
            - Comparison with existing literature
            - Implications (theoretical and practical)
            - Limitations

            ---

            ### Chapter 6: Conclusion
            - Summary of contributions
            - Recommendations
            - Future research directions

            ---

            ### Timeline

            | Phase | Start | End | Status |
            |-------|-------|-----|--------|
            | Literature review | | | |
            | Methodology design | | | |
            | Data collection | | | |
            | Analysis | | | |
            | Writing | | | |
            | Review & revision | | | |
            | Defense | | | |

            ### References
            Begin compiling references here.
            1.
            2.
            3.
            """,
            isBuiltIn: true
        )
    }

    // MARK: - Personal

    private static func weeklyPlanner() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000046")!,
            name: "Weekly Planner",
            category: .personal,
            icon: "calendar",
            description: "Weekly planner with priorities, daily tasks, and end-of-week reflection.",
            body: """
            ## Weekly Planner

            **Week of:** \(Date.now.formatted(date: .long, time: .omitted))

            ---

            ### Top Priorities This Week
            1.
            2.
            3.

            ---

            ### Monday
            - [ ] Task
            - [ ] Task
            - [ ] Task

            ### Tuesday
            - [ ] Task
            - [ ] Task
            - [ ] Task

            ### Wednesday
            - [ ] Task
            - [ ] Task
            - [ ] Task

            ### Thursday
            - [ ] Task
            - [ ] Task
            - [ ] Task

            ### Friday
            - [ ] Task
            - [ ] Task
            - [ ] Task

            ### Weekend
            - [ ] Personal task
            - [ ] Personal task

            ---

            ### Appointments & Commitments

            | Day | Time | Event |
            |-----|------|-------|
            |     |      |       |
            |     |      |       |
            |     |      |       |

            ---

            ### Habits to Maintain
            - [ ] Exercise (3x this week)
            - [ ] Read (30 min/day)
            - [ ] Meditate
            - [ ] Journal

            ---

            ### End-of-Week Reflection
            **What went well:**
            -

            **What could improve:**
            -

            **Carry over to next week:**
            -
            """,
            isBuiltIn: true
        )
    }

    private static func goalTracker() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000047")!,
            name: "Goal Tracker",
            category: .personal,
            icon: "target",
            description: "Goal tracker with objectives, key results, and milestone tracking.",
            body: """
            ## Goal Tracker

            **Period:** Q[1-4] [Year]
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))

            ---

            ### Goal 1: [Title]

            **Why this matters:**

            **Key Results:**
            - [ ] KR 1: Specific, measurable target — Progress: /
            - [ ] KR 2: Specific, measurable target — Progress: /
            - [ ] KR 3: Specific, measurable target — Progress: /

            **Milestones:**

            | Milestone | Target Date | Status |
            |-----------|-------------|--------|
            |           |             | Not Started |
            |           |             | Not Started |
            |           |             | Not Started |

            ---

            ### Goal 2: [Title]

            **Why this matters:**

            **Key Results:**
            - [ ] KR 1: Specific, measurable target — Progress: /
            - [ ] KR 2: Specific, measurable target — Progress: /

            **Milestones:**

            | Milestone | Target Date | Status |
            |-----------|-------------|--------|
            |           |             | Not Started |
            |           |             | Not Started |

            ---

            ### Goal 3: [Title]

            **Why this matters:**

            **Key Results:**
            - [ ] KR 1: Specific, measurable target — Progress: /
            - [ ] KR 2: Specific, measurable target — Progress: /

            ---

            ### Monthly Check-In

            | Month | Goal 1 Progress | Goal 2 Progress | Goal 3 Progress | Notes |
            |-------|----------------|----------------|----------------|-------|
            | Month 1 | % | % | % | |
            | Month 2 | % | % | % | |
            | Month 3 | % | % | % | |

            ### Obstacles & Adjustments
            -
            -

            ### Reflections
            -
            """,
            isBuiltIn: true
        )
    }

    private static func dailyJournal() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000048")!,
            name: "Daily Journal",
            category: .personal,
            icon: "book.closed",
            description: "Daily journal with gratitude, highlights, and reflections.",
            body: """
            ## Daily Journal

            **Date:** \\(Date.now.formatted(date: .long, time: .omitted))

            ---

            ### Gratitude
            Three things I am grateful for today:
            1.
            2.
            3.

            ---

            ### Morning Intentions
            What do I want to accomplish or focus on today?
            -
            -
            -

            ### How do I want to feel today?


            ---

            ### Today's Highlights
            What were the best moments of the day?
            -
            -
            -

            ---

            ### What I Learned
            New insights, ideas, or lessons from today.
            -

            ### Challenges
            What was difficult today? How did I handle it?
            -

            ---

            ### Evening Reflection
            **What went well today?**
            -

            **What could I have done better?**
            -

            **One thing I will do differently tomorrow:**
            -

            ---

            ### Mood Check
            How am I feeling right now? (1-10):

            ### Notes
            Free-form thoughts, ideas, or anything on my mind.
            """,
            isBuiltIn: true
        )
    }

    private static func decisionLog() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000049")!,
            name: "Decision Log",
            category: .personal,
            icon: "arrow.triangle.branch",
            description: "Decision log with options, pros and cons, and rationale for each choice.",
            body: """
            ## Decision Log

            **Date:** \(Date.now.formatted(date: .long, time: .omitted))

            ---

            ### Decision 1: [Title]

            **Context:** What prompted this decision?

            **Options:**

            | Option | Pros | Cons |
            |--------|------|------|
            | Option A | | |
            | Option B | | |
            | Option C | | |

            **Decision:** Option [X]
            **Rationale:** Why this option was chosen.
            **Expected outcome:**
            **Review date:** When to evaluate the decision.

            ---

            ### Decision 2: [Title]

            **Context:** What prompted this decision?

            **Options:**

            | Option | Pros | Cons |
            |--------|------|------|
            | Option A | | |
            | Option B | | |

            **Decision:** Option [X]
            **Rationale:**
            **Expected outcome:**
            **Review date:**

            ---

            ### Decision 3: [Title]

            **Context:**

            **Options:**

            | Option | Pros | Cons |
            |--------|------|------|
            | Option A | | |
            | Option B | | |

            **Decision:** Option [X]
            **Rationale:**
            **Expected outcome:**
            **Review date:**

            ---

            ### Past Decision Reviews

            | Decision | Date Made | Outcome | Lessons |
            |----------|-----------|---------|---------|
            |          |           | Good / Bad / Mixed |  |
            |          |           | Good / Bad / Mixed |  |
            """,
            isBuiltIn: true
        )
    }

    private static func habitTracker() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000050")!,
            name: "Habit Tracker",
            category: .personal,
            icon: "checkmark.circle",
            description: "Weekly habit tracker with streaks and reflection notes.",
            body: """
            ## Habit Tracker

            **Week of:** \(Date.now.formatted(date: .long, time: .omitted))

            ---

            ### Weekly Habits

            | Habit | Mon | Tue | Wed | Thu | Fri | Sat | Sun | Streak |
            |-------|-----|-----|-----|-----|-----|-----|-----|--------|
            | Exercise | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | days |
            | Read 30 min | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | days |
            | Meditate | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | days |
            | Drink 8 glasses water | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | days |
            | Journal | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | days |
            | No social media before noon | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | days |
            | 8 hours sleep | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | days |

            ---

            ### Habit Goals

            | Habit | Weekly Target | Actual | Hit Goal? |
            |-------|--------------|--------|-----------|
            | Exercise | 5x | | Yes / No |
            | Read 30 min | 7x | | Yes / No |
            | Meditate | 7x | | Yes / No |

            ---

            ### Weekly Reflection

            **Habits I nailed this week:**
            -

            **Habits I struggled with:**
            -

            **What made it easy / hard?**
            -

            **Adjustments for next week:**
            -

            ---

            ### Monthly Overview

            | Week | Completion Rate | Notes |
            |------|----------------|-------|
            | Week 1 | % | |
            | Week 2 | % | |
            | Week 3 | % | |
            | Week 4 | % | |
            """,
            isBuiltIn: true
        )
    }

    private static func travelPlanner() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000051")!,
            name: "Travel Planner",
            category: .personal,
            icon: "airplane",
            description: "Travel planner with itinerary, packing list, bookings, and budget.",
            body: """
            ## Travel Planner

            **Destination:**
            **Dates:** Departure — Return
            **Travelers:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))

            ---

            ### Bookings

            | Item | Details | Confirmation # | Cost |
            |------|---------|---------------|------|
            | Flight (outbound) | | | $ |
            | Flight (return) | | | $ |
            | Hotel / Accommodation | | | $ |
            | Car Rental | | | $ |
            | Travel Insurance | | | $ |

            ---

            ### Itinerary

            #### Day 1 — [Date]
            - **Morning:**
            - **Afternoon:**
            - **Evening:**
            - **Dinner reservation:**

            #### Day 2 — [Date]
            - **Morning:**
            - **Afternoon:**
            - **Evening:**

            #### Day 3 — [Date]
            - **Morning:**
            - **Afternoon:**
            - **Evening:**

            ---

            ### Budget

            | Category | Budgeted | Actual |
            |----------|----------|--------|
            | Flights | $ | $ |
            | Accommodation | $ | $ |
            | Food & Drink | $ | $ |
            | Activities | $ | $ |
            | Transportation | $ | $ |
            | Shopping | $ | $ |
            | **Total** | **$** | **$** |

            ---

            ### Packing Checklist

            **Essentials:**
            - [ ] Passport / ID
            - [ ] Boarding passes
            - [ ] Wallet / cash / cards
            - [ ] Phone + charger
            - [ ] Medications

            **Clothing:**
            - [ ] Tops
            - [ ] Bottoms
            - [ ] Outerwear
            - [ ] Shoes
            - [ ] Sleepwear

            **Toiletries:**
            - [ ] Toothbrush / toothpaste
            - [ ] Sunscreen
            - [ ] Personal care items

            ---

            ### Important Information
            - **Emergency contacts:**
            - **Embassy address:**
            - **Local emergency number:**
            - **WiFi / SIM plan:**
            """,
            isBuiltIn: true
        )
    }

    private static func personalOKRs() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000052")!,
            name: "Personal OKRs",
            category: .personal,
            icon: "scope",
            description: "Quarterly personal objectives and key results for focused goal setting.",
            body: """
            ## Personal OKRs

            **Quarter:** Q[1-4] [Year]
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))

            ---

            ### Objective 1: [Career / Professional]
            *What I want to achieve and why it matters.*

            **Key Results:**
            - [ ] KR 1.1: [Measurable outcome] — Current: / Target:
            - [ ] KR 1.2: [Measurable outcome] — Current: / Target:
            - [ ] KR 1.3: [Measurable outcome] — Current: / Target:

            **Initiatives:**
            - Action I will take to drive KR 1.1
            - Action I will take to drive KR 1.2

            ---

            ### Objective 2: [Health / Wellness]
            *What I want to achieve and why it matters.*

            **Key Results:**
            - [ ] KR 2.1: [Measurable outcome] — Current: / Target:
            - [ ] KR 2.2: [Measurable outcome] — Current: / Target:
            - [ ] KR 2.3: [Measurable outcome] — Current: / Target:

            **Initiatives:**
            -
            -

            ---

            ### Objective 3: [Personal Growth / Relationships]
            *What I want to achieve and why it matters.*

            **Key Results:**
            - [ ] KR 3.1: [Measurable outcome] — Current: / Target:
            - [ ] KR 3.2: [Measurable outcome] — Current: / Target:

            **Initiatives:**
            -
            -

            ---

            ### Scoring Guide
            - **0.0 – 0.3:** Failed to make real progress
            - **0.4 – 0.6:** Made progress but fell short
            - **0.7 – 1.0:** Delivered (0.7 is a good score)

            ### End-of-Quarter Review

            | Objective | KR Avg Score | Reflection |
            |-----------|-------------|------------|
            | Objective 1 | /1.0 | |
            | Objective 2 | /1.0 | |
            | Objective 3 | /1.0 | |

            ### What I Learned This Quarter
            -

            ### Adjustments for Next Quarter
            -
            """,
            isBuiltIn: true
        )
    }

    // MARK: - Communication

    private static func memo() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000053")!,
            name: "Memo",
            category: .communication,
            icon: "envelope",
            description: "Internal memo with standard to, from, date, subject, and body format.",
            body: """
            ## Memo

            **To:**
            **From:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Subject:**

            ---

            ### Purpose
            State the reason for this memo in one or two sentences.

            ---

            ### Background
            Provide the context needed to understand this memo. What has happened or changed that prompted this communication?

            ---

            ### Key Points

            1. **Point 1:** Explanation and supporting detail
            2. **Point 2:** Explanation and supporting detail
            3. **Point 3:** Explanation and supporting detail

            ---

            ### Impact
            Who is affected and how? What changes should people expect?

            ### Recommended Actions
            - [ ] Action item 1
            - [ ] Action item 2
            - [ ] Action item 3

            ---

            ### Timeline
            - **Effective date:**
            - **Deadline for response/action:**

            ### Questions or Concerns
            For questions, contact [name] at [email/phone].

            ---

            *This memo is confidential and intended only for the listed recipients.*
            """,
            isBuiltIn: true
        )
    }

    private static func presentationOutline() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000054")!,
            name: "Presentation Outline",
            category: .communication,
            icon: "rectangle.on.rectangle.angled",
            description: "Presentation outline with key messages, slide flow, and speaker notes.",
            body: """
            ## Presentation Outline

            **Title:**
            **Presenter:**
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Audience:**
            **Duration:** X minutes

            ---

            ### Objective
            What should the audience know, feel, or do after this presentation?

            ### Key Message
            The single most important takeaway.

            ---

            ### Slide Flow

            #### Slide 1: Title Slide
            - Title, subtitle, presenter name, date

            #### Slide 2: Agenda
            - Overview of topics to be covered

            #### Slide 3: Problem / Context
            - **Key point:**
            - **Speaker notes:**

            #### Slide 4: Solution / Proposal
            - **Key point:**
            - **Speaker notes:**

            #### Slide 5: Evidence / Data
            - **Key point:**
            - **Visual:** Chart / graph / table
            - **Speaker notes:**

            #### Slide 6: Details / Deep Dive
            - **Key point:**
            - **Speaker notes:**

            #### Slide 7: Timeline / Next Steps
            - **Key point:**
            - **Speaker notes:**

            #### Slide 8: Call to Action
            - **Key point:**
            - **Speaker notes:**

            #### Slide 9: Q&A
            - Open the floor for questions

            ---

            ### Design Notes
            - Color scheme:
            - Font:
            - Image style:

            ### Preparation Checklist
            - [ ] Draft all slides
            - [ ] Add speaker notes
            - [ ] Practice run-through (time it)
            - [ ] Test A/V setup
            - [ ] Prepare backup for demo/live portions
            - [ ] Print handouts (if needed)
            """,
            isBuiltIn: true
        )
    }

    private static func newsletter() -> DocumentTemplate {
        DocumentTemplate(
            id: UUID(uuidString: "B0000001-0000-0000-0000-000000000055")!,
            name: "Newsletter",
            category: .communication,
            icon: "tray.full",
            description: "Newsletter template with updates, highlights, and calls to action.",
            body: """
            ## Newsletter

            **Edition:** [Month Year] / Issue #
            **Date:** \(Date.now.formatted(date: .long, time: .omitted))
            **Author:**

            ---

            ### Welcome
            Brief opening message setting the tone for this edition.

            ---

            ### Top Story: [Headline]
            Lead with the most important or interesting update. Provide enough detail to engage the reader, with a link to learn more.

            ---

            ### News & Updates

            #### Update 1: [Title]
            Brief description of news item. What happened, why it matters, and what comes next.

            #### Update 2: [Title]
            Brief description of news item.

            #### Update 3: [Title]
            Brief description of news item.

            ---

            ### Highlights & Achievements
            - Achievement or milestone worth celebrating
            - Recognition of team or individual contribution
            - Interesting metric or data point

            ---

            ### Upcoming Events

            | Event | Date | Location | Details |
            |-------|------|----------|---------|
            |       |      |          |         |
            |       |      |          |         |

            ---

            ### Featured Content
            - **Article:** [Title and link]
            - **Video:** [Title and link]
            - **Resource:** [Title and link]

            ---

            ### Call to Action
            What do you want the reader to do next?

            - [ ] Register for [event]
            - [ ] Read [article]
            - [ ] Share feedback via [link]

            ---

            ### Connect With Us
            - Website:
            - Social media:
            - Contact email:

            *To unsubscribe or update your preferences, click [here].*
            """,
            isBuiltIn: true
        )
    }
}

// swiftlint:enable file_length force_unwrapping function_body_length
