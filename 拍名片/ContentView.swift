import PhotosUI
import SwiftUI
import UIKit

struct ContentView: View {
    private enum PlanTier {
        case free
        case pro
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
    @State private var myDigitalCard = MyDigitalCardStore.shared.load()
    @State private var noticeMessage = ""
    @State private var isShowingNotice = false
    @State private var outreachContext = ""
    @State private var outreachSuggestions: [OutreachSuggestion] = []
    @State private var isGeneratingOutreach = false
    @State private var copiedSuggestionID: String?
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
                    Text("拍名片")
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
                Button("我的電子名片") {
                    isShowingMyCardSheet = true
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button("拍一張") {
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
            Text("正在辨識名片...")
                .font(.headline)
            Spacer()
        }
    }

    private var reviewView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("已幫你整理好名片")
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
    }

    private var preContactSaveView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(.orange)

            VStack(spacing: 10) {
                Text("將名片加入你的手機")
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
            return "拍一張或選一張名片照片，快速存進聯絡人。"
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

    @ViewBuilder
    private func editorSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content()
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
