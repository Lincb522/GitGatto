import Combine
import Foundation
import Testing
@testable import GitGatto

@Suite("Recovery observation")
struct RecoveryObservationTests {
    @Test("Recovery observes its own state, not unrelated workspace edits")
    @MainActor
    func ignoresUnrelatedWorkspaceChanges() {
        let model = WorkspaceViewModel()
        let observation = RepositoryRecoveryObservation(model: model)
        var invalidations = 0
        let subscription = observation.objectWillChange.sink { invalidations += 1 }
        model.stashMessage = "Unrelated workspace editing"
        model.fileTimelineQuery = "unrelated.swift"
        #expect(invalidations == 0)
        model.selectedRepositoryBackupID = UUID()
        #expect(invalidations == 1)
        model.appPreferences.language = model.appPreferences.language == .english ? .simplifiedChinese : .english
        #expect(invalidations == 2)
        withExtendedLifetime(subscription) {}
    }
}
