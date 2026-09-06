from decimal import Decimal, DecimalException, ROUND_HALF_UP

from rest_framework import serializers


class RoundedCoordinateField(serializers.DecimalField):
    def to_internal_value(self, data):
        if data in (None, ""):
            return super().to_internal_value(data)
        try:
            value = Decimal(str(data)).quantize(
                Decimal("0.0000001"),
                rounding=ROUND_HALF_UP,
            )
        except (DecimalException, TypeError, ValueError):
            return super().to_internal_value(data)
        return super().to_internal_value(str(value))
