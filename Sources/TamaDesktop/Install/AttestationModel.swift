import Foundation

/// One recorded attestation as the backend reports it: the session it
/// attests (`kind` is `session`), whether it stands against the task
/// standard, every reason it does not, and where it is kept.
struct AttestationReport: Decodable, Sendable {
    let kind: String
    let id: String
    let stands: Bool
    let refusals: [String]
    let recorded: String?

    var subject: String { "\(kind) \(id)" }
}

/// One attested claim of a kept attestation.
struct AttestedClaim: Decodable, Sendable {
    let confirmed: Bool?
    let how: String?
}

/// A kept attestation and how it stands today, as `attestation/show`
/// answers.
struct ShownAttestation: Decodable, Sendable {
    /// A kept record stood when it was recorded, so it carries its claims.
    struct Document: Decodable, Sendable {
        let attestations: [String: AttestedClaim]
    }

    let kind: String
    let id: String
    let stands: Bool
    let refusals: [String]
    let recorded: String?
    let attestation: Document
}

/// The claims a session's attestation confirms and the lists it leaves
/// empty, as `attestation/standard` answers.
struct AttestationStandard: Decodable, Sendable {
    struct Claim: Decodable, Sendable {
        let key: String
        let claim: String
    }
    struct EmptyList: Decodable, Sendable {
        let key: String
        let why: String
    }
    struct Declared: Decodable, Sendable {
        let required: [Claim]
        let mustBeEmpty: [EmptyList]

        enum CodingKeys: String, CodingKey {
            case required
            case mustBeEmpty = "must_be_empty"
        }
    }

    let kind: String
    let id: String
    let standard: Declared
}

private struct RemovedAttestation: Decodable {
    let removed: String
}

/// The recorded attestations' reads and writes, each the terminal's own
/// command as a request (`tama attestation record|show|list|remove
/// --session ID`), so a refusal shows the sentence the terminal prints. A
/// commit's or a turn's attestation is not recorded: it is carried in its
/// own text (`CarriedAttestationModel`).
@MainActor
final class AttestationModel: ObservableObject {
    @Published private(set) var working: String?
    @Published private(set) var failure: String?
    @Published private(set) var verdict: AttestationReport?
    @Published private(set) var shown: ShownAttestation?
    @Published private(set) var standard: AttestationStandard?
    @Published private(set) var removed: String?
    @Published private(set) var records: [AttestationReport] = []
    @Published var session = ""
    @Published var attestationFile: URL?

    private static let operation = "The attestations"
    /// The backend's subject kind, which is also the request field that
    /// names it.
    private static let sessionKind = "session"

    /// The session the form names, or the sentence that says it is missing.
    private func subject() -> Result<[String: String], AttestationFormError> {
        let named = session.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !named.isEmpty else {
            return .failure(.init("Name the session the attestation attests."))
        }
        return .success([Self.sessionKind: named])
    }

    /// `tama attestation record --file FILE --session ID`.
    func record() {
        guard working == nil else { return }
        guard let attestationFile else {
            failure = "Choose the attestation file to record."
            return
        }
        withSubject("Judging and recording the attestation") { fields in
            let document: Any
            do {
                document = try JSONSerialization.jsonObject(with: Data(contentsOf: attestationFile))
            } catch {
                throw AttestationFormError(
                    "\(attestationFile.path) could not be read as JSON: \(error.localizedDescription)"
                )
            }
            var body: [String: Any] = fields
            body["attestation"] = document
            self.verdict = try await TamaClient().request(
                "attestation/record", body: body, as: AttestationReport.self,
                describing: Self.operation)
            await self.readList()
        }
    }

    /// `tama attestation show --session ID`.
    func show() {
        withSubject("Reading the kept attestation") { fields in
            let body: [String: Any] = fields
            self.shown = try await TamaClient().request(
                "attestation/show", body: body, as: ShownAttestation.self,
                describing: Self.operation)
        }
    }

    /// `tama attestation standard --session ID`: every claim the session's
    /// attestation must confirm, in words.
    func showStandard() {
        withSubject("Reading the attestation standard") { fields in
            let body: [String: Any] = fields
            self.standard = try await TamaClient().request(
                "attestation/standard", body: body, as: AttestationStandard.self,
                describing: Self.operation)
        }
    }

    /// `tama attestation remove --session ID` for the session the form names.
    func removeNamed() {
        withSubject("Removing the kept attestation") { fields in
            try await self.remove(fields)
        }
    }

    /// `tama attestation remove --session ID` for one listed record.
    func remove(_ record: AttestationReport) {
        guard working == nil else { return }
        run("Removing the kept attestation") { try await self.remove([record.kind: record.id]) }
    }

    /// `tama attestation list`.
    func list() {
        guard working == nil else { return }
        run("Reading the kept attestations") { await self.readList() }
    }

    private func remove(_ fields: [String: String]) async throws {
        let body: [String: Any] = fields
        let answer = try await TamaClient().request(
            "attestation/remove", body: body, as: RemovedAttestation.self,
            describing: Self.operation)
        removed = answer.removed
        shown = nil
        await readList()
    }

    private func readList() async {
        do {
            records = try await TamaClient().request(
                "attestation/list", as: [AttestationReport].self, describing: Self.operation)
        } catch {
            failure = Self.sentence(error)
        }
    }

    private func withSubject(
        _ label: String, _ work: @escaping @MainActor ([String: String]) async throws -> Void
    ) {
        guard working == nil else { return }
        switch subject() {
        case .failure(let missing):
            failure = missing.sentence
        case .success(let fields):
            run(label) { try await work(fields) }
        }
    }

    private func run(_ label: String, _ work: @escaping @MainActor () async throws -> Void) {
        working = label
        failure = nil
        removed = nil
        Task {
            do {
                try await work()
            } catch {
                failure = Self.sentence(error)
            }
            working = nil
        }
    }

    private static func sentence(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

/// What the form is missing, or the file it could not read, before a request
/// is sent.
struct AttestationFormError: LocalizedError {
    let sentence: String
    init(_ sentence: String) { self.sentence = sentence }
    var errorDescription: String? { sentence }
}
