-- Membuat Database "SQL_Analytics"
CREATE DATABASE SQL_Analytics;
-- Menggunakan Database "SQL_Analytics"
USE SQL_Analytics;

/* 1. RFM SEGMENTATION */
-- Konversi tipe data order_date menjadi "date"
ALTER TABLE 
	e_commerce_transactions 
MODIFY 
	order_date 
DATE;

-- Menggunakan CTE untuk melakukan RFM Segmentation
-- Menghitung "last_date" sebagai transaksi terakhir
WITH last_date AS (
  SELECT 
	MAX(order_date) AS max_date 
  FROM 
	e_commerce_transactions
),
-- Menghitung metrik rfm
calculate_rfm AS (
  SELECT
    customer_id,
    DATEDIFF((SELECT max_date FROM last_date), MAX(order_date)) AS recency,
    COUNT(order_id) AS frequency,
    SUM(payment_value) AS monetary
  FROM 
	e_commerce_transactions
  GROUP BY 
	customer_id
),
-- Menghitung persentil
calculate_percentile AS (
  SELECT
    -- Menghitung persentil metrik Recency
    (SELECT recency FROM calculate_rfm ORDER BY recency ASC LIMIT 1 OFFSET 199) AS r1,
    (SELECT recency FROM calculate_rfm ORDER BY recency ASC LIMIT 1 OFFSET 399) AS r2,
    (SELECT recency FROM calculate_rfm ORDER BY recency ASC LIMIT 1 OFFSET 599) AS r3,
    (SELECT recency FROM calculate_rfm ORDER BY recency ASC LIMIT 1 OFFSET 799) AS r4,
	-- Menghitung persentil metrik Frequency
    (SELECT frequency FROM calculate_rfm ORDER BY frequency DESC LIMIT 1 OFFSET 199) AS f5,
    (SELECT frequency FROM calculate_rfm ORDER BY frequency DESC LIMIT 1 OFFSET 399) AS f4,
    (SELECT frequency FROM calculate_rfm ORDER BY frequency DESC LIMIT 1 OFFSET 599) AS f3,
    (SELECT frequency FROM calculate_rfm ORDER BY frequency DESC LIMIT 1 OFFSET 799) AS f2,
	-- Menghitung persentil metrik Monetary
    (SELECT monetary FROM calculate_rfm ORDER BY monetary DESC LIMIT 1 OFFSET 199) AS m5,
    (SELECT monetary FROM calculate_rfm ORDER BY monetary DESC LIMIT 1 OFFSET 399) AS m4,
    (SELECT monetary FROM calculate_rfm ORDER BY monetary DESC LIMIT 1 OFFSET 599) AS m3,
    (SELECT monetary FROM calculate_rfm ORDER BY monetary DESC LIMIT 1 OFFSET 799) AS m2
),
-- Melakukan skoring RFM
scored_rfm AS (
  SELECT
    r.customer_id,
    r.recency,
    r.frequency,
    r.monetary,
	-- Skoring untuk metrik Recency
    CASE
      WHEN r.recency <= p.r1 THEN 5
      WHEN r.recency <= p.r2 THEN 4
      WHEN r.recency <= p.r3 THEN 3
      WHEN r.recency <= p.r4 THEN 2
      ELSE 1
    END AS skor_r,
	-- Skoring untuk metrik Frequency
    CASE
      WHEN r.frequency >= p.f5 THEN 5
      WHEN r.frequency >= p.f4 THEN 4
      WHEN r.frequency >= p.f3 THEN 3
      WHEN r.frequency >= p.f2 THEN 2
      ELSE 1
    END AS skor_f,
	-- Skoring untuk metrik Monetary
    CASE
      WHEN r.monetary >= p.m5 THEN 5
      WHEN r.monetary >= p.m4 THEN 4
      WHEN r.monetary >= p.m3 THEN 3
      WHEN r.monetary >= p.m2 THEN 2
      ELSE 1
    END AS skor_m
  FROM 
	calculate_rfm r
  CROSS JOIN 
	calculate_percentile p
)
-- Melakukan segmentasi pelanggan
SELECT *,
  CASE
    WHEN skor_r >= 4 AND skor_f >= 4 AND skor_m >= 4 THEN 'Champions/Soulmates'
    WHEN skor_f >= 4 THEN 'Loyal Customers'
    WHEN skor_r >= 4 AND skor_f IN (2, 3) THEN 'Potential Loyalist'
    WHEN skor_r = 5 AND skor_f = 1 THEN 'New Customers'
    WHEN skor_r IN (2, 3) AND skor_f <= 2 THEN 'At Risk/Hibernating'
    WHEN skor_r = 3 AND skor_f >= 3 THEN 'Need Attention'
    WHEN skor_r = 2 AND skor_f = 1 THEN 'About to Sleep'
    ELSE 'Others'
  END AS customer_segment
FROM 
	scored_rfm
ORDER BY 
	customer_id;
    
/* 2. DETEKSI ANOMALI */
-- Menggunakan CTE untuk melakukan deteksi anomali
-- Menghitung Q1 dan Q3
WITH calculate_percentile AS (
  SELECT
    -- Kuantil Q1 dan Q3
    (SELECT decoy_noise FROM e_commerce_transactions ORDER BY decoy_noise ASC LIMIT 1 OFFSET 2499) AS Q1,
    (SELECT decoy_noise FROM e_commerce_transactions ORDER BY decoy_noise ASC LIMIT 1 OFFSET 7499) AS Q3
),
-- Menghitung IQR dan menentukan batas atas dan batas bawah
iqr AS (
  SELECT
    Q1,
    Q3,
    (Q3 - Q1) AS IQR,
    Q1 - 1.5 * (Q3 - Q1) AS batas_bawah,
    Q3 + 1.5 * (Q3 - Q1) AS batas_atas
  FROM 
	calculate_percentile
),
-- Menampilkan data yang tergolong anomali
detected_anomalies AS (
  SELECT 
	e.*
  FROM 
	e_commerce_transactions e
  CROSS JOIN 
	iqr i
  WHERE e.decoy_noise < i.batas_bawah
     OR e.decoy_noise > i.batas_atas
),
-- Menghitung banyaknya anomali
anomali_count AS (
  SELECT 
	COUNT(*) AS total_anomali 
  FROM 
	detected_anomalies
)
-- Menampilkan data
SELECT 
  d.customer_id,
  COUNT(*) AS jumlah,
  a.total_anomali
FROM 
  detected_anomalies d
  CROSS JOIN anomali_count a
GROUP BY
  d.customer_id, a.total_anomali
ORDER BY
  jumlah DESC;
  
/* 3. Query repeat-purchase bulanan */
-- Menggunakan CTE untuk melakukan query repeat-purchase bulanan
-- Menghitung transaksi bulanan per customer
WITH monthly_orders AS (
  SELECT
    customer_id,
    DATE_FORMAT(order_date, '%Y-%m') AS year_months,
    COUNT(order_id) AS orders_per_month
  FROM 
	e_commerce_transactions
  GROUP BY 
	customer_id, year_months
),
-- Mengakses pelanggan dengan pembelian >= 2x dalam satu bulan
repeat_customers AS (
  SELECT
    year_months,
    customer_id
  FROM 
	monthly_orders
  WHERE 
	orders_per_month >= 2
)
-- Menghitung jumlah pengulangan pembelian customer per bulan
SELECT 
  customer_id,
  year_months,
  COUNT(DISTINCT customer_id) AS repeat_customer_count
FROM 
	repeat_customers
GROUP BY 
	year_months
ORDER BY 
	year_months;