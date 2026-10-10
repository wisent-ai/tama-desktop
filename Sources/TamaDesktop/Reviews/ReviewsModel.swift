import Foundation

struct PushReviewRecord: Decodable, Identifiable, Sendable {
    enum Outcome: String, Decodable, Sendable {
        case pass
        case sourceFinding = "source_finding"
        case reviewFailure = "review_failure"

        var title: String {
            switch self {
            case .pass: "Passed"
            case .sourceFinding: "Source finding"
            case .reviewFailure: "Review unavailable"
            }
        }
    }

    struct Result: Decodable, Sendable {
        let outcome: Outcome
        let detail: String?
    }

    let id: String
    let directory: String
    let result: Result?
    let error: String?

    private enum CodingKeys: CodingKey { case id, directory, result, error }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        directory = try values.decode(String.self, forKey: .directory)
        result = try values.decodeIfPresent(Result.self, forKey: .result)
        error = try values.decodeIfPresent(String.self, forKey: .error)
        guard (result != nil) != (error != nil) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription:
                        "Retained review \(id) requires exactly one result or read error."
                ))
        }
    }
}

struct PushReviewListing: Decodable, Sendable {
    let directory: String
    let records: [PushReviewRecord]
}

@MainActor
final class ReviewsModel: ObservableObject {
    enum State: Equatable {
        case idle, loading, ready
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var listing: PushReviewListing?
    @Published var selectedID: String?
    @Published private(set) var selected: PushReviewRecord?
    @Published private(set) var detailState: State = .idle

    func refresh() async {
        guard state != .loading else { return }
        state = .loading
        listing = nil
        selectedID = nil
        selected = nil
        detailState = .idle
        do {
            listing = try await TamaClient().request(
                "reviews/list", body: [:], as: PushReviewListing.self,
                describing: "Retained push reviews"
            )
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
            report(error, operation: "list")
        }
    }

    func readSelected() async {
        selected = nil
        guard let id = selectedID else {
            detailState = .idle
            return
        }
        detailState = .loading
        do {
            let record = try await TamaClient().request(
                "reviews/show", body: ["id": id], as: PushReviewRecord.self,
                describing: "Retained push review \(id)"
            )
            try Task.checkCancellation()
            guard selectedID == id else { return }
            selected = record
            detailState = .ready
        } catch is CancellationError {
            return
        } catch {
            guard selectedID == id, !Task.isCancelled else { return }
            detailState = .failed(error.localizedDescription)
            report(error, operation: "show")
        }
    }

    private func report(_ error: Error, operation: String) {
        TamaFailureReporting.reportSurfaced(
            failurePoint: "tama.reviews.\(operation)", error: error,
            sentence: error.localizedDescription
        )
    }
}
