package com.ifachang.paimingpian

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.graphics.Bitmap
import android.provider.ContactsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Badge
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.PersonAddAlt1
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ifachang.paimingpian.model.LabeledValue
import com.ifachang.paimingpian.model.ScannedCard
import com.ifachang.paimingpian.ai.AiEnhancementService
import com.ifachang.paimingpian.contacts.ContactStoreService
import com.ifachang.paimingpian.ocr.BusinessCardRecognizer
import com.ifachang.paimingpian.ocr.OcrTextLine
import com.ifachang.paimingpian.ocr.ScannedCardRecognitionResult
import com.ifachang.paimingpian.qr.VCardService
import com.ifachang.paimingpian.qr.QrImportService
import com.ifachang.paimingpian.ui.theme.Border
import com.ifachang.paimingpian.ui.theme.AccentSoft
import com.ifachang.paimingpian.ui.theme.AccentWash
import com.ifachang.paimingpian.ui.theme.DangerSoft
import com.ifachang.paimingpian.ui.theme.Gold
import com.ifachang.paimingpian.ui.theme.GoldDeep
import com.ifachang.paimingpian.ui.theme.Ink
import com.ifachang.paimingpian.ui.theme.Muted
import com.ifachang.paimingpian.ui.theme.Paper
import com.ifachang.paimingpian.ui.theme.SkyWash
import com.ifachang.paimingpian.ui.theme.SoftGray
import com.ifachang.paimingpian.ui.theme.Success
import com.ifachang.paimingpian.ui.theme.WarmWhite
import coil.compose.AsyncImage
import kotlinx.coroutines.launch

private enum class Screen {
    HOME,
    LOADING,
    RESULT,
    AI_INFO,
    PRE_CONTACT_SAVE,
    MY_CARD,
    QR_IMPORT,
    SUCCESS
}

@Composable
fun PaiMingPianApp() {
    val context = LocalContext.current
    val recognizer = remember { BusinessCardRecognizer() }
    val aiEnhancementService = remember { AiEnhancementService(InstallationIdStore(context)) }
    val contactStoreService = remember { ContactStoreService(context) }
    val myDigitalCardStore = remember { MyDigitalCardStore(context) }
    val qrImportService = remember { QrImportService() }
    val homeHeroService = remember { HomeHeroService() }
    val coroutineScope = rememberCoroutineScope()

    var screen by remember { mutableStateOf(Screen.HOME) }
    var scannedCard by remember { mutableStateOf(ScannedCard()) }
    var myDigitalCard by remember { mutableStateOf(myDigitalCardStore.load()) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var lastSourceLabel by remember { mutableStateOf("拍一張") }
    var loadingMessage by remember { mutableStateOf("正在辨識名片...") }
    var aiStatusMessage by remember { mutableStateOf<String?>(null) }
    var isEditingResult by remember { mutableStateOf(false) }
    var hasManualResultEdits by remember { mutableStateOf(false) }

    fun handleRecognition(result: ScannedCardRecognitionResult) {
        when (result) {
            is ScannedCardRecognitionResult.Success -> {
                scannedCard = result.card
                errorMessage = null
                isEditingResult = false
                hasManualResultEdits = false
                screen = Screen.RESULT
                val enhanceDecision = shouldAutoEnhanceWithAi(result.lines, result.card)
                if (!enhanceDecision.shouldEnhance) {
                    aiStatusMessage = enhanceDecision.reason
                    return
                }

                aiStatusMessage = "正在用 Yushan AI 補強辨識結果..."

                coroutineScope.launch {
                    val enhanced = aiEnhancementService.parseBusinessCard(result.lines, result.card)
                    enhanced
                        .onSuccess {
                            if (hasManualResultEdits) {
                                aiStatusMessage = "AI 已完成，但目前保留你的手動修改。"
                            } else {
                                scannedCard = it
                                aiStatusMessage = "已完成 AI 智慧優化，結果已更新。"
                            }
                        }
                        .onFailure {
                            val detail = it.message?.takeIf(String::isNotBlank)
                            aiStatusMessage = if (detail != null) {
                                "AI 智慧優化暫時失敗：$detail"
                            } else {
                                "AI 智慧優化暫時失敗，這次先使用基本辨識結果。"
                            }
                        }
                }
            }

            is ScannedCardRecognitionResult.Failure -> {
                errorMessage = result.message
                screen = Screen.HOME
            }
        }
    }

    fun recognizeBitmap(bitmap: Bitmap?) {
        if (bitmap == null) {
            errorMessage = "沒有取得拍照影像，請再試一次。"
            screen = Screen.HOME
            return
        }

        aiStatusMessage = null
        errorMessage = null
        loadingMessage = "正在辨識名片..."
        screen = Screen.LOADING
        coroutineScope.launch {
            handleRecognition(recognizer.recognizeFromBitmap(bitmap))
        }
    }

    val galleryLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri ->
        if (uri == null) {
            errorMessage = "沒有選到照片。"
            return@rememberLauncherForActivityResult
        }

        lastSourceLabel = "選擇照片"
        aiStatusMessage = null
        errorMessage = null
        loadingMessage = "正在辨識名片..."
        screen = Screen.LOADING
        coroutineScope.launch {
            handleRecognition(recognizer.recognizeFromUri(context, uri))
        }
    }

    val cameraPreviewLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.TakePicturePreview()
    ) { bitmap ->
        lastSourceLabel = "拍一張"
        recognizeBitmap(bitmap)
    }

    val cameraPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            cameraPreviewLauncher.launch(null)
        } else {
            errorMessage = "需要相機權限才能直接拍名片，你也可以先從相簿選擇照片。"
        }
    }

    fun handleQrImportResult(result: Result<ScannedCard>) {
        result
            .onSuccess {
                scannedCard = it
                aiStatusMessage = "已讀取對方的電子名片，你可以直接檢查後存入聯絡人。"
                errorMessage = null
                screen = Screen.RESULT
            }
            .onFailure {
                errorMessage = it.message ?: "無法讀取這個電子名片 QR Code。"
                screen = Screen.QR_IMPORT
            }
    }

    val qrGalleryLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri ->
        if (uri == null) {
            errorMessage = "沒有選到 QR 圖片。"
            return@rememberLauncherForActivityResult
        }

        loadingMessage = "正在讀取電子名片 QR..."
        lastSourceLabel = "選擇 QR 圖片"
        errorMessage = null
        screen = Screen.LOADING
        coroutineScope.launch {
            handleQrImportResult(qrImportService.importFromUri(context, uri))
        }
    }

    val qrCameraPreviewLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.TakePicturePreview()
    ) { bitmap ->
        if (bitmap == null) {
            errorMessage = "沒有取得 QR 影像，請再試一次。"
            screen = Screen.QR_IMPORT
            return@rememberLauncherForActivityResult
        }

        loadingMessage = "正在讀取電子名片 QR..."
        lastSourceLabel = "拍 QR"
        errorMessage = null
        screen = Screen.LOADING
        coroutineScope.launch {
            handleQrImportResult(qrImportService.importFromBitmap(bitmap))
        }
    }

    val qrCameraPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            qrCameraPreviewLauncher.launch(null)
        } else {
            errorMessage = "需要相機權限才能直接拍 QR Code，你也可以先從相簿選擇圖片。"
            screen = Screen.QR_IMPORT
        }
    }

    val contactsPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (!granted) {
            errorMessage = "需要聯絡人權限才能把這張名片加入手機通訊錄。"
            screen = Screen.RESULT
            return@rememberLauncherForActivityResult
        }

        coroutineScope.launch {
            contactStoreService.save(scannedCard)
                .onSuccess {
                    errorMessage = null
                    screen = Screen.SUCCESS
                }
                .onFailure {
                    errorMessage = it.message ?: "新增聯絡人失敗，請再試一次。"
                    screen = Screen.RESULT
                }
        }
    }

    Surface(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background)
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 16.dp)
        ) {
            when (screen) {
                Screen.HOME -> HomeScreen(
                    homeHeroService = homeHeroService,
                    myDigitalCard = myDigitalCard,
                    errorMessage = errorMessage,
                    onDismissError = { errorMessage = null },
                    onOpenAiInfo = { screen = Screen.AI_INFO },
                    onStartCamera = {
                        cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
                    },
                    onPickPhoto = {
                        galleryLauncher.launch("image/*")
                    },
                    onOpenMyCard = { screen = Screen.MY_CARD },
                    onOpenQrImport = { screen = Screen.QR_IMPORT }
                )

                Screen.LOADING -> LoadingScreen(
                    sourceLabel = lastSourceLabel,
                    loadingMessage = loadingMessage
                )

                Screen.RESULT -> ResultScreen(
                    card = scannedCard,
                    isEditing = isEditingResult,
                    aiStatusMessage = aiStatusMessage,
                    onCardChange = {
                        hasManualResultEdits = true
                        scannedCard = it
                    },
                    onToggleEditing = {
                        isEditingResult = !isEditingResult
                    },
                    onSave = { screen = Screen.PRE_CONTACT_SAVE },
                    onBackHome = { screen = Screen.HOME },
                    onOpenMyCard = { screen = Screen.MY_CARD }
                )

                Screen.AI_INFO -> AiInfoScreen(
                    onClose = { screen = Screen.HOME }
                )

                Screen.PRE_CONTACT_SAVE -> PreContactSaveScreen(
                    onContinue = {
                        contactsPermissionLauncher.launch(Manifest.permission.WRITE_CONTACTS)
                    },
                    onSkip = { screen = Screen.RESULT }
                )

                Screen.MY_CARD -> MyDigitalCardScreen(
                    card = myDigitalCard,
                    latestScannedCard = scannedCard,
                    onCardChange = {
                        myDigitalCard = it
                        myDigitalCardStore.save(it.normalized())
                    },
                    onClose = { screen = Screen.HOME }
                )

                Screen.QR_IMPORT -> QrImportScreen(
                    errorMessage = errorMessage,
                    onDismissError = { errorMessage = null },
                    onPickQrImage = { qrGalleryLauncher.launch("image/*") },
                    onStartQrCamera = { qrCameraPermissionLauncher.launch(Manifest.permission.CAMERA) },
                    onClose = { screen = Screen.HOME }
                )

                Screen.SUCCESS -> SuccessScreen(
                    context = context,
                    name = scannedCard.displayName,
                    onContinueScan = { screen = Screen.HOME },
                    onBackHome = { screen = Screen.HOME },
                    onOpenMyCard = { screen = Screen.MY_CARD }
                )
            }
        }
    }
}

private data class AutoEnhanceDecision(
    val shouldEnhance: Boolean,
    val reason: String?
)

private fun shouldAutoEnhanceWithAi(
    lines: List<OcrTextLine>,
    card: ScannedCard
): AutoEnhanceDecision {
    val nonEmptyPhoneCount = card.phoneNumbers.count { !it.isEmpty }
    val nonEmptyEmailCount = card.emails.count { !it.isEmpty }
    val compactName = card.fullName.replace(" ", "")
    val lineTexts = lines.map { it.text }
    val lineCount = lineTexts.size

    val missingCoreFields =
        compactName.isBlank() ||
            card.company.isBlank() ||
            (nonEmptyPhoneCount == 0 && nonEmptyEmailCount == 0)

    if (missingCoreFields) return AutoEnhanceDecision(true, null)
    val maxLineLength = lineTexts.maxOfOrNull { it.length } ?: 0

    val containsMixedLanguages = lineTexts.any { text ->
        val hasLatin = text.any { it.code in 65..90 || it.code in 97..122 }
        val hasCjk = text.any { Character.UnicodeScript.of(it.code) == Character.UnicodeScript.HAN }
        hasLatin && hasCjk
    }

    val mostlyUnstructuredResult =
        compactName.length <= 1 ||
            (compactName.length <= 3 && card.company.isBlank()) ||
            (card.jobTitle.isBlank() && card.company.isBlank()) ||
            (card.address.isBlank() && nonEmptyPhoneCount == 0 && nonEmptyEmailCount <= 1)

    if (mostlyUnstructuredResult && lineCount >= 3) {
        return AutoEnhanceDecision(true, null)
    }

    val hasManyContactMethods = nonEmptyPhoneCount + nonEmptyEmailCount >= 4
    val hasDenseLayout = lineCount >= 7
    val hasLongAddress = card.address.length >= 18
    val missingTitle = card.jobTitle.isBlank()
    val hasShortOrSuspiciousName =
        compactName.length in 2..3 ||
            compactName.any(Char::isDigit)
    val hasManyUppercaseLines = lineTexts.count { text ->
        text.length >= 4 &&
            text.any(Char::isLetter) &&
            text.filter(Char::isLetter).all(Char::isUpperCase)
    } >= 2
    val hasManySymbols = lineTexts.any { text ->
        text.count { !it.isLetterOrDigit() && !it.isWhitespace() } >= 4
    }

    val shouldEnhance =
        hasDenseLayout ||
            containsMixedLanguages ||
            hasManyContactMethods ||
            hasLongAddress ||
            (missingTitle && lineCount >= 6) ||
            hasShortOrSuspiciousName ||
            hasManyUppercaseLines ||
            hasManySymbols ||
            maxLineLength >= 24

    return if (shouldEnhance) {
        AutoEnhanceDecision(true, null)
    } else {
        AutoEnhanceDecision(false, "本地辨識結果已足夠完整，這次先不額外使用 AI。")
    }
}

@Composable
private fun HomeScreen(
    homeHeroService: HomeHeroService,
    myDigitalCard: ScannedCard,
    errorMessage: String?,
    onDismissError: () -> Unit,
    onOpenAiInfo: () -> Unit,
    onStartCamera: () -> Unit,
    onPickPhoto: () -> Unit,
    onOpenMyCard: () -> Unit,
    onOpenQrImport: () -> Unit
) {
    val myCardQrBitmap = remember(myDigitalCard) {
        VCardService.makeVCardString(myDigitalCard)?.let { VCardService.makeQrBitmap(it, 520) }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        HeroCard(
            homeHeroService = homeHeroService,
            onOpenAiInfo = onOpenAiInfo
        )

        BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
            val cardWidth = (maxWidth - 14.dp) / 2

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalAlignment = Alignment.Top
            ) {
                Card(
                    modifier = Modifier.width(cardWidth),
                    shape = RoundedCornerShape(28.dp),
                    colors = CardDefaults.cardColors(containerColor = WarmWhite),
                    elevation = CardDefaults.cardElevation(defaultElevation = 8.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(18.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        HomePill(
                            text = "完全免費",
                            containerColor = AccentWash,
                            contentColor = GoldDeep
                        )
                        Text(
                            text = "拍名片",
                            fontSize = 32.sp,
                            fontWeight = FontWeight.ExtraBold,
                            color = Ink
                        )

                        Text(
                            text = "拍照或選圖後，先用本地 OCR 辨識，再由 Yushan AI 在需要時自動補強，快速整理成可儲存的聯絡人資料。",
                            color = Muted,
                            style = MaterialTheme.typography.bodyLarge
                        )

                        Text(
                            text = "打開就能用，不需要註冊。",
                            color = GoldDeep,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }

                Card(
                    modifier = Modifier.width(cardWidth),
                    shape = RoundedCornerShape(28.dp),
                    colors = CardDefaults.cardColors(containerColor = SkyWash),
                    elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        HomePill(
                            text = "我的電子名片",
                            containerColor = Color.White,
                            contentColor = Ink
                        )

                        if (myCardQrBitmap != null) {
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(20.dp))
                                    .background(Color.White)
                                    .border(1.dp, Border, RoundedCornerShape(20.dp))
                                    .padding(12.dp)
                            ) {
                                Image(
                                    bitmap = myCardQrBitmap.asImageBitmap(),
                                    contentDescription = "我的電子名片 QR Code",
                                    modifier = Modifier.size(146.dp)
                                )
                            }
                            Text(
                                text = myDigitalCard.displayName,
                                textAlign = TextAlign.Center,
                                fontWeight = FontWeight.SemiBold,
                                fontSize = 16.sp
                            )
                        } else {
                            Text(
                                text = "建立自己的電子名片後，這裡就會直接顯示 QR Code 給別人掃描。",
                                color = Muted,
                                textAlign = TextAlign.Center
                            )
                        }

                        SecondaryTextButton(text = "編輯我的名片", onClick = onOpenMyCard)
                    }
                }
            }
        }

        if (errorMessage != null) {
            ErrorCard(
                message = errorMessage,
                onDismiss = onDismissError
            )
        }

        SectionTitle(
            title = "開始使用",
            subtitle = "先掃描紙本名片，或直接打開你的電子名片。"
        )

        PrimaryButton(
            text = "拍一張",
            icon = Icons.Outlined.PhotoCamera,
            onClick = onStartCamera
        )

        SecondaryButton(
            text = "選擇照片",
            icon = Icons.Outlined.PhotoLibrary,
            onClick = onPickPhoto
        )

        SecondaryButton(
            text = "我的電子名片",
            onClick = onOpenMyCard
        )

        SecondaryButton(
            text = "掃描電子名片 QR",
            onClick = onOpenQrImport
        )

        FeatureCard(
            title = "你可以直接做的事",
            detail = "拍照、選圖、辨識名片、存入聯絡人、建立我的電子名片，以及掃描對方的電子名片 QR。"
        )

        Spacer(modifier = Modifier.height(12.dp))
    }
}

@Composable
private fun HeroCard(
    homeHeroService: HomeHeroService,
    onOpenAiInfo: () -> Unit
) {
    val context = LocalContext.current
    val heroConfig by produceState<HomeHeroConfig?>(initialValue = null) {
        value = homeHeroService.load()
    }
    val linkUrl = heroConfig?.linkUrl?.takeIf { it.isNotBlank() }
    val imageUrl = heroConfig?.imageUrl?.takeIf { it.isNotBlank() }

    val heroModifier = Modifier
        .fillMaxWidth()
        .then(
            if (linkUrl != null) {
                Modifier.clickable {
                    runCatching {
                        context.startActivity(
                            Intent(Intent.ACTION_VIEW, Uri.parse(linkUrl)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                        )
                    }
                }
            } else {
                Modifier
            }
        )

    Card(
        modifier = heroModifier,
        shape = RoundedCornerShape(32.dp),
        colors = CardDefaults.cardColors(containerColor = Paper),
        elevation = CardDefaults.cardElevation(defaultElevation = 12.dp)
    ) {
        Column(
            modifier = Modifier.padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(248.dp)
                    .clip(RoundedCornerShape(28.dp))
                    .background(
                        brush = Brush.linearGradient(
                            colors = listOf(Color(0xFFFFE4A3), Gold, GoldDeep)
                        )
                    )
            ) {
                if (imageUrl != null) {
                    AsyncImage(
                        model = imageUrl,
                        contentDescription = "首頁主視覺",
                        modifier = Modifier.fillMaxSize()
                    )
                } else {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(20.dp)
                    ) {
                        Text(
                            text = "AI 已內建",
                            modifier = Modifier
                                .align(Alignment.TopEnd)
                                .clip(RoundedCornerShape(999.dp))
                                .background(Color.White.copy(alpha = 0.88f))
                                .padding(horizontal = 12.dp, vertical = 8.dp),
                            color = GoldDeep,
                            fontWeight = FontWeight.Bold
                        )

                        Card(
                            modifier = Modifier
                                .align(Alignment.CenterStart)
                                .size(width = 164.dp, height = 118.dp),
                            shape = RoundedCornerShape(26.dp),
                            colors = CardDefaults.cardColors(containerColor = Color.White)
                        ) {}

                        Card(
                            modifier = Modifier
                                .align(Alignment.CenterEnd)
                                .size(width = 192.dp, height = 126.dp),
                            shape = RoundedCornerShape(28.dp),
                            colors = CardDefaults.cardColors(containerColor = Ink)
                        ) {
                            Column(
                                modifier = Modifier.padding(18.dp),
                                verticalArrangement = Arrangement.spacedBy(12.dp)
                            ) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth(0.68f)
                                        .height(12.dp)
                                        .clip(RoundedCornerShape(999.dp))
                                        .background(Color.White)
                                )
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth(0.44f)
                                        .height(10.dp)
                                        .clip(RoundedCornerShape(999.dp))
                                        .background(Color.White.copy(alpha = 0.76f))
                                )
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth(0.8f)
                                        .height(10.dp)
                                        .clip(RoundedCornerShape(999.dp))
                                        .background(Color.White.copy(alpha = 0.4f))
                                )
                            }
                        }

                        Column(
                            modifier = Modifier
                                .align(Alignment.BottomStart)
                                .padding(4.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            HomePill(
                                text = "拍下紙本名片",
                                containerColor = Color.White.copy(alpha = 0.92f),
                                contentColor = Ink
                            )
                            Text(
                                text = "幾秒內整理成可儲存的聯絡人",
                                color = Color.White,
                                fontWeight = FontWeight.Bold,
                                fontSize = 22.sp,
                                lineHeight = 28.sp
                            )
                        }
                    }
                }

                Text(
                    text = "AI 已內建",
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(14.dp)
                        .clip(RoundedCornerShape(999.dp))
                        .background(Color.White.copy(alpha = 0.92f))
                        .clickable(onClick = onOpenAiInfo)
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    color = GoldDeep,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}

@Composable
private fun LoadingScreen(
    sourceLabel: String,
    loadingMessage: String
) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Card(
            shape = RoundedCornerShape(28.dp),
            colors = CardDefaults.cardColors(containerColor = WarmWhite),
            elevation = CardDefaults.cardElevation(defaultElevation = 10.dp)
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 28.dp, vertical = 30.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                CircularProgressIndicator(color = Ink)
                Spacer(modifier = Modifier.height(18.dp))
                Text(
                    text = loadingMessage,
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "來源：$sourceLabel",
                    color = Muted
                )
            }
        }
    }
}

@Composable
private fun ResultScreen(
    card: ScannedCard,
    isEditing: Boolean,
    aiStatusMessage: String?,
    onCardChange: (ScannedCard) -> Unit,
    onToggleEditing: () -> Unit,
    onSave: () -> Unit,
    onBackHome: () -> Unit,
    onOpenMyCard: () -> Unit = {}
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        SectionTitle(
            title = "已幫你整理好名片",
            subtitle = "確認後即可存入手機通訊錄"
        )

        if (!aiStatusMessage.isNullOrBlank()) {
            AiStatusCard(aiStatusMessage)
        }

        if (isEditing) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(28.dp),
                colors = CardDefaults.cardColors(containerColor = WarmWhite),
                elevation = CardDefaults.cardElevation(defaultElevation = 6.dp)
            ) {
                Column(
                    modifier = Modifier.padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    CardField("名", card.givenName) { onCardChange(card.copy(givenName = it)) }
                    CardField("姓", card.familyName) { onCardChange(card.copy(familyName = it)) }
                    CardField("公司", card.company) { onCardChange(card.copy(company = it)) }
                    CardField("職稱", card.jobTitle) { onCardChange(card.copy(jobTitle = it)) }
                    CardField("電話", card.phoneNumbers.firstOrNull()?.value.orEmpty()) {
                        val values = card.phoneNumbers.toMutableList().apply {
                            if (isEmpty()) add(LabeledValue(LabeledValue.Kind.MOBILE, it)) else this[0] = this[0].copy(value = it)
                        }
                        onCardChange(card.copy(phoneNumbers = values))
                    }
                    CardField("Email", card.emails.firstOrNull()?.value.orEmpty()) {
                        val values = card.emails.toMutableList().apply {
                            if (isEmpty()) add(LabeledValue(LabeledValue.Kind.WORK, it)) else this[0] = this[0].copy(value = it)
                        }
                        onCardChange(card.copy(emails = values))
                    }
                    CardField("地址", card.address) { onCardChange(card.copy(address = it)) }
                }
            }
        } else {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(30.dp),
                colors = CardDefaults.cardColors(containerColor = WarmWhite),
                elevation = CardDefaults.cardElevation(defaultElevation = 8.dp)
            ) {
                Column(
                    modifier = Modifier.padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    HomePill(
                        text = "辨識結果",
                        containerColor = AccentWash,
                        contentColor = GoldDeep
                    )
                    Text(card.displayName, fontSize = 28.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                    if (card.company.isNotBlank()) {
                        Text(card.company, color = Muted, textAlign = TextAlign.Center)
                    }
                    if (card.jobTitle.isNotBlank()) {
                        Text(card.jobTitle, color = Muted, textAlign = TextAlign.Center)
                    }

                    card.phoneNumbers.filterNot(LabeledValue::isEmpty).forEach {
                        ContactLine("${it.kind.displayName}｜${it.value}")
                    }
                    card.emails.filterNot(LabeledValue::isEmpty).forEach {
                        ContactLine("${it.kind.displayName}｜${it.value}")
                    }

                    if (card.address.isNotBlank()) {
                        ContactLine(card.address, color = Muted)
                    }
                }
            }
        }

        PrimaryButton(text = "儲存聯絡人", onClick = onSave)

        Text(
            text = "可隨時編輯",
            modifier = Modifier.fillMaxWidth(),
            textAlign = TextAlign.Center,
            color = Muted,
            style = MaterialTheme.typography.bodySmall
        )

        SecondaryTextButton(text = if (isEditing) "完成修改" else "修改", onClick = onToggleEditing)
        SecondaryTextButton(text = "顯示我的電子名片 QR", onClick = onOpenMyCard)
        SecondaryTextButton(text = "回到首頁", onClick = onBackHome)
    }
}

@Composable
private fun AiStatusCard(message: String) {
    val isProcessing = message.contains("正在用 Yushan AI 補強辨識結果")
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (isProcessing) Color(0xFFFFE8B0) else Color(0xFFFFF6E9)
        )
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.Top
        ) {
            Icon(
                imageVector = Icons.Outlined.AutoAwesome,
                contentDescription = null,
                tint = GoldDeep
            )
            Text(
                text = message,
                color = Ink,
                fontSize = if (isProcessing) 18.sp else 15.sp,
                fontWeight = if (isProcessing) FontWeight.ExtraBold else FontWeight.Medium,
                lineHeight = if (isProcessing) 26.sp else 22.sp
            )
        }
    }
}

@Composable
private fun AiInfoScreen(
    onClose: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Text(
            text = "AI 功能已內建",
            fontSize = 32.sp,
            fontWeight = FontWeight.ExtraBold
        )

        Text(
            text = "本 App 會先進行本地 OCR；需要時會自動呼叫後台的 Yushan AI 模型，使用者不需要另外輸入 API Key。",
            color = Muted,
            style = MaterialTheme.typography.bodyLarge
        )

        FeatureCard(
            title = "AI 智慧功能",
            detail = "複雜名片會在需要時自動交由後台的 Yushan AI 模型補強整理，讓姓名、公司、職稱、電話、Email 與地址更完整。"
        )

        FeatureCard(
            title = "什麼時候會自動啟用",
            detail = "當名片版面較複雜、欄位缺失較多、或中英混排時，系統會自動啟用 Yushan AI 補強。一般簡單名片則直接使用本地辨識結果。"
        )

        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(22.dp),
            colors = CardDefaults.cardColors(containerColor = SoftGray)
        ) {
            Column(
                modifier = Modifier.padding(18.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = "目前狀態",
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "目前的 AI 功能由後台的 Yushan AI 服務提供。這樣使用者不需要管理 API Key，也能在需要時自動取得更完整的名片整理結果。",
                    color = Muted
                )
            }
        }

        SecondaryButton(text = "關閉", onClick = onClose)
    }
}

@Composable
private fun PreContactSaveScreen(
    onContinue: () -> Unit,
    onSkip: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(88.dp)
                    .clip(CircleShape)
                    .background(Gold.copy(alpha = 0.18f)),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Outlined.PersonAddAlt1,
                    contentDescription = null,
                    tint = GoldDeep,
                    modifier = Modifier.size(42.dp)
                )
            }

            Text(
                text = "將名片加入你的手機",
                fontSize = 28.sp,
                fontWeight = FontWeight.ExtraBold,
                textAlign = TextAlign.Center
            )

            Text(
                text = "我們只會新增這一筆聯絡人",
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center
            )

            Text(
                text = "不會讀取或上傳你的其他通訊錄資料",
                color = Color(0xFFC62828),
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .clip(RoundedCornerShape(16.dp))
                    .background(DangerSoft)
                    .padding(horizontal = 16.dp, vertical = 12.dp)
            )

            Text(
                text = "你的資料只存在你的裝置。",
                color = Muted,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(4.dp))

            PrimaryButton(text = "繼續儲存", onClick = onContinue)
            SecondaryTextButton(text = "先不要", onClick = onSkip)
        }
    }
}

@Composable
private fun SuccessScreen(
    context: android.content.Context,
    name: String,
    onContinueScan: () -> Unit,
    onBackHome: () -> Unit,
    onOpenMyCard: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            Icon(
                imageVector = Icons.Outlined.CheckCircle,
                contentDescription = null,
                tint = Success,
                modifier = Modifier.size(72.dp)
            )

            Text(
                text = "已成功加入聯絡人 🎉",
                fontSize = 28.sp,
                fontWeight = FontWeight.ExtraBold,
                textAlign = TextAlign.Center
            )

            Text(
                text = name,
                fontSize = 22.sp,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center
            )

            Text(
                text = "下次掃描會更快",
                color = Muted,
                textAlign = TextAlign.Center
            )

            PrimaryButton(text = "繼續掃描", onClick = onContinueScan)
            SecondaryButton(
                text = "查看聯絡人",
                onClick = {
                    val intent = Intent(Intent.ACTION_VIEW, ContactsContract.Contacts.CONTENT_URI).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    runCatching { context.startActivity(intent) }
                }
            )
            SecondaryTextButton(text = "顯示我的電子名片 QR", onClick = onOpenMyCard)
            SecondaryTextButton(text = "回首頁", onClick = onBackHome)
        }
    }
}

@Composable
private fun MyDigitalCardScreen(
    card: ScannedCard,
    latestScannedCard: ScannedCard,
    onCardChange: (ScannedCard) -> Unit,
    onClose: () -> Unit
) {
    val qrBitmap = remember(card) {
        VCardService.makeVCardString(card)?.let { VCardService.makeQrBitmap(it, 720) }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Text(
            text = "我的電子名片",
            fontSize = 30.sp,
            fontWeight = FontWeight.ExtraBold
        )

        Text(
            text = "你可以先把自己的資料存在這裡，之後直接打開 QR Code 給別人掃描。",
            color = Muted
        )

        if (latestScannedCard.hasContent) {
            SecondaryButton(
                text = "套用目前掃描到的名片資料",
                onClick = { onCardChange(latestScannedCard.normalized()) }
            )
        }

        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(24.dp),
            colors = CardDefaults.cardColors(containerColor = Color.White)
        ) {
            Column(
                modifier = Modifier.padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                if (qrBitmap != null) {
                    Text("給對方掃描的 QR Code", fontWeight = FontWeight.Bold)
                    Image(
                        bitmap = qrBitmap.asImageBitmap(),
                        contentDescription = "電子名片 QR Code",
                        modifier = Modifier
                            .size(260.dp)
                            .clip(RoundedCornerShape(24.dp))
                            .background(Color.White)
                            .padding(16.dp)
                    )
                } else {
                    Text("目前無法生成 QR Code", fontWeight = FontWeight.Bold)
                    Text(
                        "請先確認這張名片至少有姓名、電話或 Email 等基本資料。",
                        color = Muted,
                        textAlign = TextAlign.Center
                    )
                }

                Text(card.displayName, fontWeight = FontWeight.Bold, fontSize = 20.sp)
                if (card.company.isNotBlank()) {
                    Text(card.company, color = Muted)
                }
                if (card.jobTitle.isNotBlank()) {
                    Text(card.jobTitle, color = Muted)
                }
            }
        }

        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(24.dp),
            colors = CardDefaults.cardColors(containerColor = SoftGray)
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                CardField("名", card.givenName) { onCardChange(card.copy(givenName = it)) }
                CardField("姓", card.familyName) { onCardChange(card.copy(familyName = it)) }
                CardField("公司", card.company) { onCardChange(card.copy(company = it)) }
                CardField("職稱", card.jobTitle) { onCardChange(card.copy(jobTitle = it)) }
                CardField("電話", card.phoneNumbers.firstOrNull()?.value.orEmpty()) {
                    val values = card.phoneNumbers.toMutableList().apply {
                        if (isEmpty()) add(LabeledValue(LabeledValue.Kind.MOBILE, it)) else this[0] = this[0].copy(value = it)
                    }
                    onCardChange(card.copy(phoneNumbers = values))
                }
                CardField("Email", card.emails.firstOrNull()?.value.orEmpty()) {
                    val values = card.emails.toMutableList().apply {
                        if (isEmpty()) add(LabeledValue(LabeledValue.Kind.WORK, it)) else this[0] = this[0].copy(value = it)
                    }
                    onCardChange(card.copy(emails = values))
                }
                CardField("地址", card.address) { onCardChange(card.copy(address = it)) }
            }
        }

        Text(
            text = "這個版本不需要 server，電子名片資料會直接寫進 QR Code。",
            color = Muted,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth()
        )

        SecondaryButton(text = "關閉", onClick = onClose)
    }
}

@Composable
private fun QrImportScreen(
    errorMessage: String?,
    onDismissError: () -> Unit,
    onPickQrImage: () -> Unit,
    onStartQrCamera: () -> Unit,
    onClose: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Text(
            text = "掃描對方的電子名片 QR",
            fontSize = 30.sp,
            fontWeight = FontWeight.ExtraBold
        )

        Text(
            text = "先支援用相機拍 QR 或從相簿選 QR 圖片，讀取後會直接帶入可存成聯絡人的資料。",
            color = Muted
        )

        if (errorMessage != null) {
            ErrorCard(
                message = errorMessage,
                onDismiss = onDismissError
            )
        }

        PrimaryButton(text = "拍 QR", onClick = onStartQrCamera)
        SecondaryButton(text = "選擇 QR 圖片", onClick = onPickQrImage)
        SecondaryButton(text = "關閉", onClick = onClose)
    }
}

@Composable
private fun CardField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        singleLine = label != "地址"
    )
}

@Composable
private fun ErrorCard(
    message: String,
    onDismiss: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(containerColor = DangerSoft)
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = "這次沒有順利辨識",
                fontWeight = FontWeight.Bold,
                color = Ink
            )
            Text(
                text = message,
                color = Muted
            )
            SecondaryTextButton(text = "知道了", onClick = onDismiss)
        }
    }
}

@Composable
private fun FeatureCard(
    title: String,
    detail: String
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(containerColor = WarmWhite),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Outlined.Badge,
                    contentDescription = null,
                    tint = GoldDeep
                )
                Text(title, fontWeight = FontWeight.Bold)
            }
            Text(detail, color = Muted)
        }
    }
}

@Composable
private fun PrimaryButton(
    text: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector? = null,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .height(58.dp),
        shape = RoundedCornerShape(20.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Ink, contentColor = Paper)
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.size(8.dp))
        }
        Text(text, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun SecondaryButton(
    text: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector? = null,
    onClick: () -> Unit
) {
    OutlinedButton(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .height(58.dp),
        shape = RoundedCornerShape(20.dp),
        border = androidx.compose.foundation.BorderStroke(1.dp, Border),
        colors = ButtonDefaults.outlinedButtonColors(containerColor = WarmWhite, contentColor = Ink)
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.size(8.dp))
        }
        Text(text, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun SecondaryTextButton(
    text: String,
    onClick: () -> Unit = {}
) {
    Text(
        text = text,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .border(1.dp, Color.Transparent, RoundedCornerShape(16.dp))
            .padding(vertical = 4.dp),
        textAlign = TextAlign.Center,
        color = Muted,
        fontWeight = FontWeight.SemiBold
    )
}

@Composable
private fun HomePill(
    text: String,
    containerColor: Color,
    contentColor: Color
) {
    Text(
        text = text,
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(containerColor)
            .padding(horizontal = 12.dp, vertical = 7.dp),
        color = contentColor,
        fontWeight = FontWeight.Bold,
        fontSize = 13.sp
    )
}

@Composable
private fun SectionTitle(
    title: String,
    subtitle: String
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(
            text = title,
            fontSize = 30.sp,
            fontWeight = FontWeight.ExtraBold,
            color = Ink
        )
        Text(
            text = subtitle,
            color = Muted,
            style = MaterialTheme.typography.bodyLarge
        )
    }
}

@Composable
private fun ContactLine(
    text: String,
    color: Color = Ink
) {
    Text(
        text = text,
        textAlign = TextAlign.Center,
        color = color,
        lineHeight = 22.sp
    )
}
