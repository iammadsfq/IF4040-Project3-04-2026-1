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
