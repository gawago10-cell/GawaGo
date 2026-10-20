"""Cloudinary-backed storage for PUBLIC media only.

Why this is hand-written rather than `django-cloudinary-storage`: that package's
last release is 0.3.0 (2020) and it configures itself through
`DEFAULT_FILE_STORAGE`, which Django removed in 5.1. This project runs Django
6.x, so it talks to Cloudinary's own SDK (actively maintained) directly.

**This must never back private media.** Government IDs, worker certificates and
complaint evidence use `apps.complaints.storage.PrivateMediaStorage`, whose
`url()` raises on purpose so no public link can exist for them -- a Cloudinary
delivery URL is public to anyone holding it, which would undo exactly the
private-media fix. Wire this up as the *default* storage only; the
private fields pin their own storage on the field and are unaffected.
"""

from django.core.files.storage import Storage
from django.utils.deconstruct import deconstructible


def _configure():
    """Point the SDK at the configured account. Called per operation rather
    than at import so settings overrides in tests are picked up."""
    import cloudinary
    from django.conf import settings

    cloudinary.config(
        cloud_name=settings.CLOUDINARY_CLOUD_NAME,
        api_key=settings.CLOUDINARY_API_KEY,
        api_secret=settings.CLOUDINARY_API_SECRET,
        secure=True,
    )
    return cloudinary


@deconstructible
class CloudinaryMediaStorage(Storage):
    """Uploads to Cloudinary and stores the returned public_id as the file
    name, so `url()` can rebuild the delivery URL from the database value
    alone."""

    def _save(self, name, content):
        cloudinary = _configure()
        from cloudinary import uploader

        content.seek(0)
        # `name` already carries the dated, UUID-based path each model's
        # upload_to built, so it is unique; Cloudinary adds the extension
        # back itself, hence stripping it from the public_id.
        public_id = name.rsplit(".", 1)[0]
        result = uploader.upload(
            content,
            public_id=public_id,
            resource_type="auto",
            overwrite=False,
            invalidate=True,
        )
        # Keep the real identifier Cloudinary assigned, not the one requested:
        # they differ whenever a public_id was already taken.
        stored = result.get("public_id") or public_id
        file_format = result.get("format")
        return f"{stored}.{file_format}" if file_format else stored

    def _open(self, name, mode="rb"):
        from urllib import request

        from django.core.files.base import ContentFile

        with request.urlopen(self.url(name), timeout=20) as response:
            return ContentFile(response.read(), name=name)

    def url(self, name):
        cloudinary = _configure()
        from cloudinary.utils import cloudinary_url

        url, _options = cloudinary_url(name, secure=True)
        return url

    def exists(self, name):
        # Django calls this to find a free name before saving. Every
        # upload_to here already produces a UUID path, and `_save` returns
        # whatever public_id Cloudinary actually used, so claiming "free"
        # avoids a network round-trip per upload without risking a clash.
        return False

    def delete(self, name):
        _configure()
        from cloudinary import uploader

        uploader.destroy(name.rsplit(".", 1)[0], invalidate=True)

    def size(self, name):
        _configure()
        from cloudinary import api

        return api.resource(name.rsplit(".", 1)[0]).get("bytes", 0)

    def get_accessed_time(self, name):
        raise NotImplementedError("Cloudinary does not expose an access time.")

    def get_created_time(self, name):
        _configure()
        from cloudinary import api

        from django.utils.dateparse import parse_datetime

        return parse_datetime(api.resource(name.rsplit(".", 1)[0])["created_at"])

    def get_modified_time(self, name):
        return self.get_created_time(name)
