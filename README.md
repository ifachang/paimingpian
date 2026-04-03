# Wo名片

`Wo名片` 是一個極簡 iPhone 原型：掃描一張名片或選一張名片照片，做 OCR 後整理成聯絡人資料，確認後存入 `Contacts`。

## 這版包含

- 首頁：`掃描名片`、`選擇照片`
- OCR 掃描流程
- 結果預覽與修改
- 存入 iPhone 聯絡人
- 成功頁

## 專案結構

- `拍名片.xcodeproj`：Xcode 專案
- `拍名片/`：SwiftUI app 原始碼

## 注意

- 目前環境沒有完整 Xcode，所以這裡先建立可交接的專案骨架與程式碼，未在本機完成 iOS 編譯驗證。
- OCR 使用 `Vision`，聯絡人寫入使用 `Contacts`。
