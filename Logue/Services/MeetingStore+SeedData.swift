// swiftlint:disable file_length
import Foundation
import SwiftUI

// MARK: - Seed Data for Website Screenshots

// swiftlint:disable line_length force_unwrapping function_body_length

extension MeetingStore {
    static func makeSeedMeetings() -> [MeetingNote] {
        let now = Date()
        let cal = Calendar.current

        func daysAgo(_ days: Int, hour: Int = 10) -> Date {
            cal.date(
                byAdding: .hour,
                value: hour,
                to: cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: now))!
            )!
        }

        return [
            makeMeeting1(date: daysAgo(0, hour: 10)),
            makeMeeting2(date: daysAgo(1, hour: 14)),
            makeMeeting3(date: daysAgo(2, hour: 11)),
            makeMeeting4(date: daysAgo(4, hour: 10)),
            makeMeeting5(date: daysAgo(6, hour: 15)),
            makeMeeting6(date: daysAgo(1, hour: 9)),
            makeMeeting7(date: daysAgo(3, hour: 16)),
            makeMeeting8(date: daysAgo(0, hour: 13)),
            makeMeeting9(date: daysAgo(2, hour: 15)),
        ]
    }

    // MARK: - Helper

    private static func seg(_ text: String, start: TimeInterval, end: TimeInterval, speaker: String, confidence: Double = 0.95) -> TranscriptSegment {
        TranscriptSegment(text: text, startTime: start, endTime: end, speakerLabel: speaker, confidence: confidence)
    }

    private static func spkSeg(_ speakerId: String, start: TimeInterval, end: TimeInterval, text: String) -> SpeakerSegment {
        SpeakerSegment(speakerId: speakerId, startTime: start, endTime: end, text: text)
    }

    /// Due date helper — days from now (positive = future, negative = overdue).
    private static func due(_ daysFromNow: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: daysFromNow, to: Calendar.current.startOfDay(for: .now))!
    }

    // MARK: - Meeting 1: Acme Q3 Kickoff

    private static func makeMeeting1(date: Date) -> MeetingNote {
        let sp1 = "speaker-sarah", sp2 = "speaker-james", sp3 = "speaker-priya"
        let speakers = [
            Speaker(id: sp1, name: "Sarah", color: AppThemeConstants.speakerBlurple),
            Speaker(id: sp2, name: "James", color: AppThemeConstants.speakerGreen),
            Speaker(id: sp3, name: "Priya", color: AppThemeConstants.speakerOrange),
        ]
        let segments = [
            seg(
                "Alright everyone, thanks for joining. Let's kick off the Q3 campaign planning for Acme.",
                start: 0,
                end: 12,
                speaker: "Sarah"
            ),
            seg(
                "Thanks Sarah. From our side, the big priority this quarter is the product rebrand launch in August.",
                start: 12,
                end: 26,
                speaker: "James"
            ),
            seg(
                "That aligns well with what we had in mind. Priya, can you walk us through the creative direction?",
                start: 26,
                end: 38,
                speaker: "Sarah"
            ),
            seg(
                "Sure. We're thinking a clean, modern aesthetic — moving away from the heavy illustration style toward photography-driven layouts.",
                start: 38,
                end: 55,
                speaker: "Priya"
            ),
            seg(
                "I love that direction. Our internal brand team has been pushing for exactly that kind of shift.",
                start: 55,
                end: 68,
                speaker: "James"
            ),
            seg(
                "Great. In terms of deliverables, we're looking at the landing page, social assets, and a launch video. Timeline is six weeks.",
                start: 68,
                end: 85,
                speaker: "Sarah"
            ),
            seg(
                "Six weeks is tight but doable if we lock the creative brief by end of this week.",
                start: 85,
                end: 98,
                speaker: "Priya"
            ),
            seg(
                "Agreed. James, does the forty-five K budget we discussed still work on your end?",
                start: 98,
                end: 112,
                speaker: "Sarah"
            ),
            seg(
                "Yes, that's been approved internally. I'll send the signed SOW over by Thursday.",
                start: 112,
                end: 125,
                speaker: "James"
            ),
            seg(
                "Perfect. Let's schedule the design review for next Tuesday so we can keep momentum. I'll send the invite out today.",
                start: 125,
                end: 142,
                speaker: "Sarah"
            ),
            seg(
                "Sounds good. I'll have initial mood boards and a style tile ready by then.",
                start: 142,
                end: 155,
                speaker: "Priya"
            ),
            seg(
                "This is shaping up nicely. Looking forward to seeing the first concepts. Thanks everyone.",
                start: 155,
                end: 168,
                speaker: "James"
            ),
        ]
        let speakerSegments = [
            spkSeg(sp1, start: 0, end: 12, text: "Alright everyone, thanks for joining. Let's kick off the Q3 campaign planning for Acme."),
            spkSeg(
                sp2,
                start: 12,
                end: 26,
                text: "Thanks Sarah. From our side, the big priority this quarter is the product rebrand launch in August."
            ),
            spkSeg(
                sp1,
                start: 26,
                end: 38,
                text: "That aligns well with what we had in mind. Priya, can you walk us through the creative direction?"
            ),
            spkSeg(
                sp3,
                start: 38,
                end: 55,
                text: "Sure. We're thinking a clean, modern aesthetic — moving away from the heavy illustration style toward photography-driven layouts."
            ),
            spkSeg(sp2, start: 55, end: 68, text: "I love that direction. Our internal brand team has been pushing for exactly that kind of shift."),
            spkSeg(
                sp1,
                start: 68,
                end: 85,
                text: "Great. In terms of deliverables, we're looking at the landing page, social assets, and a launch video. Timeline is six weeks."
            ),
            spkSeg(sp3, start: 85, end: 98, text: "Six weeks is tight but doable if we lock the creative brief by end of this week."),
            spkSeg(sp1, start: 98, end: 112, text: "Agreed. James, does the forty-five K budget we discussed still work on your end?"),
            spkSeg(sp2, start: 112, end: 125, text: "Yes, that's been approved internally. I'll send the signed SOW over by Thursday."),
            spkSeg(
                sp1,
                start: 125,
                end: 142,
                text: "Perfect. Let's schedule the design review for next Tuesday so we can keep momentum. I'll send the invite out today."
            ),
            spkSeg(sp3, start: 142, end: 155, text: "Sounds good. I'll have initial mood boards and a style tile ready by then."),
            spkSeg(sp2, start: 155, end: 168, text: "This is shaping up nicely. Looking forward to seeing the first concepts. Thanks everyone."),
        ]

        var meeting = MeetingNote(
            title: "Acme Q3 Kickoff",
            createdAt: date,
            modifiedAt: date,
            recordingMode: .inPerson,
            spaceID: SeedSpaceID.clientProjects
        )
        meeting.duration = 168
        meeting.speakers = speakers
        meeting.segments = segments
        meeting.speakerSegments = speakerSegments
        meeting.hasSpeakerData = true
        meeting.summary = "Kicked off Q3 campaign planning for Acme's product rebrand. Agreed on a photography-driven creative direction, six-week timeline, and $45K budget. Design review scheduled for next Tuesday."
        meeting.isPinned = true
        meeting.tags = ["client", "Q3"]
        meeting.actionItems = [
            ActionItem(title: "Finalize creative brief", assignee: "Priya", dueDescription: "End of this week", dueDate: due(3)),
            ActionItem(title: "Schedule design review for next Tuesday", assignee: "Sarah", dueDescription: "Today", dueDate: due(0)),
            ActionItem(title: "Send signed SOW", assignee: "James", dueDescription: "By Thursday", dueDate: due(2)),
        ]
        meeting.bookmarks = [
            Bookmark(label: "Creative direction", timestamp: 38, color: .blue),
            Bookmark(label: "Budget confirmed", timestamp: 98, color: .purple),
            Bookmark(label: "Next steps", timestamp: 125, color: .orange),
        ]
        meeting.smartMinutes = SmartMinutes(
            keyDecisions: [
                "Photography-driven creative direction approved over illustration style",
                "Budget set at $45K — approved by Acme internally",
                "Six-week delivery timeline starting this week",
            ],
            discussionPoints: [
                "Q3 priority is the August product rebrand launch",
                "Deliverables include landing page, social assets, and launch video",
                "Creative brief must be locked this week to meet timeline",
            ],
            actionItems: [
                "Priya to finalize creative brief by end of week",
                "Sarah to send design review invite for next Tuesday",
                "James to send signed SOW by Thursday",
            ],
            followUps: [
                "Design review next Tuesday with mood boards and style tile",
                "Priya to prepare initial concepts before review",
            ],
            attendeeSummary: [
                AttendeeContribution(name: "Sarah", keyPoints: ["Set timeline and deliverables", "Confirmed budget"], speakingTimePercent: 40),
                AttendeeContribution(name: "James", keyPoints: ["Confirmed rebrand priority", "Approved budget"], speakingTimePercent: 30),
                AttendeeContribution(
                    name: "Priya",
                    keyPoints: ["Proposed creative direction", "Committed to brief timeline"],
                    speakingTimePercent: 30
                ),
            ]
        )
        return meeting
    }

    // MARK: - Meeting 2: Sprint Retrospective

    private static func makeMeeting2(date: Date) -> MeetingNote {
        let sp1 = "speaker-alex", sp2 = "speaker-dana", sp3 = "speaker-raj"
        let speakers = [
            Speaker(id: sp1, name: "Alex", color: AppThemeConstants.speakerBlurple),
            Speaker(id: sp2, name: "Dana", color: AppThemeConstants.speakerPink),
            Speaker(id: sp3, name: "Raj", color: AppThemeConstants.speakerCyan),
        ]
        let segments = [
            seg(
                "Let's get the retro started. Same format — what went well, what didn't, and what we want to change.",
                start: 0,
                end: 14,
                speaker: "Alex"
            ),
            seg(
                "I'll start with what went well. The new component library saved us a ton of time on the settings page redesign.",
                start: 14,
                end: 28,
                speaker: "Dana"
            ),
            seg(
                "Agreed. On the backend side, the migration to the new database schema went smoother than expected. Zero downtime.",
                start: 28,
                end: 44,
                speaker: "Raj"
            ),
            seg(
                "Nice. Now what didn't go well? I know code review turnaround was an issue again.",
                start: 44,
                end: 56,
                speaker: "Alex"
            ),
            seg(
                "Yeah, I had a PR sitting for three days. It blocked the entire notifications feature from moving forward.",
                start: 56,
                end: 70,
                speaker: "Dana"
            ),
            seg(
                "That's on me partly. I was deep in the migration and let reviews pile up. We need a better system for that.",
                start: 70,
                end: 86,
                speaker: "Raj"
            ),
            seg(
                "What if we set a twenty-four hour SLA for reviews? And rotate a designated reviewer each day so someone always has it as a priority.",
                start: 86,
                end: 106,
                speaker: "Alex"
            ),
            seg(
                "I like that. Also, we should add more integration tests. We caught two regressions late in the sprint that better test coverage would have prevented.",
                start: 106,
                end: 125,
                speaker: "Dana"
            ),
            seg(
                "Good call. I can set up a testing workshop next week to get everyone aligned on the integration test patterns we want to use.",
                start: 125,
                end: 140,
                speaker: "Raj"
            ),
        ]
        let speakerSegments = [
            spkSeg(
                sp1,
                start: 0,
                end: 14,
                text: "Let's get the retro started. Same format — what went well, what didn't, and what we want to change."
            ),
            spkSeg(
                sp2,
                start: 14,
                end: 28,
                text: "I'll start with what went well. The new component library saved us a ton of time on the settings page redesign."
            ),
            spkSeg(
                sp3,
                start: 28,
                end: 44,
                text: "Agreed. On the backend side, the migration to the new database schema went smoother than expected. Zero downtime."
            ),
            spkSeg(sp1, start: 44, end: 56, text: "Nice. Now what didn't go well? I know code review turnaround was an issue again."),
            spkSeg(
                sp2,
                start: 56,
                end: 70,
                text: "Yeah, I had a PR sitting for three days. It blocked the entire notifications feature from moving forward."
            ),
            spkSeg(
                sp3,
                start: 70,
                end: 86,
                text: "That's on me partly. I was deep in the migration and let reviews pile up. We need a better system for that."
            ),
            spkSeg(
                sp1,
                start: 86,
                end: 106,
                text: "What if we set a twenty-four hour SLA for reviews? And rotate a designated reviewer each day so someone always has it as a priority."
            ),
            spkSeg(
                sp2,
                start: 106,
                end: 125,
                text: "I like that. Also, we should add more integration tests. We caught two regressions late in the sprint that better test coverage would have prevented."
            ),
            spkSeg(
                sp3,
                start: 125,
                end: 140,
                text: "Good call. I can set up a testing workshop next week to get everyone aligned on the integration test patterns we want to use."
            ),
        ]

        var meeting = MeetingNote(
            title: "Sprint Retrospective",
            createdAt: date,
            modifiedAt: date,
            recordingMode: .inPerson,
            spaceID: SeedSpaceID.internal
        )
        meeting.duration = 140
        meeting.speakers = speakers
        meeting.segments = segments
        meeting.speakerSegments = speakerSegments
        meeting.hasSpeakerData = true
        meeting.summary = "Sprint retro covering wins (component library, zero-downtime migration) and pain points (slow code reviews blocking features). Agreed on a 24-hour review SLA with daily rotation and more integration tests."
        meeting.isPinned = false
        meeting.tags = ["sprint", "retro"]
        meeting.actionItems = [
            ActionItem(
                title: "Implement 24-hour code review SLA with daily reviewer rotation",
                assignee: "Alex",
                dueDescription: "Next sprint",
                dueDate: due(5)
            ),
            ActionItem(
                title: "Add integration tests for notifications and settings flows",
                assignee: "Dana",
                dueDescription: "Next sprint",
                dueDate: due(5)
            ),
            ActionItem(title: "Run testing workshop on integration test patterns", assignee: "Raj", dueDescription: "Next week", dueDate: due(4)),
        ]
        meeting.bookmarks = [
            Bookmark(label: "What went well", timestamp: 14, color: .blue),
            Bookmark(label: "Review bottleneck", timestamp: 56, color: .red),
            Bookmark(label: "Improvement ideas", timestamp: 86, color: .purple),
        ]
        meeting.smartMinutes = SmartMinutes(
            keyDecisions: [
                "24-hour SLA for code reviews with rotating daily reviewer",
                "Increase integration test coverage as a sprint goal",
            ],
            discussionPoints: [
                "Component library accelerated settings page redesign",
                "Database migration completed with zero downtime",
                "PR blocked for three days due to review backlog",
                "Two regressions caught late due to missing integration tests",
            ],
            actionItems: [
                "Alex to formalize the 24-hour review SLA and rotation schedule",
                "Dana to add integration tests for notifications and settings",
                "Raj to run a testing workshop next week",
            ],
            followUps: [
                "Review the new SLA process effectiveness in next retro",
                "Track regression count next sprint to measure improvement",
            ],
            attendeeSummary: [
                AttendeeContribution(
                    name: "Alex",
                    keyPoints: ["Facilitated discussion", "Proposed review SLA and rotation"],
                    speakingTimePercent: 35
                ),
                AttendeeContribution(
                    name: "Dana",
                    keyPoints: ["Highlighted review bottleneck", "Proposed integration test improvements"],
                    speakingTimePercent: 35
                ),
                AttendeeContribution(
                    name: "Raj",
                    keyPoints: ["Shared migration success", "Offered to lead testing workshop"],
                    speakingTimePercent: 30
                ),
            ]
        )
        return meeting
    }

    // MARK: - Meeting 3: CS 301 Study Group

    private static func makeMeeting3(date: Date) -> MeetingNote {
        let sp1 = "speaker-you", sp2 = "speaker-mia"
        let speakers = [
            Speaker(id: sp1, name: "You", color: AppThemeConstants.speakerBlurple),
            Speaker(id: sp2, name: "Mia", color: AppThemeConstants.speakerGreen),
        ]
        let segments = [
            seg(
                "Okay so the midterm is in two weeks. I think we should focus on graph algorithms since that's the biggest chunk of the exam.",
                start: 0,
                end: 15,
                speaker: "You"
            ),
            seg(
                "Yeah, Professor Kim said at least thirty percent would be on graphs. Should we start with shortest path or spanning trees?",
                start: 15,
                end: 28,
                speaker: "Mia"
            ),
            seg(
                "Let's do shortest path first. I always get confused about when to use Dijkstra versus Bellman-Ford.",
                start: 28,
                end: 42,
                speaker: "You"
            ),
            seg(
                "The key thing is negative edges. Dijkstra doesn't handle them, Bellman-Ford does. Also Dijkstra is greedy, Bellman-Ford is dynamic programming.",
                start: 42,
                end: 58,
                speaker: "Mia"
            ),
            seg(
                "Right, and the time complexity difference is pretty big. Dijkstra is O of V squared with a basic array or E log V with a min-heap.",
                start: 58,
                end: 74,
                speaker: "You"
            ),
            seg(
                "We should also practice the trace-through problems. Last year's exam had two of those where you had to show each step of the algorithm.",
                start: 74,
                end: 88,
                speaker: "Mia"
            ),
            seg(
                "Good idea. I found a set of practice problems on the course website. Want to split them and then compare answers Thursday?",
                start: 88,
                end: 102,
                speaker: "You"
            ),
            seg(
                "Sounds good. I'll also review the past two exams — I heard the TA has them posted in the shared drive.",
                start: 102,
                end: 118,
                speaker: "Mia"
            ),
        ]
        let speakerSegments = [
            spkSeg(
                sp1,
                start: 0,
                end: 15,
                text: "Okay so the midterm is in two weeks. I think we should focus on graph algorithms since that's the biggest chunk of the exam."
            ),
            spkSeg(
                sp2,
                start: 15,
                end: 28,
                text: "Yeah, Professor Kim said at least thirty percent would be on graphs. Should we start with shortest path or spanning trees?"
            ),
            spkSeg(
                sp1,
                start: 28,
                end: 42,
                text: "Let's do shortest path first. I always get confused about when to use Dijkstra versus Bellman-Ford."
            ),
            spkSeg(
                sp2,
                start: 42,
                end: 58,
                text: "The key thing is negative edges. Dijkstra doesn't handle them, Bellman-Ford does. Also Dijkstra is greedy, Bellman-Ford is dynamic programming."
            ),
            spkSeg(
                sp1,
                start: 58,
                end: 74,
                text: "Right, and the time complexity difference is pretty big. Dijkstra is O of V squared with a basic array or E log V with a min-heap."
            ),
            spkSeg(
                sp2,
                start: 74,
                end: 88,
                text: "We should also practice the trace-through problems. Last year's exam had two of those where you had to show each step of the algorithm."
            ),
            spkSeg(
                sp1,
                start: 88,
                end: 102,
                text: "Good idea. I found a set of practice problems on the course website. Want to split them and then compare answers Thursday?"
            ),
            spkSeg(
                sp2,
                start: 102,
                end: 118,
                text: "Sounds good. I'll also review the past two exams — I heard the TA has them posted in the shared drive."
            ),
        ]

        var meeting = MeetingNote(
            title: "CS 301 Study Group",
            createdAt: date,
            modifiedAt: date,
            recordingMode: .inPerson,
            spaceID: SeedSpaceID.cs301
        )
        meeting.duration = 118
        meeting.speakers = speakers
        meeting.segments = segments
        meeting.speakerSegments = speakerSegments
        meeting.hasSpeakerData = true
        meeting.summary = "Planned midterm study strategy for CS 301. Focused on graph algorithms — Dijkstra vs Bellman-Ford, complexity analysis, and trace-through problems. Splitting practice problems and reviewing past exams before Thursday."
        meeting.isPinned = false
        meeting.tags = ["study", "algorithms"]
        meeting.actionItems = [
            ActionItem(
                title: "Practice Dijkstra and Bellman-Ford trace-through problems",
                assignee: "You",
                dueDescription: "By Thursday",
                dueDate: due(1)
            ),
            ActionItem(title: "Review past two midterm exams from shared drive", assignee: "Mia", dueDescription: "By Thursday", dueDate: due(1)),
        ]
        meeting.bookmarks = [
            Bookmark(label: "Dijkstra vs Bellman-Ford", timestamp: 42, color: .blue),
            Bookmark(label: "Practice plan", timestamp: 88, color: .purple),
        ]
        meeting.smartMinutes = SmartMinutes(
            keyDecisions: [
                "Focus study efforts on graph algorithms for the midterm",
                "Start with shortest path algorithms before spanning trees",
            ],
            discussionPoints: [
                "Graph algorithms make up at least 30% of the midterm",
                "Dijkstra is greedy and fails on negative edges; Bellman-Ford uses DP",
                "Time complexity: Dijkstra O(E log V) with min-heap vs Bellman-Ford O(VE)",
                "Past exams include step-by-step trace-through problems",
            ],
            actionItems: [
                "Split practice problems from course website and compare Thursday",
                "Mia to pull past exams from shared drive",
            ],
            followUps: [
                "Meet Thursday to compare answers on practice problems",
                "Move to spanning trees and MST algorithms after shortest path",
            ],
            attendeeSummary: [
                AttendeeContribution(name: "You", keyPoints: ["Set study focus on graphs", "Found practice problems"], speakingTimePercent: 50),
                AttendeeContribution(
                    name: "Mia",
                    keyPoints: ["Clarified algorithm differences", "Suggested trace-through practice"],
                    speakingTimePercent: 50
                ),
            ]
        )
        return meeting
    }

    // MARK: - Meeting 4: Project Check-in w/ Prof. Lee

    private static func makeMeeting4(date: Date) -> MeetingNote {
        let sp1 = "speaker-you", sp2 = "speaker-prof-lee"
        let speakers = [
            Speaker(id: sp1, name: "You", color: AppThemeConstants.speakerBlurple),
            Speaker(id: sp2, name: "Prof. Lee", color: AppThemeConstants.speakerOrange),
        ]
        let segments = [
            seg(
                "Hi Professor Lee, thanks for meeting. I wanted to get your feedback on my case study draft before I go further.",
                start: 0,
                end: 14,
                speaker: "You"
            ),
            seg(
                "Of course. I read through it last night. Your analysis of the Patagonia case is solid, but the stakeholder section needs more depth.",
                start: 14,
                end: 30,
                speaker: "Prof. Lee"
            ),
            seg(
                "Can you be more specific about what's missing? I thought I covered the main groups — shareholders, employees, and customers.",
                start: 30,
                end: 44,
                speaker: "You"
            ),
            seg(
                "You did, but you're not addressing the supply chain workers. For an ethics paper, that's a critical stakeholder group you can't overlook.",
                start: 44,
                end: 58,
                speaker: "Prof. Lee"
            ),
            seg(
                "That's a great point. I'll add a section on supply chain labor practices and how they factor into the ethical framework.",
                start: 58,
                end: 72,
                speaker: "You"
            ),
            seg(
                "Also, your citations are a bit thin in the theoretical framework section. You should reference Freeman's stakeholder theory directly and maybe add Donaldson and Preston.",
                start: 72,
                end: 88,
                speaker: "Prof. Lee"
            ),
            seg(
                "Got it. I have the Freeman text — I'll pull the relevant sections. Is Donaldson and Preston the 1995 paper?",
                start: 88,
                end: 100,
                speaker: "You"
            ),
            seg(
                "Yes, the instrumental, normative, and descriptive taxonomy one. Submit the revised draft by Friday and I'll give you final feedback before the deadline.",
                start: 100,
                end: 114,
                speaker: "Prof. Lee"
            ),
        ]
        let speakerSegments = [
            spkSeg(
                sp1,
                start: 0,
                end: 14,
                text: "Hi Professor Lee, thanks for meeting. I wanted to get your feedback on my case study draft before I go further."
            ),
            spkSeg(
                sp2,
                start: 14,
                end: 30,
                text: "Of course. I read through it last night. Your analysis of the Patagonia case is solid, but the stakeholder section needs more depth."
            ),
            spkSeg(
                sp1,
                start: 30,
                end: 44,
                text: "Can you be more specific about what's missing? I thought I covered the main groups — shareholders, employees, and customers."
            ),
            spkSeg(
                sp2,
                start: 44,
                end: 58,
                text: "You did, but you're not addressing the supply chain workers. For an ethics paper, that's a critical stakeholder group you can't overlook."
            ),
            spkSeg(
                sp1,
                start: 58,
                end: 72,
                text: "That's a great point. I'll add a section on supply chain labor practices and how they factor into the ethical framework."
            ),
            spkSeg(
                sp2,
                start: 72,
                end: 88,
                text: "Also, your citations are a bit thin in the theoretical framework section. You should reference Freeman's stakeholder theory directly and maybe add Donaldson and Preston."
            ),
            spkSeg(
                sp1,
                start: 88,
                end: 100,
                text: "Got it. I have the Freeman text — I'll pull the relevant sections. Is Donaldson and Preston the 1995 paper?"
            ),
            spkSeg(
                sp2,
                start: 100,
                end: 114,
                text: "Yes, the instrumental, normative, and descriptive taxonomy one. Submit the revised draft by Friday and I'll give you final feedback before the deadline."
            ),
        ]

        var meeting = MeetingNote(
            title: "Project Check-in w/ Prof. Lee",
            createdAt: date,
            modifiedAt: date,
            recordingMode: .onlineMeeting,
            spaceID: SeedSpaceID.businessEthics
        )
        meeting.duration = 114
        meeting.speakers = speakers
        meeting.segments = segments
        meeting.speakerSegments = speakerSegments
        meeting.hasSpeakerData = true
        meeting.summary = "Reviewed Business Ethics case study draft with Prof. Lee. Key feedback: expand stakeholder analysis to include supply chain workers, and strengthen citations with Freeman and Donaldson & Preston. Revised draft due Friday."
        meeting.isPinned = false
        meeting.tags = ["office-hours"]
        meeting.actionItems = [
            ActionItem(
                title: "Revise stakeholder section to include supply chain workers",
                assignee: "You",
                dueDescription: "Before Friday",
                dueDate: due(2)
            ),
            ActionItem(
                title: "Add Freeman and Donaldson & Preston citations to theoretical framework",
                assignee: "You",
                dueDescription: "Before Friday",
                dueDate: due(2)
            ),
            ActionItem(title: "Submit revised draft", assignee: "You", dueDescription: "Friday", dueDate: due(3)),
        ]
        meeting.bookmarks = [
            Bookmark(label: "Stakeholder feedback", timestamp: 44, color: .red),
            Bookmark(label: "Citation guidance", timestamp: 72, color: .blue),
            Bookmark(label: "Deadline confirmed", timestamp: 100, color: .orange),
        ]
        meeting.smartMinutes = SmartMinutes(
            keyDecisions: [
                "Add supply chain workers as a key stakeholder group in the analysis",
                "Revised draft deadline set for Friday",
            ],
            discussionPoints: [
                "Patagonia case analysis is solid overall",
                "Stakeholder section missing supply chain labor perspective",
                "Theoretical framework needs stronger citations",
                "Freeman's stakeholder theory and Donaldson & Preston (1995) recommended",
            ],
            actionItems: [
                "Expand stakeholder section with supply chain labor practices",
                "Add Freeman and Donaldson & Preston references",
                "Submit revised draft by Friday for final feedback",
            ],
            followUps: [
                "Prof. Lee to provide final feedback after Friday submission",
                "Final paper due after incorporating last round of feedback",
            ],
            attendeeSummary: [
                AttendeeContribution(name: "You", keyPoints: ["Presented draft progress", "Clarified missing areas"], speakingTimePercent: 45),
                AttendeeContribution(
                    name: "Prof. Lee",
                    keyPoints: ["Identified stakeholder gap", "Recommended key citations"],
                    speakingTimePercent: 55
                ),
            ]
        )
        return meeting
    }

    // MARK: - Meeting 5: Trip Planning Call

    private static func makeMeeting5(date: Date) -> MeetingNote {
        let sp1 = "speaker-you", sp2 = "speaker-kai"
        let speakers = [
            Speaker(id: sp1, name: "You", color: AppThemeConstants.speakerBlurple),
            Speaker(id: sp2, name: "Kai", color: AppThemeConstants.speakerCyan),
        ]
        let segments = [
            seg(
                "Alright, let's nail down the Japan trip. We've got two weeks in September — I'm thinking Tokyo, Kyoto, and Osaka.",
                start: 0,
                end: 14,
                speaker: "You"
            ),
            seg(
                "Love that route. I'd say five days in Tokyo, four in Kyoto, and three in Osaka. That leaves a couple of buffer days for day trips.",
                start: 14,
                end: 30,
                speaker: "Kai"
            ),
            seg(
                "Perfect. For Tokyo I want to hit Shibuya, Akihabara, and definitely Tsukiji outer market. Maybe a day trip to Kamakura?",
                start: 30,
                end: 46,
                speaker: "You"
            ),
            seg(
                "Kamakura is a great call. We should get the JR Pass — it'll cover the bullet trains between cities and the Kamakura day trip.",
                start: 46,
                end: 60,
                speaker: "Kai"
            ),
            seg(
                "Yeah, the fourteen-day pass is around fifty thousand yen. Totally worth it. What about accommodation — hotels or ryokans?",
                start: 60,
                end: 74,
                speaker: "You"
            ),
            seg(
                "I'd say hotels in Tokyo and Osaka, but we should definitely do a ryokan in Kyoto. There's one in Arashiyama that has private onsen rooms.",
                start: 74,
                end: 90,
                speaker: "Kai"
            ),
            seg(
                "Oh that sounds amazing. Budget-wise, I'm thinking we should aim for around three thousand each for everything minus flights.",
                start: 90,
                end: 104,
                speaker: "You"
            ),
            seg(
                "That's doable. Flights are cheapest if we book in the next two weeks. I saw round trips for around eight hundred from SFO.",
                start: 104,
                end: 120,
                speaker: "Kai"
            ),
        ]
        let speakerSegments = [
            spkSeg(
                sp1,
                start: 0,
                end: 14,
                text: "Alright, let's nail down the Japan trip. We've got two weeks in September — I'm thinking Tokyo, Kyoto, and Osaka."
            ),
            spkSeg(
                sp2,
                start: 14,
                end: 30,
                text: "Love that route. I'd say five days in Tokyo, four in Kyoto, and three in Osaka. That leaves a couple of buffer days for day trips."
            ),
            spkSeg(
                sp1,
                start: 30,
                end: 46,
                text: "Perfect. For Tokyo I want to hit Shibuya, Akihabara, and definitely Tsukiji outer market. Maybe a day trip to Kamakura?"
            ),
            spkSeg(
                sp2,
                start: 46,
                end: 60,
                text: "Kamakura is a great call. We should get the JR Pass — it'll cover the bullet trains between cities and the Kamakura day trip."
            ),
            spkSeg(
                sp1,
                start: 60,
                end: 74,
                text: "Yeah, the fourteen-day pass is around fifty thousand yen. Totally worth it. What about accommodation — hotels or ryokans?"
            ),
            spkSeg(
                sp2,
                start: 74,
                end: 90,
                text: "I'd say hotels in Tokyo and Osaka, but we should definitely do a ryokan in Kyoto. There's one in Arashiyama that has private onsen rooms."
            ),
            spkSeg(
                sp1,
                start: 90,
                end: 104,
                text: "Oh that sounds amazing. Budget-wise, I'm thinking we should aim for around three thousand each for everything minus flights."
            ),
            spkSeg(
                sp2,
                start: 104,
                end: 120,
                text: "That's doable. Flights are cheapest if we book in the next two weeks. I saw round trips for around eight hundred from SFO."
            ),
        ]

        var meeting = MeetingNote(
            title: "Trip Planning Call",
            createdAt: date,
            modifiedAt: date,
            recordingMode: .inPerson,
            spaceID: SeedSpaceID.personal
        )
        meeting.duration = 120
        meeting.speakers = speakers
        meeting.segments = segments
        meeting.speakerSegments = speakerSegments
        meeting.hasSpeakerData = true
        meeting.summary = "Planned two-week Japan trip for September covering Tokyo, Kyoto, and Osaka. Agreed on itinerary split, JR Pass, ryokan in Kyoto, and $3K per-person budget excluding flights."
        meeting.isPinned = false
        meeting.tags = ["travel", "japan"]
        meeting.actionItems = [
            ActionItem(title: "Book flights from SFO within the next two weeks", assignee: "Kai", dueDescription: "Next two weeks", dueDate: due(10)),
            ActionItem(title: "Reserve ryokan in Arashiyama, Kyoto", assignee: "You", dueDescription: "This month", dueDate: due(14)),
            ActionItem(title: "Purchase 14-day JR Pass", assignee: "You", dueDescription: "Before departure", dueDate: due(21)),
        ]
        meeting.bookmarks = [
            Bookmark(label: "Itinerary breakdown", timestamp: 14, color: .blue),
            Bookmark(label: "JR Pass decision", timestamp: 46, color: .purple),
            Bookmark(label: "Budget discussion", timestamp: 90, color: .orange),
        ]
        meeting.smartMinutes = SmartMinutes(
            keyDecisions: [
                "Route: Tokyo (5 days) → Kyoto (4 days) → Osaka (3 days) with buffer days",
                "Ryokan stay in Arashiyama, Kyoto; hotels in Tokyo and Osaka",
                "Budget: ~$3K per person excluding flights",
            ],
            discussionPoints: [
                "Tokyo highlights: Shibuya, Akihabara, Tsukiji, day trip to Kamakura",
                "14-day JR Pass covers bullet trains and day trips (~¥50,000)",
                "Round-trip flights from SFO around $800 if booked soon",
                "Arashiyama ryokan with private onsen rooms",
            ],
            actionItems: [
                "Kai to book flights within two weeks for best price",
                "Reserve Arashiyama ryokan",
                "Purchase JR Pass before departure",
            ],
            followUps: [
                "Research specific restaurants and reservations needed in advance",
                "Look into pocket Wi-Fi rental for the trip",
            ],
            attendeeSummary: [
                AttendeeContribution(name: "You", keyPoints: ["Proposed route and Tokyo activities", "Set budget target"], speakingTimePercent: 50),
                AttendeeContribution(name: "Kai", keyPoints: ["Suggested time split and ryokan", "Found flight pricing"], speakingTimePercent: 50),
            ]
        )
        return meeting
    }

    // MARK: - Meeting 6: Contract Review — Meridian Deal (Legal, .presentation)

    private static func makeMeeting6(date: Date) -> MeetingNote {
        let sp1 = "speaker-rebecca", sp2 = "speaker-michael", sp3 = "speaker-lisa"
        let speakers = [
            Speaker(id: sp1, name: "Rebecca", color: AppThemeConstants.speakerBlurple),
            Speaker(id: sp2, name: "Michael", color: AppThemeConstants.speakerGreen),
            Speaker(id: sp3, name: "Lisa", color: AppThemeConstants.speakerOrange),
        ]
        let segments = [
            seg(
                "Good morning everyone. Let's walk through the Meridian Technologies engagement agreement. Michael, you've reviewed the liability section?",
                start: 0,
                end: 14,
                speaker: "Rebecca"
            ),
            seg(
                "Yes. The indemnification clause in Section 4 is too broad. They want us to indemnify against any third-party IP claims, which is unusual for this type of engagement.",
                start: 14,
                end: 30,
                speaker: "Michael"
            ),
            seg(
                "I agree. In our standard template, indemnification is limited to direct damages from our work product. This goes well beyond that.",
                start: 30,
                end: 44,
                speaker: "Lisa"
            ),
            seg(
                "Let's counter with a mutual indemnification clause and cap our liability at twice the contract value. That's the approach we took with the Nexus deal.",
                start: 44,
                end: 60,
                speaker: "Rebecca"
            ),
            seg(
                "Good reference. The NDA section looks fine, standard twelve-month tail. But the non-compete clause in Section 7 is problematic — it would block us from working with any fintech client for two years.",
                start: 60,
                end: 80,
                speaker: "Michael"
            ),
            seg(
                "That's a non-starter. We have three active fintech clients. I'd suggest narrowing it to direct competitors of Meridian specifically, not the entire sector.",
                start: 80,
                end: 96,
                speaker: "Lisa"
            ),
            seg(
                "Exactly. I'll draft the redline today. Michael, can you prepare the liability cap analysis with the financial scenarios? Lisa, please pull the Nexus precedent for the indemnification language.",
                start: 96,
                end: 116,
                speaker: "Rebecca"
            ),
            seg(
                "Will do. I'll also flag the termination clause — they have a termination for convenience with only seven days notice, which doesn't give us enough runway.",
                start: 116,
                end: 132,
                speaker: "Michael"
            ),
            seg(
                "Good catch. Let's push for thirty days minimum. Rebecca, should we schedule the client call for Thursday or Friday?",
                start: 132,
                end: 146,
                speaker: "Lisa"
            ),
            seg(
                "Thursday afternoon works best. I want the redline done by Wednesday so we can align internally before the call. Let's wrap up — everyone clear on action items?",
                start: 146,
                end: 164,
                speaker: "Rebecca"
            ),
        ]
        let speakerSegments = [
            spkSeg(
                sp1,
                start: 0,
                end: 14,
                text: "Good morning everyone. Let's walk through the Meridian Technologies engagement agreement. Michael, you've reviewed the liability section?"
            ),
            spkSeg(
                sp2,
                start: 14,
                end: 30,
                text: "Yes. The indemnification clause in Section 4 is too broad. They want us to indemnify against any third-party IP claims, which is unusual for this type of engagement."
            ),
            spkSeg(
                sp3,
                start: 30,
                end: 44,
                text: "I agree. In our standard template, indemnification is limited to direct damages from our work product. This goes well beyond that."
            ),
            spkSeg(
                sp1,
                start: 44,
                end: 60,
                text: "Let's counter with a mutual indemnification clause and cap our liability at twice the contract value. That's the approach we took with the Nexus deal."
            ),
            spkSeg(
                sp2,
                start: 60,
                end: 80,
                text: "Good reference. The NDA section looks fine, standard twelve-month tail. But the non-compete clause in Section 7 is problematic — it would block us from working with any fintech client for two years."
            ),
            spkSeg(
                sp3,
                start: 80,
                end: 96,
                text: "That's a non-starter. We have three active fintech clients. I'd suggest narrowing it to direct competitors of Meridian specifically, not the entire sector."
            ),
            spkSeg(
                sp1,
                start: 96,
                end: 116,
                text: "Exactly. I'll draft the redline today. Michael, can you prepare the liability cap analysis with the financial scenarios? Lisa, please pull the Nexus precedent for the indemnification language."
            ),
            spkSeg(
                sp2,
                start: 116,
                end: 132,
                text: "Will do. I'll also flag the termination clause — they have a termination for convenience with only seven days notice, which doesn't give us enough runway."
            ),
            spkSeg(
                sp3,
                start: 132,
                end: 146,
                text: "Good catch. Let's push for thirty days minimum. Rebecca, should we schedule the client call for Thursday or Friday?"
            ),
            spkSeg(
                sp1,
                start: 146,
                end: 164,
                text: "Thursday afternoon works best. I want the redline done by Wednesday so we can align internally before the call. Let's wrap up — everyone clear on action items?"
            ),
        ]

        var meeting = MeetingNote(
            title: "Contract Review — Meridian Deal",
            createdAt: date,
            modifiedAt: date,
            recordingMode: .onlineMeeting,
            template: .presentation,
            spaceID: SeedSpaceID.legal
        )
        meeting.duration = 164
        meeting.speakers = speakers
        meeting.segments = segments
        meeting.speakerSegments = speakerSegments
        meeting.hasSpeakerData = true
        meeting.summary = "Reviewed Meridian Technologies engagement agreement. Key issues: overbroad indemnification (counter with mutual + 2x cap), non-compete too wide (narrow to direct competitors), termination notice too short (push for 30 days). Redline draft by Wednesday, client call Thursday."
        meeting.isPinned = true
        meeting.tags = ["contract", "meridian", "review"]
        meeting.topicKeywords = ["contract", "liability", "indemnification", "NDA", "non-compete"]
        meeting.transcriptionLanguage = "en"
        meeting.calendarEventID = "CAL-MERIDIAN-2026-03"
        meeting.scheduledStartTime = date
        meeting.actionItems = [
            ActionItem(
                title: "Draft contract redline with counter-proposals",
                assignee: "Rebecca",
                dueDescription: "Wednesday",
                isCompleted: true,
                dueDate: due(1)
            ),
            ActionItem(
                title: "Prepare liability cap analysis with financial scenarios",
                assignee: "Michael",
                dueDescription: "Wednesday",
                dueDate: due(1),
                reminderDate: due(0)
            ),
            ActionItem(
                title: "Pull Nexus deal indemnification language as precedent",
                assignee: "Lisa",
                dueDescription: "Tuesday",
                isCompleted: true,
                dueDate: due(0)
            ),
            ActionItem(
                title: "Schedule client call for Thursday afternoon",
                assignee: "Rebecca",
                dueDescription: "Today",
                isCompleted: true,
                dueDate: due(0)
            ),
            ActionItem(
                title: "Flag termination clause — push for 30-day notice minimum",
                assignee: "Michael",
                dueDescription: "In redline",
                dueDate: due(1)
            ),
        ]
        meeting.bookmarks = [
            Bookmark(label: "Indemnification issue", timestamp: 14, color: .red),
            Bookmark(label: "Liability cap approach", timestamp: 44, color: .blue),
            Bookmark(label: "Non-compete problem", timestamp: 60, color: .yellow),
            Bookmark(label: "Action items", timestamp: 96, color: .purple),
            Bookmark(label: "Termination clause", timestamp: 116, color: .orange),
        ]
        meeting.chatMessages = [
            MeetingChatMessage(role: .user, content: "What exactly is the risk with the broad indemnification clause?"),
            MeetingChatMessage(
                role: .assistant,
                content: "The indemnification clause in Section 4 requires your firm to cover any third-party IP claims, even those unrelated to your work product. This means if Meridian is sued for patent infringement on their own technology, they could potentially seek indemnification from you. The standard approach — which Rebecca proposed — is mutual indemnification limited to direct damages arising from each party's own work, with a liability cap (2x contract value in this case). This protects both parties proportionally."
            ),
        ]
        meeting.smartMinutes = SmartMinutes(
            keyDecisions: [
                "Counter indemnification with mutual clause capped at 2x contract value",
                "Narrow non-compete from entire fintech sector to Meridian direct competitors only",
                "Push termination notice from 7 days to 30 days minimum",
                "Client call scheduled for Thursday afternoon",
            ],
            discussionPoints: [
                "Section 4 indemnification is overbroad — covers third-party IP claims beyond work product",
                "NDA section acceptable with standard 12-month tail",
                "Non-compete in Section 7 would block work with 3 active fintech clients",
                "Termination for convenience with 7-day notice insufficient for transition",
                "Nexus deal precedent used successfully for similar indemnification language",
            ],
            actionItems: [
                "Rebecca to draft redline by Wednesday",
                "Michael to prepare liability cap financial analysis",
                "Lisa to pull Nexus indemnification precedent",
                "Michael to address termination clause in redline",
            ],
            followUps: [
                "Internal alignment meeting Wednesday to review redline before client call",
                "Client call Thursday afternoon to present counter-proposals",
            ],
            attendeeSummary: [
                AttendeeContribution(
                    name: "Rebecca",
                    keyPoints: ["Led discussion", "Proposed liability cap approach", "Set timeline"],
                    speakingTimePercent: 40
                ),
                AttendeeContribution(
                    name: "Michael",
                    keyPoints: ["Identified indemnification and termination issues", "Referenced NDA review"],
                    speakingTimePercent: 35
                ),
                AttendeeContribution(name: "Lisa", keyPoints: ["Flagged non-compete risk", "Suggested narrowing scope"], speakingTimePercent: 25),
            ]
        )
        return meeting
    }

    // MARK: - Meeting 7: Compliance Training Standup (Legal, .standup, voiceNote, archived)

    private static func makeMeeting7(date: Date) -> MeetingNote {
        let segments = [
            seg(
                "Quick compliance update. The GDPR audit prep is on track — we've completed four of seven data protection impact assessments. The remaining three cover our analytics pipeline, customer support tools, and the new marketing platform.",
                start: 0,
                end: 18,
                speaker: "Speaker"
            ),
            seg(
                "Training completion is at eighty-two percent across the company. Engineering and legal are at one hundred percent. Sales and marketing are lagging — about sixty-five percent. I've sent reminders and set a hard deadline for next Friday.",
                start: 18,
                end: 36,
                speaker: "Speaker"
            ),
            seg(
                "The cookie consent banner update went live yesterday. We're now compliant with the latest ePrivacy guidance. Analytics shows a forty-three percent opt-in rate, which is actually above industry average.",
                start: 36,
                end: 52,
                speaker: "Speaker"
            ),
            seg(
                "One blocker — the data erasure API endpoint is still in progress. Engineering says it needs another week. I've flagged it as high priority since it's required for GDPR Article 17 compliance. That's the main risk item right now.",
                start: 52,
                end: 70,
                speaker: "Speaker"
            ),
            seg(
                "Next steps: I'll follow up with sales leadership on the training gaps, and I have a call with our external auditor on Monday to review the DPIA documentation. That's it for today.",
                start: 70,
                end: 84,
                speaker: "Speaker"
            ),
        ]

        var meeting = MeetingNote(
            title: "Compliance Training Standup",
            createdAt: date,
            modifiedAt: date,
            recordingMode: .voiceNote,
            template: .standup,
            spaceID: SeedSpaceID.legal
        )
        meeting.duration = 84
        meeting.segments = segments
        meeting.hasSpeakerData = false
        meeting.isArchived = true
        meeting.summary = "Voice note standup on compliance status. GDPR audit: 4/7 DPIAs done. Training at 82% (sales/marketing lagging). Cookie consent live with 43% opt-in. Blocker: erasure API needs another week."
        meeting.tags = ["compliance", "standup", "GDPR"]
        meeting.topicKeywords = ["GDPR", "compliance", "audit", "training", "cookie consent", "data erasure"]
        meeting.actionItems = [
            ActionItem(
                title: "Complete remaining 3 DPIAs (analytics, support, marketing)",
                assignee: "Rebecca",
                dueDescription: "End of month",
                dueDate: due(7)
            ),
            ActionItem(
                title: "Follow up with sales leadership on training completion",
                assignee: "Rebecca",
                dueDescription: "This week",
                isCompleted: true,
                dueDate: due(-1)
            ),
            ActionItem(title: "External auditor call — review DPIA documentation", assignee: "Rebecca", dueDescription: "Monday", dueDate: due(2)),
        ]
        meeting.smartMinutes = SmartMinutes(
            keyDecisions: [
                "Hard deadline set for training completion: next Friday",
                "Data erasure API flagged as high-priority blocker",
            ],
            discussionPoints: [
                "4 of 7 DPIAs completed; remaining cover analytics, support tools, and marketing platform",
                "Company-wide training at 82% — engineering and legal at 100%, sales/marketing at 65%",
                "Cookie consent banner live with 43% opt-in rate (above industry average)",
                "Erasure API needs another week from engineering",
            ],
            actionItems: [
                "Follow up with sales leadership on training gaps",
                "Monday call with external auditor on DPIA review",
                "Escalate erasure API timeline with engineering lead",
            ],
            followUps: [
                "Check training numbers again by Friday deadline",
                "Review erasure API progress mid-week",
            ],
            attendeeSummary: []
        )
        return meeting
    }

    // MARK: - Meeting 8: Patient Case Conference (Healthcare, .oneOnOne)

    private static func makeMeeting8(date: Date) -> MeetingNote {
        let sp1 = "speaker-dr-chen", sp2 = "speaker-dr-patel"
        let speakers = [
            Speaker(id: sp1, name: "Dr. Chen", color: AppThemeConstants.speakerBlurple),
            Speaker(id: sp2, name: "Dr. Patel", color: AppThemeConstants.speakerPink),
        ]
        let segments = [
            seg(
                "Thanks for the consult, Dr. Patel. I have a forty-two year old female presenting with six weeks of fatigue and bilateral hand joint pain. Morning stiffness lasting about forty-five minutes.",
                start: 0,
                end: 16,
                speaker: "Dr. Chen"
            ),
            seg(
                "Any lab results back yet?",
                start: 16,
                end: 20,
                speaker: "Dr. Patel"
            ),
            seg(
                "Yes — RF is positive at sixty-eight, anti-CCP is elevated at ninety-two. ESR and CRP both elevated. ANA is weakly positive at one to eighty.",
                start: 20,
                end: 36,
                speaker: "Dr. Chen"
            ),
            seg(
                "That's a strong serologic profile for rheumatoid arthritis. With the clinical presentation — symmetric small joint involvement, prolonged morning stiffness, and positive RF and anti-CCP — she meets the 2010 ACR/EULAR criteria.",
                start: 36,
                end: 56,
                speaker: "Dr. Patel"
            ),
            seg(
                "That's what I was thinking. Her mother also has RA, and her sister has lupus. Should I be concerned about overlap given the positive ANA?",
                start: 56,
                end: 70,
                speaker: "Dr. Chen"
            ),
            seg(
                "The ANA at one to eighty is low titer and nonspecific — it can occur in RA without indicating lupus. I'd check dsDNA and complement levels to rule it out, but the clinical picture points squarely to RA.",
                start: 70,
                end: 90,
                speaker: "Dr. Patel"
            ),
            seg(
                "What's your recommended treatment approach? She's currently on levothyroxine for hypothyroidism and taking ibuprofen as needed.",
                start: 90,
                end: 104,
                speaker: "Dr. Chen"
            ),
            seg(
                "I'd start with methotrexate fifteen milligrams weekly — that's first-line for moderate RA. Add folic acid one milligram daily to reduce side effects. We should get baseline liver function and CBC before starting.",
                start: 104,
                end: 124,
                speaker: "Dr. Patel"
            ),
            seg(
                "Makes sense. And if she doesn't respond adequately to methotrexate alone?",
                start: 124,
                end: 132,
                speaker: "Dr. Chen"
            ),
            seg(
                "Then we'd consider adding a biologic — likely a TNF inhibitor or a JAK inhibitor depending on her profile. But let's give methotrexate twelve weeks to assess response before escalating. I'll see her in my clinic in four weeks for a rheumatology baseline.",
                start: 132,
                end: 154,
                speaker: "Dr. Patel"
            ),
        ]
        let speakerSegments = [
            spkSeg(
                sp1,
                start: 0,
                end: 16,
                text: "Thanks for the consult, Dr. Patel. I have a forty-two year old female presenting with six weeks of fatigue and bilateral hand joint pain. Morning stiffness lasting about forty-five minutes."
            ),
            spkSeg(sp2, start: 16, end: 20, text: "Any lab results back yet?"),
            spkSeg(
                sp1,
                start: 20,
                end: 36,
                text: "Yes — RF is positive at sixty-eight, anti-CCP is elevated at ninety-two. ESR and CRP both elevated. ANA is weakly positive at one to eighty."
            ),
            spkSeg(
                sp2,
                start: 36,
                end: 56,
                text: "That's a strong serologic profile for rheumatoid arthritis. With the clinical presentation — symmetric small joint involvement, prolonged morning stiffness, and positive RF and anti-CCP — she meets the 2010 ACR/EULAR criteria."
            ),
            spkSeg(
                sp1,
                start: 56,
                end: 70,
                text: "That's what I was thinking. Her mother also has RA, and her sister has lupus. Should I be concerned about overlap given the positive ANA?"
            ),
            spkSeg(
                sp2,
                start: 70,
                end: 90,
                text: "The ANA at one to eighty is low titer and nonspecific — it can occur in RA without indicating lupus. I'd check dsDNA and complement levels to rule it out, but the clinical picture points squarely to RA."
            ),
            spkSeg(
                sp1,
                start: 90,
                end: 104,
                text: "What's your recommended treatment approach? She's currently on levothyroxine for hypothyroidism and taking ibuprofen as needed."
            ),
            spkSeg(
                sp2,
                start: 104,
                end: 124,
                text: "I'd start with methotrexate fifteen milligrams weekly — that's first-line for moderate RA. Add folic acid one milligram daily to reduce side effects. We should get baseline liver function and CBC before starting."
            ),
            spkSeg(sp1, start: 124, end: 132, text: "Makes sense. And if she doesn't respond adequately to methotrexate alone?"),
            spkSeg(
                sp2,
                start: 132,
                end: 154,
                text: "Then we'd consider adding a biologic — likely a TNF inhibitor or a JAK inhibitor depending on her profile. But let's give methotrexate twelve weeks to assess response before escalating. I'll see her in my clinic in four weeks for a rheumatology baseline."
            ),
        ]

        var meeting = MeetingNote(
            title: "Patient Case Conference",
            createdAt: date,
            modifiedAt: date,
            recordingMode: .inPerson,
            template: .oneOnOne,
            spaceID: SeedSpaceID.healthcare
        )
        meeting.duration = 154
        meeting.speakers = speakers
        meeting.segments = segments
        meeting.speakerSegments = speakerSegments
        meeting.hasSpeakerData = true
        meeting.summary = "Rheumatology consult for 42F with fatigue and bilateral hand joint pain. Labs show positive RF (68) and anti-CCP (92), elevated inflammatory markers. Diagnosis: rheumatoid arthritis per 2010 ACR/EULAR criteria. Plan: start methotrexate 15mg weekly with folic acid, rheumatology follow-up in 4 weeks."
        meeting.isPinned = true
        meeting.tags = ["case-conference", "rheumatology"]
        meeting.topicKeywords = ["patient", "diagnosis", "treatment", "rheumatoid arthritis", "methotrexate"]
        meeting.transcriptionLanguage = "en"
        meeting.actionItems = [
            ActionItem(
                title: "Order baseline CBC and liver function panel before starting methotrexate",
                assignee: "Dr. Chen",
                dueDescription: "Before treatment",
                isCompleted: true,
                dueDate: due(-1),
                reminderDate: due(-2)
            ),
            ActionItem(
                title: "Prescribe methotrexate 15mg weekly + folic acid 1mg daily",
                assignee: "Dr. Chen",
                dueDescription: "At next visit",
                isCompleted: true,
                dueDate: due(0)
            ),
            ActionItem(
                title: "Order dsDNA and complement levels to rule out lupus overlap",
                assignee: "Dr. Chen",
                dueDescription: "With baseline labs",
                isCompleted: true,
                dueDate: due(-1)
            ),
            ActionItem(
                title: "Schedule rheumatology baseline visit in 4 weeks",
                assignee: "Dr. Patel",
                dueDescription: "4 weeks",
                isCompleted: true,
                dueDate: due(0),
                reminderDate: due(-1)
            ),
        ]
        meeting.bookmarks = [
            Bookmark(label: "Lab results", timestamp: 20, color: .blue),
            Bookmark(label: "RA diagnosis", timestamp: 36, color: .purple),
            Bookmark(label: "ANA discussion", timestamp: 70, color: .yellow),
            Bookmark(label: "Treatment plan", timestamp: 104, color: .orange),
        ]
        meeting.chatMessages = [
            MeetingChatMessage(role: .user, content: "What are the main side effects of methotrexate I should counsel the patient about?"),
            MeetingChatMessage(
                role: .assistant,
                content: "The most common side effects of methotrexate for RA include: (1) GI symptoms — nausea, mouth sores, and decreased appetite, which folic acid supplementation helps mitigate; (2) Liver toxicity — requires baseline and periodic liver function monitoring; (3) Bone marrow suppression — monitor CBC regularly; (4) Increased infection risk due to immunosuppression. Less common but important: pulmonary toxicity (pneumonitis) and teratogenicity — contraception is essential for women of childbearing age."
            ),
            MeetingChatMessage(role: .user, content: "Should I be concerned about drug interactions with her levothyroxine?"),
            MeetingChatMessage(
                role: .assistant,
                content: "Methotrexate and levothyroxine do not have a significant direct interaction. However, methotrexate can affect liver metabolism and protein binding, so it's prudent to recheck TSH about 6-8 weeks after starting methotrexate to ensure thyroid hormone levels remain stable. No dose adjustment is typically needed upfront."
            ),
        ]
        meeting.smartMinutes = SmartMinutes(
            keyDecisions: [
                "Diagnosis: rheumatoid arthritis based on 2010 ACR/EULAR criteria",
                "First-line treatment: methotrexate 15mg weekly with folic acid 1mg daily",
                "Rule out lupus overlap with dsDNA and complement levels",
                "Reassess at 12 weeks; escalate to biologic if inadequate response",
            ],
            discussionPoints: [
                "Presentation: 42F, 6 weeks fatigue and bilateral hand joint pain, 45-min morning stiffness",
                "Labs: RF 68 (positive), anti-CCP 92 (elevated), ESR and CRP elevated, ANA 1:80 (weak positive)",
                "Family history notable for RA (mother) and lupus (sister)",
                "Low-titer ANA is nonspecific in RA context — not indicative of lupus",
                "Methotrexate is first-line for moderate RA; biologics reserved for inadequate responders",
            ],
            actionItems: [
                "Dr. Chen to order baseline labs (CBC, LFTs, dsDNA, complement)",
                "Dr. Chen to prescribe methotrexate + folic acid at next visit",
                "Dr. Patel to see patient in 4 weeks for rheumatology baseline",
            ],
            followUps: [
                "Reassess methotrexate response at 12 weeks",
                "Consider biologic (TNF inhibitor or JAK inhibitor) if inadequate response",
                "Recheck TSH 6-8 weeks after starting methotrexate",
            ],
            attendeeSummary: [
                AttendeeContribution(
                    name: "Dr. Chen",
                    keyPoints: ["Presented case and labs", "Asked about lupus overlap and drug interactions"],
                    speakingTimePercent: 45
                ),
                AttendeeContribution(
                    name: "Dr. Patel",
                    keyPoints: ["Confirmed RA diagnosis", "Recommended methotrexate regimen", "Addressed ANA concern"],
                    speakingTimePercent: 55
                ),
            ]
        )
        return meeting
    }

    // MARK: - Meeting 9: Research Protocol Brainstorm (Healthcare, .brainstorm)

    private static func makeMeeting9(date: Date) -> MeetingNote {
        let sp1 = "speaker-dr-nakamura", sp2 = "speaker-kate", sp3 = "speaker-dr-wong"
        let speakers = [
            Speaker(id: sp1, name: "Dr. Nakamura", color: AppThemeConstants.speakerBlurple),
            Speaker(id: sp2, name: "Kate", color: AppThemeConstants.speakerCyan),
            Speaker(id: sp3, name: "Dr. Wong", color: AppThemeConstants.speakerPink),
        ]
        let segments = [
            seg(
                "Let's brainstorm the Phase Two protocol design. We need to finalize the enrollment criteria and endpoint strategy before the IND submission next month.",
                start: 0,
                end: 14,
                speaker: "Dr. Nakamura"
            ),
            seg(
                "I've been looking at comparable trials. Most Phase Two RA trials target two hundred to three hundred patients with a one-to-one-to-one randomization across low dose, high dose, and placebo.",
                start: 14,
                end: 30,
                speaker: "Kate"
            ),
            seg(
                "Two forty is our sweet spot — eighty per arm gives us ninety percent power for the ACR20 primary endpoint assuming a twenty-five percentage point difference from placebo.",
                start: 30,
                end: 46,
                speaker: "Dr. Wong"
            ),
            seg(
                "What about the dose selection? The Phase One PK data suggests five and fifteen milligrams bracket the target exposure range.",
                start: 46,
                end: 60,
                speaker: "Dr. Nakamura"
            ),
            seg(
                "The five milligram dose showed good JAK1 selectivity with minimal JAK2 inhibition. Fifteen milligrams had stronger efficacy signals but we need to watch the hematologic parameters closely.",
                start: 60,
                end: 78,
                speaker: "Kate"
            ),
            seg(
                "I'd recommend adding a Data Safety Monitoring Board review at the Week 8 interim. If we see unexpected hepatotoxicity or significant cytopenias, we can pause enrollment.",
                start: 78,
                end: 96,
                speaker: "Dr. Wong"
            ),
            seg(
                "Good idea. What about the patient population? We discussed requiring inadequate response to methotrexate as an inclusion criterion.",
                start: 96,
                end: 110,
                speaker: "Dr. Nakamura"
            ),
            seg(
                "That's standard for this class. I'd also suggest excluding prior JAK inhibitor use to keep the population clean. And we should think about the site selection — I'm proposing eighteen centers across the US and Canada.",
                start: 110,
                end: 130,
                speaker: "Kate"
            ),
            seg(
                "Eighteen sites should give us good enrollment velocity. Target twelve to fourteen months for full enrollment. One thing I want to flag — the FDA has been asking about cardiovascular safety for JAK inhibitors lately. We should include MACE as an exploratory endpoint.",
                start: 130,
                end: 152,
                speaker: "Dr. Wong"
            ),
            seg(
                "Absolutely. Let's add that. Kate, can you draft the full protocol document this week? I'd like to circulate it to the advisory board by Friday.",
                start: 152,
                end: 166,
                speaker: "Dr. Nakamura"
            ),
        ]
        let speakerSegments = [
            spkSeg(
                sp1,
                start: 0,
                end: 14,
                text: "Let's brainstorm the Phase Two protocol design. We need to finalize the enrollment criteria and endpoint strategy before the IND submission next month."
            ),
            spkSeg(
                sp2,
                start: 14,
                end: 30,
                text: "I've been looking at comparable trials. Most Phase Two RA trials target two hundred to three hundred patients with a one-to-one-to-one randomization across low dose, high dose, and placebo."
            ),
            spkSeg(
                sp3,
                start: 30,
                end: 46,
                text: "Two forty is our sweet spot — eighty per arm gives us ninety percent power for the ACR20 primary endpoint assuming a twenty-five percentage point difference from placebo."
            ),
            spkSeg(
                sp1,
                start: 46,
                end: 60,
                text: "What about the dose selection? The Phase One PK data suggests five and fifteen milligrams bracket the target exposure range."
            ),
            spkSeg(
                sp2,
                start: 60,
                end: 78,
                text: "The five milligram dose showed good JAK1 selectivity with minimal JAK2 inhibition. Fifteen milligrams had stronger efficacy signals but we need to watch the hematologic parameters closely."
            ),
            spkSeg(
                sp3,
                start: 78,
                end: 96,
                text: "I'd recommend adding a Data Safety Monitoring Board review at the Week 8 interim. If we see unexpected hepatotoxicity or significant cytopenias, we can pause enrollment."
            ),
            spkSeg(
                sp1,
                start: 96,
                end: 110,
                text: "Good idea. What about the patient population? We discussed requiring inadequate response to methotrexate as an inclusion criterion."
            ),
            spkSeg(
                sp2,
                start: 110,
                end: 130,
                text: "That's standard for this class. I'd also suggest excluding prior JAK inhibitor use to keep the population clean. And we should think about the site selection — I'm proposing eighteen centers across the US and Canada."
            ),
            spkSeg(
                sp3,
                start: 130,
                end: 152,
                text: "Eighteen sites should give us good enrollment velocity. Target twelve to fourteen months for full enrollment. One thing I want to flag — the FDA has been asking about cardiovascular safety for JAK inhibitors lately. We should include MACE as an exploratory endpoint."
            ),
            spkSeg(
                sp1,
                start: 152,
                end: 166,
                text: "Absolutely. Let's add that. Kate, can you draft the full protocol document this week? I'd like to circulate it to the advisory board by Friday."
            ),
        ]

        var meeting = MeetingNote(
            title: "Research Protocol Brainstorm",
            createdAt: date,
            modifiedAt: date,
            recordingMode: .onlineMeeting,
            template: .brainstorm,
            spaceID: SeedSpaceID.healthcare
        )
        meeting.duration = 166
        meeting.speakers = speakers
        meeting.segments = segments
        meeting.speakerSegments = speakerSegments
        meeting.hasSpeakerData = true
        meeting.scheduledStartTime = date
        meeting.summary = "Brainstormed Phase II clinical trial protocol for BTC-4501 (JAK1 inhibitor for RA). Key decisions: 240 patients across 3 arms, 5mg and 15mg doses, ACR20 primary endpoint at Week 12, DSMB interim at Week 8, 18 trial sites, MACE as exploratory CV safety endpoint."
        meeting.isPinned = false
        meeting.tags = ["research", "protocol", "phase-2"]
        meeting.topicKeywords = ["trial", "protocol", "endpoints", "enrollment", "JAK inhibitor", "ACR20"]
        meeting.actionItems = [
            ActionItem(title: "Draft full Phase II protocol document", assignee: "Kate", dueDescription: "This week", dueDate: due(-2)),
            ActionItem(title: "Circulate protocol to advisory board", assignee: "Dr. Nakamura", dueDescription: "Friday", dueDate: due(-1)),
            ActionItem(
                title: "Finalize site selection list — 18 centers US and Canada",
                assignee: "Kate",
                dueDescription: "Before IND submission",
                dueDate: due(-3)
            ),
            ActionItem(
                title: "Add MACE as exploratory cardiovascular safety endpoint",
                assignee: "Dr. Wong",
                dueDescription: "In protocol draft",
                isCompleted: true,
                dueDate: due(-2)
            ),
        ]
        meeting.bookmarks = [
            Bookmark(label: "Sample size rationale", timestamp: 30, color: .blue),
            Bookmark(label: "Dose selection", timestamp: 46, color: .purple),
            Bookmark(label: "DSMB interim review", timestamp: 78, color: .red),
            Bookmark(label: "CV safety endpoint", timestamp: 130, color: .orange),
        ]
        meeting.smartMinutes = SmartMinutes(
            keyDecisions: [
                "240 patients total — 80 per arm (low dose, high dose, placebo)",
                "Doses: 5mg and 15mg oral, once daily",
                "Primary endpoint: ACR20 response at Week 12",
                "DSMB interim safety review at Week 8",
                "18 trial sites across US and Canada",
                "MACE added as exploratory cardiovascular safety endpoint",
            ],
            discussionPoints: [
                "Comparable trials use 200-300 patients with 1:1:1 randomization",
                "90% power for 25-percentage-point ACR20 difference from placebo",
                "Phase 1 PK data supports 5mg and 15mg dose bracket",
                "5mg shows good JAK1 selectivity; 15mg stronger efficacy but hematologic monitoring needed",
                "FDA increasingly focused on CV safety for JAK inhibitor class",
                "Enrollment target: 12-14 months across 18 sites",
            ],
            actionItems: [
                "Kate to draft full protocol document this week",
                "Dr. Nakamura to circulate to advisory board by Friday",
                "Kate to finalize site selection list",
                "Dr. Wong to incorporate MACE exploratory endpoint",
            ],
            followUps: [
                "Advisory board feedback due within 2 weeks of circulation",
                "IND submission target: next month",
                "Pre-IND meeting with FDA to discuss CV safety monitoring plan",
            ],
            attendeeSummary: [
                AttendeeContribution(
                    name: "Dr. Nakamura",
                    keyPoints: ["Set timeline for IND submission", "Led dose selection discussion"],
                    speakingTimePercent: 30
                ),
                AttendeeContribution(
                    name: "Kate",
                    keyPoints: ["Benchmarked comparable trials", "Analyzed PK data for dose rationale", "Proposed site strategy"],
                    speakingTimePercent: 35
                ),
                AttendeeContribution(
                    name: "Dr. Wong",
                    keyPoints: ["Calculated sample size", "Recommended DSMB interim", "Flagged CV safety endpoint"],
                    speakingTimePercent: 35
                ),
            ]
        )
        return meeting
    }
}

// swiftlint:enable line_length force_unwrapping function_body_length
// swiftlint:enable file_length
