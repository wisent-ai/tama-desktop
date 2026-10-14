import SwiftUI
import WisentDesignSystem

/// One attestation as `tama attestation list` prints it for a person,
/// whichever registry keeps it: what is attested, by whom, verified how and
/// read from where. The registry's own statement, scope and lifetime are in
/// `tama attestation list --json`.
struct RegistryRecord: Decodable, Sendable {
    let kind: String
    let subject: String
    let attester: String
    let verification: String
    let store: String

    var line: String {
        "\(kind) \(subject) by the \(attester), verified by \(verification), from \(store)"
    }
}

/// One verification as `tama attestation verify --json` prints it. A place
/// the ledger and a registry view disagree carries no record, only why.
struct VerifiedRecord: Decodable, Sendable {
    let record: RegistryRecord?
    let verified: Bool
    let failure: String?

    /// The record verified, or, for a disagreement, what disagrees.
    var title: String {
        if let record { return record.line }
        return "The ledger and a registry disagree"
    }
}

/// What `attestation/migrate` answers: the ledger and the records it
/// brought in from the registries.
struct MigratedLedger: Decodable, Sendable {
    let ledger: String
    let attestations: [RegistryRecord]
}

/// What `attestation/revoke` answers: the kind and subject withdrawn.
struct RevokedAttestation: Decodable, Sendable {
    let kind: String
    let subject: String
}

/// What `attestation/attest` answers: the subject recorded and the registry
/// that keeps it.
struct RecordedAttestation: Decodable, Sendable {
    let recorded: String
    let registry: String
}

/// `tama attestation list [--kind]` and `verify [--kind]` as the
/// `attestation/registries` and `attestation/verify` requests: the same
/// records, the same refusals, no model.
@MainActor
final class AttestationRegistriesModel: ObservableObject {
    @Published private(set) var working: String?
    @Published private(set) var failure: String?
    @Published private(set) var records: [RegistryRecord] = []
    @Published private(set) var verified: [VerifiedRecord]?
    /// What the last migration brought into the ledger.
    @Published private(set) var migrated: String?
    /// Every kind Tama names (`attestation/kinds`), for narrowing the
    /// listing and picking what to record, whether or not a record of it
    /// exists yet.
    @Published private(set) var kinds: [String] = []
    @Published var kind = ""
    /// What `attest` records: the subject and the statement made of it.
    @Published var subject = ""
    @Published var statement = ""

    private static let operation = "The attestation registries"

    private var body: [String: Any] { kind.isEmpty ? [:] : ["kind": kind] }

    func list() {
        run("Reading every attestation registry") {
            self.verified = nil
            self.kinds = try await TamaClient().request(
                "attestation/kinds", body: [:], as: [String].self, describing: Self.operation)
            self.records = try await TamaClient().request(
                "attestation/registries", body: self.body, as: [RegistryRecord].self,
                describing: Self.operation)
        }
    }

    func verify() {
        run("Verifying every attestation") {
            self.verified = try await TamaClient().request(
                "attestation/verify", body: self.body, as: [VerifiedRecord].self,
                describing: Self.operation)
        }
    }

    /// `tama attestation revoke --kind KIND --subject SUBJECT`, then the
    /// listing again; a refusal (a test approval, a spent build consent)
    /// carries the command's sentence.
    func revoke(_ record: RegistryRecord) {
        run("Revoking \(record.kind) \(record.subject)") {
            let fields: [String: Any] = ["kind": record.kind, "subject": record.subject]
            let _: RevokedAttestation = try await TamaClient().request(
                "attestation/revoke", body: fields, as: RevokedAttestation.self,
                describing: Self.operation)
            self.verified = nil
            self.records = try await TamaClient().request(
                "attestation/registries", body: self.body, as: [RegistryRecord].self,
                describing: Self.operation)
        }
    }

    /// `tama attestation record --kind KIND --subject SUBJECT --statement
    /// TEXT` with the kind picked above, then the listing again; a kind only
    /// the operator gives is refused with the act that records it.
    func attest() {
        run("Recording \(kind) \(subject)") {
            let fields: [String: Any] = [
                "kind": self.kind, "subject": self.subject, "statement": self.statement,
            ]
            let _: RecordedAttestation = try await TamaClient().request(
                "attestation/attest", body: fields, as: RecordedAttestation.self,
                describing: Self.operation)
            self.verified = nil
            self.records = try await TamaClient().request(
                "attestation/registries", body: self.body, as: [RegistryRecord].self,
                describing: Self.operation)
        }
    }

    /// `tama attestation migrate`: bring every registry into the one
    /// attestation ledger, then the listing again.
    func migrate() {
        run("Bringing every registry into the attestation ledger") {
            let migrated: MigratedLedger = try await TamaClient().request(
                "attestation/migrate", body: [:], as: MigratedLedger.self,
                describing: Self.operation)
            self.migrated =
                "Brought \(migrated.attestations.count) attestation(s) into \(migrated.ledger)"
            self.verified = nil
            self.records = try await TamaClient().request(
                "attestation/registries", body: self.body, as: [RegistryRecord].self,
                describing: Self.operation)
        }
    }

    private func run(_ label: String, _ work: @escaping @MainActor () async throws -> Void) {
        guard working == nil else { return }
        working = label
        failure = nil
        Task {
            do {
                try await work()
            } catch let error as LocalizedError {
                failure = error.errorDescription
            } catch {
                failure = error.localizedDescription
            }
            working = nil
        }
    }
}

/// Everything an agent or the operator has attested, read as one record from
/// every registry Tama keeps (session records, file, CUA and SSH
/// justifications, test approvals, spent build consents), and verified by
/// re-reading what each names: an operator's grant must cite a sentence that
/// stands in the session's transcript.
struct AttestationRegistriesSection: View {
    @StateObject private var model = AttestationRegistriesModel()

    var body: some View {
        WisentSectionBox(
            title: "Every attestation",
            detail:
                "One ledger keeps every attestation; the registries the gates read are its views. Migrate brings what a registry holds into the ledger; Verify re-reads what each names and names any disagreement."
        ) {
            HStack(spacing: WisentDesign.Space.x3) {
                Picker("Kind", selection: $model.kind) {
                    Text("Every kind").tag("")
                    ForEach(model.kinds, id: \.self) { kind in Text(kind).tag(kind) }
                }
                Button("List") { model.list() }
                Button("Verify") { model.verify() }
                Button("Migrate") { model.migrate() }
            }
            .disabled(model.working != nil)
            HStack(spacing: WisentDesign.Space.x3) {
                TextField("Subject", text: $model.subject)
                TextField("Statement", text: $model.statement)
                Button("Record") { model.attest() }
                    .disabled(model.subject.isEmpty || model.statement.isEmpty)
            }
            .disabled(model.working != nil)
            if let working = model.working { WisentSkeletonText(label: working) }
            if let migrated = model.migrated {
                Text(migrated).font(WisentTypeScale.caption())
            }
            if let failure = model.failure {
                WisentAlertPanel(tone: .danger, title: "Tama refused", detail: failure)
            }
            if let verified = model.verified {
                ForEach(Array(verified.enumerated()), id: \.offset) { _, each in
                    if let failure = each.failure {
                        WisentAlertPanel(tone: .warning, title: each.title, detail: failure)
                    } else {
                        WisentAlertPanel(
                            tone: .success, title: each.title, detail: "verifies")
                    }
                }
            } else {
                ForEach(Array(model.records.enumerated()), id: \.offset) { _, record in
                    HStack {
                        Text(record.line).font(WisentTypeScale.caption())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Revoke") { model.revoke(record) }
                            .disabled(model.working != nil)
                    }
                }
            }
        }
        .task { model.list() }
    }
}
