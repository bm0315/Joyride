import AgentAvatarCore
import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let library: AvatarPackLibrary
    private let preferences: AppPreferences
    private let onPackSelected: (InstalledAvatarPack) -> Void
    private let onPrivacyChanged: (Bool) -> Void

    private let packPopup = NSPopUpButton()
    private let packStatus = NSTextField(labelWithString: "")
    private let privacyCheckbox = NSButton(checkboxWithTitle: "Private mode: show neutral working during tasks", target: nil, action: nil)
    private let blacklistField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let modelPopup = NSPopUpButton()
    private let photoLabel = NSTextField(labelWithString: "No reference photo selected")
    private let rightsCheckbox = NSButton(checkboxWithTitle: "I own this photo or have permission to use it", target: nil, action: nil)
    private let generationNameField = NSTextField(string: "My Avatar")
    private let generationButton = NSButton(title: "Generate 8-state pack", target: nil, action: nil)
    private let progressLabel = NSTextField(labelWithString: "")
    private var selectedPhotoURL: URL?

    init(
        library: AvatarPackLibrary,
        preferences: AppPreferences,
        onPackSelected: @escaping (InstalledAvatarPack) -> Void,
        onPrivacyChanged: @escaping (Bool) -> Void
    ) {
        self.library = library
        self.preferences = preferences
        self.onPackSelected = onPackSelected
        self.onPrivacyChanged = onPrivacyChanged
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 650),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Joyride Settings"
        super.init(window: window)
        configureUI(window)
        reloadValues()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func refresh() {
        reloadValues()
    }

    @objc private func importPack() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an Avatar Pack v1 ZIP archive"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let pack = try library.importArchive(at: url)
            reloadValues()
            packPopup.selectItem(withTitle: pack.name)
            showMessage("Imported \(pack.name)", detail: pack.validation.certificationReason)
        } catch {
            showError(error)
        }
    }

    @objc private func selectPack() {
        guard let id = packPopup.selectedItem?.representedObject as? String else { return }
        do {
            let pack = try library.select(id: id)
            updatePackStatus(pack)
            onPackSelected(pack)
        } catch {
            showError(error)
        }
    }

    @objc private func deletePack() {
        guard let id = packPopup.selectedItem?.representedObject as? String else { return }
        do {
            try library.delete(id: id)
            reloadValues()
        } catch {
            showError(error)
        }
    }

    @objc private func savePrivacy() {
        preferences.privacyMode = privacyCheckbox.state == .on
        preferences.keywordBlacklist = blacklistField.stringValue
            .split(separator: ",")
            .map(String.init)
        blacklistField.stringValue = preferences.keywordBlacklist.joined(separator: ", ")
        onPrivacyChanged(preferences.privacyMode)
        progressLabel.stringValue = "Privacy settings saved. Adapters refresh the blacklist within five seconds."
    }

    @objc private func saveAPIKey() {
        do {
            try APIKeyStore.save(apiKeyField.stringValue)
            apiKeyField.stringValue = ""
            progressLabel.stringValue = "API key saved to macOS Keychain."
        } catch {
            showError(error)
        }
    }

    @objc private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the character anchor used by all eight states"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedPhotoURL = url
        photoLabel.stringValue = url.lastPathComponent
    }

    @objc private func generatePack() {
        guard let photo = selectedPhotoURL else {
            showMessage("No photo selected", detail: "Choose one character reference image.")
            return
        }
        guard rightsCheckbox.state == .on else {
            showError(AvatarPackGenerationError.portraitRightsRequired)
            return
        }
        guard let model = modelPopup.selectedItem?.title else { return }
        preferences.generationModel = model

        do {
            guard let key = try APIKeyStore.read(), !key.isEmpty else {
                throw AvatarPackGenerationError.missingAPIKey
            }
            generationButton.isEnabled = false
            progressLabel.stringValue = "Preparing generation…"
            let name = generationNameField.stringValue
            Task { [self] in
                do {
                    let temporary = try await OpenAIAvatarPackGenerator(session: .shared).generate(
                        name: name,
                        anchorImage: photo,
                        model: model,
                        apiKey: key,
                        portraitRightsConfirmed: true
                    ) { [weak self] index, total, state in
                        Task { @MainActor in
                            self?.progressLabel.stringValue = index == total
                                ? "Validating the avatar pack…"
                                : "Generating \(index + 1)/\(total): \(state.displayName)"
                        }
                    }
                    let pack = try library.installGeneratedPack(from: temporary)
                    try? FileManager.default.removeItem(at: temporary)
                    reloadValues()
                    packPopup.selectItem(withTitle: pack.name)
                    _ = try library.select(id: pack.id)
                    onPackSelected(pack)
                    progressLabel.stringValue = "Generated and activated \(pack.name)"
                    generationButton.isEnabled = true
                } catch {
                    generationButton.isEnabled = true
                    showError(error)
                }
            }
        } catch {
            showError(error)
        }
    }

    private func configureUI(_ window: NSWindow) {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = NSView()
        window.contentView?.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            root.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor),
        ])

        root.addArrangedSubview(sectionTitle("Avatar Library · Pack v1"))
        packPopup.target = self
        packPopup.action = #selector(selectPack)
        root.addArrangedSubview(packPopup)
        packPopup.widthAnchor.constraint(equalToConstant: 400).isActive = true
        let packButtons = NSStackView(views: [
            button("Import ZIP…", #selector(importPack)),
            button("Switch", #selector(selectPack)),
            button("Move to Trash", #selector(deletePack)),
        ])
        packButtons.spacing = 8
        root.addArrangedSubview(packButtons)
        packStatus.textColor = .secondaryLabelColor
        root.addArrangedSubview(packStatus)
        root.addArrangedSubview(separator())

        root.addArrangedSubview(sectionTitle("Privacy"))
        privacyCheckbox.target = self
        root.addArrangedSubview(privacyCheckbox)
        root.addArrangedSubview(NSTextField(labelWithString: "Task keyword blacklist (comma-separated; matches publish only working)"))
        blacklistField.placeholderString = "Example: finance, medical, confidential project"
        blacklistField.widthAnchor.constraint(equalToConstant: 550).isActive = true
        root.addArrangedSubview(blacklistField)
        root.addArrangedSubview(button("Save privacy settings", #selector(savePrivacy)))
        root.addArrangedSubview(separator())

        root.addArrangedSubview(sectionTitle("BYOK · Generate a pack from a photo"))
        let explanation = NSTextField(wrappingLabelWithString: "The API key stays in local Keychain. This Mac calls the model service directly and usage is billed to your account. The platform supplies only the scene prompt matrix.")
        explanation.textColor = .secondaryLabelColor
        explanation.maximumNumberOfLines = 2
        explanation.widthAnchor.constraint(equalToConstant: 550).isActive = true
        root.addArrangedSubview(explanation)
        let noKey = NSTextField(labelWithString: "Without a key, no photo is uploaded. Platform-funded generation is not available yet.")
        noKey.textColor = .tertiaryLabelColor
        root.addArrangedSubview(noKey)
        apiKeyField.placeholderString = "OpenAI API key (save an empty value to delete)"
        apiKeyField.widthAnchor.constraint(equalToConstant: 420).isActive = true
        let keyRow = NSStackView(views: [apiKeyField, button("Save to Keychain", #selector(saveAPIKey))])
        keyRow.spacing = 8
        root.addArrangedSubview(keyRow)
        modelPopup.addItems(withTitles: CertifiedModelRegistry.recommendedOpenAIModels)
        root.addArrangedSubview(modelPopup)
        generationNameField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        root.addArrangedSubview(generationNameField)
        let photoRow = NSStackView(views: [button("Choose reference photo…", #selector(choosePhoto)), photoLabel])
        photoRow.spacing = 8
        root.addArrangedSubview(photoRow)
        root.addArrangedSubview(rightsCheckbox)
        generationButton.target = self
        generationButton.action = #selector(generatePack)
        root.addArrangedSubview(generationButton)
        progressLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(progressLabel)
    }

    private func reloadValues() {
        packPopup.removeAllItems()
        for pack in library.packs {
            packPopup.addItem(withTitle: pack.name)
            packPopup.lastItem?.representedObject = pack.id
        }
        if let selected = library.selectedPack {
            packPopup.selectItem(withTitle: selected.name)
            updatePackStatus(selected)
        }
        privacyCheckbox.state = preferences.privacyMode ? .on : .off
        blacklistField.stringValue = preferences.keywordBlacklist.joined(separator: ", ")
        modelPopup.selectItem(withTitle: preferences.generationModel)
    }

    private func updatePackStatus(_ pack: InstalledAvatarPack) {
        packStatus.stringValue = pack.isCertified
            ? "✓ Certified · \(pack.validation.manifest.generator.model) · Format v\(pack.validation.manifest.formatVersion)"
            : "⚠ Uncertified · Not eligible for recommendations · \(pack.validation.certificationReason)"
    }

    private func sectionTitle(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        return label
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let value = NSButton(title: title, target: self, action: action)
        value.bezelStyle = .rounded
        return value
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 550).isActive = true
        return box
    }

    private func showError(_ error: Error) {
        showMessage("Operation failed", detail: error.localizedDescription)
    }

    private func showMessage(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.beginSheetModal(for: window!)
    }
}
