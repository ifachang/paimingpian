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
        case success
    }

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
    @State private var noticeMessage = ""
    @State private var isShowingNotice = false
    @State private var outreachContext = ""
    @State private var outreachSuggestions: [OutreachSuggestion] = []
    @State private var isGeneratingOutreach = false
    @State private var copiedSuggestionID: String?
    @State private var isEnhancingCard = false
    @State private var enhancementMessage = ""
    @State private var currentScanID = UUID()
    @AppStorage("isProUnlocked") private var isProUnlocked = false
    @AppStorage("openAIAPIKey") private var openAIAPIKey = ""

    private let contactStoreService = ContactStoreService()
    private let openAIService = OpenAIService()

    private var planTier: PlanTier {
        isProUnlocked ? .pro : .free
    }

    private var isProLLMReady: Bool {
        isProUnlocked && !openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                        Text(isProUnlocked ? "PRO" : "升級 Pro")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isProUnlocked ? .orange : .primary)
                    }
                }
            }
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
                isProUnlocked: isProUnlocked,
                apiKey: $openAIAPIKey,
                onUpgrade: {
                    isProUnlocked = true
                    isShowingProSheet = false
                }
            )
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
        .alert("已改用基本辨識", isPresented: $isShowingNotice) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(noticeMessage)
        }
    }

    private var homeView: some View {
        VStack(spacing: 24) {
            homeIllustration

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text("拍名片")
                        .font(.largeTitle.bold())

                    Text(isProUnlocked ? "PRO" : "FREE")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isProUnlocked ? Color.orange.opacity(0.15) : Color(.secondarySystemBackground))
                        .foregroundStyle(isProUnlocked ? .orange : .secondary)
                        .clipShape(Capsule())
                }

                Text(homeSubtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
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
            }

            planCard

            Spacer()

            Link("Developed by WoWo AI Commerce", destination: URL(string: "https://wowo.one")!)
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
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
            Text("幫你整理好了")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .center)

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

                Button("存入聯絡人") {
                    saveContact()
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("修改") {
                    isShowingEditor = true
                }
                .foregroundStyle(.secondary)
            }

            if planTier == .free {
                upgradeBanner
            }

            if isEnhancingCard {
                enhancementBanner
            }

            outreachSection

            Button("重新開始") {
                resetFlow()
            }
            .foregroundStyle(.secondary)
        }
    }

    private var successView: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("已存入聯絡人")
                .font(.title2.bold())

            Text(savedName)
                .font(.title3)

            Text("已加入你的聯絡人")
                .foregroundStyle(.secondary)

            Button("再拍一張") {
                resetFlow()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 12)

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

                isEnhancingCard = true
                enhancementMessage = "正在用 Pro 智慧辨識優化姓名、公司與聯絡方式..."

                Task {
                    do {
                        let enhancedCard = try await openAIService.parseBusinessCard(
                            lines: lines,
                            fallback: localCard,
                            apiKey: openAIAPIKey
                        )

                        guard currentScanID == scanID else {
                            return
                        }

                        scannedCard = enhancedCard
                        isEnhancingCard = false
                        enhancementMessage = ""
                        noticeMessage = "已完成智慧優化，結果已更新。"
                        isShowingNotice = true
                    } catch {
                        guard currentScanID == scanID else {
                            return
                        }

                        isEnhancingCard = false
                        enhancementMessage = ""
                        noticeMessage = "智慧辨識暫時失敗，這次先使用基本辨識結果。"
                        isShowingNotice = true
                    }
                }
            } catch {
                screen = .home
                showError(error)
            }
        }
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
                ? "使用 Pro 智慧辨識，更穩定整理複雜版面、雙語名片與多張名片照片。"
                : "Pro 已啟用。再填入 OpenAI API Key，就能開始使用智慧辨識。"
        }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(planTier == .pro ? "你目前使用 Pro 版" : "免費版可先完成基本掃描")
                .font(.headline)

            Text(
                planTier == .pro
                ? (isProLLMReady
                    ? "目前已接上智慧辨識流程，會先做本地 OCR，再用模型整理姓名、公司、地址與職稱。"
                    : "再填入 OpenAI API Key，就能開始使用 Pro 智慧辨識。")
                : "升級 Pro 後，可解鎖更準確的智慧辨識，減少手動修改時間。"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if planTier == .free {
                Button("查看 Pro 方案") {
                    isShowingProSheet = true
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var homeIllustration: some View {
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
        }
        .frame(height: 220)
    }

    private var upgradeBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("升級 Pro，辨識更準")
                .font(.headline)

            Text("複雜版面、雙語名片與多張名片照片，都能更穩定整理。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("升級 Pro") {
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
                Button("升級 Pro 以生成聯絡訊息") {
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
                    context: outreachContext,
                    apiKey: openAIAPIKey
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
    let isProUnlocked: Bool
    @Binding var apiKey: String
    let onUpgrade: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("升級 Pro，辨識更準")
                            .font(.largeTitle.bold())

                        Text("少改幾次，快很多。Pro 會更準確辨識姓名、公司、地址與職稱，幫你省下手動修改時間。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        FeatureRow(title: "免費版", detail: "本地 OCR、基本欄位整理、手動修改、存入聯絡人")
                        FeatureRow(title: "Pro", detail: "智慧辨識、職稱抽取、複雜版面更穩、雙語名片更好、多張名片照片處理更穩")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("目前狀態")
                            .font(.headline)

                        Text(
                            isProUnlocked
                            ? "你已經是 Pro。填入 OpenAI API Key 後，App 會在 Pro 模式下呼叫模型做名片欄位整理。"
                            : "先啟用 Pro 原型，再填入 OpenAI API Key 測試智慧辨識。"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("OpenAI API Key（原型測試）")
                            .font(.headline)

                        SecureField("sk-...", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Text("這個欄位只適合原型測試。正式版不應把 API key 直接放在手機 App 裡。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button(isProUnlocked ? "已啟用 Pro" : "啟用 Pro 原型") {
                        if !isProUnlocked {
                            onUpgrade()
                        } else {
                            dismiss()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isProUnlocked)
                }
                .padding(24)
            }
            .navigationTitle("Pro 方案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("關閉") {
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
