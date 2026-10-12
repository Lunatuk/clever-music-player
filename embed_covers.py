import os
import subprocess
import sys
from pathlib import Path

def has_cover_ffprobe(file_path):
    """Проверяет, есть ли в файле видеопоток (обложка) через ffprobe."""
    try:
        cmd = [
            "ffprobe",
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=codec_type",
            "-of", "default=noprint_wrappers=1:nokey=1",
            str(file_path)
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        return result.stdout.strip() == "video"
    except Exception:
        return False  # Если ошибка, лучше перезаписать

def embed_cover(m4a_path, cover_path, dry_run=False):
    """Вшивает обложку в один m4a-файл через ffmpeg."""
    if dry_run:
        print(f"[DRY RUN] would embed {cover_path} into {m4a_path}")
        return True

    # Если обложка уже есть, можно пропустить (опционально)
    if has_cover_ffprobe(m4a_path):
        print(f"⏭️  {m4a_path} уже имеет обложку, пропускаем")
        return True

    temp_path = m4a_path.with_suffix(".temp.m4a")
    cmd = [
        "ffmpeg",
        "-i", str(m4a_path),
        "-i", str(cover_path),
        "-map", "0",
        "-map", "1",
        "-c", "copy",
        "-disposition:v:0", "attached_pic",
        "-y",  # перезаписывать временный файл, если существует
        str(temp_path)
    ]
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True)
        # Заменяем оригинал временным
        os.replace(temp_path, m4a_path)
        print(f"✅  Обложка добавлена в {m4a_path}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌  Ошибка при обработке {m4a_path}: {e.stderr}")
        if temp_path.exists():
            temp_path.unlink()
        return False
    except Exception as e:
        print(f"❌  Непредвиденная ошибка: {e}")
        return False

def process_folder(root_dir, dry_run=False):
    """Рекурсивно обходит root_dir, находит cover.jpg и вшивает во все m4a в той же папке."""
    root_path = Path(root_dir).resolve()
    if not root_path.is_dir():
        print(f"❌  Папка {root_dir} не существует или не является директорией.")
        return

    # Собираем все папки, содержащие cover.jpg
    cover_dirs = []
    for dirpath, _, filenames in os.walk(root_path):
        if "cover.jpg" in filenames:
            cover_dirs.append(Path(dirpath))

    if not cover_dirs:
        print("⚠️  Не найдено ни одной папки с cover.jpg")
        return

    total = 0
    for album_dir in cover_dirs:
        cover_path = album_dir / "cover.jpg"
        m4a_files = list(album_dir.glob("*.m4a"))
        if not m4a_files:
            continue
        print(f"\n📁  Обработка {album_dir} (найдено {len(m4a_files)} треков)")
        for m4a in m4a_files:
            if embed_cover(m4a, cover_path, dry_run):
                total += 1

    print(f"\n🎉  Готово! Обработано {total} файлов.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Использование: python embed_covers.py <путь_к_папке_МУЗЫКА> [--dry-run]")
        sys.exit(1)

    root = sys.argv[1]
    dry = "--dry-run" in sys.argv
    process_folder(root, dry_run=dry)