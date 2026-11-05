# 🏛️ Analisis Operasional & Efisiensi Layanan Notaris Berbasis SQL

## 📌 Ringkasan Proyek
Proyek ini merupakan analisis data operasional berbasis studi kasus dari **Sistem Informasi Manajemen Layanan Notaris** (Skripsi Sarjana Sistem Informasi - Universitas Komputer Indonesia). 

Tujuan utama analisis ini adalah untuk mengidentifikasi hambatan proses (*bottleneck*), mengukur durasi penyelesaian layanan, serta memberikan rekomendasi berbasis data (*data-driven recommendations*) untuk meningkatkan efisiensi alur kerja operasional kantor notaris.

---

## 🛠️ Teknologi yang Digunakan
* **Database Management System:** MySQL / MariaDB
* **Bahasa Pemrograman Query:** SQL (Data Query Language, Aggregations, Subqueries, Date Functions)
* **Visualisasi/Reporting Concept:** Looker Studio / Power BI Dashboard Mockup

---

## ❓ Pertanyaan Bisnis (Business Questions)
1. **Durasi Penyelesaian:** Berapa rata-rata waktu (dalam hari) yang dibutuhkan untuk menyelesaikan setiap jenis layanan akta/perjanjian?
2. **Hambatan Proses (*Bottleneck*):** Tahapan tracking mana yang paling sering mengalami penundaan (*delay*)?
3. **Pola Konsultasi:** Pada jam berapa slot konsultasi paling banyak dipesan oleh klien?
4. **Tingkat Efektivitas Layanan:** Berapa persentase pengajuan yang berhasil diselesaikan tepat waktu versus yang tertunda lebih dari 7 hari?

---

## 🔍 Highlight Query SQL & Hasil Analisis

### 1. Rata-rata Durasi Penyelesaian Layanan per Kategori
Mengukur durasi pengerjaan dari status diajukan hingga selesai:
```sql
SELECT 
    p.jenis_layanan,
    COUNT(p.id_pengajuan) AS total_pengajuan,
    ROUND(AVG(DATEDIFF(p.updated_at, p.created_at)), 1) AS rata_rata_hari_penyelesaian
FROM pengajuans p
WHERE p.status = 'Selesai'
GROUP BY p.jenis_layanan
ORDER BY rata_rata_hari_penyelesaian DESC;