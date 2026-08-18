@testable import Logue
import Testing

@Suite("Speaker short labels")
struct SpeakerShortLabelTests {
    @Test("Automatic speaker names collapse to S plus their number")
    func automaticNames() {
        #expect(SpeakerShortLabel.forSpeaker("Speaker 1") == "S1")
        #expect(SpeakerShortLabel.forSpeaker("Speaker 12") == "S12")
        #expect(SpeakerShortLabel.forSpeaker("speaker 3") == "S3")
    }

    @Test("A person's name becomes their initials")
    func peopleBecomeInitials() {
        #expect(SpeakerShortLabel.forSpeaker("Charan") == "C")
        #expect(SpeakerShortLabel.forSpeaker("Ada Lovelace") == "AL")
        #expect(SpeakerShortLabel.forSpeaker("You") == "Y")
    }

    @Test("Only the first two words count, so the column keeps its width")
    func atMostTwoInitials() {
        #expect(SpeakerShortLabel.forSpeaker("Jean Luc Picard") == "JL")
    }

    @Test("Something that merely looks like a speaker name is treated as a name")
    func notTheAutomaticPattern() {
        #expect(SpeakerShortLabel.forSpeaker("Speaker Two") == "ST")
        #expect(SpeakerShortLabel.forSpeaker("Speaker") == "S")
    }

    @Test("Blank input yields nothing rather than a stray character")
    func blankIsEmpty() {
        #expect(SpeakerShortLabel.forSpeaker("").isEmpty)
        #expect(SpeakerShortLabel.forSpeaker("   ").isEmpty)
    }
}
