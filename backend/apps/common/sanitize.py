"""Strips markup from free-text fields before they are stored.

React escapes everything it renders, so a stored `<script>` tag is not an
XSS risk on the web client today -- but it is still live markup sitting in
the database, waiting for the next place that renders it unescaped (an
admin page, an email template, a CSV viewer, a future mobile WebView).
Stripping it at write time means there is never anything dangerous to leak.
"""

from django.utils.html import strip_tags


def sanitize_text(value):
    if not isinstance(value, str):
        return value
    return strip_tags(value)
