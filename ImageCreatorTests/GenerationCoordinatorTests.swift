import XCTest
@testable import ImageCreator

final class GenerationCoordinatorTests: XCTestCase {
    func testCoordinatorNeverExceedsConcurrencyLimit() async {
        let runner = RecordingGenerationRunner(delayNanoseconds: 20_000_000)
        let coordinator = GenerationCoordinator(runner: runner)
        let request = GenerationRequest(
            prompt: "simple icon",
            count: 5,
            concurrency: 2,
            transparentBackground: false,
            outputMode: .raster
        )

        let jobs = await coordinator.run(request: request)

        XCTAssertEqual(jobs.count, 5)
        let maxConcurrent = await runner.maxConcurrentValue()
        XCTAssertEqual(maxConcurrent, 2)
        XCTAssertTrue(jobs.allSatisfy { $0.status == .succeeded })
    }
}

private actor RecordingGenerationRunner: GenerationRunning {
    private let delayNanoseconds: UInt64
    private var current = 0
    private(set) var maxConcurrent = 0

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func run(job: GenerationJob, request: GenerationRequest) async -> GenerationJob {
        current += 1
        maxConcurrent = max(maxConcurrent, current)
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        current -= 1

        var completed = job
        completed.status = .succeeded
        completed.imageData = Data([0x89, 0x50, 0x4E, 0x47])
        return completed
    }

    func maxConcurrentValue() -> Int {
        maxConcurrent
    }
}
