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

    func testTurnInputIncludesLocalImageWhenEditingExistingPNG() {
        let input = CodexTurnInputFactory.input(
            prompt: "背景を夜にする",
            referenceImagePath: "/tmp/history/item.png"
        )

        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(input[0]["type"] as? String, "text")
        XCTAssertEqual(input[0]["text"] as? String, "背景を夜にする")
        XCTAssertEqual(input[1]["type"] as? String, "localImage")
        XCTAssertEqual(input[1]["path"] as? String, "/tmp/history/item.png")
    }

    func testPromptIncludesSelectedAspectRatio() {
        let request = GenerationRequest(
            prompt: "minimal app icon",
            count: 1,
            concurrency: 1,
            transparentBackground: false,
            outputMode: .raster,
            aspectRatio: .portrait
        )

        let prompt = PromptFactory.prompt(for: request, jobIndex: 0)

        XCTAssertTrue(prompt.contains("Aspect ratio: 3:4"))
        XCTAssertTrue(prompt.contains("portrait"))
    }

    func testHistoryStorePersistsGeneratedPNGAndMetadata() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = GenerationHistoryStore(rootDirectory: rootDirectory)
        let request = GenerationRequest(
            prompt: "simple icon",
            count: 1,
            concurrency: 1,
            transparentBackground: true,
            outputMode: .raster,
            aspectRatio: .wide
        )
        var job = GenerationJob(index: 0, prompt: "simple icon", status: .succeeded)
        job.imageData = Data([0x89, 0x50, 0x4E, 0x47])
        job.revisedPrompt = "revised simple icon"

        let item = try store.add(job: job, request: request, createdAt: Date(timeIntervalSince1970: 1_000))
        let loaded = try store.load()

        XCTAssertEqual(loaded, [item])
        XCTAssertEqual(item.prompt, "simple icon")
        XCTAssertEqual(item.outputMode, .raster)
        XCTAssertTrue(item.transparentBackground)
        XCTAssertEqual(item.aspectRatio, .wide)
        XCTAssertEqual(item.revisedPrompt, "revised simple icon")
        XCTAssertEqual(try Data(contentsOf: item.fileURL(in: rootDirectory)), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testPreferredSaveFolderStorePersistsSelectedFolder() throws {
        let defaults = UserDefaults(suiteName: "ImageCreatorTests-\(UUID().uuidString)")!
        let store = PreferredSaveFolderStore(userDefaults: defaults)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try store.save(directory)

        XCTAssertEqual(store.load()?.standardizedFileURL, directory.standardizedFileURL)
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
