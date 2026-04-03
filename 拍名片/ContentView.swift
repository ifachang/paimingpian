import PhotosUI
import SwiftUI
import UIKit

struct ContentView: View {
    private enum PlanTier {
        case free
        case pro
    }

    private enum RelationshipGoal: String, CaseIterable, Identifiable {
        case client = "開發客戶"
        case partnership = "找合作機會"
        case investor = "找資源或投資"
        case network = "建立長期關係"

        var id: String { rawValue }
    }

    private enum Screen {
        case home
        case loading
        case review
        case preContactSave
        case success
    }

    @Environment(\.openURL) private var openURL
    @State private var screen: Screen = .home
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var scannedCard = ScannedCard()
    @State private var savedName = ""
    @State private var errorMessage = ""
    @State private var isShowingError = false
    @State private var isShowingCamera = false
    @State private var isShowingEditor = false
    @State private var cardCandidates: [DetectedCardCandidate] = []
    @State private var isShowingCardPicker = false
    @State private var isShowingProSheet = false
    @State private var isShowingMyCardSheet = false
    @State private var isShowingQRScanner = false
    @State private var isShowingPeopleSearch = false
    @State private var myDigitalCard = MyDigitalCardStore.shared.load()
    @State private var noticeMessage = ""
    @State private var isShowingNotice = false
    @State private var outreachContext = ""
    @State private var outreachSuggestions: [OutreachSuggestion] = []
    @State private var isGeneratingOutreach = false
    @State private var copiedSuggestionID: String?
    @State private var relationshipGoal: RelationshipGoal = .network
    @State private var relationshipAnalysisContext = ""
    @State private var relationshipAnalysis: RelationshipValueAnalysis?
    @State private var isAnalyzingRelationship = false
    @State private var savedRelationshipAnalyses = RelationshipAnalysisStore.shared.load()
    @State private var peopleSearchQuery = ""
    @State private var peopleSearchResults: [PeopleSearchResultCard] = []
    @State private var peopleSearchSummary = ""
    @State private var isSearchingPeople = false
    @State private var isEnhancingCard = false
    @State private var enhancementMessage = ""
    @State private var currentScanID = UUID()
    @State private var homeHeroConfig: HomeHeroConfig?
    @State private var didLoadHomeHeroConfig = false
    @State private var currentHeroIndex = 0
    private let isProUnlocked = true

    private let contactStoreService = ContactStoreService()
    private let openAIService = OpenAIService()

    private var planTier: PlanTier {
        .pro
    }

    private var isProLLMReady: Bool {
        !AppSecrets.aiProxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                switch screen {
                case .home:
                    homeView
                case .loading:
                    loadingView
                case .review:
                    reviewView
                case .preContactSave:
                    preContactSaveView
                case .success:
                    successView
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .animation(.easeInOut(duration: 0.2), value: screen)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingProSheet = true
                    } label: {
                        Text(isProLLMReady ? "AI 已可用" : "AI 服務")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .task {
            await loadHomeHeroConfigIfNeeded()
        }
        .sheet(isPresented: $isShowingCamera) {
            ImagePicker(sourceType: .camera) { image in
                process(image: image)
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        editorSection(title: "基本資料") {
                            VStack(spacing: 12) {
                                TextField("名", text: $scannedCard.givenName)
                                    .editorFieldStyle()
                                TextField("姓", text: $scannedCard.familyName)
                                    .editorFieldStyle()
                                TextField("公司", text: $scannedCard.company)
                                    .editorFieldStyle()
                                TextField("職稱", text: $scannedCard.jobTitle)
                                    .editorFieldStyle()
                                TextField("地址", text: $scannedCard.address, axis: .vertical)
                                    .lineLimit(2...4)
                                    .editorFieldStyle()
                            }
                        }

                        editorSection(title: "電話") {
                            VStack(spacing: 12) {
                                ForEach($scannedCard.phoneNumbers) { $phone in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Picker("類型", selection: $phone.kind) {
                                            ForEach(LabeledValue.Kind.allCases, id: \.self) { kind in
                                                Text(kind.displayName).tag(kind)
                                            }
                                        }
                                        .pickerStyle(.menu)

                                        TextField("電話", text: $phone.value)
                                            .keyboardType(.phonePad)
                                            .editorFieldStyle()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }

                                Button("新增電話") {
                                    scannedCard.phoneNumbers.append(LabeledValue(kind: .other, value: ""))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        editorSection(title: "Email") {
                            VStack(spacing: 12) {
                                ForEach($scannedCard.emails) { $email in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Picker("類型", selection: $email.kind) {
                                            ForEach(LabeledValue.Kind.allCases, id: \.self) { kind in
                                                Text(kind.displayName).tag(kind)
                                            }
                                        }
                                        .pickerStyle(.menu)

                                        TextField("Email", text: $email.value)
                                            .textInputAutocapitalization(.never)
                                            .keyboardType(.emailAddress)
                                            .editorFieldStyle()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }

                                Button("新增 Email") {
                                    scannedCard.emails.append(LabeledValue(kind: .other, value: ""))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(20)
                }
                .navigationTitle("修改資料")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") {
                            isShowingEditor = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingCardPicker) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        Text("偵測到多張名片")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("請先選一張要辨識的名片，避免資料混在一起。")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(cardCandidates) { candidate in
                                Button {
                                    isShowingCardPicker = false
                                    performOCR(on: candidate.image)
                                } label: {
                                    Image(uiImage: candidate.image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 140)
                                        .padding(8)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(24)
                }
                .navigationTitle("選擇名片")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("取消") {
                            resetFlow()
                            isShowingCardPicker = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingProSheet) {
            ProUpgradeView(
                onClose: {
                    isShowingProSheet = false
                }
            )
        }
        .sheet(isPresented: $isShowingMyCardSheet) {
            NavigationStack {
                MyDigitalCardView(
                    card: $myDigitalCard,
                    latestScannedCard: scannedCard
                )
            }
        }
        .sheet(isPresented: $isShowingQRScanner) {
            NavigationStack {
                QRImportView(
                    onClose: {
                        isShowingQRScanner = false
                    },
                    onImport: { importedCard in
                        scannedCard = importedCard
                        relationshipAnalysis = nil
                        relationshipAnalysisContext = ""
                        outreachSuggestions = []
                        copiedSuggestionID = nil
                        isShowingQRScanner = false
                        screen = .review
                        noticeMessage = "已讀取對方的電子名片，你可以直接檢查後存入聯絡人。"
                        isShowingNotice = true
                    },
                    onFailure: { error in
                        isShowingQRScanner = false
                        showError(error)
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingPeopleSearch) {
            NavigationStack {
                PeopleSearchView(
                    query: $peopleSearchQuery,
                    results: $peopleSearchResults,
                    summary: $peopleSearchSummary,
                    isSearching: $isSearchingPeople,
                    onSearch: {
                        searchPeople()
                    },
                    onClose: {
                        isShowingPeopleSearch = false
                    }
                )
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }

            Task {
                do {
                    guard let data = try await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data)
                    else {
                        throw OCRServiceError.noTextDetected
                    }

                    process(image: image)
                } catch {
                    showError(error)
                }
            }
        }
        .alert("辨識失敗", isPresented: $isShowingError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("提醒", isPresented: $isShowingNotice) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(noticeMessage)
        }
    }

    @MainActor
    private func loadHomeHeroConfigIfNeeded() async {
        guard !didLoadHomeHeroConfig else { return }
        didLoadHomeHeroConfig = true
        homeHeroConfig = await HomeHeroService.shared.fetchConfig()
        currentHeroIndex = 0
    }

    private var homeView: some View {
        VStack(spacing: 24) {
            homeIllustration

            myDigitalCardPreview

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text("Wo名片")
                        .font(.largeTitle.bold())

                    Text("AI")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }

                Text(homeSubtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button("小Wo找人") {
                    isShowingPeopleSearch = true
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button("我的電子名片") {
                    isShowingMyCardSheet = true
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button("掃描名片") {
                    isShowingCamera = true
                }
                .buttonStyle(PrimaryButtonStyle())

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Text("選擇照片")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button("掃描電子名片 QR") {
                    isShowingQRScanner = true
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            planCard

            Spacer()

            Link(destination: URL(string: "https://wowo.one")!) {
                HStack(spacing: 6) {
                    Image("WoWoLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .opacity(0.85)

                    Text("Developed by WoWo AI Commerce")
                        .font(.footnote)
                }
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var myDigitalCardPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("我的電子名片")
                        .font(.headline)

                    Text("直接出示 QR Code，讓對方快速掃描匯入。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("編輯") {
                    isShowingMyCardSheet = true
                }
                .font(.subheadline.weight(.semibold))
            }

            if let qrImage = myDigitalCardPreviewImage {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(myDigitalCard.displayName)
                            .font(.headline)

                        if !myDigitalCard.company.isEmpty {
                            Text(myDigitalCard.company)
                                .foregroundStyle(.secondary)
                        }

                        if !myDigitalCard.jobTitle.isEmpty {
                            Text(myDigitalCard.jobTitle)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 108, height: 108)
                        .padding(10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            } else {
                Button("建立我的電子名片") {
                    isShowingMyCardSheet = true
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var myDigitalCardPreviewImage: UIImage? {
        guard myDigitalCard.hasContent,
              let vCard = try? VCardService.makeVCardString(from: myDigitalCard)
        else {
            return nil
        }

        return VCardService.makeQRCode(from: vCard, sideLength: 480)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)
            Text("Wo名片正在辨識中...")
                .font(.headline)
            Spacer()
        }
    }

    private var reviewView: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Wo名片已幫你整理完成")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("確認後即可存入手機通訊錄")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    VStack(spacing: 6) {
                        Text(scannedCard.displayName)
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)

                        if !scannedCard.company.isEmpty {
                            Text(scannedCard.company)
                                .foregroundStyle(.secondary)
                        }

                        if !scannedCard.jobTitle.isEmpty {
                            Text(scannedCard.jobTitle)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(scannedCard.phoneNumbers.filter { !$0.isEmpty }) { phone in
                            Text("\(phone.kind.displayName)｜\(phone.value)")
                        }

                        ForEach(scannedCard.emails.filter { !$0.isEmpty }) { email in
                            Text("\(email.kind.displayName)｜\(email.value)")
                        }

                        if !scannedCard.address.isEmpty {
                            Text(scannedCard.address)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 1)
                    )

                    Button("儲存聯絡人") {
                        screen = .preContactSave
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Text("可隨時編輯")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("修改") {
                        isShowingEditor = true
                    }
                    .foregroundStyle(.secondary)

                    Button("顯示我的電子名片 QR") {
                        isShowingMyCardSheet = true
                    }
                    .foregroundStyle(.secondary)
                }

                if isEnhancingCard {
                    enhancementBanner
                }

                relationshipAnalysisSection

                outreachSection

                Button("重新開始") {
                    resetFlow()
                }
                .foregroundStyle(.secondary)

                Button("回到首頁") {
                    resetFlow()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
    }

    private var preContactSaveView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(.orange)

            VStack(spacing: 10) {
                Text("將這張名片加入手機")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("我們只會新增這一筆聯絡人")
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("不會讀取或上傳你的其他通訊錄資料")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("你的資料只存在你的裝置。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button("繼續儲存") {
                    saveContact()
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("先不要") {
                    screen = .review
                }
                .font(.headline)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var successView: some View {
        VStack(spacing: 18) {
            Spacer()

            Text("已成功加入聯絡人 🎉")
                .font(.title2.bold())

            Text(savedName)
                .font(.title3)

            Text("下次掃描會更快")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("繼續掃描") {
                resetFlow()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 12)

            Button("查看聯絡人") {
                openContactsApp()
            }
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button("回首頁") {
                resetFlow()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)

            Button("顯示我的電子名片 QR") {
                isShowingMyCardSheet = true
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private func process(image: UIImage) {
        screen = .loading

        Task {
            let candidates = await CardDetectionService.detectCards(in: image)

            if candidates.count > 1 {
                cardCandidates = candidates
                screen = .home
                isShowingCardPicker = true
                return
            }

            let targetImage = candidates.first?.image ?? image
            performOCR(on: targetImage)
        }
    }

    private func performOCR(on image: UIImage) {
        screen = .loading

        Task {
            do {
                let lines = try await OCRService.recognizeLines(from: image)
                let localCard = BusinessCardParser.parse(lines: lines)
                let scanID = UUID()

                currentScanID = scanID
                scannedCard = localCard
                relationshipAnalysis = nil
                relationshipAnalysisContext = ""
                outreachSuggestions = []
                copiedSuggestionID = nil
                isEnhancingCard = false
                enhancementMessage = ""
                screen = .review

                guard isProLLMReady else {
                    return
                }

                let autoEnhanceDecision = shouldAutoEnhanceWithAI(lines: lines, card: localCard)
                guard autoEnhanceDecision.shouldEnhance else {
                    if let reason = autoEnhanceDecision.reason {
                        noticeMessage = reason
                        isShowingNotice = true
                    }
                    return
                }

                isEnhancingCard = true
                enhancementMessage = "偵測到這張名片較複雜，正在用 AI 智慧辨識優化姓名、公司與聯絡方式..."

                Task {
                    do {
                        let enhancedCard = try await openAIService.parseBusinessCard(
                            lines: lines,
                            fallback: localCard
                        )

                        guard currentScanID == scanID else {
                            return
                        }

                        scannedCard = enhancedCard
                        isEnhancingCard = false
                        enhancementMessage = ""
                        noticeMessage = "已完成 AI 智慧優化，結果已更新。"
                        isShowingNotice = true
                    } catch {
                        guard currentScanID == scanID else {
                            return
                        }

                        isEnhancingCard = false
                        enhancementMessage = ""
                        noticeMessage = "AI 智慧優化暫時失敗，這次先使用基本辨識結果。"
                        isShowingNotice = true
                    }
                }
            } catch {
                screen = .home
                showError(error)
            }
        }
    }

    private func shouldAutoEnhanceWithAI(lines: [OCRTextLine], card: ScannedCard) -> (shouldEnhance: Bool, reason: String?) {
        let nonEmptyPhoneCount = card.phoneNumbers.filter { !$0.isEmpty }.count
        let nonEmptyEmailCount = card.emails.filter { !$0.isEmpty }.count
        let compactName = card.fullName.replacingOccurrences(of: " ", with: "")
        let missingCoreFields =
            compactName.isEmpty ||
            card.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            (nonEmptyPhoneCount == 0 && nonEmptyEmailCount == 0)

        if missingCoreFields {
            return (true, nil)
        }

        let lineTexts = lines.map(\.text)
        let lineCount = lines.count
        let maxLineLength = lineTexts.map(\.count).max() ?? 0

        let containsMixedLanguages = lineTexts.contains { text in
            let hasLatin = text.range(of: "[A-Za-z]", options: .regularExpression) != nil
            let hasCJK = text.range(of: #"\p{Han}"#, options: .regularExpression) != nil
            return hasLatin && hasCJK
        }

        let hasManyContactMethods = nonEmptyPhoneCount + nonEmptyEmailCount >= 4
        let hasDenseLayout = lineCount >= 9
        let hasLongAddress = card.address.count >= 28
        let missingTitle = card.jobTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let shouldEnhance =
            hasDenseLayout ||
            containsMixedLanguages ||
            hasManyContactMethods ||
            hasLongAddress ||
            (missingTitle && lineCount >= 6) ||
            maxLineLength >= 30

        if shouldEnhance {
            return (true, nil)
        }

        return (false, "本地辨識結果已足夠完整，這次先不額外使用 AI。")
    }

    private func saveContact() {
        Task {
            do {
                scannedCard.normalized()
                try await contactStoreService.save(card: scannedCard)
                savedName = scannedCard.displayName
                screen = .success
            } catch {
                showError(error)
            }
        }
    }

    private func openContactsApp() {
        let possibleURLs = ["contacts://", "addressbook://"].compactMap(URL.init(string:))

        for url in possibleURLs where UIApplication.shared.canOpenURL(url) {
            openURL(url)
            return
        }

        noticeMessage = "目前無法直接打開聯絡人 App，你也可以稍後在手機通訊錄中查看。"
        isShowingNotice = true
    }

    private func resetFlow() {
        selectedPhoto = nil
        scannedCard = ScannedCard()
        savedName = ""
        cardCandidates = []
        relationshipGoal = .network
        relationshipAnalysisContext = ""
        relationshipAnalysis = nil
        isAnalyzingRelationship = false
        peopleSearchQuery = ""
        peopleSearchResults = []
        peopleSearchSummary = ""
        isSearchingPeople = false
        outreachContext = ""
        outreachSuggestions = []
        copiedSuggestionID = nil
        isEnhancingCard = false
        enhancementMessage = ""
        currentScanID = UUID()
        screen = .home
    }

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        isShowingError = true
    }

    private var homeSubtitle: String {
        switch planTier {
        case .free:
            return "掃描一張或選一張名片照片，快速存進聯絡人。"
        case .pro:
            return isProLLMReady
                ? "會先做本地 OCR，遇到較複雜的名片時再由後台 AI 補強整理。"
                : "可先用本地 OCR 完成掃描；接上後台 AI 服務後可自動補強複雜名片。"
        }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                planTier == .free
                ? "免費版可先完成基本掃描"
                : "AI 智慧功能已可使用"
            )
                .font(.headline)

            Text(
                planTier == .pro
                ? "目前會先做本地 OCR，遇到較複雜的名片時再交由後台 AI 服務補強整理。"
                : "免費版可先用本地 OCR。"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var homeIllustration: some View {
        let heroItems = homeHeroConfig?.items ?? []

        return Group {
            if homeHeroConfig?.usesCarousel == true, !heroItems.isEmpty {
                TabView(selection: $currentHeroIndex) {
                    ForEach(Array(heroItems.enumerated()), id: \.offset) { index, item in
                        heroIllustrationLink(for: item) {
                            remoteHomeIllustration(url: item.imageURL)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: 236)
                .task(id: heroItems.map(\.id).joined(separator: "|")) {
                    guard homeHeroConfig?.usesCarousel == true, heroItems.count > 1 else { return }

                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(4))
                        guard !Task.isCancelled, homeHeroConfig?.usesCarousel == true, heroItems.count > 1 else { break }

                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                currentHeroIndex = (currentHeroIndex + 1) % heroItems.count
                            }
                        }
                    }
                }
            } else if let firstItem = heroItems.first {
                heroIllustrationLink(for: firstItem) {
                    remoteHomeIllustration(url: firstItem.imageURL)
                }
            } else {
                heroIllustrationLink(for: nil) {
                    fallbackHomeIllustration
                }
            }
        }
    }

    private func remoteHomeIllustration(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            default:
                fallbackHomeIllustration
            }
        }
    }

    private func heroIllustrationLink<Content: View>(for item: HomeHeroItem?, @ViewBuilder content: () -> Content) -> some View {
        let linkURL = item?.linkURL ?? homeHeroConfig?.linkURL ?? URL(string: "https://wowo.one")!

        return Link(destination: linkURL) {
            content()
        }
        .buttonStyle(.plain)
    }

    private var fallbackHomeIllustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.83, blue: 0.47),
                            Color(red: 0.95, green: 0.72, blue: 0.33)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 180, height: 180)
                .offset(x: -90, y: -50)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white)
                .frame(width: 220, height: 160)
                .rotationEffect(.degrees(-8))
                .offset(x: -28, y: 10)
                .shadow(color: .black.opacity(0.08), radius: 18, y: 10)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.12, green: 0.13, blue: 0.15))
                .frame(width: 220, height: 160)
                .rotationEffect(.degrees(8))
                .offset(x: 44, y: 4)
                .shadow(color: .black.opacity(0.1), radius: 18, y: 10)

            VStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 0.84, green: 0.63, blue: 0.22))
                    .frame(width: 40, height: 40)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.84, green: 0.63, blue: 0.22))
                    .frame(width: 72, height: 34)
            }
            .offset(x: -58, y: 8)

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white)
                    .frame(width: 88, height: 12)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.75))
                    .frame(width: 62, height: 10)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.45))
                    .frame(width: 106, height: 10)
            }
            .offset(x: 72, y: 6)

            Image("WoWoLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 118, height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
                .offset(x: 76, y: -54)
        }
        .frame(height: 220)
    }

    private var upgradeBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("啟用 AI，辨識更準")
                .font(.headline)

            Text("複雜版面、雙語名片與多張名片照片，都能更穩定整理。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("啟用 AI") {
                isShowingProSheet = true
            }
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var enhancementBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)

            VStack(alignment: .leading, spacing: 4) {
                Text("智慧優化中")
                    .font(.headline)

                Text(enhancementMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var relationshipAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("人脈價值分析")
                .font(.headline)

            Text("選一個你的目標，AI 會幫你分析這位聯絡人的合作潛力、優先級與建議跟進方式。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("分析目標", selection: $relationshipGoal) {
                ForEach(RelationshipGoal.allCases) { goal in
                    Text(goal.rawValue).tag(goal)
                }
            }
            .pickerStyle(.segmented)

            TextField("補充背景（選填），例如：在展會聊過跨境電商、對方提到想找品牌合作", text: $relationshipAnalysisContext, axis: .vertical)
                .lineLimit(2...4)
                .editorFieldStyle()

            if isProLLMReady {
                Button(isAnalyzingRelationship ? "分析中..." : "幫我分析") {
                    generateRelationshipAnalysis()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isAnalyzingRelationship)
            } else {
                Button("啟用 AI 以分析人脈價值") {
                    isShowingProSheet = true
                }
                .font(.subheadline.weight(.semibold))
            }

            if let relationshipAnalysis {
                relationshipDecisionCard(analysis: relationshipAnalysis)
                relationshipInsightCard(analysis: relationshipAnalysis)
            }

            if !savedRelationshipAnalyses.isEmpty {
                recentRelationshipAnalysesSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func relationshipDecisionCard(analysis: RelationshipValueAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(decisionCardTitle(for: analysis.priority))
                        .font(.title3.bold())
                        .foregroundStyle(.white)

                    Text(analysis.headline)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.96))

                    Text(analysis.summary)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.86))
                }

                Spacer()

                Image(systemName: decisionCardIcon(for: analysis.priority))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.white.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(spacing: 10) {
                decisionMetric(title: "目前判斷", value: priorityBadgeTitle(analysis.priority))
                decisionMetric(title: "你的目標", value: relationshipGoal.rawValue)
                decisionMetric(title: "建議節奏", value: decisionCadence(for: analysis.priority))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(
                colors: decisionCardColors(for: analysis.priority),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func relationshipInsightCard(analysis: RelationshipValueAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            analysisGroup(
                title: "這個人可能的價值",
                items: analysis.valueReasons,
                icon: "sparkles.rectangle.stack.fill"
            )

            analysisGroup(
                title: "可發展的機會",
                items: analysis.opportunities,
                icon: "arrow.triangle.branch"
            )

            insightRow(
                title: "建議下一步",
                body: analysis.nextAction,
                icon: "figure.walk.motion"
            )

            insightRow(
                title: "提醒",
                body: analysis.caution,
                icon: "exclamationmark.bubble"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var recentRelationshipAnalysesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近分析")
                .font(.subheadline.weight(.semibold))

            ForEach(savedRelationshipAnalyses.prefix(3)) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(item.card.displayName)
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        Text(priorityBadgeTitle(item.analysis.priority))
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(priorityBadgeColor(item.analysis.priority).opacity(0.14))
                            .foregroundStyle(priorityBadgeColor(item.analysis.priority))
                            .clipShape(Capsule())
                    }

                    Text([item.card.company, item.goal].filter { !$0.isEmpty }.joined(separator: "・"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text(item.analysis.headline)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var outreachSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("聯絡建議")
                .font(.headline)

            Text("掃完名片後，直接幫你生成 3 種初次聯絡訊息。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("補充情境（選填），例如：今天在展會認識，想約時間聊合作", text: $outreachContext, axis: .vertical)
                .lineLimit(2...4)
                .editorFieldStyle()

            if isProLLMReady {
                Button(isGeneratingOutreach ? "生成中..." : "幫我生成") {
                    generateOutreach()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isGeneratingOutreach)
            } else {
                Button("啟用 AI 以生成聯絡訊息") {
                    isShowingProSheet = true
                }
                .font(.subheadline.weight(.semibold))
            }

            ForEach(outreachSuggestions) { suggestion in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(suggestion.title)
                            .font(.headline)

                        Spacer()

                        Button(copiedSuggestionID == suggestion.id ? "已複製" : "複製") {
                            UIPasteboard.general.string = suggestion.message
                            copiedSuggestionID = suggestion.id

                            Task {
                                try? await Task.sleep(for: .seconds(1.2))
                                if copiedSuggestionID == suggestion.id {
                                    copiedSuggestionID = nil
                                }
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                    }

                    Text(suggestion.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func generateOutreach() {
        guard isProLLMReady else {
            isShowingProSheet = true
            return
        }

        isGeneratingOutreach = true

        Task {
            do {
                outreachSuggestions = try await openAIService.generateOutreachSuggestions(
                    card: scannedCard,
                    context: outreachContext
                )
            } catch {
                noticeMessage = "聯絡建議生成失敗，請稍後再試。"
                isShowingNotice = true
            }

            isGeneratingOutreach = false
        }
    }

    private func generateRelationshipAnalysis() {
        guard isProLLMReady else {
            isShowingProSheet = true
            return
        }

        isAnalyzingRelationship = true

        Task {
            do {
                relationshipAnalysis = try await openAIService.analyzeRelationshipValue(
                    card: scannedCard,
                    goal: relationshipGoal.rawValue,
                    context: relationshipAnalysisContext
                )
                if let relationshipAnalysis {
                    savedRelationshipAnalyses = RelationshipAnalysisStore.shared.save(
                        goal: relationshipGoal.rawValue,
                        card: scannedCard,
                        analysis: relationshipAnalysis
                    )
                }
            } catch {
                noticeMessage = "人脈價值分析失敗，請稍後再試。"
                isShowingNotice = true
            }

            isAnalyzingRelationship = false
        }
    }

    private func searchPeople() {
        let trimmedQuery = peopleSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            peopleSearchSummary = "請先輸入你想找的人脈條件。"
            peopleSearchResults = []
            return
        }

        isSearchingPeople = true

        Task {
            defer { isSearchingPeople = false }

            do {
                let contacts = try await contactStoreService.fetchSearchableContacts()
                let candidates = quickFilterContacts(contacts, query: trimmedQuery)

                guard !candidates.isEmpty else {
                    await MainActor.run {
                        peopleSearchSummary = "我暫時找不到明顯符合「\(trimmedQuery)」的人脈。"
                        peopleSearchResults = []
                    }
                    return
                }

                if isProLLMReady {
                    let aiRecommendations = try await openAIService.rerankContactsForPeopleSearch(
                        query: trimmedQuery,
                        candidates: Array(candidates.prefix(20))
                    )

                    let mapped = aiRecommendations.map { recommendation in
                        let matched = candidates.first(where: { $0.id == recommendation.id })
                        return PeopleSearchResultCard(
                            id: recommendation.id,
                            name: recommendation.name,
                            company: recommendation.company.isEmpty ? (matched?.displayCompany ?? "未提供公司") : recommendation.company,
                            reason: recommendation.reason,
                            email: matched?.email ?? "",
                            jobTitle: matched?.jobTitle ?? ""
                        )
                    }

                    await MainActor.run {
                        peopleSearchSummary = "我幫你找到 \(mapped.count) 位可能的人👇"
                        peopleSearchResults = mapped
                    }
                } else {
                    let localResults = Array(candidates.prefix(3)).map { contact in
                        PeopleSearchResultCard(
                            id: contact.id,
                            name: contact.name,
                            company: contact.displayCompany,
                            reason: localMatchReason(for: contact, query: trimmedQuery),
                            email: contact.email,
                            jobTitle: contact.jobTitle
                        )
                    }

                    await MainActor.run {
                        peopleSearchSummary = "我先幫你找到 \(localResults.count) 位可能的人👇"
                        peopleSearchResults = localResults
                    }
                }
            } catch {
                await MainActor.run {
                    peopleSearchSummary = "找人脈時發生問題，請稍後再試。"
                    peopleSearchResults = []
                    showError(error)
                }
            }
        }
    }

    private func quickFilterContacts(_ contacts: [SearchableContact], query: String) -> [SearchableContact] {
        let normalizedQuery = query.lowercased()
        let tokens = normalizedQuery
            .split { $0 == " " || $0 == "　" || $0 == "," || $0 == "，" }
            .map(String.init)
            .filter { !$0.isEmpty }

        let scored: [(SearchableContact, Int)] = contacts.compactMap { contact in
            let haystacks = [
                contact.name.lowercased(),
                contact.company.lowercased(),
                contact.email.lowercased(),
                contact.jobTitle.lowercased(),
                emailDomain(from: contact.email),
            ]

            var score = 0

            if haystacks.contains(where: { $0.contains(normalizedQuery) }) {
                score += 6
            }

            for token in tokens {
                if contact.company.lowercased().contains(token) { score += 4 }
                if contact.jobTitle.lowercased().contains(token) { score += 4 }
                if emailDomain(from: contact.email).contains(token) { score += 3 }
                if contact.name.lowercased().contains(token) { score += 2 }
                if contact.email.lowercased().contains(token) { score += 2 }
            }

            guard score > 0 else { return nil }
            return (contact, score)
        }

        return scored
            .sorted {
                if $0.1 == $1.1 {
                    return $0.0.name < $1.0.name
                }
                return $0.1 > $1.1
            }
            .map(\.0)
    }

    private func emailDomain(from email: String) -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let atIndex = trimmed.firstIndex(of: "@") else { return "" }
        return String(trimmed[trimmed.index(after: atIndex)...])
    }

    private func localMatchReason(for contact: SearchableContact, query: String) -> String {
        let loweredQuery = query.lowercased()

        if !contact.jobTitle.isEmpty, contact.jobTitle.lowercased().contains(loweredQuery) {
            return "職稱與你要找的條件相近。"
        }

        if !contact.company.isEmpty, contact.company.lowercased().contains(loweredQuery) {
            return "公司名稱與你的需求高度相關。"
        }

        if emailDomain(from: contact.email).contains(loweredQuery) {
            return "Email 網域看起來和這個領域有關。"
        }

        return "目前是根據名字、公司或職稱的關鍵字相似度推薦。"
    }

    @ViewBuilder
    private func analysisGroup(title: String, items: [String], icon: String) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))

                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)

                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func insightRow(title: String, body: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))

            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func decisionMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func priorityBadgeTitle(_ priority: String) -> String {
        switch priority.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high", "高", "高優先":
            return "高優先"
        case "medium", "中", "中優先":
            return "值得維護"
        default:
            return "先觀察"
        }
    }

    private func priorityBadgeColor(_ priority: String) -> Color {
        switch priority.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high", "高", "高優先":
            return .red
        case "medium", "中", "中優先":
            return .orange
        default:
            return .gray
        }
    }

    private func decisionCardTitle(for priority: String) -> String {
        switch normalizedPriority(priority) {
        case "high":
            return "值得馬上跟進"
        case "medium":
            return "適合長期維護"
        default:
            return "先觀察比較好"
        }
    }

    private func decisionCadence(for priority: String) -> String {
        switch normalizedPriority(priority) {
        case "high":
            return "今天就聯絡"
        case "medium":
            return "一週內維護"
        default:
            return "先補資訊"
        }
    }

    private func decisionCardIcon(for priority: String) -> String {
        switch normalizedPriority(priority) {
        case "high":
            return "bolt.fill"
        case "medium":
            return "leaf.fill"
        default:
            return "hourglass"
        }
    }

    private func decisionCardColors(for priority: String) -> [Color] {
        switch normalizedPriority(priority) {
        case "high":
            return [Color(red: 0.93, green: 0.36, blue: 0.23), Color(red: 0.72, green: 0.14, blue: 0.17)]
        case "medium":
            return [Color(red: 0.94, green: 0.63, blue: 0.20), Color(red: 0.79, green: 0.42, blue: 0.10)]
        default:
            return [Color(red: 0.36, green: 0.42, blue: 0.49), Color(red: 0.19, green: 0.23, blue: 0.30)]
        }
    }

    private func normalizedPriority(_ priority: String) -> String {
        switch priority.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high", "高", "高優先":
            return "high"
        case "medium", "中", "中優先":
            return "medium"
        default:
            return "low"
        }
    }

    @ViewBuilder
    private func editorSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content()
        }
    }
}

private struct PeopleSearchResultCard: Identifiable, Equatable {
    let id: String
    let name: String
    let company: String
    let reason: String
    let email: String
    let jobTitle: String
}

private struct PeopleSearchView: View {
    @Binding var query: String
    @Binding var results: [PeopleSearchResultCard]
    @Binding var summary: String
    @Binding var isSearching: Bool
    let onSearch: () -> Void
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("小Wo找人")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("一句話描述你要找的人脈，Wo名片會先幫你快速篩選，再挑出最相關的人。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 12) {
                TextField("例如：我需要找做 AI 的人", text: $query, axis: .vertical)
                    .lineLimit(2...4)
                    .editorFieldStyle()

                Button(isSearching ? "小Wo搜尋中..." : "開始找人") {
                    onSearch()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSearching)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if results.isEmpty, !isSearching {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("你可以這樣問")
                                .font(.subheadline.weight(.semibold))

                            Text("我需要找做 AI 的人")
                            Text("我認識誰在醫療通路？")
                            Text("有沒有做品牌合作的人脈？")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.name)
                                        .font(.headline)

                                    Text(result.company)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    if !result.jobTitle.isEmpty {
                                        Text(result.jobTitle)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("為什麼推薦")
                                    .font(.subheadline.weight(.semibold))

                                Text(result.reason)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Spacer()

                                Button("聯絡（即將推出）") {}
                                    .font(.subheadline.weight(.semibold))
                                    .disabled(true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 16)
            }
        }
        .padding(24)
        .navigationTitle("小Wo找人")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("關閉") {
                    onClose()
                    dismiss()
                }
            }
        }
    }
}

private struct MyDigitalCardView: View {
    @Binding var card: ScannedCard
    let latestScannedCard: ScannedCard

    @Environment(\.dismiss) private var dismiss

    private var qrImage: UIImage? {
        guard let vCard = try? VCardService.makeVCardString(from: card) else {
            return nil
        }
        return VCardService.makeQRCode(from: vCard)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("我的電子名片")
                        .font(.title2.bold())

                    Text("你可以先把自己的資料存在這裡，之後直接打開 QR Code 給別人掃描。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if latestScannedCard.hasContent {
                    Button("套用目前掃描到的名片資料") {
                        card = latestScannedCard
                        persistCard()
                    }
                    .font(.subheadline.weight(.semibold))
                }

                VStack(spacing: 14) {
                    if let qrImage {
                        VStack(spacing: 12) {
                            Text("給對方掃描的 QR Code")
                                .font(.headline)

                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 280)
                                .padding(20)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(Color(.separator), lineWidth: 1)
                                )
                        }
                    } else {
                        VStack(spacing: 8) {
                            Text("目前無法生成 QR Code")
                                .font(.headline)
                            Text("請先確認這張名片至少有姓名、電話或 Email 等基本資料。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    VStack(spacing: 6) {
                        Text(card.displayName)
                            .font(.headline)

                        if !card.company.isEmpty {
                            Text(card.company)
                                .foregroundStyle(.secondary)
                        }

                        if !card.jobTitle.isEmpty {
                            Text(card.jobTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    TextField("名", text: $card.givenName)
                        .editorFieldStyle()
                    TextField("姓", text: $card.familyName)
                        .editorFieldStyle()
                    TextField("公司", text: $card.company)
                        .editorFieldStyle()
                    TextField("職稱", text: $card.jobTitle)
                        .editorFieldStyle()
                    TextField("電話", text: binding(forPhoneAt: 0, defaultKind: .mobile))
                        .keyboardType(.phonePad)
                        .editorFieldStyle()
                    TextField("Email", text: binding(forEmailAt: 0, defaultKind: .work))
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .editorFieldStyle()
                    TextField("地址", text: $card.address, axis: .vertical)
                        .lineLimit(2...4)
                        .editorFieldStyle()
                }

                Text("這個版本不需要 server，電子名片資料會直接寫進 QR Code。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .navigationTitle("電子名片 QR")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            card.normalized()
        }
        .onChange(of: card) { _, newValue in
            MyDigitalCardStore.shared.save(newValue)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("關閉") {
                    dismiss()
                }
            }
        }
    }

    private func binding(forPhoneAt index: Int, defaultKind: LabeledValue.Kind) -> Binding<String> {
        Binding(
            get: {
                guard card.phoneNumbers.indices.contains(index) else { return "" }
                return card.phoneNumbers[index].value
            },
            set: { newValue in
                ensurePhoneSlot(at: index, defaultKind: defaultKind)
                card.phoneNumbers[index].value = newValue
                persistCard()
            }
        )
    }

    private func binding(forEmailAt index: Int, defaultKind: LabeledValue.Kind) -> Binding<String> {
        Binding(
            get: {
                guard card.emails.indices.contains(index) else { return "" }
                return card.emails[index].value
            },
            set: { newValue in
                ensureEmailSlot(at: index, defaultKind: defaultKind)
                card.emails[index].value = newValue
                persistCard()
            }
        )
    }

    private func ensurePhoneSlot(at index: Int, defaultKind: LabeledValue.Kind) {
        while !card.phoneNumbers.indices.contains(index) {
            card.phoneNumbers.append(LabeledValue(kind: defaultKind, value: ""))
        }
    }

    private func ensureEmailSlot(at index: Int, defaultKind: LabeledValue.Kind) {
        while !card.emails.indices.contains(index) {
            card.emails.append(LabeledValue(kind: defaultKind, value: ""))
        }
    }

    private func persistCard() {
        var normalized = card
        normalized.normalized()
        card = normalized
        MyDigitalCardStore.shared.save(normalized)
    }
}

private struct QRImportView: View {
    let onClose: () -> Void
    let onImport: (ScannedCard) -> Void
    let onFailure: (Error) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            QRScannerView { result in
                switch result {
                case .success(let payload):
                    do {
                        let importedCard = try VCardService.parseScannedCard(fromVCard: payload)
                        onImport(importedCard)
                    } catch {
                        onFailure(error)
                    }
                case .failure(let error):
                    onFailure(error)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 10) {
                Text("掃描對方的電子名片 QR")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("請把 QR Code 對準取景框，讀取後會直接帶入可存成聯絡人的資料。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.65))
        }
        .navigationTitle("掃描電子名片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("關閉") {
                    onClose()
                    dismiss()
                }
                .foregroundStyle(.white)
            }
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(configuration.isPressed ? Color.black.opacity(0.8) : Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension View {
    func editorFieldStyle() -> some View {
        self
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ProUpgradeView: View {
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var isAIReady: Bool {
        !AppSecrets.aiProxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AI 功能已內建")
                            .font(.largeTitle.bold())

                        Text("本 App 會先進行本地 OCR；需要時會自動呼叫後台的 Yushan AI 模型，使用者不需要另外輸入 API Key。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        FeatureRow(title: "本地基礎能力", detail: "本地 OCR、基本欄位整理、手動修改、存入聯絡人")
                        FeatureRow(title: "AI 智慧功能", detail: "複雜名片會在需要時自動交由後台的 Yushan AI 模型補強整理，並可生成聯絡訊息")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("目前狀態")
                            .font(.headline)

                        Text(isAIReady ? "目前已可使用 Yushan AI 智慧辨識與聯絡建議功能。" : "目前尚未完成 Yushan AI 服務設定，AI 智慧功能暫時不會啟用。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("原型說明")
                            .font(.headline)

                        Text("目前的 AI 功能由後台的 Yushan AI 服務提供。這樣使用者不需要管理 API Key，也能在需要時自動取得更完整的名片整理結果。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("完成並關閉") {
                        onClose()
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(24)
            }
            .navigationTitle("AI 功能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("關閉") {
                        onClose()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct FeatureRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    ContentView()
}
