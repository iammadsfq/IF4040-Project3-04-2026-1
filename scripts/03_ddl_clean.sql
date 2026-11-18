CREATE EXTENSION IF NOT EXISTS postgis;

DROP TABLE IF EXISTS titik_transportasi CASCADE;
DROP TABLE IF EXISTS area_transportasi CASCADE;
DROP TABLE IF EXISTS jalur_transportasi CASCADE;
DROP TABLE IF EXISTS provinsi CASCADE;

-- ==========================================
-- 1. TABEL PROVINSI (POLYGON)
-- ==========================================
CREATE TABLE provinsi (
    id_provinsi SERIAL PRIMARY KEY,
    osm_id VARCHAR(50) UNIQUE NOT NULL,
    nama_provinsi VARCHAR(100) NOT NULL,
    geom GEOMETRY(MultiPolygon, 4326) NOT NULL
);

INSERT INTO provinsi (osm_id, nama_provinsi, geom)
SELECT DISTINCT ON (clean_osm_id)
    clean_osm_id,
    TRIM(name) AS nama_provinsi,
    ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Transform(geom, 4326)), 3))::GEOMETRY(MultiPolygon, 4326)
FROM (
    SELECT
        COALESCE(NULLIF(osm_id, ''), NULLIF(osm_way_id, ''), 'FID-' || ogc_fid::text) AS clean_osm_id,
        name,
        admin_level,
        geom
    FROM stg_provinsi
    WHERE name IS NOT NULL 
      AND TRIM(name) <> ''
      AND geom IS NOT NULL
      AND admin_level = '4'
      AND other_tags LIKE '%"ISO3166-2"=>"ID-%'
) sub;

CREATE INDEX idx_provinsi_geom ON provinsi USING GIST (geom);

-- ==========================================
-- 2. TABEL AREA TRANSPORTASI (POLYGON BANDARA & PELABUHAN)
-- ==========================================
CREATE TABLE area_transportasi (
    id_area SERIAL PRIMARY KEY,
    osm_id VARCHAR(50) UNIQUE NOT NULL,
    nama_area VARCHAR(150) NOT NULL,
    jenis_area VARCHAR(30) NOT NULL, -- aerodrome, port, harbour, station, bus_station
    id_provinsi INT REFERENCES provinsi(id_provinsi) ON DELETE SET NULL,
    geom GEOMETRY(MultiPolygon, 4326) NOT NULL
);

INSERT INTO area_transportasi (osm_id, nama_area, jenis_area, geom)
SELECT DISTINCT ON (clean_osm_id)
    clean_osm_id,
    TRIM(name) AS nama_area,
    COALESCE(
        NULLIF(aeroway, ''),
        NULLIF(landuse, ''),
        CASE WHEN substring(other_tags FROM '"harbour"=>"([^"]+)"') = 'yes' THEN 'harbour' ELSE NULL END,
        NULLIF(substring(other_tags FROM '"railway"=>"([^"]+)"'), ''),
        NULLIF(amenity, ''),
        'lainnya'
    ) AS jenis_area,
    ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Transform(geom, 4326)), 3))::GEOMETRY(MultiPolygon, 4326)
FROM (
    SELECT
        COALESCE(NULLIF(osm_id, ''), NULLIF(osm_way_id, ''), 'FID-' || ogc_fid::text) AS clean_osm_id,
        name,
        aeroway,
        landuse,
        amenity,
        other_tags,
        geom
    FROM stg_fasilitas_poly
    WHERE name IS NOT NULL 
      AND TRIM(name) <> ''
      AND geom IS NOT NULL
) sub;

CREATE INDEX idx_area_transportasi_geom ON area_transportasi USING GIST (geom);

-- ==========================================
-- 3. TABEL JALUR TRANSPORTASI (POLYLINE JALAN & REL)
-- ==========================================
CREATE TABLE jalur_transportasi (
    id_jalur SERIAL PRIMARY KEY,
    osm_id VARCHAR(50) UNIQUE NOT NULL,
    nama_jalur VARCHAR(150) NOT NULL,
    jenis_jalur VARCHAR(30) NOT NULL, -- motorway, trunk, primary, rail
    geom GEOMETRY(MultiLineString, 4326) NOT NULL
);

INSERT INTO jalur_transportasi (osm_id, nama_jalur, jenis_jalur, geom)
SELECT DISTINCT ON (osm_id)
    osm_id,
    TRIM(name) AS nama_jalur,
    COALESCE(NULLIF(highway, ''), NULLIF(railway, ''), 'lainnya') AS jenis_jalur,
    ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Transform(geom, 4326)), 2))::GEOMETRY(MultiLineString, 4326)
FROM stg_jalur
WHERE name IS NOT NULL 
  AND TRIM(name) <> ''
  AND geom IS NOT NULL;

CREATE INDEX idx_jalur_transportasi_geom ON jalur_transportasi USING GIST (geom);

-- ==========================================
-- 4. TABEL TITIK TRANSPORTASI (POINT STASIUN, BANDARA, PELABUHAN, TERMINAL)
-- ==========================================
CREATE TABLE titik_transportasi (
    id_titik SERIAL PRIMARY KEY,
    osm_id VARCHAR(50) UNIQUE NOT NULL,
    nama_titik VARCHAR(150) NOT NULL,
    jenis_titik VARCHAR(30) NOT NULL, -- station, aerodrome, ferry_terminal, bus_station, port, harbour
    id_provinsi INT REFERENCES provinsi(id_provinsi) ON DELETE SET NULL,
    geom GEOMETRY(Point, 4326) NOT NULL
);

-- Gabungkan titik murni + titik tengah permukaan (ST_PointOnSurface) dari area fasilitas
INSERT INTO titik_transportasi (osm_id, nama_titik, jenis_titik, geom)
SELECT DISTINCT ON (osm_id)
    osm_id,
    nama_titik,
    jenis_titik,
    geom
FROM (
    SELECT
        'N-' || COALESCE(NULLIF(osm_id, ''), 'FID-' || ogc_fid::text) AS osm_id,
        TRIM(name) AS nama_titik,
        COALESCE(
            NULLIF(substring(other_tags FROM '"railway"=>"([^"]+)"'), ''),
            NULLIF(substring(other_tags FROM '"aeroway"=>"([^"]+)"'), ''),
            NULLIF(substring(other_tags FROM '"amenity"=>"([^"]+)"'), ''),
            CASE WHEN substring(other_tags FROM '"harbour"=>"([^"]+)"') = 'yes' THEN 'harbour' ELSE NULL END,
            'lainnya'
        ) AS jenis_titik,
        ST_Transform(geom, 4326)::GEOMETRY(Point, 4326) AS geom
    FROM stg_fasilitas_pts
    WHERE name IS NOT NULL AND TRIM(name) <> '' AND geom IS NOT NULL

    UNION ALL

    SELECT
        'A-' || COALESCE(NULLIF(osm_id, ''), NULLIF(osm_way_id, ''), 'FID-' || ogc_fid::text) AS osm_id,
        TRIM(name) AS nama_titik,
        COALESCE(
            NULLIF(aeroway, ''),
            NULLIF(landuse, ''),
            CASE WHEN substring(other_tags FROM '"harbour"=>"([^"]+)"') = 'yes' THEN 'harbour' ELSE NULL END,
            NULLIF(substring(other_tags FROM '"railway"=>"([^"]+)"'), ''),
            NULLIF(amenity, ''),
            'lainnya'
        ) AS jenis_titik,
        ST_PointOnSurface(ST_MakeValid(ST_Transform(geom, 4326)))::GEOMETRY(Point, 4326) AS geom
    FROM stg_fasilitas_poly
    WHERE name IS NOT NULL AND TRIM(name) <> '' AND geom IS NOT NULL
) gabungan;

CREATE INDEX idx_titik_transportasi_geom ON titik_transportasi USING GIST (geom);

-- ==========================================
-- 5. ISI RELASI PROVINSI SECARA SPASIAL (SPATIAL JOIN)
-- ==========================================
UPDATE area_transportasi a
SET id_provinsi = p.id_provinsi
FROM provinsi p
WHERE ST_Intersects(ST_PointOnSurface(a.geom), p.geom);

UPDATE titik_transportasi t
SET id_provinsi = p.id_provinsi
FROM provinsi p
WHERE ST_Within(t.geom, p.geom);

-- ==========================================
-- 6. BERSIHKAN TABEL SEMENTARA & TAMPILKAN RINGKASAN
-- ==========================================
DROP TABLE IF EXISTS stg_provinsi;
DROP TABLE IF EXISTS stg_jalur;
DROP TABLE IF EXISTS stg_fasilitas_pts;
DROP TABLE IF EXISTS stg_fasilitas_poly;

SELECT 'provinsi' AS tabel, COUNT(*) AS jumlah_baris FROM provinsi
UNION ALL
SELECT 'area_transportasi', COUNT(*) FROM area_transportasi
UNION ALL
SELECT 'jalur_transportasi', COUNT(*) FROM jalur_transportasi
UNION ALL
SELECT 'titik_transportasi', COUNT(*) FROM titik_transportasi;