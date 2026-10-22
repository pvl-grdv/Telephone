import SwiftUI

@MainActor
struct CRMProgramCatalogScene: Scene {
    static let id = "telephone-program-catalog"
    let makeModel: @MainActor () -> CRMProgramCatalogModel

    var body: some Scene {
        Window(NSLocalizedString("Program Catalog", comment: "Program catalogue window."), id: Self.id) {
            CRMProgramCatalogView(model: makeModel())
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 1000, height: 640)
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)
    }
}

struct CRMProgramCatalogView: View {
    @State private var model: CRMProgramCatalogModel

    init(model: CRMProgramCatalogModel) { _model = State(initialValue: model) }

    var body: some View {
        VStack(spacing: 0) {
            if model.settings.enabled {
                HStack {
                    TextField(NSLocalizedString("Name, ID, version or directory", comment: "Catalogue search."), text: $model.search)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 200, maxWidth: 330)
                    Toggle(NSLocalizedString("Available for new supply", comment: "Catalogue activity filter."), isOn: $model.availableOnly)
                        .toggleStyle(.checkbox)
                    Spacer()
                    Picker(NSLocalizedString("Protection", comment: "Programme protection type."), selection: $model.usesStealth) {
                        Text("Sign").tag(false)
                        Text("Stealth").tag(true)
                    }
                    .frame(width: 180)
                }
                .padding()

                Table(model.visibleRecords) {
                    TableColumn("ID") { row in Text(String(row.id)).monospacedDigit() }
                        .width(min: 55, ideal: 65, max: 90)
                    TableColumn(NSLocalizedString("Program", comment: "Catalogue programme column."), value: \.name)
                        .width(min: 220, ideal: 340)
                    TableColumn(NSLocalizedString("Version", comment: "Catalogue version column.")) { row in
                        Text((model.usesStealth ? row.stealthVersion : row.signVersion) ?? "—")
                    }.width(min: 75, ideal: 95)
                    TableColumn(NSLocalizedString("Release", comment: "Catalogue release column.")) { row in
                        Text((model.usesStealth ? row.stealthRelease : row.signRelease) ?? "—").monospacedDigit()
                    }.width(min: 80, ideal: 100)
                    TableColumn(NSLocalizedString("Distribution directory", comment: "Catalogue distribution folder.")) { row in
                        Text((model.usesStealth ? row.stealthDirectory : row.signDirectory) ?? "—")
                            .textSelection(.enabled)
                    }.width(min: 150, ideal: 180)
                    TableColumn(NSLocalizedString("Available", comment: "Catalogue availability column.")) { row in
                        Image(systemName: row.availableForSupply ? "checkmark.circle" : "minus.circle")
                            .foregroundStyle(row.availableForSupply ? Color.primary : Color.secondary)
                            .accessibilityLabel(row.availableForSupply
                                ? NSLocalizedString("Available for new supply", comment: "Catalogue available state.")
                                : NSLocalizedString("Unavailable for new supply", comment: "Catalogue unavailable state."))
                    }.width(min: 65, ideal: 85)
                }
                .overlay {
                    if model.isLoading { ProgressView() }
                    else if model.error != nil {
                        VStack(spacing: 10) {
                            Text(NSLocalizedString("Unable to load the program catalog. Check CRM settings and update Gateway if necessary.", comment: "Catalogue failure."))
                                .multilineTextAlignment(.center)
                            Button(NSLocalizedString("Retry", comment: "Retry catalogue.")) { Task { await model.reload() } }
                        }.padding().background(.regularMaterial)
                    } else if model.visibleRecords.isEmpty {
                        Text(NSLocalizedString("No programs found", comment: "Empty catalogue search."))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("\(model.visibleRecords.count) / \(model.records.count)").monospacedDigit()
                    Text(NSLocalizedString("Availability applies to new supply; customers keep manufactured older versions.", comment: "Catalogue semantics footer."))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }.padding(10)
            } else {
                VStack(spacing: 12) {
                    Text(NSLocalizedString("Enable CRM lookup", comment: "Enable CRM for catalogue."))
                    SettingsLink()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 820, minHeight: 430)
        .toolbar {
            Button { Task { await model.reload() } } label: {
                Label(NSLocalizedString("Refresh", comment: "Reload catalogue."), systemImage: "arrow.clockwise")
            }.disabled(model.isLoading || !model.settings.enabled)
        }
        .task(id: model.settings.generation) { if model.settings.enabled { await model.reload() } else { model.clear() } }
        .onDisappear { model.clear() }
    }
}
