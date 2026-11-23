# IF4040 Transportasi Indonesia (PostGIS)

## 1. Jalankan Database PostGIS
Pastikan Docker dan Docker Compose sudah terpasang, lalu jalankan:
```bash
docker compose up -d
```
Database akan berjalan di `localhost:5433` (`dbname=if4040_transport`, `user=postgres`, `password=postgres`).

---

## 2. Preprocessing & Load Data (via Container ETL)
Semua tools (`curl`, `osmium-tool`, `gdal-bin`/`ogr2ogr`, `psql`) sudah disiapkan di service `etl`, jadi tidak perlu install manual di host.

### a. Download data OSM Indonesia (skip jika `data/raw/indonesia-latest.osm.pbf` sudah ada)
```bash
docker compose run --rm etl bash /scripts/01_download.sh
```

### b. Filter & load ke tabel staging (`stg_*`)
```bash
docker compose run --rm etl bash /scripts/02_filter_load.sh
```

### c. Bersihkan & bentuk tabel final (`provinsi`, `area_transportasi`, `jalur_transportasi`, `titik_transportasi`)
```bash
docker compose exec -T postgis psql -U postgres -d if4040_transport -f /scripts/03_ddl_clean.sql
```

---

## 3. Akses Database
- **Host**: `localhost`
- **Port**: `5433`
- **Database**: `if4040_transport`
- **User / Password**: `postgres` / `postgres`

Atau masuk lewat terminal:
```bash
docker compose exec postgis psql -U postgres -d if4040_transport
```

---

## 4. Viewer QGIS
Data PostGIS bisa dilihat di [QGIS Desktop](https://qgis.org/download/) (versi 3.x LTR atau lebih baru). Di Windows bisa install lewat:
```bash
winget install OSGeo.QGIS_LTR
```

Folder `qgis/` berisi:

| File | Isi |
|---|---|
| `qgis/koneksi_postgis.xml` | Koneksi PostgreSQL `localhost:5433`, database `if4040_transport`, user/password `postgres`/`postgres` |
| `qgis/if4040_transport.qgs` | Project QGIS siap pakai dengan 4 layer: `titik_transportasi`, `jalur_transportasi`, `area_transportasi`, `provinsi` (EPSG:4326, zoom ke Indonesia) |

Pastikan database sudah jalan (`docker compose up -d`) dan tabel final sudah dibuat (langkah 2c).

### a. Buka project langsung
Buka `qgis/if4040_transport.qgs` lewat **Project → Open**. Keempat layer langsung tampil.

### b. Tambah koneksi ke Browser QGIS (opsional)
Supaya tabel lain bisa dibuka dari panel Browser:
1. Di panel **Browser**, klik kanan **PostgreSQL → Load Connections...** dan pilih `qgis/koneksi_postgis.xml`.
2. Atau buat manual lewat **PostgreSQL → New Connection...** dengan isian:
   - **Name**: `IF4040 Transport (localhost:5433)`
   - **Host**: `localhost`
   - **Port**: `5433`
   - **Database**: `if4040_transport`
   - **Authentication → Basic**: `postgres` / `postgres`
3. Expand koneksi → schema `public` → drag tabel ke peta.
