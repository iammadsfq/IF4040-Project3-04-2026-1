#!/usr/bin/env bash
set -e

RAW_FILE="data/raw/indonesia-latest.osm.pbf"
TMP_DIR="data/tmp"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_CONN="PG:dbname=if4040_transport user=postgres password=postgres host=${PGHOST:-localhost} port=${PGPORT:-5433}"

mkdir -p "$TMP_DIR" data/processed

echo "[1/4] Mengambil batas wilayah provinsi..."
# boundary=administrative (batas wilayah) & admin_level=4 (tingkat provinsi di Indonesia)
if [ ! -f "$TMP_DIR/provinsi.osm.pbf" ]; then
    osmium tags-filter "$RAW_FILE" r/boundary=administrative -o "$TMP_DIR/admin.osm.pbf" --overwrite
    osmium tags-filter "$TMP_DIR/admin.osm.pbf" r/admin_level=4 -o "$TMP_DIR/provinsi.osm.pbf" --overwrite
else
    echo "   -> Dilewati (file provinsi.osm.pbf sudah ada)"
fi

# Tambal batas Kalimantan Utara (way 1181737260) & Kepulauan Riau (way 1147865283).
# Kedua garis ini ada di OSM, tapi di luar area potong Geofabrik sehingga poligon provinsinya tidak tertutup.
osmium merge "$TMP_DIR/provinsi.osm.pbf" "${SCRIPT_DIR}/patch_batas_provinsi.osm" \
    -o "$TMP_DIR/provinsi_lengkap.osm.pbf" --overwrite

echo "[2/4] Mengambil jaringan jalan tol, jalan nasional, dan rel kereta..."
# motorway = jalan tol
# trunk    = jalan nasional / arteri lintas provinsi
# primary  = jalan arteri utama penghubung antar-kota
# rail     = jalur rel kereta api utama
if [ ! -f "$TMP_DIR/jalur.osm.pbf" ]; then
osmium tags-filter "$RAW_FILE" \
    w/highway=motorway,trunk,primary \
    w/railway=rail \
    -o "$TMP_DIR/jalur.osm.pbf" --overwrite
else
    echo "   -> Dilewati (file jalur.osm.pbf sudah ada)"
fi

echo "[3/4] Mengambil data titik dan area stasiun, bandara, pelabuhan, serta terminal..."
# railway=station        = stasiun kereta api (jarak jauh & komuter)
# aeroway=aerodrome      = bandara dan lapangan terbang
# amenity=ferry_terminal = pelabuhan / dermaga penyeberangan feri
# amenity=bus_station    = terminal bus besar antar-kota/provinsi
# landuse=port           = kawasan pelabuhan laut dan kargo
# harbour=yes            = pelabuhan laut / dermaga tambahan
if [ ! -f "$TMP_DIR/fasilitas.osm.pbf" ]; then
osmium tags-filter "$RAW_FILE" \
    nwr/railway=station \
    nwr/aeroway=aerodrome \
    nwr/amenity=ferry_terminal,bus_station \
    nwr/landuse=port \
    nwr/harbour=yes \
    -o "$TMP_DIR/fasilitas.osm.pbf" --overwrite
else
    echo "   -> Dilewati (file fasilitas.osm.pbf sudah ada)"
fi

echo "[4/4] Memasukkan data ke tabel sementara di PostgreSQL..."
# stg_provinsi       : poligon batas 38 provinsi
ogr2ogr -f "PostgreSQL" "$DB_CONN" "$TMP_DIR/provinsi_lengkap.osm.pbf" multipolygons \
  -nln stg_provinsi -overwrite -lco GEOMETRY_NAME=geom

# stg_jalur          : garis jaringan tol, jalan utama, dan rel kereta
ogr2ogr -f "PostgreSQL" "$DB_CONN" "$TMP_DIR/jalur.osm.pbf" lines \
  -nln stg_jalur -overwrite -lco GEOMETRY_NAME=geom

# stg_fasilitas_pts  : fasilitas transportasi yang dicatat OSM sebagai titik (node)
ogr2ogr -f "PostgreSQL" "$DB_CONN" "$TMP_DIR/fasilitas.osm.pbf" points \
  -nln stg_fasilitas_pts -overwrite -lco GEOMETRY_NAME=geom

# stg_fasilitas_poly : fasilitas transportasi yang dicatat OSM sebagai area/bangunan (polygon)
ogr2ogr -f "PostgreSQL" "$DB_CONN" "$TMP_DIR/fasilitas.osm.pbf" multipolygons \
  -nln stg_fasilitas_poly -overwrite -lco GEOMETRY_NAME=geom

