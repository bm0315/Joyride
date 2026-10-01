import JoyrideCore
import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let library: AvatarPackLibrary
    private let preferences: AppPreferences
    private let feedbackConfiguration: FeedbackConfiguration
    private let analytics: ProductAnalyticsStore
    private let onPackSelected: (InstalledAvatarPack) -> Void
    private let onPrivacyChanged: (Bool) -> Void

    private let packPopup = NSPopUpButton()
    private let packStatus = NSTextField(labelWithString: "")
    private let privacyCheckbox = NSButton(checkboxWithTitle: "Private mode: show neutral working during tasks", target: nil, action: nil)
    private let blacklistField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let providerPopup = NSPopUpButton()
    private let modelPopup = NSPopUpButton()
    private let tierPopup = NSPopUpButton()
    private let providerCapabilityLabel = NSTextField(labelWithString: "")
    private let photoLabel = NSTextField(labelWithString: "No reference photo selected")
    private let rightsCheckbox = NSButton(checkboxWithTitle: "I own this photo or have permission to use it", target: nil, action: nil)
    private let generationNameField = NSTextField(string: "My Avatar")
    private let generationButton = NSButton(title: "Generate 8-state tier pack", target: nil, action: nil)
    private let analyticsCheckbox = NSButton(checkboxWithTitle: "Share anonymous product metrics", target: nil, action: nil)
    private let progressLabel = NSTextField(labelWithString: "")
    private var selectedPhotoURL: URL?

    init(
        library: AvatarPackLibrary,
        preferences: AppPreferences,
        feedbackConfiguration: FeedbackConfiguration,
        analytics: ProductAnalyticsStore,
        onPackSelected: @escaping (InstalledAvatarPack) -> Void,
        onPrivacyChanged: @escaping (Bool) -> Void
    ) {
        self.library = library
        self.preferences = preferences
        self.feedbackConfiguration = feedbackConfiguration
        self.analytics = analytics
        self.onPackSelected = onPackSelected
        self.onPrivacyChanged = onPrivacyChanged
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 820),
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
        panel.message = "Choose a Joyride Avatar Pack v3 ZIP archive"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let pack = try library.importArchive(at: url)
            analytics.record(.packImported, tier: nil, provider: nil, outcome: "success")
            reloadValues()
            packPopup.selectItem(withTitle: pack.name)
            showMessage("Imported \(pack.name)", detail: pack.validation.certificationReason)
        } catch {
            analytics.record(.packImported, tier: nil, provider: nil, outcome: "failure")
            showError(error)
        }
    }

    @objc private func selectPack() {
        guard let id = packPopup.selectedItem?.representedObject as? String else { return }
        do {
            let pack = try library.select(id: id)
            updatePackStatus(pack)
            onPackSelected(pack)
            analytics.record(.packSelected, tier: nil, provider: nil, outcome: "success")
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
            let provider = selectedProvider()
            try APIKeyStore.save(apiKeyField.stringValue, provider: provider)
            apiKeyField.stringValue = ""
            progressLabel.stringValue = "\(provider.displayName) API key saved to macOS Keychain."
        } catch {
            showError(error)
        }
    }

    @objc private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the character anchor shared by every generated state"
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
        let provider = selectedProvider()
        guard provider.supportsReferenceImageGeneration else {
            showError(AvatarPackGenerationError.unsupportedProvider(provider))
            return
        }
        guard let model = modelPopup.selectedItem?.title,
              let tierValue = tierPopup.selectedItem?.representedObject as? String,
              let tier = StateTier(rawValue: tierValue) else { return }
        preferences.generationProvider = provider
        preferences.generationModel = model
        preferences.generationTier = tier

        do {
            guard let key = try APIKeyStore.read(provider: provider), !key.isEmpty else {
                throw AvatarPackGenerationError.missingAPIKey(provider)
            }
            generationButton.isEnabled = false
            progressLabel.stringValue = "Preparing generation…"
            let name = generationNameField.stringValue
            analytics.record(.generationStarted, tier: tier, provider: provider, outcome: nil)
            Task { [self] in
                do {
                    let temporary = try await BYOKAvatarPackGenerator(session: .shared).generate(
                        name: name,
                        anchorImage: photo,
                        provider: provider,
                        model: model,
                        tier: tier,
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
                    analytics.record(.generationSucceeded, tier: tier, provider: provider, outcome: "success")
                    generationButton.isEnabled = true
                } catch {
                    generationButton.isEnabled = true
                    analytics.record(.generationFailed, tier: tier, provider: provider, outcome: "failure")
                    showError(error)
                }
            }
        } catch {
            showError(error)
        }
    }

    @objc private func selectProvider() {
        let provider = selectedProvider()
        preferences.generationProvider = provider
        reloadProviderControls(provider)
    }

    @objc private func saveAnalyticsPreference() {
        preferences.analyticsOptIn = analyticsCheckbox.state == .on
        progressLabel.stringValue = preferences.analyticsOptIn
            ? "Anonymous product metrics enabled."
            : "Anonymous product metrics disabled."
    }

    @objc private func openWaitlist() {
        openFeedbackURL(feedbackConfiguration.waitlistURL)
    }

    @objc private func openFeedbackForm() {
        openFeedbackURL(feedbackConfiguration.feedbackFormURL)
    }

    @objc private func emailSupport() {
        openFeedbackURL(feedbackConfiguration.supportEmailURL)
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

        root.addArrangedSubview(sectionTitle("Avatar Library · Pack v3"))
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
        providerPopup.target = self
        providerPopup.action = #selector(selectProvider)
        for provider in ModelProvider.allCases {
            providerPopup.addItem(withTitle: provider.displayName)
            providerPopup.lastItem?.representedObject = provider.rawValue
        }
        root.addArrangedSubview(providerPopup)
        providerCapabilityLabel.textColor = .secondaryLabelColor
        providerCapabilityLabel.maximumNumberOfLines = 2
        providerCapabilityLabel.widthAnchor.constraint(equalToConstant: 550).isActive = true
        root.addArrangedSubview(providerCapabilityLabel)
        apiKeyField.widthAnchor.constraint(equalToConstant: 420).isActive = true
        let keyRow = NSStackView(views: [apiKeyField, button("Save to Keychain", #selector(saveAPIKey))])
        keyRow.spacing = 8
        root.addArrangedSubview(keyRow)
        root.addArrangedSubview(modelPopup)
        for tier in StateTier.allCases {
            tierPopup.addItem(withTitle: "\(tier.displayName) · 8 states")
            tierPopup.lastItem?.representedObject = tier.rawValue
        }
        root.addArrangedSubview(tierPopup)
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
        root.addArrangedSubview(separator())

        root.addArrangedSubview(sectionTitle("Feedback & Privacy-Preserving Metrics"))
        let feedbackButtons = NSStackView(views: [
            configuredButton(
                feedbackConfiguration.waitlistURL == nil ? "Waitlist not configured" : "Join waitlist",
                #selector(openWaitlist),
                isEnabled: feedbackConfiguration.waitlistURL != nil
            ),
            configuredButton(
                feedbackConfiguration.feedbackFormURL == nil ? "Feedback form not configured" : "Feedback form",
                #selector(openFeedbackForm),
                isEnabled: feedbackConfiguration.feedbackFormURL != nil
            ),
            configuredButton(
                feedbackConfiguration.supportEmail == nil ? "Support email not configured" : "Email support",
                #selector(emailSupport),
                isEnabled: feedbackConfiguration.supportEmail != nil
            ),
        ])
        feedbackButtons.spacing = 8
        root.addArrangedSubview(feedbackButtons)
        analyticsCheckbox.target = self
        analyticsCheckbox.action = #selector(saveAnalyticsPreference)
        root.addArrangedSubview(analyticsCheckbox)
        let metricsNote = NSTextField(wrappingLabelWithString: "Metrics are off by default and never include prompts, task text, tool arguments, filenames, agent IDs, API keys, or images. A global waitlist count appears only after a trusted waitlist service is configured.")
        metricsNote.textColor = .secondaryLabelColor
        metricsNote.maximumNumberOfLines = 3
        metricsNote.widthAnchor.constraint(equalToConstant: 550).isActive = true
        root.addArrangedSubview(metricsNote)
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
        let provider = preferences.generationProvider
        providerPopup.selectItem(withTitle: provider.displayName)
        reloadProviderControls(provider)
        tierPopup.selectItem(withTitle: "\(preferences.generationTier.displayName) · 8 states")
        analyticsCheckbox.state = preferences.analyticsOptIn ? .on : .off
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

    private func configuredButton(_ title: String, _ action: Selector, isEnabled: Bool) -> NSButton {
        let value = button(title, action)
        value.isEnabled = isEnabled
        return value
    }

    private func selectedProvider() -> ModelProvider {
        guard let rawValue = providerPopup.selectedItem?.representedObject as? String,
              let provider = ModelProvider(rawValue: rawValue) else { return .openAI }
        return provider
    }

    private func reloadProviderControls(_ provider: ModelProvider) {
        apiKeyField.placeholderString = "\(provider.displayName) API key (save empty to delete)"
        modelPopup.removeAllItems()
        modelPopup.addItems(withTitles: CertifiedModelRegistry.recommendedModels(for: provider))
        let preferredModel = preferences.generationModel
        if !preferredModel.isEmpty {
            modelPopup.selectItem(withTitle: preferredModel)
        }
        modelPopup.isEnabled = provider.supportsReferenceImageGeneration
        generationButton.isEnabled = provider.supportsReferenceImageGeneration
        providerCapabilityLabel.stringValue = provider.supportsReferenceImageGeneration
            ? "Certified reference-image generation is available for \(provider.displayName)."
            : "Anthropic keys are supported for future orchestration, but Claude does not produce image output, so pack generation is disabled."
    }

    private func openFeedbackURL(_ url: URL?) {
        guard let url else { return }
        analytics.record(.feedbackOpened, tier: nil, provider: nil, outcome: "success")
        NSWorkspace.shared.open(url)
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
