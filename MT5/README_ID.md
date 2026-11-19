# Gold Session Liquidity Free MT5 v1.10

**FXLINER / ForexReview.top — Free educational market analysis, 19 November 2026**

## Tujuan

Indikator GRATIS khusus analisis XAUUSD di MetaTrader 5. Membaca rentang sesi Asia, konteks sesi London/New York, sweep level harga historis, swing structure break, EMA H1, dan membantu merencanakan risiko. **Bukan Expert Advisor dan tidak membuka order.**

## Fitur default

- Sesi Asia (00:00–06:00 UTC sebagai pengaturan awal), London, New York dan overlap; aturan DST Eropa dan Amerika Serikat.
- Garis **completed Asian High/Low** hanya setelah sesi Asia berakhir dan harga sebelumnya tersedia.
- Penanda hijau untuk liquidity sweep di bawah swing low yang direklamasi; merah untuk sweep di atas swing high yang ditolak.
- Penanda structure break naik/turun memakai pivot yang sudah terkonfirmasi, candle tertutup dan level historis.
- Panel 520px: sesi terkini, jam UTC, arah EMA H1, spread dalam point dan rasio spread/ATR, Asian range, sweep terbaru dan swing break terbaru.
- Planner lot manual berdasarkan **ekuitas akun MT5, spesifikasi lot broker, OrderCalcProfit, estimasi komisi dan risk budget**.
- **Panah BUY/SELL eksperimen OFF**, alert eksperimen juga tidak aktif secara default.
- Risiko stop loss hanya estimasi awal; kerugian dapat lebih besar akibat gap, spread dan slippage.

## Install

1. Ekstrak file `Gold_Session_Liquidity_Free_MT5.ex5` ke `MQL5/Indicators/GoldSessionLiquidityFree/` di folder data MetaTrader 5.
2. Di MT5, Navigator → Indicators → Refresh.
3. Tambahkan ke grafik **XAUUSD M5 atau M15** untuk mulai.
4. Periksa `BrokerWinterUTCOffsetHours` dan `BrokerClock`. Default UTC+2 winter / UTC+3 summer (EU DST) adalah **asumsi**, dan tidak benar bagi semua broker.
5. Jangan menjalankan versi gratis dan Pro dalam satu chart dengan `InstanceID` yang sama. Versi gratis memakai prefix objek yang berbeda, sehingga tidak menghapus panel Pro.

## Memakai manual risk planner

Di Inputs:
- `RiskBudgetPercent`: contoh 0.50 = 0,5% ekuitas akun.
- `ManualEntryPrice`: perkiraan harga entry yang ingin dianalisis.
- `ManualStopPrice`: stop hipotetis (di bawah entry untuk BUY, di atas untuk SELL).
- `ManualTargetPrice` opsional: menampilkan rasio jarak reward terhadap risk, **belum termasuk biaya eksekusi**.
- `CommissionPerLotRoundTrip`: taksiran biaya per satu lot (dalam **mata uang akun**) untuk pembukaan + penutupan, default 7.00 hanya ilustrasi.

Kalkulator menggunakan `OrderCalcProfit` untuk memproyeksikan kerugian stop pada volume minimum broker, kemudian menormalisasi volume ke `SYMBOL_VOLUME_STEP` dan membulatkannya **ke bawah**. Jika lot minimum melebihi budget, hasilnya “min broker lot exceeds budget” dan **tidak** menyarankan lot di atas budget.

Ini bukan fitur penempatan order atau instruksi trading. Dengan akun yang belum terhubung, planner menampilkan bahwa ekuitas tidak tersedia.

## Buffer indikator

| Buffer | Kegunaan |
|---|---|
| 0, 1 | BUY/SELL **eksperimental**, kosong secara default |
| 2, 3 | Completed Asian High / Low |
| 4–11 | SL dan tiga TP eksperimen, kosong secara default |
| 12 | Skor heuristik eksperimen 0–100; **bukan probabilitas win rate** |
| 13 | Liquidity sweep rendah |
| 14 | Liquidity sweep tinggi |
| 15 | Break swing structure ke atas |
| 16 | Break swing structure ke bawah |

Penanda historical dihitung pada candle yang sudah tertutup, dan hanya mempertahankan tampilan dalam jendela `MaxBarsToScan` (default 900). Tidak ada klaim tidak repaint selamanya/di semua broker.

Jika pengguna secara sengaja menghidupkan `ShowExperimentalSignals`, panah dan skor riset bisa muncul kembali. **Backtest strategi sinyal lama/baru belum menunjukkan keunggulan keuntungan konsisten**; opsi ini disediakan hanya untuk kajian, tidak disarankan sebagai dasar keputusan finansial.

## QA yang telah dijalankan

MetaEditor MT5: 0 error / 0 warning.

Strategy Tester MT5 MetaQuotes-Demo, model 1-minute OHLC:
- **M15, 1 Agustus–30 Oktober 2026:** 5.734 candle, 390.157 pemeriksaan historis, 0 pelanggaran, 0 error CopyBuffer.
- **M5, 1 September–30 Oktober 2026:** 11.658 candle, 755.498 pemeriksaan historis, 0 pelanggaran, 0 error CopyBuffer.

Pengujian mengonfirmasi buffer eksperimen kosong secara default pada candle tertutup dan berlangsung, serta penanda sweep/structure stabil selama berada dalam jendela uji. Ini **bukan** backtest hasil perdagangan atau verifikasi pasar real-tick.

## Distribusi dan lisensi

Gratis untuk penggunaan edukasi. Source ini mengandung bagian yang diturunkan dari Smart Liquidity Hunter v1.11 di bawah **Lisensi MIT**. Wajib mempertahankan pemberitahuan atribusi dan lisensi pada `THIRD_PARTY_NOTICES.txt` apabila mendistribusikan source atau salinan signifikan.

Rencana publikasi: paket gratis `.ex5` dan paket source `.mq5` disiapkan terpisah. Tidak diunggah ke repositori publik/MQL5 Market/Code Base tanpa pemeriksaan akhir.

© 2026 FXLINER. Tidak ada janji profit, win rate, atau batas maksimum kerugian.
