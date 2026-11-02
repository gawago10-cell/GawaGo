import os
from urllib import error as url_error
from urllib import request as url_request

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.storage import FileSystemStorage, Storage
from django.utils.deconstruct import deconstructible

NO_PUBLIC_URL = "Private files have no public URL; serve them through a permission-checked view."


class LocalPrivateStorage(FileSystemStorage):
    """PRIVATE_MEDIA_ROOT on local disk, which nothing serves directly
    (unlike MEDIA_ROOT, which is exposed at /media/).

    The location is read from settings on every access rather than cached,
    so tests can point it at a temporary directory with override_settings.
    """

    @property
    def base_location(self):
        return settings.PRIVATE_MEDIA_ROOT

    @property
    def location(self):
        return os.path.abspath(self.base_location)

    def url(self, name):
        raise ValueError(NO_PUBLIC_URL)


class CloudinaryPrivateStorage(Storage):
    """Cloudinary "authenticated" raw uploads, for hosts whose disk is wiped
    on every deploy or restart (Render's free plan lost every uploaded ID).

    An authenticated asset has no public delivery URL. The backend reads it
    through Cloudinary's API download link, signed with the API secret and
    short-lived, and streams it through the same permission-checked views,
    so that link never reaches a browser. The API route rather than a signed
    delivery URL because free accounts refuse to deliver PDFs (401 "deny or
    ACL failure"). "raw" keeps the bytes exactly as uploaded. The stored name
    is the public_id, extension included.
    """

    RESOURCE_TYPE = "raw"
    DELIVERY_TYPE = "authenticated"

    def _options(self):
        return {"resource_type": self.RESOURCE_TYPE, "type": self.DELIVERY_TYPE}

    def _save(self, name, content):
        from apps.common.cloudinary_storage import _configure

        _configure()
        from cloudinary import uploader

        content.seek(0)
        result = uploader.upload(content, public_id=name, overwrite=False, **self._options())
        return result.get("public_id") or name

    def download_url(self, name):
        from apps.common.cloudinary_storage import _configure

        _configure()
        from cloudinary.utils import private_download_url

        # Raw public_ids carry their extension, so no separate format.
        return private_download_url(name, "", **self._options())

    def _open(self, name, mode="rb"):
        try:
            with url_request.urlopen(self.download_url(name), timeout=20) as response:
                return ContentFile(response.read(), name=name)
        except url_error.HTTPError as error:
            if error.code == 404:
                raise FileNotFoundError(name) from error
            raise

    def url(self, name):
        raise ValueError(NO_PUBLIC_URL)

    def exists(self, name):
        # Every private upload_to builds a UUID path, so a clash can't happen;
        # answering "free" saves a network round-trip per upload.
        return False

    def delete(self, name):
        from apps.common.cloudinary_storage import _configure

        _configure()
        from cloudinary import uploader

        uploader.destroy(name, invalidate=True, **self._options())

    def size(self, name):
        from apps.common.cloudinary_storage import _configure

        _configure()
        from cloudinary import api

        return api.resource(name, **self._options()).get("bytes", 0)


@deconstructible
class PrivateMediaStorage(Storage):
    """Government IDs, worker certificates and complaint evidence. Files are
    only ever returned by views that check permissions first, so there is
    deliberately no URL.

    Where they live follows USE_CLOUDINARY, read on every call: Cloudinary
    as authenticated assets on hosts with a throwaway disk, PRIVATE_MEDIA_ROOT
    otherwise. Either way the backend is the only way in.
    """

    def _target(self):
        return CloudinaryPrivateStorage() if settings.USE_CLOUDINARY else LocalPrivateStorage()

    def save(self, name, content, max_length=None):
        return self._target().save(name, content, max_length=max_length)

    def open(self, name, mode="rb"):
        return self._target().open(name, mode)

    def delete(self, name):
        return self._target().delete(name)

    def exists(self, name):
        return self._target().exists(name)

    def size(self, name):
        return self._target().size(name)

    def path(self, name):
        return self._target().path(name)

    def listdir(self, path):
        return self._target().listdir(path)

    def get_accessed_time(self, name):
        return self._target().get_accessed_time(name)

    def get_created_time(self, name):
        return self._target().get_created_time(name)

    def get_modified_time(self, name):
        return self._target().get_modified_time(name)

    def url(self, name):
        raise ValueError(NO_PUBLIC_URL)
