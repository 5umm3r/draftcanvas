import XCTest
@testable import DraftCanvas

final class GenerationCoordinatorTests: XCTestCase {
    func testCoordinatorNeverExceedsConcurrencyLimit() async {
        let runner = RecordingGenerationRunner(delayNanoseconds: 20_000_000)
        let coordinator = GenerationCoordinator(runner: runner)
        let request = GenerationRequest(
            prompt: "simple icon",
            count: 5,
            concurrency: 2
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
            aspectRatio: .portrait
        )

        let prompt = PromptFactory.prompt(for: request, jobIndex: 0)

        XCTAssertTrue(prompt.contains("Aspect ratio: 3:4"))
        XCTAssertTrue(prompt.contains("portrait"))
    }

    func testPromptUsesNormalizedEnglishBriefForGenerationWhenAvailable() {
        let request = GenerationRequest(
            prompt: "雨上がりの森に立つ小さな白い家",
            count: 1,
            concurrency: 1,
            translateToEnglish: true,
            normalizedPrompt: "A small white house standing in a forest after rain, with soft mist and wet leaves."
        )

        let prompt = PromptFactory.prompt(for: request, jobIndex: 0)

        XCTAssertTrue(prompt.contains("Generation brief: A small white house standing in a forest after rain"))
        XCTAssertFalse(prompt.contains("User prompt: 雨上がりの森"))
    }

    func testPromptEnhancerCanRequestEnglishOutput() {
        let prompt = PromptEnhancer.buildPrompt(
            userPrompt: "雨上がりの森に立つ小さな白い家",
            translateToEnglish: true
        )

        XCTAssertTrue(prompt.contains("Output the enhanced prompt in English"))
        XCTAssertFalse(prompt.contains("Maintain the same language as the input"))
    }

    func testPromptEnhancerCanPreserveInputLanguage() {
        let prompt = PromptEnhancer.buildPrompt(
            userPrompt: "雨上がりの森に立つ小さな白い家",
            translateToEnglish: false
        )

        XCTAssertTrue(prompt.contains("Maintain the same language as the input"))
    }

    func testPreferredSaveFolderStorePersistsSelectedFolder() throws {
        let defaults = UserDefaults(suiteName: "DraftCanvasTests-\(UUID().uuidString)")!
        let store = PreferredSaveFolderStore(userDefaults: defaults)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try store.save(directory)

        XCTAssertEqual(store.load()?.standardizedFileURL, directory.standardizedFileURL)
    }

    @MainActor
    func testAccountUsageRefreshCoalescesDuplicateStaleRefreshes() async throws {
        let accountClient = RecordingAccountClient(delayNanoseconds: 100_000_000)
        let viewModel = makeAccountRefreshViewModel(accountClient: accountClient)

        viewModel.refreshAccountUsageIfStale()
        viewModel.refreshAccountUsageIfStale()

        try await Task.sleep(nanoseconds: 20_000_000)
        let inFlightReadCount = await accountClient.readAccountUsageCallCount()
        XCTAssertEqual(inFlightReadCount, 1)

        try await waitForAccountLabel("tester@example.com", viewModel: viewModel)
        let completedReadCount = await accountClient.readAccountUsageCallCount()
        XCTAssertEqual(completedReadCount, 1)
    }

    @MainActor
    func testAccountUsageRefreshDefersWhileGenerationIsRunning() async {
        let accountClient = RecordingAccountClient()
        let viewModel = makeAccountRefreshViewModel(accountClient: accountClient)
        viewModel.generatingProjectIDs.insert(UUID())

        viewModel.refreshAccountUsageIfStale()

        XCTAssertTrue(viewModel.needsAccountUsageRefreshAfterGeneration)
        let readCount = await accountClient.readAccountUsageCallCount()
        XCTAssertEqual(readCount, 0)
    }

    @MainActor
    func testPrewarmLoadsModelsOnlyOnceUnlessForced() async throws {
        let accountClient = RecordingAccountClient()
        let viewModel = makeAccountRefreshViewModel(accountClient: accountClient)

        viewModel.prewarmAndRefresh()
        try await Task.sleep(nanoseconds: 80_000_000)
        viewModel.prewarmAndRefresh()
        try await Task.sleep(nanoseconds: 80_000_000)

        let initialModelListCount = await accountClient.listModelsCallCount()
        XCTAssertEqual(initialModelListCount, 1)

        viewModel.prewarmAndRefresh(forceMetadata: true)
        try await Task.sleep(nanoseconds: 80_000_000)

        let forcedModelListCount = await accountClient.listModelsCallCount()
        XCTAssertEqual(forcedModelListCount, 2)
    }

    @MainActor
    private func makeAccountRefreshViewModel(accountClient: RecordingAccountClient) -> DraftCanvasViewModel {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DraftCanvasTests-\(UUID().uuidString)", isDirectory: true)
        return DraftCanvasViewModel(
            projectStore: ProjectStore(rootDirectory: root),
            preferredSaveFolderStore: PreferredSaveFolderStore(
                userDefaults: UserDefaults(suiteName: "DraftCanvasTests-\(UUID().uuidString)")!
            ),
            accountClient: accountClient,
            prewarmOnInit: false
        )
    }

    @MainActor
    private func waitForAccountLabel(
        _ expected: String,
        viewModel: DraftCanvasViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<20 {
            if viewModel.accountUsageStatus.accountLabel == expected {
                return
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTFail(
            "Expected account label \(expected), got \(viewModel.accountUsageStatus.accountLabel)",
            file: file,
            line: line
        )
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

private actor RecordingAccountClient: CodexAccountProviding {
    nonisolated let codexExecutablePath = "/usr/bin/false"
    private let delayNanoseconds: UInt64
    private var readCount = 0
    private var modelCount = 0
    private var startCount = 0

    init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
    }

    func readAccountUsageCallCount() -> Int {
        readCount
    }

    func listModelsCallCount() -> Int {
        modelCount
    }

    func startCallCount() -> Int {
        startCount
    }

    func start() async throws {
        startCount += 1
    }

    nonisolated func stop() {}

    func readAccountUsageStatus() async throws -> CodexAccountUsageStatus {
        readCount += 1

        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        return CodexAccountUsageStatus.parse(
            accountResponse: [
                "account": [
                    "type": "chatgpt",
                    "email": "tester@example.com",
                    "planType": "plus"
                ]
            ],
            rateLimitsResponse: [
                "rateLimits": [
                    "primary": ["usedPercent": 20],
                    "secondary": ["usedPercent": 30],
                    "planType": "plus"
                ]
            ]
        )
    }

    func listModels() async throws -> [CodexModel] {
        modelCount += 1

        return [
            CodexModel(
                id: "gpt-test",
                displayName: "GPT Test",
                supportedReasoningEfforts: ["low", "medium"],
                defaultReasoningEffort: "low",
                isDefault: true
            )
        ]
    }
}
