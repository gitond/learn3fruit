# External files in this directory

These files are gitignored. Download them manually before running the data pipeline.

---

## downloader.py

**Source:** https://raw.githubusercontent.com/openimages/dataset/master/downloader.py  
**From:** Open Images Dataset GitHub (Google)  
**Why:** Official script for downloading Open Images images by ID from the CVDF AWS S3 bucket. Takes a text file of image IDs (`split/image_id` format) and downloads the corresponding JPEGs.  
**Dependencies:** `boto3`, `botocore`, `tqdm` (all already in venv)

```bash
wget https://raw.githubusercontent.com/openimages/dataset/master/downloader.py
```

---

## oidv7-class-descriptions-boxable.csv

**Source:** https://storage.googleapis.com/openimages/v7/oidv7-class-descriptions-boxable.csv  
**From:** Open Images V7 (Google)  
**Why:** Maps human-readable class names (e.g. `Apple`) to Open Images label codes (e.g. `/m/014j1m`). Required to filter bbox annotation CSVs by class name.

```bash
wget https://storage.googleapis.com/openimages/v7/oidv7-class-descriptions-boxable.csv
```

---

## validation-annotations-bbox.csv

**Source:** https://storage.googleapis.com/openimages/v5/validation-annotations-bbox.csv  
**From:** Open Images V5/V7 (Google) — validation split annotations are shared across versions  
**Why:** Bounding box annotations for the validation split (~41k images). Used for test/exploration downloads because it is small enough to load in memory. For full training data use `oidv6-train-annotations-bbox.csv` instead.

```bash
wget https://storage.googleapis.com/openimages/v5/validation-annotations-bbox.csv
```

---

## oidv6-train-annotations-bbox.csv

**Source:** https://storage.googleapis.com/openimages/v6/oidv6-train-annotations-bbox.csv  
**From:** Open Images V6/V7 (Google) — training split bbox annotations are shared across versions  
**Why:** Bounding box annotations for the full training split (~1.7M images). Large file (~1-2 GB). Only needed once the data pipeline is validated on the validation split and ready to run at full scale.

```bash
wget https://storage.googleapis.com/openimages/v6/oidv6-train-annotations-bbox.csv
```

---

## OID_COCO_overlaps.csv

**Source:** https://storage.googleapis.com/openimages/v6/OID_COCO_overlaps.csv  
**From:** Open Images V6/V7 download page (Google) — external file, not our code  
**Why:** Lists every Open Images image that also appears in the COCO 2017 dataset (by Flickr photo ID). Used by `prep_data_dl.sh` to exclude these images from our dataset, since the pretrained MobileNet-V2 backbone was trained on COCO and training on the same images would leak data. Contains 9875 entries (header + 9874 overlap pairs).  
**Format:** `coco_id,open_images_id` — `open_images_id` matches the `ImageID` column in the bbox annotation CSVs directly.

```bash
wget https://storage.googleapis.com/openimages/v6/OID_COCO_overlaps.csv
```
