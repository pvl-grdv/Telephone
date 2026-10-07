import Testing

struct SIPURISnapshotTests {
    @Test func snapshotDoesNotRetainMutableParserURI() {
        let parsed = AKSIPURI(
            user: "204",
            host: "2001:db8::1",
            displayName: "Caller — тест",
            port: 5061
        )
        let snapshot = SIPURISnapshot(parsed)

        parsed.user = "changed"
        parsed.host = "other.invalid"
        parsed.displayName = "Changed"
        parsed.port = 1234

        let consumerURI = snapshot.makeURI()
        #expect(consumerURI.user == "204")
        #expect(consumerURI.host == "2001:db8::1")
        #expect(consumerURI.displayName == "Caller — тест")
        #expect(consumerURI.port == 5061)
    }

    @Test func snapshotCrossesTasksWithoutSharingMutableConsumerURIs() async {
        let snapshot = SIPURISnapshot(AKSIPURI(
            user: "+79101234567",
            host: "sip.example.invalid",
            displayName: "Example Caller",
            port: 5070
        ))
        let transferred = await Task.detached { snapshot }.value
        #expect(transferred == snapshot)

        let first = transferred.makeURI()
        let second = transferred.makeURI()
        #expect(first !== second)
        #expect(first.description == second.description)

        first.user = "replacement"
        first.port = 9999
        #expect(second.user == "+79101234567")
        #expect(second.port == 5070)
        #expect(transferred.user == "+79101234567")
        #expect(transferred.port == 5070)
    }

    @Test func missingParsedURIKeepsEmptyFallback() {
        let consumerURI = SIPURISnapshot(nil).makeURI()
        #expect(consumerURI == AKSIPURI())
    }
}
