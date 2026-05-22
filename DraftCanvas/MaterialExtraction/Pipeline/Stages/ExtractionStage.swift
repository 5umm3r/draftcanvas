protocol ExtractionStage {
    associatedtype Input
    associatedtype Output
    func run(_ input: Input) throws -> Output
}
