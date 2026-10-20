import os

from django.conf import settings
from django.core.files.storage import FileSystemStorage
from django.utils.deconstruct import deconstructible


@deconstructible
class PrivateMediaStorage(FileSystemStorage):
    """Stores files under PRIVATE_MEDIA_ROOT, which nothing serves directly
    (unlike MEDIA_ROOT, which is exposed at /media/). Files are only returned
    by views that check permissions first, so there is deliberately no URL.

    The location is read from settings on every access rather than cached,
    so tests can point it at a temporary directory with override_settings.
    """

    def __init__(self):
        super().__init__()

    @property
    def base_location(self):
        return settings.PRIVATE_MEDIA_ROOT

    @property
    def location(self):
        return os.path.abspath(self.base_location)

    def url(self, name):
        raise ValueError("Private files have no public URL; serve them through a permission-checked view.")
