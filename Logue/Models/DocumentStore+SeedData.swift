// swiftlint:disable file_length
import Foundation

// MARK: - Seed Data

// swiftlint:disable line_length function_body_length
extension DocumentStore {
    static func makeSeedDocuments() -> [WritingDocument] {
        let now = Date()
        let cal = Calendar.current

        /// Date helper — spread documents across the last week
        func daysAgo(_ days: Int, hour: Int = 10) -> Date {
            cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: now)) ?? Date()) ?? Date()
        }

        return [
            makeDoc1(date: daysAgo(0, hour: 9)),
            makeDoc2(date: daysAgo(1, hour: 14)),
            makeDoc3(date: daysAgo(2, hour: 11)),
            makeDoc4(date: daysAgo(3, hour: 15)),
            makeDoc5(date: daysAgo(5, hour: 10)),
            makeDoc6(date: daysAgo(7, hour: 13)),
            makeDoc7(date: daysAgo(1, hour: 10)),
            makeDoc8(date: daysAgo(3, hour: 9)),
            makeDoc9(date: daysAgo(0, hour: 14)),
            makeDoc10(date: daysAgo(2, hour: 16)),
        ]
    }

    // MARK: - Doc 1: Q3 Campaign Brief

    private static func makeDoc1(date: Date) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = "Q3 Campaign Brief"
        doc.goalMode = .business
        doc.tags = ["marketing", "Q3"]
        doc.spaceID = SeedSpaceID.clientProjects
        doc.isPinned = true
        doc.createdAt = date
        doc.modifiedAt = date
        doc.score = WritingScore(overall: 88, correctness: 91, clarity: 85, engagement: 84, delivery: 90)
        doc.body = """
        # Q3 Campaign Brief — Acme Corp

        ## Overview

        This document outlines the strategic marketing campaign for Acme Corp's Q3 product launch. The campaign spans July through September and targets both existing customers and new market segments in the mid-enterprise space.

        ## Objectives

        - **Primary:** Drive 2,500 qualified leads for the new Analytics Pro tier by end of Q3
        - **Secondary:** Increase brand awareness by 30% in the developer tools category
        - **Tertiary:** Achieve a 4:1 return on ad spend across all paid channels

        ## Target Audience

        Our primary audience is engineering managers and technical directors at companies with 200–2,000 employees. Secondary audience includes individual developers who influence purchasing decisions within their organizations.

        **Key personas:**
        - *Decision Maker Dana* — VP Engineering, budget authority, cares about ROI and team velocity
        - *Evaluator Eric* — Senior engineer, hands-on tester, values documentation and API quality

        ## Key Messaging

        The campaign centers on the theme **"Build Faster, Ship Smarter."** Core messages include:

        1. Analytics Pro reduces debugging time by 40% compared to legacy tools
        2. Seamless integration with existing CI/CD pipelines — setup in under 10 minutes
        3. Enterprise-grade security with SOC 2 Type II compliance

        ## Timeline

        | Phase | Dates | Focus |
        |-------|-------|-------|
        | Pre-launch | Jul 1–14 | Teaser content, influencer seeding |
        | Launch | Jul 15–31 | Product announcement, press outreach |
        | Sustain | Aug 1–Sep 15 | Paid media, webinars, case studies |
        | Close | Sep 16–30 | Retargeting, promotional offers |

        ## Budget Overview

        Total allocated budget: **$185,000**

        - Paid media (Google, LinkedIn): $78,000 (42%)
        - Content production: $35,000 (19%)
        - Events and webinars: $28,000 (15%)
        - Influencer partnerships: $24,000 (13%)
        - Contingency: $20,000 (11%)

        ## Success Metrics

        We will track weekly dashboards covering lead volume, cost per lead, conversion rates at each funnel stage, and pipeline attribution. A mid-campaign review is scheduled for August 8 to assess performance and reallocate spend if needed.
        """
        return doc
    }

    // MARK: - Doc 2: Weekly Status Update

    private static func makeDoc2(date: Date) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = "Weekly Status Update"
        doc.goalMode = .casual
        doc.tags = ["status", "weekly"]
        doc.spaceID = SeedSpaceID.internal
        doc.isPinned = false
        doc.createdAt = date
        doc.modifiedAt = date
        doc.score = WritingScore(overall: 79, correctness: 83, clarity: 80, engagement: 72, delivery: 78)
        doc.body = """
        # Weekly Status Update — Mar 10–14

        ## Completed

        - Finalized the onboarding flow redesign and handed off to engineering for implementation
        - Published two blog posts for the Q3 campaign pipeline (both scheduled for next week)
        - Wrapped up user interviews — 8 sessions completed, synthesis doc shared in #research
        - Fixed the broken analytics event on the pricing page (was causing a 15% undercount)

        ## In Progress

        - **Dashboard migration:** Moving legacy charts to the new component library. About 60% done, aiming to finish by Wednesday
        - **API docs rewrite:** Covering the authentication and webhooks sections. First draft out for review
        - **Hiring:** Phone screens for the senior frontend role — 3 candidates moving to the next round

        ## Blockers

        - Waiting on legal review for the updated Terms of Service before we can ship the data export feature. Followed up on Thursday, expecting a response Monday
        - The staging environment has been flaky since the infra migration. Filed a ticket with platform team but no ETA yet

        ## Notes

        - Out of office on Wednesday afternoon for a dentist appointment
        - Reminder: team retro is Thursday at 2pm, please add topics to the shared board beforehand
        """
        return doc
    }

    // MARK: - Doc 3: CS 301 — Lecture Notes: Graphs

    private static func makeDoc3(date: Date) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = "CS 301 — Lecture Notes: Graphs"
        doc.goalMode = .academic
        doc.tags = ["lecture", "algorithms"]
        doc.spaceID = SeedSpaceID.cs301
        doc.isPinned = false
        doc.createdAt = date
        doc.modifiedAt = date
        doc.score = WritingScore(overall: 85, correctness: 92, clarity: 82, engagement: 78, delivery: 86)
        doc.body = """
        # Graph Algorithms — Lecture 12

        ## Representations

        Graphs can be stored as an **adjacency matrix** (O(V²) space, O(1) edge lookup) or an **adjacency list** (O(V + E) space, O(degree) edge lookup). For sparse graphs, adjacency lists are almost always preferred.

        ## Breadth-First Search (BFS)

        BFS explores vertices layer by layer, making it ideal for finding the shortest path in unweighted graphs.

        ```
        BFS(G, s):
            for each vertex u in V - {s}:
                u.color = WHITE, u.d = INF, u.parent = NIL
            s.color = GRAY, s.d = 0, s.parent = NIL
            Q = empty queue
            ENQUEUE(Q, s)
            while Q is not empty:
                u = DEQUEUE(Q)
                for each v in Adj[u]:
                    if v.color == WHITE:
                        v.color = GRAY, v.d = u.d + 1, v.parent = u
                        ENQUEUE(Q, v)
                u.color = BLACK
        ```

        **Complexity:** O(V + E) time, O(V) space for the queue and visited set.

        ## Depth-First Search (DFS)

        DFS explores as deep as possible along each branch before backtracking. It naturally produces a DFS forest and assigns discovery/finish timestamps useful for topological sorting.

        ```
        DFS(G):
            for each vertex u in V:
                u.color = WHITE, u.parent = NIL
            time = 0
            for each vertex u in V:
                if u.color == WHITE:
                    DFS-VISIT(G, u)

        DFS-VISIT(G, u):
            time = time + 1, u.d = time, u.color = GRAY
            for each v in Adj[u]:
                if v.color == WHITE:
                    v.parent = u
                    DFS-VISIT(G, v)
            u.color = BLACK, time = time + 1, u.f = time
        ```

        **Complexity:** O(V + E) time, O(V) space (recursion stack in worst case).

        ## Shortest Path — Dijkstra's Algorithm

        For graphs with **non-negative edge weights**, Dijkstra's algorithm finds single-source shortest paths using a priority queue.

        ```
        DIJKSTRA(G, w, s):
            INITIALIZE-SINGLE-SOURCE(G, s)
            S = empty set
            Q = min-priority queue of V keyed by d
            while Q is not empty:
                u = EXTRACT-MIN(Q)
                S = S ∪ {u}
                for each v in Adj[u]:
                    RELAX(u, v, w)   // update v.d if u.d + w(u,v) < v.d
        ```

        **Complexity:** O((V + E) log V) with a binary heap, or O(V² + E) with a simple array.

        ## Key Takeaways

        - BFS → shortest path in unweighted graphs, level-order traversal
        - DFS → topological sort, cycle detection, connected components
        - Dijkstra → shortest path with non-negative weights; fails with negative edges (use Bellman-Ford instead)
        - All three run in O(V + E) or near-linear time, making them practical for large-scale graph problems
        """
        return doc
    }

    // MARK: - Doc 4: Business Ethics Case Study

    private static func makeDoc4(date: Date) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = "Business Ethics Case Study"
        doc.goalMode = .academic
        doc.tags = ["case-study", "ethics"]
        doc.spaceID = SeedSpaceID.businessEthics
        doc.isPinned = false
        doc.createdAt = date
        doc.modifiedAt = date
        doc.score = WritingScore(overall: 83, correctness: 86, clarity: 81, engagement: 80, delivery: 84)
        doc.body = """
        # Case Study: DataVault Inc. and User Privacy

        ## Background

        DataVault Inc. is a mid-size analytics company that provides behavioral tracking tools to e-commerce platforms. In 2025, an internal audit revealed that DataVault had been collecting granular location data from end users without explicit consent, bundling it into audience profiles sold to third-party advertisers. While their terms of service contained broad data-use language, no specific disclosure about location tracking or third-party sales was provided to users.

        ## Stakeholder Analysis

        - **End users:** Primary affected party. Location data was collected without informed consent, violating reasonable expectations of privacy. Risk of surveillance, profiling, and identity exposure.
        - **E-commerce clients:** Integrated DataVault's SDK in good faith. Now face reputational damage and potential regulatory liability for enabling unconsented data collection on their platforms.
        - **DataVault employees:** Engineers who raised concerns during development were told the feature was "within legal bounds." This created a culture of compliance over ethics.
        - **Advertisers:** Benefited from enriched audience profiles but may face scrutiny if the data is deemed unlawfully obtained.
        - **Regulators:** GDPR and CCPA authorities have a mandate to investigate and enforce, with potential fines reaching 4% of annual revenue.

        ## Ethical Framework Analysis

        **Utilitarian perspective:** The data collection generated revenue and improved ad relevance, but the aggregate harm to millions of users — loss of privacy, erosion of trust — substantially outweighs these commercial benefits.

        **Deontological perspective:** Kant's categorical imperative demands that individuals never be treated merely as means to an end. Collecting and selling personal location data without consent treats users as commodities, violating their autonomy and dignity.

        **Virtue ethics perspective:** A virtuous company would prioritize transparency and honesty. DataVault's deliberate obfuscation of its practices reflects a character failing at the organizational level — one that undermines trust in the broader tech ecosystem.

        ## Recommendation

        DataVault should immediately halt third-party location data sales, issue a transparent public disclosure, notify all affected users, and implement a genuine opt-in consent framework. The company should commission an independent privacy audit, establish an ethics review board with external members, and retrain its engineering and product teams on ethical data practices. Proactive cooperation with regulators will mitigate penalties and signal a genuine commitment to reform rather than damage control.
        """
        return doc
    }

    // MARK: - Doc 5: Travel Itinerary — Japan

    private static func makeDoc5(date: Date) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = "Travel Itinerary — Japan"
        doc.goalMode = .casual
        doc.tags = ["travel", "planning"]
        doc.spaceID = SeedSpaceID.personal
        doc.isPinned = true
        doc.createdAt = date
        doc.modifiedAt = date
        doc.score = WritingScore(overall: 76, correctness: 78, clarity: 79, engagement: 75, delivery: 73)
        doc.body = """
        # Japan Trip — 10 Days in April

        ## Overview

        - **Dates:** April 5–15
        - **Route:** Tokyo (4 nights) → Kyoto (3 nights) → Osaka (2 nights) → Tokyo (1 night, fly out)
        - **Budget:** ~$3,200 total (flights excluded)

        ## Tokyo — Days 1–4

        - **Day 1:** Arrive Narita, check into hotel in Shinjuku. Evening walk around Omoide Yokocho for yakitori and beer.
        - **Day 2:** Tsukiji Outer Market for breakfast. Teamlab Borderless in the morning. Shibuya crossing, Harajuku, and Meiji Shrine in the afternoon. Dinner in Ebisu.
        - **Day 3:** Day trip to Kamakura — Great Buddha, Hase-dera Temple, Komachi-dori street. Back to Tokyo for dinner in Akihabara.
        - **Day 4:** Asakusa (Senso-ji Temple), Ueno Park, and the Tokyo National Museum. Evening: Shinjuku Gyoen if cherry blossoms are still blooming. Pack for Kyoto.

        **Accommodation:** Hotel Gracery Shinjuku — $130/night

        ## Kyoto — Days 5–7

        - **Day 5:** Shinkansen to Kyoto (2h 15m). Check in near Gion. Fushimi Inari in the late afternoon when crowds thin out.
        - **Day 6:** Arashiyama bamboo grove early morning. Tenryu-ji Temple. Monkey park. Afternoon: Nishiki Market.
        - **Day 7:** Kinkaku-ji (Golden Pavilion), Ryoan-ji rock garden, and Nijo Castle. Evening tea ceremony experience in Gion.

        **Accommodation:** Piece Hostel Sanjo — $75/night

        ## Osaka — Days 8–9

        - **Day 8:** Train to Osaka (15 min). Osaka Castle in the morning. Dotonbori for street food — takoyaki, okonomiyaki, kushikatsu. Evening: Shinsekai district.
        - **Day 9:** Day trip to Nara — deer park, Todai-ji Temple. Back to Osaka for a final dinner at a local izakaya.

        **Accommodation:** Cross Hotel Osaka — $110/night

        ## Day 10 — Return

        Morning shinkansen back to Tokyo. Last-minute shopping in Tokyo Station. Fly out from Narita at 6pm.

        ## Budget Breakdown

        | Category | Estimate |
        |----------|----------|
        | Accommodation | $1,235 |
        | JR Pass (14-day) | $380 |
        | Food | $900 |
        | Activities & entry fees | $250 |
        | Misc & souvenirs | $435 |
        | **Total** | **~$3,200** |

        ## Packing Notes

        - Comfortable walking shoes (15k+ steps per day expected)
        - Portable Wi-Fi or eSIM — rent from airport on arrival
        - Light layers — April weather is mild but rain is possible
        """
        return doc
    }

    // MARK: - Doc 6: Meeting Prep — Acme Review

    private static func makeDoc6(date: Date) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = "Meeting Prep — Acme Review"
        doc.goalMode = .business
        doc.tags = ["meeting-prep", "acme"]
        doc.spaceID = SeedSpaceID.clientProjects
        doc.isPinned = false
        doc.createdAt = date
        doc.modifiedAt = date
        doc.score = WritingScore(overall: 81, correctness: 84, clarity: 82, engagement: 76, delivery: 80)
        doc.body = """
        # Quarterly Review — Acme Corp

        ## Meeting Details

        - **Date:** March 21, 2026, 2:00–3:30 PM
        - **Attendees:** Sarah Chen (Acme VP Product), Mike Torres (Acme Eng Lead), our team (Priya, James, me)
        - **Format:** Video call, slides shared async beforehand

        ## Agenda

        1. **Q1 performance review** (20 min) — walk through KPI dashboard, highlight wins and areas for improvement
        2. **Roadmap update** (15 min) — preview Q2 deliverables, get alignment on priorities
        3. **Open issues** (15 min) — address the three outstanding bugs and the API rate-limiting request
        4. **Contract renewal discussion** (20 min) — current agreement expires May 31, propose terms for renewal
        5. **Q&A and next steps** (20 min)

        ## KPIs to Present

        - **Uptime:** 99.94% (target was 99.9%) — exceeded SLA for 11 of 12 weeks
        - **API response time:** P95 at 142ms, down from 210ms at the start of the engagement
        - **Support tickets resolved:** Average resolution time dropped from 18 hours to 6.5 hours
        - **Feature delivery:** 14 of 16 planned features shipped on time; 2 pushed to Q2 due to scope changes approved by Acme

        ## Questions to Ask

        - How is the team finding the new dashboard? Any gaps in the data they need?
        - Are there upcoming product launches on Acme's side that would affect our integration timeline?
        - What does their internal budget cycle look like for the renewal — do they need a proposal by a specific date?
        - Would they be open to a case study or co-marketing opportunity?

        ## Prep Checklist

        - [ ] Finalize the slide deck and share by EOD Wednesday
        - [ ] Pull the latest KPI numbers from the analytics dashboard
        - [ ] Review the three open bug tickets and have status updates ready
        - [ ] Draft renewal proposal with two pricing options (annual flat rate vs. usage-based)
        - [ ] Test screen sharing and video setup 15 minutes before the call
        """
        return doc
    }

    // MARK: - Doc 7: Client Engagement Agreement (Legal)

    private static func makeDoc7(date: Date) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = "Client Engagement Agreement"
        doc.goalMode = .business
        doc.tags = ["contract", "engagement", "legal"]
        doc.spaceID = SeedSpaceID.legal
        doc.isPinned = true
        doc.createdAt = date
        doc.modifiedAt = date
        doc.score = WritingScore(overall: 90, correctness: 93, clarity: 88, engagement: 86, delivery: 92)
        doc.body = """
        # Client Engagement Agreement

        **Agreement No.:** LEG-2026-0347
        **Effective Date:** March 15, 2026
        **Parties:** Logue Legal Partners LLP ("Firm") and Meridian Technologies Inc. ("Client")

        ---

        ## 1. Scope of Engagement

        The Firm agrees to provide the following legal services to the Client:

        - **Primary:** Corporate governance advisory for Series C funding round
        - **Secondary:** Intellectual property review and patent filing coordination
        - **Tertiary:** Regulatory compliance assessment (SEC, FTC)

        > **Note:** This engagement does not cover litigation, tax advisory, or immigration matters unless explicitly amended in writing per Section 8 below.

        ### 1.1 Deliverables

        1. Due diligence report on existing IP portfolio
           - Patent landscape analysis
           - Trademark conflict assessment
           - Trade secret audit
        2. Corporate restructuring memo for investor-ready governance
           - Board composition recommendations
           - Stock option plan review
           - ~~Shareholder agreement redline~~ *(moved to Phase 2)*
        3. Regulatory compliance checklist with gap analysis

        ## 2. Fee Schedule

        | Service Category | Rate Type | Rate | Estimated Hours | Cap |
        |-----------------|-----------|------|----------------|-----|
        | Partner consultation | Hourly | $650/hr | 40 | $26,000 |
        | Associate research | Hourly | $375/hr | 120 | $45,000 |
        | Patent filing | Flat fee | $8,500/filing | 3 filings | $25,500 |
        | Regulatory review | Blended | $450/hr | 60 | $27,000 |
        | **Total estimated** | | | | **$123,500** |

        > All fees are exclusive of government filing fees, court costs, and third-party expenses, which shall be billed at cost plus 5% administrative overhead.

        ## 3. Payment Terms

        - [x] Net-30 invoicing on the 1st of each month
        - [x] 2% early payment discount if paid within 10 days
        - [ ] Late payments accrue interest at 1.5% per month
        - [ ] Retainer of $15,000 due upon execution

        ## 4. Confidentiality

        Both parties agree to maintain strict confidentiality of all information exchanged during this engagement. This obligation survives termination of the agreement for a period of **five (5) years**.

        ```
        CONFIDENTIALITY CLASSIFICATION:
        Level 1 — Public: Marketing materials, press releases
        Level 2 — Internal: Financial projections, org charts
        Level 3 — Restricted: IP filings, trade secrets, source code
        Level 4 — Privileged: Attorney-client communications
        ```

        ## 5. Termination

        Either party may terminate this agreement with **30 days written notice**. Upon termination:

        1. All outstanding fees become immediately due
        2. Work product completed to date shall be delivered to Client
        3. Confidentiality obligations continue per Section 4

        ---

        *This agreement constitutes the entire understanding between the parties and supersedes all prior negotiations, representations, or agreements relating to this subject matter.*
        """
        doc.reviewGrade = OverallGrade(
            averageScore: 88,
            letterGrade: "A-",
            summary: "Well-structured legal document with clear terms. Fee schedule is transparent. Minor improvements needed in termination clause specificity.",
            grades: [
                Grade(
                    category: .thesis,
                    score: 90,
                    letterGrade: "A",
                    feedback: "Clear statement of engagement scope and limitations.",
                    strengths: ["Explicit exclusions listed", "Well-defined deliverables"],
                    improvements: ["Add timeline for each deliverable"]
                ),
                Grade(
                    category: .evidence,
                    score: 85,
                    letterGrade: "B+",
                    feedback: "Fee schedule is detailed with caps. Payment terms could be more specific.",
                    strengths: ["Itemized fee breakdown", "Rate caps protect client"],
                    improvements: ["Specify invoice dispute process"]
                ),
                Grade(
                    category: .organization,
                    score: 92,
                    letterGrade: "A",
                    feedback: "Logical section flow from scope through fees to termination.",
                    strengths: ["Numbered sections", "Clear hierarchy"],
                    improvements: []
                ),
                Grade(
                    category: .style,
                    score: 86,
                    letterGrade: "B+",
                    feedback: "Professional tone appropriate for legal document.",
                    strengths: ["Consistent formatting", "Appropriate legal register"],
                    improvements: ["Simplify some compound sentences"]
                ),
                Grade(
                    category: .grammar,
                    score: 90,
                    letterGrade: "A",
                    feedback: "Clean prose with no grammatical errors.",
                    strengths: ["Error-free text", "Proper punctuation"],
                    improvements: []
                ),
                Grade(
                    category: .clarity,
                    score: 87,
                    letterGrade: "B+",
                    feedback: "Most terms are clearly defined. Confidentiality levels are a nice touch.",
                    strengths: ["Classification system is clear", "Termination steps are numbered"],
                    improvements: ["Define 'written notice' — email, certified mail, or both?"]
                ),
            ]
        )
        doc.reviewReactions = [
            SectionReaction(
                sectionTitle: "Scope of Engagement",
                sectionText: "The Firm agrees to provide the following legal services...",
                dominantEmotion: .engaged,
                emotionScores: [.engaged: 75, .inspired: 15, .bored: 10],
                explanation: "Clear, well-organized scope sets expectations effectively."
            ),
            SectionReaction(
                sectionTitle: "Fee Schedule",
                sectionText: "Service Category | Rate Type | Rate...",
                dominantEmotion: .skeptical,
                emotionScores: [.skeptical: 45, .engaged: 35, .confused: 20],
                explanation: "Rates are high; readers may question value. The caps provide some comfort."
            ),
            SectionReaction(
                sectionTitle: "Confidentiality",
                sectionText: "Both parties agree to maintain strict confidentiality...",
                dominantEmotion: .inspired,
                emotionScores: [.inspired: 50, .engaged: 40, .bored: 10],
                explanation: "The classification system is a thoughtful addition that goes beyond standard boilerplate."
            ),
        ]
        doc.vocabSuggestions = [
            VocabSuggestion(
                original: "strict confidentiality",
                suggestion: "absolute confidentiality",
                explanation: "'Absolute' carries stronger legal weight than 'strict' in confidentiality clauses.",
                category: "precision"
            ),
            VocabSuggestion(
                original: "survives termination",
                suggestion: "survives termination or expiration",
                explanation: "Standard legal drafting includes both termination and natural expiration.",
                category: "completeness"
            ),
            VocabSuggestion(
                original: "immediately due",
                suggestion: "immediately due and payable",
                explanation: "'Due and payable' is the standard legal phrase for accelerated payment obligations.",
                category: "legal convention"
            ),
        ]
        return doc
    }

    // MARK: - Doc 8: Regulatory Compliance Checklist (Legal)

    private static func makeDoc8(date: Date) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = "Regulatory Compliance Checklist"
        doc.goalMode = .technical
        doc.tags = ["compliance", "GDPR", "CCPA", "checklist"]
        doc.spaceID = SeedSpaceID.legal
        doc.isPinned = false
        doc.createdAt = date
        doc.modifiedAt = date
        doc.score = WritingScore(overall: 84, correctness: 89, clarity: 83, engagement: 78, delivery: 85)
        doc.body = """
        # Regulatory Compliance Checklist — Data Privacy

        **Last Updated:** March 2026
        **Applicable Regulations:** GDPR (EU), CCPA/CPRA (California), PIPEDA (Canada)
        **Compliance Officer:** Rebecca Torres, JD

        ## GDPR Compliance

        ### Lawful Basis for Processing

        - [x] Documented lawful basis for each processing activity
        - [x] Consent mechanism meets GDPR requirements (freely given, specific, informed, unambiguous)
        - [ ] Legitimate interest assessments completed for non-consent processing
        - [x] Data processing agreements signed with all processors

        > **GDPR Article 6(1):** Processing shall be lawful only if and to the extent that at least one of the following applies: (a) consent, (b) contract performance, (c) legal obligation, (d) vital interests, (e) public task, (f) legitimate interests.

        ### Data Subject Rights

        | Right | GDPR Article | Implementation Status | Response SLA |
        |-------|-------------|----------------------|-------------|
        | Access | Art. 15 | **Complete** | 30 days |
        | Rectification | Art. 16 | **Complete** | 30 days |
        | Erasure | Art. 17 | **In Progress** | 30 days |
        | Portability | Art. 20 | **Planned** | 30 days |
        | Objection | Art. 21 | **Complete** | 30 days |

        ### Data Protection Impact Assessment

        ```
        DPIA Required When:
        ├── Systematic monitoring of public areas
        ├── Large-scale processing of sensitive data
        ├── Automated decision-making with legal effects
        └── New technology deployment affecting personal data

        DPIA Template Reference: DPIA-TEMPLATE-v3.2
        Completed DPIAs: 4/7 processing activities
        Next Review: Q2 2026
        ```

        ## CCPA/CPRA Compliance

        ### Consumer Rights Implementation

        - [x] "Do Not Sell My Personal Information" link on all customer-facing pages
        - [x] Privacy policy updated with CCPA-required disclosures
        - [ ] Sensitive personal information opt-out mechanism
        - [ ] Annual data inventory refresh for CPRA categories
        - [x] Service provider agreements updated with CCPA addendum

        ### Data Categories Inventory

        ```
        Category A — Identifiers: name, email, IP address, account ID
        Category B — Personal Records: billing address, phone number
        Category C — Protected Classifications: age, gender (voluntary)
        Category D — Commercial Info: purchase history, preferences
        Category F — Internet Activity: browsing history, search terms
        Category G — Geolocation: approximate city-level location
        ```

        ## PIPEDA Compliance (Canada)

        - [x] Privacy policy available in English and French
        - [ ] Cross-border data transfer documentation
        - [x] Breach notification procedures established (72-hour window)
        - [ ] Annual privacy impact assessment

        ## Open Items & Risk Register

        | Item | Regulation | Risk Level | Owner | Due Date |
        |------|-----------|-----------|-------|----------|
        | Erasure API endpoint | GDPR Art. 17 | **High** | Engineering | Apr 15 |
        | Data portability export | GDPR Art. 20 | **Medium** | Engineering | May 30 |
        | Sensitive data opt-out | CPRA | **High** | Product | Apr 1 |
        | Cross-border docs | PIPEDA | **Medium** | Legal | Apr 30 |
        | Cookie consent refresh | ePrivacy | **Low** | Marketing | Jun 1 |
        """
        doc.factChecks = [
            FactCheck(
                claim: "GDPR Article 6(1) lists six lawful bases for processing",
                status: .verified,
                explanation: "Article 6(1)(a)-(f) of the GDPR lists exactly six lawful bases: consent, contract, legal obligation, vital interests, public task, and legitimate interests.",
                sources: ["EU General Data Protection Regulation, Article 6(1)"],
                confidence: 98
            ),
            FactCheck(
                claim: "GDPR requires 30-day response SLA for data subject requests",
                status: .verified,
                explanation: "Article 12(3) states controllers must respond 'without undue delay and in any event within one month of receipt of the request.'",
                sources: ["GDPR Article 12(3)"],
                confidence: 95
            ),
            FactCheck(
                claim: "PIPEDA requires 72-hour breach notification window",
                status: .uncertain,
                explanation: "PIPEDA's breach notification regulations require notification 'as soon as feasible' after determination of a breach. The 72-hour window is a GDPR requirement (Article 33), not PIPEDA.",
                sources: ["PIPEDA Breach of Security Safeguards Regulations", "GDPR Article 33"],
                confidence: 40
            ),
            FactCheck(
                claim: "CCPA requires a 'Do Not Sell My Personal Information' link",
                status: .verified,
                explanation: "California Civil Code §1798.135(a) requires businesses to provide a clear and conspicuous link titled 'Do Not Sell My Personal Information' on their internet homepage.",
                sources: ["California Civil Code §1798.135(a)"],
                confidence: 97
            ),
        ]
        doc.chatMessages = [
            ChatMessage(role: .user, content: "Does the erasure endpoint need to handle data stored in backups too?"),
            ChatMessage(
                role: .assistant,
                content: "Under GDPR Article 17, the right to erasure applies to all copies of the data, including backups. However, the ICO guidance notes that if erasure from backups is technically infeasible, you may keep the backup data provided you have measures to ensure the data is not actively processed and is deleted when the backup cycle completes. Document this approach in your DPIA."
            ),
        ]
        return doc
    }

    // MARK: - Doc 9: Patient Intake Summary (Healthcare — PII showcase)

    private static func makeDoc9(date: Date) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = "Patient Intake Summary — Maria Santos"
        doc.goalMode = .business
        doc.tags = ["patient", "intake", "confidential"]
        doc.spaceID = SeedSpaceID.healthcare
        doc.isPinned = true
        doc.createdAt = date
        doc.modifiedAt = date
        doc.score = WritingScore(overall: 82, correctness: 88, clarity: 80, engagement: 74, delivery: 84)
        doc.body = """
        # Patient Intake Summary

        **Date of Visit:** March 20, 2026
        **Provider:** Dr. Angela Chen, MD — Internal Medicine
        **Facility:** Bayside Medical Center, Suite 204

        ---

        ## Demographics

        | Field | Details |
        |-------|---------|
        | **Full Name** | Maria Elena Santos |
        | **Date of Birth** | July 14, 1983 |
        | **Age** | 42 |
        | **Sex** | Female |
        | **SSN** | 478-22-9163 |
        | **MRN** | BMC-2026-081447 |
        | **Address** | 2847 Lakeshore Drive, Apt 6B, San Mateo, CA 94401 |
        | **Phone** | (650) 555-0193 |
        | **Email** | maria.santos83@example.com |
        | **Emergency Contact** | Carlos Santos (spouse) — (650) 555-0247 |

        ## Insurance Information

        | Field | Details |
        |-------|---------|
        | **Primary Insurance** | Blue Shield of California |
        | **Policy Number** | BSC-4478291-A |
        | **Group Number** | GRP-887421 |
        | **Subscriber** | Maria Elena Santos |
        | **Secondary Insurance** | None |
        | **Copay** | $35 |

        ## Chief Complaint

        Patient presents with persistent fatigue and intermittent joint pain in both hands for the past 6 weeks. Reports morning stiffness lasting approximately 45 minutes daily. No recent trauma or injury.

        ## Medical History

        ### Current Medications

        | Medication | Dosage | Frequency | Prescriber |
        |-----------|--------|-----------|-----------|
        | Levothyroxine | 75 mcg | Daily, AM | Dr. Chen |
        | Vitamin D3 | 2000 IU | Daily | OTC |
        | Ibuprofen | 400 mg | PRN | OTC |

        ### Past Medical History

        - Hypothyroidism (diagnosed 2019)
        - Seasonal allergies
        - Appendectomy (2005)
        - ~~Gestational diabetes (2014)~~ — resolved postpartum

        ### Family History

        - **Mother:** Rheumatoid arthritis, Type 2 diabetes
        - **Father:** Hypertension, coronary artery disease
        - **Sister:** Lupus (SLE)

        ## Vitals

        | Measurement | Value | Normal Range |
        |------------|-------|-------------|
        | Blood Pressure | 128/82 mmHg | <120/80 |
        | Heart Rate | 76 bpm | 60–100 |
        | Temperature | 98.4°F | 97.8–99.1 |
        | Weight | 148 lbs | — |
        | BMI | 25.3 | 18.5–24.9 |
        | SpO2 | 98% | 95–100% |

        ## Assessment & Plan

        1. **Fatigue with joint pain** — differential includes early rheumatoid arthritis, lupus, or thyroid under-replacement
           - Order: CBC, CMP, ESR, CRP, ANA, RF, anti-CCP, TSH
           - Referral to rheumatology if ANA or RF positive
        2. **Hypothyroidism** — TSH last checked 8 months ago
           - Recheck TSH and free T4 with above labs
           - May need levothyroxine dose adjustment
        3. **Elevated BMI** — borderline overweight
           - Dietary counseling provided
           - Follow up in 4 weeks with lab results

        > **HIPAA Notice:** This document contains Protected Health Information (PHI). Unauthorized disclosure is prohibited under 45 CFR Parts 160 and 164.

        ---

        *Next appointment: April 17, 2026 at 10:30 AM — Dr. Chen*
        *Patient portal: bayside-medical.com/portal — Username: msantos2026*
        """
        doc.piiFindings = [
            PIIFinding(
                category: .identity,
                text: "Maria Elena Santos",
                detail: "Full patient name appears multiple times in demographics and insurance sections"
            ),
            PIIFinding(category: .identity, text: "July 14, 1983", detail: "Patient date of birth — combined with name enables identity theft"),
            PIIFinding(category: .governmentIDs, text: "478-22-9163", detail: "Social Security Number — highest-risk PII, enables financial fraud"),
            PIIFinding(category: .contact, text: "(650) 555-0193", detail: "Patient phone number"),
            PIIFinding(category: .contact, text: "maria.santos83@example.com", detail: "Patient email address"),
            PIIFinding(category: .contact, text: "2847 Lakeshore Drive, Apt 6B, San Mateo, CA 94401", detail: "Full home address"),
            PIIFinding(category: .health, text: "BSC-4478291-A", detail: "Health insurance policy number — can be used for insurance fraud"),
            PIIFinding(category: .health, text: "BMC-2026-081447", detail: "Medical Record Number — links to full patient medical history"),
            PIIFinding(category: .identity, text: "Carlos Santos", detail: "Emergency contact name — reveals family relationship"),
            PIIFinding(category: .contact, text: "(650) 555-0247", detail: "Emergency contact phone number"),
            PIIFinding(
                category: .credentials,
                text: "msantos2026",
                detail: "Patient portal username — could enable unauthorized medical record access"
            ),
        ]
        return doc
    }

    // MARK: - Doc 10: Clinical Research Protocol (Healthcare)

    private static func makeDoc10(date: Date) -> WritingDocument {
        var doc = WritingDocument()
        doc.title = "Clinical Research Protocol — Phase II Trial"
        doc.goalMode = .academic
        doc.tags = ["research", "clinical-trial", "protocol"]
        doc.spaceID = SeedSpaceID.healthcare
        doc.isPinned = false
        doc.createdAt = date
        doc.modifiedAt = date
        doc.score = WritingScore(overall: 87, correctness: 92, clarity: 84, engagement: 80, delivery: 89)
        doc.body = """
        # Phase II Clinical Trial Protocol

        **Protocol ID:** BTC-RA-2026-Phase2
        **Sponsor:** Bayside Therapeutics Corp.
        **Principal Investigator:** Dr. James Nakamura, MD, PhD
        **IND Number:** IND-182934

        ---

        ## 1. Study Overview

        > *"The goal of this Phase II trial is to evaluate the efficacy and safety of BTC-4501, a novel JAK1-selective inhibitor, in patients with moderate-to-severe rheumatoid arthritis who have had an inadequate response to methotrexate."*

        ### 1.1 Primary Objective

        Determine the proportion of patients achieving ACR20 response at Week 12 compared to placebo.

        ### 1.2 Secondary Objectives

        1. Assess ACR50 and ACR70 response rates at Weeks 12 and 24
        2. Evaluate change from baseline in DAS28-CRP
        3. Characterize safety and tolerability profile
           - Adverse event frequency and severity
           - Laboratory abnormalities (hepatic, hematologic)
           - Infection rates

        ## 2. Study Design

        Randomized, double-blind, placebo-controlled, parallel-group study.

        | Parameter | Details |
        |-----------|---------|
        | **Enrollment target** | 240 patients (80 per arm) |
        | **Randomization** | 1:1:1 (low dose : high dose : placebo) |
        | **Treatment duration** | 24 weeks |
        | **Follow-up** | 4 weeks post-treatment |
        | **Sites** | 18 centers across US and Canada |

        ### 2.1 Dosing Schedule

        | Arm | Drug | Dose | Route | Frequency |
        |-----|------|------|-------|-----------|
        | A | BTC-4501 | 5 mg | Oral | Once daily |
        | B | BTC-4501 | 15 mg | Oral | Once daily |
        | C | Placebo | — | Oral | Once daily |

        > **21 CFR 312.23(a)(6):** The protocol must include a description of the dosage form, route of administration, and duration of treatment.

        ## 3. Statistical Analysis Plan

        ### 3.1 Sample Size Justification

        Assuming ACR20 response rates of 55% (treatment) vs 30% (placebo), with α = 0.05 (two-sided) and 90% power:

        ```
        n = (Z_α/2 + Z_β)² × (p₁(1-p₁) + p₂(1-p₂)) / (p₁ - p₂)²
        n = (1.96 + 1.28)² × (0.55×0.45 + 0.30×0.70) / (0.55 - 0.30)²
        n = 10.4976 × (0.2475 + 0.21) / 0.0625
        n = 10.4976 × 0.4575 / 0.0625
        n ≈ 77 per arm → 80 per arm (accounting for ~5% dropout)
        ```

        ### 3.2 Primary Endpoint Analysis

        ```python
        # Primary analysis — logistic regression
        from scipy import stats

        def primary_analysis(treatment, placebo):
            # Cochran-Mantel-Haenszel test stratified by region
            # and prior biologic use
            odds_ratio, p_value = stats.fisher_exact(
                [[responders_tx, non_responders_tx],
                 [responders_pl, non_responders_pl]]
            )
            return odds_ratio, p_value

        # Missing data: multiple imputation (m=20)
        # Sensitivity: tipping point analysis
        ```

        ### 3.3 Endpoints Summary

        | Endpoint | Measure | Timepoint | Analysis Method |
        |----------|---------|-----------|----------------|
        | **Primary** | ACR20 response | Week 12 | CMH test, stratified |
        | Secondary | ACR50/70 response | Week 12, 24 | Logistic regression |
        | Secondary | DAS28-CRP change | Week 12, 24 | MMRM |
        | Safety | AE incidence | Ongoing | Descriptive statistics |
        | Exploratory | ~~HAQ-DI change~~ | ~~Week 24~~ | *Amended: removed per DSMB recommendation* |

        ## 4. Inclusion / Exclusion Criteria

        ### 4.1 Inclusion

        - Adults aged 18–75 with RA diagnosis per 2010 ACR/EULAR criteria
        - Active disease: DAS28-CRP ≥ 3.2 at screening
        - Inadequate response to methotrexate (≥ 15 mg/week for ≥ 12 weeks)
        - Stable methotrexate dose for ≥ 4 weeks prior to randomization

        ### 4.2 Exclusion

        - Prior use of any JAK inhibitor
        - Active or latent tuberculosis
        - History of malignancy within 5 years (except non-melanoma skin cancer)
        - ~~eGFR < 40 mL/min~~ → *Amended to eGFR < 30 mL/min per Protocol Amendment 2*
        - Pregnancy or breastfeeding

        ## 5. Regulatory References

        > **ICH E6(R2) §4.5.1:** *"The investigator should ensure that the clinical trial is conducted in compliance with the protocol."*

        > **Declaration of Helsinki (2013) §25:** *"The design and performance of each research study involving human subjects must be clearly described and justified in a research protocol."*
        """
        doc.aiDetectionResult = "AI Likelihood: 12% — This document appears to be primarily human-authored. The technical specificity of the protocol design, regulatory citations, and statistical formulas are consistent with expert scientific writing. Minor AI-like patterns detected in the overview section phrasing."
        doc.plagiarismResult = "Similarity Score: 8% — Low risk. Matched content limited to standard regulatory citations (ICH E6, Declaration of Helsinki) and conventional clinical trial terminology. No substantial overlap with published protocols in the reference database."
        doc.rewriteResult = RewriteResult(
            style: "Plain Language Summary",
            originalText: "Determine the proportion of patients achieving ACR20 response at Week 12 compared to placebo.",
            rewrittenText: "Find out how many patients show meaningful improvement in their rheumatoid arthritis symptoms after 12 weeks of treatment with BTC-4501 compared to patients who received a sugar pill."
        )
        return doc
    }
}

// swiftlint:enable line_length function_body_length
