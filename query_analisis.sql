-- =====================================================================
-- ANALISIS OPERASIONAL KANTOR NOTARIS (data simulasi)
-- Database: notaris_skripsi (MySQL / MariaDB 10.4+)
-- Jalankan 02_data_simulasi.sql dulu. Semua data fiktif.
-- =====================================================================
SET @acuan = '2026-11-05';   -- tanggal acuan analisis (supaya hasil selalu sama)

-- ---------------------------------------------------------------------
-- Q1. Berapa pengajuan per jenis layanan, dan berapa persen yang selesai?
--     Teknik: GROUP BY, agregasi bersyarat
-- ---------------------------------------------------------------------
SELECT jenis_layanan,
       COUNT(*)                                         AS total,
       SUM(status = 'Selesai')                          AS selesai,
       SUM(status = 'Aktif')                            AS aktif,
       ROUND(100 * SUM(status = 'Selesai') / COUNT(*), 1) AS persen_selesai
FROM pengajuans
GROUP BY jenis_layanan
ORDER BY total DESC;

-- ---------------------------------------------------------------------
-- Q2. Tahap mana yang paling lama? (rata-rata hari per tahap)
--     Teknik: CTE, window function LAG, TIMESTAMPDIFF
-- ---------------------------------------------------------------------
WITH tahap AS (
  SELECT k.step, k.nama_tahap, k.updated_at AS selesai_pada,
         COALESCE(LAG(k.updated_at) OVER (PARTITION BY k.id_pengajuan ORDER BY k.step), p.created_at) AS mulai_pada
  FROM pengajuan_trackings k
  JOIN pengajuans p ON p.id_pengajuan = k.id_pengajuan
  WHERE k.is_completed = 1
)
SELECT step, nama_tahap, COUNT(*) AS jumlah,
       ROUND(AVG(TIMESTAMPDIFF(HOUR, mulai_pada, selesai_pada)) / 24, 1) AS rata_rata_hari
FROM tahap
GROUP BY step, nama_tahap
ORDER BY step;

-- ---------------------------------------------------------------------
-- Q3. Berapa lama satu layanan selesai, dari pengajuan sampai dokumen jadi?
--     Teknik: subquery terkorelasi, MIN/MAX/AVG
-- ---------------------------------------------------------------------
SELECT p.jenis_layanan, COUNT(*) AS jumlah_selesai,
       ROUND(AVG(d.hari), 1) AS rata_rata_hari,
       MIN(d.hari) AS tercepat_hari, MAX(d.hari) AS terlama_hari
FROM pengajuans p
JOIN (SELECT id_pengajuan,
             TIMESTAMPDIFF(HOUR, MIN(created_at), MAX(updated_at)) / 24 AS hari
      FROM pengajuan_trackings GROUP BY id_pengajuan) d ON d.id_pengajuan = p.id_pengajuan
WHERE p.status = 'Selesai'
GROUP BY p.jenis_layanan
ORDER BY rata_rata_hari DESC;

-- ---------------------------------------------------------------------
-- Q4. Pengajuan aktif yang tidak bergerak lebih dari 7 hari (perlu ditindaklanjuti)
--     Teknik: CTE, JOIN, subquery skalar
-- ---------------------------------------------------------------------
WITH terakhir AS (
  SELECT id_pengajuan, MAX(updated_at) AS update_terakhir, SUM(is_completed) AS tahap_selesai
  FROM pengajuan_trackings GROUP BY id_pengajuan
)
SELECT p.nomor_tiket, p.jenis_layanan, t.tahap_selesai,
       (SELECT x.nama_tahap FROM pengajuan_trackings x
         WHERE x.id_pengajuan = p.id_pengajuan AND x.is_completed = 0
         ORDER BY x.step LIMIT 1)                       AS menunggu_tahap,
       DATEDIFF(@acuan, t.update_terakhir)             AS hari_tanpa_pembaruan
FROM pengajuans p
JOIN terakhir t ON t.id_pengajuan = p.id_pengajuan
WHERE p.status = 'Aktif' AND DATEDIFF(@acuan, t.update_terakhir) > 7
ORDER BY hari_tanpa_pembaruan DESC;

-- ---------------------------------------------------------------------
-- Q5. Beban kerja dan kecepatan verifikasi berkas tiap staf
--     Teknik: JOIN, agregasi
-- ---------------------------------------------------------------------
SELECT u.name AS staf, COUNT(*) AS berkas_diverifikasi,
       ROUND(AVG(TIMESTAMPDIFF(HOUR, b.created_at, b.diverifikasi_pada)), 1) AS rata_rata_jam_verifikasi
FROM berkas_kliens b
JOIN users u ON u.id_user = b.id_user_verifikator
WHERE b.diverifikasi_pada IS NOT NULL
GROUP BY u.id_user, u.name
ORDER BY berkas_diverifikasi DESC;

-- ---------------------------------------------------------------------
-- Q6. Jam berapa konsultasi paling padat?
--     Teknik: fungsi tanggal dan waktu, filter status
-- ---------------------------------------------------------------------
SELECT HOUR(jam_mulai) AS jam, COUNT(*) AS jumlah_konsultasi
FROM jadwal_konsultasis
WHERE status <> 'ditolak'
GROUP BY HOUR(jam_mulai)
ORDER BY jam;

-- ---------------------------------------------------------------------
-- Q7. Jenis dokumen mana yang paling sering harus direvisi?
--     Teknik: agregasi bersyarat, IS NOT NULL
-- ---------------------------------------------------------------------
SELECT jenis_dokumen, COUNT(*) AS total,
       SUM(catatan_revisi IS NOT NULL) AS pernah_direvisi,
       ROUND(100 * SUM(catatan_revisi IS NOT NULL) / COUNT(*), 1) AS persen_revisi
FROM berkas_kliens
GROUP BY jenis_dokumen
ORDER BY persen_revisi DESC;

-- ---------------------------------------------------------------------
-- Q8. Tren pengajuan per bulan dan perubahannya dari bulan lalu
--     Teknik: CTE, window function LAG (bulan berjalan tidak dihitung)
-- ---------------------------------------------------------------------
WITH bulanan AS (
  SELECT DATE_FORMAT(created_at, '%Y-%m') AS bulan, COUNT(*) AS jumlah
  FROM pengajuans WHERE created_at < '2026-11-01'
  GROUP BY DATE_FORMAT(created_at, '%Y-%m')
)
SELECT bulan, jumlah,
       LAG(jumlah) OVER (ORDER BY bulan) AS bulan_lalu,
       ROUND(100 * (jumlah - LAG(jumlah) OVER (ORDER BY bulan)) / LAG(jumlah) OVER (ORDER BY bulan), 1) AS persen_perubahan
FROM bulanan
ORDER BY bulan;

-- ---------------------------------------------------------------------
-- Q9. Tiga layanan terbanyak di tiap bulan
--     Teknik: CTE berantai, ROW_NUMBER() OVER (PARTITION BY ...)
-- ---------------------------------------------------------------------
WITH per_bulan AS (
  SELECT DATE_FORMAT(created_at, '%Y-%m') AS bulan, jenis_layanan, COUNT(*) AS jumlah
  FROM pengajuans WHERE created_at < '2026-11-01'
  GROUP BY DATE_FORMAT(created_at, '%Y-%m'), jenis_layanan
), urut AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY bulan ORDER BY jumlah DESC, jenis_layanan) AS peringkat
  FROM per_bulan
)
SELECT bulan, peringkat, jenis_layanan, jumlah
FROM urut WHERE peringkat <= 3
ORDER BY bulan, peringkat;

-- ---------------------------------------------------------------------
-- Q10. Jadwal konsultasi yang waktunya bertabrakan
--      Teknik: self join dengan kondisi tumpang tindih waktu
-- ---------------------------------------------------------------------
SELECT a.tanggal, a.jam_mulai,
       a.id_jadwal_konsultasi AS jadwal_a, b.id_jadwal_konsultasi AS jadwal_b,
       a.status AS status_a, b.status AS status_b
FROM jadwal_konsultasis a
JOIN jadwal_konsultasis b
  ON a.tanggal = b.tanggal
 AND a.id_jadwal_konsultasi < b.id_jadwal_konsultasi
 AND a.jam_mulai < b.jam_selesai
 AND b.jam_mulai < a.jam_selesai
WHERE a.status <> 'ditolak' AND b.status <> 'ditolak'
ORDER BY a.tanggal, a.jam_mulai
LIMIT 15;

-- ---------------------------------------------------------------------
-- Q11. Aktivitas staf di luar jam kerja (pengawasan lewat audit trail)
--      Teknik: JOIN, fungsi waktu, filter peran
-- ---------------------------------------------------------------------
SELECT u.name AS pengguna, u.role AS peran, COUNT(*) AS aksi_luar_jam_kerja
FROM audit_logs a
JOIN users u ON u.id_user = a.id_user
WHERE u.role IN ('staff', 'notaris')
  AND (HOUR(a.created_at) < 8 OR HOUR(a.created_at) >= 18 OR DAYOFWEEK(a.created_at) IN (1, 7))
GROUP BY u.id_user, u.name, u.role
ORDER BY aksi_luar_jam_kerja DESC;
