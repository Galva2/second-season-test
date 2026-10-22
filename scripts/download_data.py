"""Download the IMDb non-commercial datasets used by this project into data/raw/.

Only the four files the analysis needs are downloaded (title.principals is
deliberately excluded). Files are kept gzipped; DuckDB reads .tsv.gz directly.

Usage:
    python scripts/download_data.py          # skip files that already exist
    python scripts/download_data.py --force  # re-download everything

Data source: IMDb non-commercial datasets, https://datasets.imdbws.com/
Personal, non-commercial use only. See https://developer.imdb.com/non-commercial-datasets/
"""

import argparse
import shutil
import sys
import urllib.request
from pathlib import Path

BASE_URL = "https://datasets.imdbws.com/"
FILES = [
    "title.basics.tsv.gz",
    "title.episode.tsv.gz",
    "title.ratings.tsv.gz",
    "title.crew.tsv.gz",
]
RAW_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"


def download(filename: str, force: bool) -> None:
    """Stream one file to data/raw/, writing to a .part file first so an
    interrupted download never leaves a truncated file that looks complete."""
    target = RAW_DIR / filename
    if target.exists() and not force:
        print(f"skip      {filename} (already exists, {target.stat().st_size / 1e6:.1f} MB)")
        return

    tmp = target.with_suffix(target.suffix + ".part")
    print(f"download  {BASE_URL + filename} ...", flush=True)
    with urllib.request.urlopen(BASE_URL + filename) as resp, open(tmp, "wb") as out:
        shutil.copyfileobj(resp, out, length=1024 * 1024)
    tmp.replace(target)
    print(f"done      {filename} ({target.stat().st_size / 1e6:.1f} MB)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--force", action="store_true", help="re-download existing files")
    args = parser.parse_args()

    RAW_DIR.mkdir(parents=True, exist_ok=True)
    for filename in FILES:
        download(filename, args.force)
    return 0


if __name__ == "__main__":
    sys.exit(main())
