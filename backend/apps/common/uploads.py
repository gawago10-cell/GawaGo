"""One place that decides whether an upload is actually acceptable.

Every upload path used to check only the filename's extension, so arbitrary
bytes named `.jpg` were stored and served as an image, and nothing capped the
size -- a 25 MB "photo" was accepted in four different places. The extension
is the easiest thing in the request to lie about, so the file's own contents
decide, and the caller gets one readable error either way.
"""

from pathlib import Path

from django.core.exceptions import ValidationError as DjangoValidationError

IMAGE_EXTENSIONS = frozenset({".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif"})
DOCUMENT_EXTENSIONS = frozenset(IMAGE_EXTENSIONS | {".pdf"})

MAX_IMAGE_BYTES = 5 * 1024 * 1024
MAX_DOCUMENT_BYTES = 10 * 1024 * 1024

PDF_MAGIC = b"%PDF-"


class UploadRejected(Exception):
    """Carries a message meant for the person who picked the file."""


def _check_extension_and_size(upload, *, allowed_extensions, max_bytes, kind):
    suffix = Path(upload.name or "").suffix.lower()
    if suffix not in allowed_extensions:
        readable = ", ".join(sorted(ext.lstrip(".").upper() for ext in allowed_extensions))
        raise UploadRejected(f"Choose a {kind} file ({readable}).")
    if upload.size and upload.size > max_bytes:
        raise UploadRejected(f"Each file must be {max_bytes // (1024 * 1024)} MB or smaller.")
    return suffix


def _verify_image_bytes(upload):
    """True when the bytes really are a readable image.

    HEIC/HEIF need a Pillow plugin that may not be installed, and Pillow
    cannot confirm those on its own. Rather than reject photos straight off an
    iPhone, those fall back to the extension-and-size check.
    """
    from PIL import Image, UnidentifiedImageError

    upload.seek(0)
    try:
        Image.open(upload).verify()
    except (UnidentifiedImageError, DjangoValidationError, OSError, ValueError, SyntaxError):
        return False
    finally:
        upload.seek(0)
    return True


def validate_image_upload(upload, *, max_bytes=MAX_IMAGE_BYTES):
    suffix = _check_extension_and_size(
        upload, allowed_extensions=IMAGE_EXTENSIONS, max_bytes=max_bytes, kind="image"
    )
    if suffix in {".heic", ".heif"}:
        return upload
    if not _verify_image_bytes(upload):
        raise UploadRejected("That file isn't a readable image. Please pick a different photo.")
    return upload


def validate_document_upload(upload, *, max_bytes=MAX_DOCUMENT_BYTES):
    """An image or a PDF -- used for IDs and credentials."""
    suffix = _check_extension_and_size(
        upload, allowed_extensions=DOCUMENT_EXTENSIONS, max_bytes=max_bytes, kind="image or PDF"
    )
    if suffix == ".pdf":
        upload.seek(0)
        header = upload.read(len(PDF_MAGIC))
        upload.seek(0)
        if header != PDF_MAGIC:
            raise UploadRejected("That file isn't a readable PDF. Please pick a different file.")
        return upload
    if suffix in {".heic", ".heif"}:
        return upload
    if not _verify_image_bytes(upload):
        raise UploadRejected("That file isn't a readable image or PDF.")
    return upload
