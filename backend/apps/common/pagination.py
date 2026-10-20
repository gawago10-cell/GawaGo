from rest_framework.pagination import PageNumberPagination


def paginated_response(request, queryset, serializer_class, **serializer_kwargs):
    """Page a queryset exactly like a generic list view does (the configured
    PAGE_SIZE, `count`/`next`/`previous`/`results`).

    For APIView-based list endpoints, which returned every row in one
    response: a user with a long history made each poll download all of it.
    Both clients already follow `next`, so paging them is not a breaking
    change.
    """
    paginator = PageNumberPagination()
    page = paginator.paginate_queryset(queryset, request)
    data = serializer_class(page, many=True, **serializer_kwargs).data
    return paginator.get_paginated_response(data)
