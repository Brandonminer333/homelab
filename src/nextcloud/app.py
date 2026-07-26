import os
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

import pandas as pd
import streamlit as st

DATA_ROOT = Path(os.environ.get("NEXTCLOUD_DATA_ROOT", "/data"))
SKIP_DIR_NAMES = {
    "cache",
    "thumbnails",
    "uploads",
    "files_versions",
    "files_trashbin",
    "appdata_oc",
}
SKIP_EXTENSIONS = {".part", ".tmp"}


@dataclass(frozen=True)
class FileRecord:
    user: str
    relative_path: str
    top_folder: str
    extension: str
    size_bytes: int


def format_bytes(size: int) -> str:
    units = ("B", "KB", "MB", "GB", "TB")
    value = float(size)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.1f} {unit}"
        value /= 1024
    return f"{size} B"


def user_files_root(data_root: Path, entry: Path) -> Path | None:
    files_dir = entry / "files"
    if files_dir.is_dir():
        return files_dir
    return None


def iter_user_dirs(data_root: Path) -> list[tuple[str, Path]]:
    if not data_root.is_dir():
        return []

    users: list[tuple[str, Path]] = []
    for entry in sorted(data_root.iterdir()):
        if not entry.is_dir() or entry.name.startswith("."):
            continue
        files_dir = user_files_root(data_root, entry)
        if files_dir is not None:
            users.append((entry.name, files_dir))
    return users


def top_folder_for(relative_path: Path) -> str:
    parts = relative_path.parts
    if not parts:
        return "(root)"
    return parts[0]


def extension_for(path: Path) -> str:
    suffix = path.suffix.lower()
    return suffix if suffix else "(no extension)"


def scan_nextcloud_data(data_root: Path) -> list[FileRecord]:
    records: list[FileRecord] = []

    for user, files_dir in iter_user_dirs(data_root):
        for dirpath, dirnames, filenames in os.walk(files_dir, followlinks=False):
            dirnames[:] = [
                name
                for name in dirnames
                if not name.startswith(".") and name not in SKIP_DIR_NAMES
            ]

            current_dir = Path(dirpath)
            for filename in filenames:
                if filename.startswith("."):
                    continue

                path = current_dir / filename
                if path.suffix.lower() in SKIP_EXTENSIONS:
                    continue

                try:
                    stat = path.stat()
                except OSError:
                    continue

                if not stat.is_file():
                    continue

                relative_path = path.relative_to(files_dir)
                records.append(
                    FileRecord(
                        user=user,
                        relative_path=str(relative_path),
                        top_folder=top_folder_for(relative_path),
                        extension=extension_for(path),
                        size_bytes=stat.st_size,
                    )
                )

    return records


@st.cache_data(show_spinner=False)
def load_metrics(data_root: str) -> pd.DataFrame:
    records = scan_nextcloud_data(Path(data_root))
    return pd.DataFrame([record.__dict__ for record in records])


st.set_page_config(page_title="Nextcloud File Metrics", layout="wide")
st.title("Nextcloud File Metrics")
st.caption(f"Scanning data root: `{DATA_ROOT}`")

if not DATA_ROOT.is_dir():
    st.error(
        "Nextcloud data directory is not mounted or does not exist. "
        "Set `NEXTCLOUD_DATA_ROOT` and mount the Nextcloud data volume."
    )
    st.stop()

controls = st.columns([1, 1, 2])
with controls[0]:
    if st.button("Rescan files", type="primary"):
        load_metrics.clear()
with controls[1]:
    st.write(f"Users found: **{len(iter_user_dirs(DATA_ROOT))}**")

with st.spinner("Scanning files..."):
    files_df = load_metrics(str(DATA_ROOT))

if files_df.empty:
    st.warning("No user files found under `*/files/` in the data directory.")
    st.stop()

total_files = len(files_df)
total_size = int(files_df["size_bytes"].sum())
unique_extensions = files_df["extension"].nunique()
unique_users = files_df["user"].nunique()

summary = st.columns(4)
summary[0].metric("Total files", f"{total_files:,}")
summary[1].metric("Total size", format_bytes(total_size))
summary[2].metric("File types", f"{unique_extensions:,}")
summary[3].metric("Users", f"{unique_users:,}")

st.divider()

left, right = st.columns(2)

with left:
    st.subheader("Files by extension")
    by_extension = (
        files_df.groupby("extension", as_index=False)
        .agg(files=("relative_path", "count"), size_bytes=("size_bytes", "sum"))
        .sort_values("files", ascending=False)
    )
    by_extension["size"] = by_extension["size_bytes"].map(format_bytes)
    st.bar_chart(by_extension.set_index("extension")["files"])
    st.dataframe(
        by_extension[["extension", "files", "size"]].rename(
            columns={"extension": "Extension", "files": "Files", "size": "Size"}
        ),
        use_container_width=True,
        hide_index=True,
    )

with right:
    st.subheader("Files by user")
    by_user = (
        files_df.groupby("user", as_index=False)
        .agg(files=("relative_path", "count"), size_bytes=("size_bytes", "sum"))
        .sort_values("files", ascending=False)
    )
    by_user["size"] = by_user["size_bytes"].map(format_bytes)
    st.bar_chart(by_user.set_index("user")["files"])
    st.dataframe(
        by_user[["user", "files", "size"]].rename(
            columns={"user": "User", "files": "Files", "size": "Size"}
        ),
        use_container_width=True,
        hide_index=True,
    )

st.subheader("Top folders")
selected_user = st.selectbox(
    "User",
    options=["All users", *sorted(files_df["user"].unique())],
)
folder_df = files_df if selected_user == "All users" else files_df[files_df["user"] == selected_user]
by_folder = (
    folder_df.groupby("top_folder", as_index=False)
    .agg(files=("relative_path", "count"), size_bytes=("size_bytes", "sum"))
    .sort_values("files", ascending=False)
    .head(25)
)
by_folder["size"] = by_folder["size_bytes"].map(format_bytes)
st.dataframe(
    by_folder[["top_folder", "files", "size"]].rename(
        columns={"top_folder": "Folder", "files": "Files", "size": "Size"}
    ),
    use_container_width=True,
    hide_index=True,
)

st.subheader("Largest files")
largest = files_df.sort_values("size_bytes", ascending=False).head(25).copy()
largest["size"] = largest["size_bytes"].map(format_bytes)
st.dataframe(
    largest[["user", "relative_path", "extension", "size"]].rename(
        columns={
            "user": "User",
            "relative_path": "Path",
            "extension": "Extension",
            "size": "Size",
        }
    ),
    use_container_width=True,
    hide_index=True,
)

with st.expander("Extension breakdown (full list)"):
    extension_counts = Counter(files_df["extension"])
    extension_table = pd.DataFrame(
        [{"extension": ext, "files": count} for ext, count in extension_counts.most_common()]
    )
    st.dataframe(extension_table, use_container_width=True, hide_index=True)
