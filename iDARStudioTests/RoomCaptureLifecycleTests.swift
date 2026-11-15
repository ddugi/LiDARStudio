import Testing
@testable import iDARStudio

struct RoomCaptureLifecycleTests {
    @Test func roomCaptureRequiresOrderedFrameworkTransitions() {
        var lifecycle = RoomCaptureLifecycle()

        let startBeforeAttach = lifecycle.requestStart()
        #expect(!startBeforeAttach)
        lifecycle.attach()
        #expect(lifecycle.phase == .ready)
        let start = lifecycle.requestStart()
        #expect(start)
        #expect(lifecycle.phase == .starting)
        let duplicateStart = lifecycle.requestStart()
        #expect(!duplicateStart)

        lifecycle.confirmStarted()
        #expect(lifecycle.phase == .capturing)
        let finish = lifecycle.requestFinish()
        #expect(finish)
        #expect(lifecycle.phase == .stopping)
        let duplicateFinish = lifecycle.requestFinish()
        #expect(!duplicateFinish)

        lifecycle.beginProcessing()
        #expect(lifecycle.keepsCaptureViewMounted)
        lifecycle.presentReview()
        #expect(lifecycle.phase == .review)
        let save = lifecycle.requestSave()
        #expect(save)
        lifecycle.confirmSaved()
        #expect(lifecycle.phase == .saved)
    }

    @Test func roomCaptureCanPrepareBeforeCaptureViewIsMounted() {
        var lifecycle = RoomCaptureLifecycle()

        lifecycle.attach()
        let start = lifecycle.requestStart()

        #expect(start)
        #expect(lifecycle.phase == .starting)
        #expect(lifecycle.keepsCaptureViewMounted)
    }

    @Test func roomCaptureCancellationIsTerminalUntilReset() {
        var lifecycle = RoomCaptureLifecycle()
        lifecycle.attach()
        let start = lifecycle.requestStart()
        #expect(start)
        lifecycle.cancel()

        #expect(lifecycle.phase == .cancelled)
        lifecycle.confirmStarted()
        #expect(lifecycle.phase == .cancelled)
        let finishAfterCancel = lifecycle.requestFinish()
        #expect(!finishAfterCancel)

        lifecycle.reset()
        lifecycle.attach()
        #expect(lifecycle.phase == .ready)
        let restart = lifecycle.requestStart()
        #expect(restart)
    }

    @Test func roomCaptureCannotSaveBeforeRealProcessedResult() {
        var lifecycle = RoomCaptureLifecycle()
        lifecycle.attach()

        let saveBeforeStart = lifecycle.requestSave()
        #expect(!saveBeforeStart)
        let start = lifecycle.requestStart()
        #expect(start)
        lifecycle.confirmStarted()
        let saveDuringCapture = lifecycle.requestSave()
        #expect(!saveDuringCapture)
        let finish = lifecycle.requestFinish()
        #expect(finish)
        lifecycle.beginProcessing()
        let saveDuringProcessing = lifecycle.requestSave()
        #expect(!saveDuringProcessing)
        lifecycle.presentReview()
        let saveAfterReview = lifecycle.requestSave()
        #expect(saveAfterReview)
    }

    @Test func roomCaptureFailureCannotBeRevivedByLateCallbacks() {
        var lifecycle = RoomCaptureLifecycle()
        lifecycle.attach()
        let start = lifecycle.requestStart()
        #expect(start)
        lifecycle.fail()

        lifecycle.confirmStarted()
        lifecycle.beginProcessing()
        lifecycle.presentReview()
        lifecycle.confirmSaved()
        #expect(lifecycle.phase == .failed)
    }
}
