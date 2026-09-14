"""HTTP boundary for the Happy Bus JSON API and its small browser client."""
import csv
import io
import json
import re
import uuid
from functools import wraps

from django.contrib.auth import authenticate, get_user_model, login, logout
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db import IntegrityError, transaction
from django.db.models import F, Max
from django.http import FileResponse, HttpResponse, JsonResponse
from django.middleware.csrf import get_token, rotate_token
from django.shortcuts import render
from django.urls import reverse
from PIL import Image, UnidentifiedImageError

from .models import Bus, Receipt, Report

User = get_user_model()
MAX_RECEIPT_SIZE = 2 * 1024 * 1024
INTEGER_FIELDS = ("km_awal", "km_akhir", "uang_saku", "bbm", "uang_makan", "extra", "tagihan")
TEXT_FIELDS = (
    "hari_tgl_berangkat",
    "jam_berangkat",
    "hari_tgl_kembali",
    "pengemudi",
    "kernet",
    "nama_crew",
    "catatan",
)
REQUIRED_TEXT_FIELDS = ("hari_tgl_berangkat", "jam_berangkat", "hari_tgl_kembali", "pengemudi", "nama_crew")
USERNAME_RE = re.compile(r"[A-Za-z0-9_.@+\-]{1,150}\Z")
REPORT_CSV_COLUMNS = (
    "id",
    "owner_id",
    "no_polisi",
    "pengemudi",
    "status",
    "uang_saku",
    "total_pengeluaran",
    "sisa",
    "jarak_tempuh",
)
CSV_FORMULA_PREFIXES = ("=", "+", "-", "@", "\t", "\r", "\n")


def json_error(message, status=400):
    return JsonResponse({"error": message}, status=status)


def method_error(methods):
    response = json_error("Method not allowed", 405)
    response["Allow"] = ", ".join(methods)
    return response


def parse_json(request):
    try:
        value = json.loads(request.body.decode("utf-8") or "{}")
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise ValueError("Request body must be valid JSON")
    if not isinstance(value, dict):
        raise ValueError("Request body must be a JSON object")
    return value


def is_admin(user):
    return bool(user.is_authenticated and user.is_active and (user.is_staff or user.is_superuser))


def user_role(user):
    return "admin" if user.is_staff or user.is_superuser else "crew"


def api_auth(view):
    @wraps(view)
    def wrapped(request, *args, **kwargs):
        user = request.user
        if not user.is_authenticated or not user.is_active:
            return json_error("Authentication required", 401)
        return view(request, *args, **kwargs)

    return wrapped


def api_admin(view):
    @wraps(view)
    def wrapped(request, *args, **kwargs):
        user = request.user
        if not user.is_authenticated or not user.is_active:
            return json_error("Authentication required", 401)
        if not is_admin(user):
            return json_error("Administrator access required", 403)
        return view(request, *args, **kwargs)

    return wrapped


def csrf_failure(request, reason=""):
    return json_error("CSRF verification failed", 403)


def user_payload(user):
    return {"id": user.id, "username": user.username, "role": user_role(user)}


def session_payload(request):
    user = request.user
    return {"user": user_payload(user) if user.is_authenticated and user.is_active else None, "csrf_token": get_token(request)}


def session_view(request):
    if request.method != "GET":
        return method_error(("GET",))
    return JsonResponse(session_payload(request))


def login_view(request):
    if request.method != "POST":
        return method_error(("POST",))
    try:
        data = parse_json(request)
    except ValueError as exc:
        return json_error(str(exc))
    username = data.get("username")
    password = data.get("password")
    if not isinstance(username, str) or not isinstance(password, str):
        return json_error("Invalid credentials", 401)
    user = authenticate(request, username=username, password=password)
    if user is None or not user.is_active:
        return json_error("Invalid credentials", 401)
    login(request, user)
    rotate_token(request)
    return JsonResponse({"user": user_payload(user), "csrf_token": get_token(request)})


def logout_view(request):
    if request.method != "POST":
        return method_error(("POST",))
    logout(request)
    return JsonResponse({"ok": True})


@api_auth
def users_view(request):
    if request.method == "GET":
        return _users_list(request)
    if request.method == "POST":
        return _users_create(request)
    return method_error(("GET", "POST"))


@api_admin
def _users_list(request):
    if request.method != "GET":
        return method_error(("GET",))
    users = User.objects.order_by("id")
    return JsonResponse([
        {"id": user.id, "username": user.username, "role": user_role(user), "is_active": user.is_active}
        for user in users
    ], safe=False)


@api_admin
def _users_create(request):
    if request.method != "POST":
        return method_error(("POST",))
    try:
        data = parse_json(request)
    except ValueError as exc:
        return json_error(str(exc))
    username = data.get("username")
    password = data.get("password")
    if not isinstance(username, str):
        return json_error("Username is required")
    username = username.strip()
    if not USERNAME_RE.fullmatch(username):
        return json_error("Username must use 1-150 ASCII letters, digits, _, ., @, +, or -")
    if not isinstance(password, str) or len(password) < 10:
        return json_error("Passwords must be at least 10 characters")
    try:
        with transaction.atomic():
            user = User(username=username, is_active=True, is_staff=False, is_superuser=False)
            user.set_password(password)
            user.save()
    except IntegrityError:
        return json_error("Username already exists", 409)
    return JsonResponse({"id": user.id, "username": user.username, "role": "crew", "is_active": user.is_active}, status=201)


@api_admin
def user_detail_view(request, user_id):
    if request.method != "PATCH":
        return method_error(("PATCH",))
    try:
        user = User.objects.get(pk=user_id)
    except User.DoesNotExist:
        return json_error("User not found", 404)
    if user.is_staff or user.is_superuser:
        return json_error("Administrator accounts cannot be changed here", 403)
    try:
        data = parse_json(request)
    except ValueError as exc:
        return json_error(str(exc))
    if "is_active" in data and not isinstance(data["is_active"], bool):
        return json_error("is_active must be boolean")
    if "is_active" in data:
        user.is_active = data["is_active"]
        user.save(update_fields=["is_active"])
    return JsonResponse({"id": user.id, "username": user.username, "role": "crew", "is_active": user.is_active})


def _ensure_default_buses():
    """Repair only missing fixed slots; existing names, plates, and history stay untouched."""
    for slot in range(1, 7):
        Bus.objects.get_or_create(
            id=slot,
            defaults={"name": f"Bus {slot}", "plate": f"BUS-{slot}", "last_oil_change_km": 0, "oil_interval_km": 10000},
        )


def _fixed_bus(bus_id):
    if isinstance(bus_id, bool) or not isinstance(bus_id, int) or bus_id < 1 or bus_id > 6:
        return None
    try:
        return Bus.objects.get(pk=bus_id)
    except Bus.DoesNotExist:
        return None


def bus_payload(bus):
    current_km = Report.objects.filter(no_polisi=bus.plate).aggregate(max_km=Max("km_akhir"))["max_km"] or 0
    next_service = bus.last_oil_change_km + bus.oil_interval_km
    remaining = next_service - current_km
    status = "due" if remaining <= 0 else "soon" if remaining <= 2000 else "healthy"
    return {
        "id": bus.id,
        "name": bus.name,
        "plate": bus.plate,
        "last_oil_change_km": bus.last_oil_change_km,
        "oil_interval_km": bus.oil_interval_km,
        "current_km": current_km,
        "next_service_km": next_service,
        "remaining_km": remaining,
        "maintenance_status": status,
    }


@api_auth
def buses_view(request):
    if request.method != "GET":
        if request.method == "PATCH" or request.method == "POST":
            return method_error(("GET",))
        return method_error(("GET",))
    _ensure_default_buses()
    return JsonResponse([bus_payload(bus) for bus in Bus.objects.filter(id__range=(1, 6)).order_by("id")], safe=False)


@api_admin
def bus_detail_view(request, bus_id):
    if request.method != "PATCH":
        return method_error(("PATCH",))
    bus = _fixed_bus(bus_id)
    if bus is None:
        return json_error("Bus not found", 404)
    try:
        data = parse_json(request)
    except ValueError as exc:
        return json_error(str(exc))
    changes = {}
    if "name" in data:
        if not isinstance(data["name"], str):
            return json_error("name must be a string")
        changes["name"] = data["name"].strip()
    if "plate" in data:
        if not isinstance(data["plate"], str):
            return json_error("plate must be a string")
        changes["plate"] = data["plate"].strip().upper()
    name = changes.get("name", bus.name)
    plate = changes.get("plate", bus.plate)
    if not name or len(name) > 80:
        return json_error("name must be a nonempty string of at most 80 characters")
    if not plate or len(plate) > 80:
        return json_error("plate must be a nonempty string of at most 80 characters")
    bus.name, bus.plate = name, plate
    try:
        bus.save(update_fields=["name", "plate"])
    except IntegrityError:
        return json_error("Bus plate already exists", 409)
    return JsonResponse(bus_payload(bus))


@api_admin
def oil_change_view(request, bus_id):
    if request.method != "POST":
        return method_error(("POST",))
    bus = _fixed_bus(bus_id)
    if bus is None:
        return json_error("Bus not found", 404)
    try:
        data = parse_json(request)
    except ValueError as exc:
        return json_error(str(exc))
    km = data.get("km")
    if isinstance(km, bool) or not isinstance(km, int) or km < 0 or km > 1_000_000_000:
        return json_error("km must be an integer from 0 to 1000000000")
    bus.last_oil_change_km = km
    bus.save(update_fields=["last_oil_change_km"])
    return JsonResponse(bus_payload(bus))


def _parse_integer(value, field):
    if isinstance(value, bool) or not isinstance(value, int) or value < 0 or value > 1_000_000_000:
        raise ValueError(f"{field} must be an integer from 0 to 1000000000")
    return value


def _parse_report_values(data, existing=None):
    """Validate mutable fields and return a complete, trimmed record for a report."""
    result = {}
    if existing is None:
        for field in REQUIRED_TEXT_FIELDS:
            if field not in data:
                raise ValueError(f"{field} is required")
        for field in INTEGER_FIELDS:
            if field not in data:
                raise ValueError(f"{field} is required")
        for field in TEXT_FIELDS:
            value = data.get(field, "")
            if not isinstance(value, str):
                raise ValueError(f"{field} must be a string")
            value = value.strip()
            max_length = 4000 if field == "catatan" else 200
            if len(value) > max_length:
                raise ValueError(f"{field} is too long")
            if field in REQUIRED_TEXT_FIELDS and not value:
                raise ValueError(f"{field} must not be blank")
            result[field] = value
        for field in INTEGER_FIELDS:
            result[field] = _parse_integer(data[field], field)
    else:
        for field in TEXT_FIELDS:
            if field in data:
                value = data[field]
                if not isinstance(value, str):
                    raise ValueError(f"{field} must be a string")
                value = value.strip()
                max_length = 4000 if field == "catatan" else 200
                if len(value) > max_length:
                    raise ValueError(f"{field} is too long")
                result[field] = value
            else:
                result[field] = getattr(existing, field)
        for field in INTEGER_FIELDS:
            if field in data:
                result[field] = _parse_integer(data[field], field)
            else:
                result[field] = getattr(existing, field)
    for field in REQUIRED_TEXT_FIELDS:
        if not result[field]:
            raise ValueError(f"{field} must not be blank")
    if result["km_akhir"] < result["km_awal"]:
        raise ValueError("km_akhir must be at least km_awal")
    return result


def receipt_payload(receipt, request=None):
    return {
        "id": receipt.id,
        "report_id": receipt.report_id,
        "filename": receipt.filename,
        "content_type": receipt.content_type,
        "size": receipt.size,
        "url": reverse("receipt-detail", args=[receipt.id]),
    }


def report_payload(report, request=None):
    return {
        "id": report.id,
        "status": report.status,
        "tanggal_buat": report.tanggal_buat.isoformat(),
        "hari_tgl_berangkat": report.hari_tgl_berangkat,
        "jam_berangkat": report.jam_berangkat,
        "hari_tgl_kembali": report.hari_tgl_kembali,
        "no_polisi": report.no_polisi,
        "pengemudi": report.pengemudi,
        "kernet": report.kernet,
        "km_awal": report.km_awal,
        "km_akhir": report.km_akhir,
        "uang_saku": report.uang_saku,
        "bbm": report.bbm,
        "uang_makan": report.uang_makan,
        "extra": report.extra,
        "tagihan": report.tagihan,
        "nama_crew": report.nama_crew,
        "catatan": report.catatan,
        "bus_id": report.bus_id,
        "owner_id": report.owner_id,
        "total_pengeluaran": report.bbm + report.uang_makan + report.extra + report.tagihan,
        "sisa": report.uang_saku - (report.bbm + report.uang_makan + report.extra + report.tagihan),
        "jarak_tempuh": report.km_akhir - report.km_awal,
        "receipts": [receipt_payload(receipt, request) for receipt in report.receipts.order_by("id")],
    }


def _get_report_for_user(request, report_id):
    try:
        report = Report.objects.get(pk=report_id)
    except Report.DoesNotExist:
        return None
    if not is_admin(request.user) and report.owner_id != request.user.id:
        return None
    return report


@api_auth
def reports_view(request):
    if request.method == "GET":
        return _reports_list(request)
    if request.method == "POST":
        return _report_create(request)
    return method_error(("GET", "POST"))


def _filtered_reports(request):
    queryset = Report.objects.all()
    if not is_admin(request.user):
        queryset = queryset.filter(owner=request.user)

    raw_bus_id = request.GET.get("bus_id")
    if raw_bus_id is not None:
        if not re.fullmatch(r"[0-9]+", raw_bus_id):
            raise ValueError("bus_id must be an integer from 1 to 6")
        bus_id = int(raw_bus_id)
        if bus_id < 1 or bus_id > 6:
            raise ValueError("bus_id must be an integer from 1 to 6")
        queryset = queryset.filter(bus_id=bus_id)

    raw_status = request.GET.get("status")
    if raw_status is not None:
        if raw_status not in (Report.STATUS_DRAFT, Report.STATUS_SUBMITTED):
            raise ValueError("status must be draft or submitted")
        queryset = queryset.filter(status=raw_status)

    if request.GET.get("deficit") == "1":
        queryset = queryset.extra(where=["(uang_saku - bbm - uang_makan - extra - tagihan) < 0"])
    return queryset.order_by("-tanggal_buat", "-id")


@api_auth
def _reports_list(request):
    try:
        reports = _filtered_reports(request).prefetch_related("receipts")
    except ValueError as exc:
        return json_error(str(exc))
    return JsonResponse([report_payload(report, request) for report in reports], safe=False)


def _csv_text(value):
    value = "" if value is None else str(value)
    if value.startswith(CSV_FORMULA_PREFIXES):
        return "'" + value
    return value


def _report_csv_row(report):
    total = report.bbm + report.uang_makan + report.extra + report.tagihan
    return [
        report.id,
        report.owner_id,
        _csv_text(report.no_polisi),
        _csv_text(report.pengemudi),
        report.status,
        report.uang_saku,
        total,
        report.uang_saku - total,
        report.km_akhir - report.km_awal,
    ]


@api_admin
def reports_export_view(request):
    if request.method != "GET":
        return method_error(("GET",))
    try:
        reports = _filtered_reports(request)
    except ValueError as exc:
        return json_error(str(exc))

    output = io.StringIO(newline="")
    writer = csv.writer(output, lineterminator="\r\n")
    writer.writerow(REPORT_CSV_COLUMNS)
    for report in reports.iterator():
        writer.writerow(_report_csv_row(report))
    response = HttpResponse(output.getvalue(), content_type="text/csv; charset=utf-8")
    response["Content-Disposition"] = 'attachment; filename="reports.csv"'
    return response


@api_auth
def _report_create(request):
    if request.method != "POST":
        return method_error(("POST",))
    try:
        data = parse_json(request)
        values = _parse_report_values(data)
    except ValueError as exc:
        return json_error(str(exc))
    bus_id = data.get("bus_id")
    if isinstance(bus_id, bool) or not isinstance(bus_id, int) or bus_id < 1 or bus_id > 6:
        return json_error("bus_id must select one of the six buses")
    bus = _fixed_bus(bus_id)
    if bus is None:
        return json_error("Bus not found", 400)
    report = Report.objects.create(owner=request.user, bus=bus, no_polisi=bus.plate, **values)
    return JsonResponse(report_payload(report, request), status=201)


@api_auth
def report_detail_view(request, report_id):
    if request.method not in ("GET", "PATCH", "DELETE"):
        return method_error(("GET", "PATCH", "DELETE"))
    report = _get_report_for_user(request, report_id)
    if report is None:
        return json_error("Report not found", 404)
    if request.method == "GET":
        return JsonResponse(report_payload(report, request))
    filters = {"pk": report_id, "status": Report.STATUS_DRAFT}
    if not is_admin(request.user):
        filters["owner_id"] = request.user.id
    if request.method == "DELETE":
        with transaction.atomic():
            # SQLite does not implement SELECT ... FOR UPDATE. A conditional
            # write takes the database write lock before the cascade begins.
            claimed = Report.objects.filter(**filters).update(status=F("status"))
            if claimed != 1:
                try:
                    current = Report.objects.get(pk=report_id)
                except Report.DoesNotExist:
                    return json_error("Report not found", 404)
                if not is_admin(request.user) and current.owner_id != request.user.id:
                    return json_error("Report not found", 404)
                if current.status != Report.STATUS_DRAFT:
                    return json_error("Submitted reports must be reopened before mutation", 409)
                return json_error("Report not found", 404)
            locked = Report.objects.get(pk=report_id)
            paths = list(locked.receipts.values_list("file", flat=True))
            locked.delete()
        for path in paths:
            if path:
                default_storage.delete(path)
        return HttpResponse(status=204)
    with transaction.atomic():
        # The same conditional write makes the status check and final update
        # one SQLite transaction, including an empty-body PATCH.
        claimed = Report.objects.filter(**filters).update(status=F("status"))
        if claimed != 1:
            try:
                current = Report.objects.get(pk=report_id)
            except Report.DoesNotExist:
                return json_error("Report not found", 404)
            if not is_admin(request.user) and current.owner_id != request.user.id:
                return json_error("Report not found", 404)
            if current.status != Report.STATUS_DRAFT:
                return json_error("Submitted reports must be reopened before mutation", 409)
            return json_error("Report not found", 404)
        locked = Report.objects.get(pk=report_id)
        try:
            data = parse_json(request)
            values = _parse_report_values(data, existing=locked)
        except ValueError as exc:
            return json_error(str(exc))
        updated = Report.objects.filter(
            pk=report_id, status=Report.STATUS_DRAFT
        ).update(**values)
        if updated != 1:
            return json_error("Report not found", 404)
        for field, value in values.items():
            setattr(locked, field, value)
        report = locked
    return JsonResponse(report_payload(report, request))

@api_auth
def report_submit_view(request, report_id):
    if request.method != "POST":
        return method_error(("POST",))
    with transaction.atomic():
        # The conditional write is the SQLite transaction boundary. It takes
        # the write lock before the receipt check, so a concurrent upload or
        # submit cannot pass the check and then change the report underneath it.
        filters = {"pk": report_id, "status": Report.STATUS_DRAFT}
        if not is_admin(request.user):
            filters["owner_id"] = request.user.id
        claimed = Report.objects.filter(**filters).update(status=F("status"))
        if claimed != 1:
            try:
                current = Report.objects.get(pk=report_id)
            except Report.DoesNotExist:
                return json_error("Report not found", 404)
            if not is_admin(request.user) and current.owner_id != request.user.id:
                return json_error("Report not found", 404)
            if current.status != Report.STATUS_DRAFT:
                return json_error("Report is already submitted", 409)
            return json_error("Report not found", 404)
        report = Report.objects.get(pk=report_id)
        if report.bbm > 0 and not Receipt.objects.filter(report_id=report_id).exists():
            return json_error("At least one receipt is required when bbm is greater than zero", 400)
        updated = Report.objects.filter(
            pk=report_id, status=Report.STATUS_DRAFT
        ).update(status=Report.STATUS_SUBMITTED)
        if updated != 1:
            return json_error("Report is already submitted", 409)
        report.status = Report.STATUS_SUBMITTED
    return JsonResponse(report_payload(report, request))

@api_auth
def report_reopen_view(request, report_id):
    if request.method != "POST":
        return method_error(("POST",))
    if not is_admin(request.user):
        try:
            report = Report.objects.get(pk=report_id)
        except Report.DoesNotExist:
            return json_error("Report not found", 404)
        if report.owner_id != request.user.id:
            return json_error("Report not found", 404)
        return json_error("Administrator access required", 403)
    with transaction.atomic():
        # Admin transitions use a conditional write as the state check and
        # mutation, so another SQLite transaction cannot interleave a change.
        updated = Report.objects.filter(
            pk=report_id, status=Report.STATUS_SUBMITTED
        ).update(status=Report.STATUS_DRAFT)
        if updated != 1:
            try:
                report = Report.objects.get(pk=report_id)
            except Report.DoesNotExist:
                return json_error("Report not found", 404)
            return json_error("Report is already a draft", 409)
        report = Report.objects.get(pk=report_id)
    return JsonResponse(report_payload(report, request))


def _authorized_receipt(request, receipt_id):
    try:
        receipt = Receipt.objects.select_related("report").get(pk=receipt_id)
    except Receipt.DoesNotExist:
        return None
    if not is_admin(request.user) and receipt.report.owner_id != request.user.id:
        return None
    return receipt


@api_auth
def receipts_view(request, report_id):
    if request.method != "POST":
        return method_error(("POST",))
    receipt = None
    try:
        with transaction.atomic():
            # Take the SQLite write lock before validating or storing bytes.
            # This serializes an upload with submit/reopen/delete operations.
            claimed = Report.objects.filter(pk=report_id).update(status=F("status"))
            if claimed != 1:
                return json_error("Report not found", 404)
            report = Report.objects.get(pk=report_id)
            if not is_admin(request.user) and report.owner_id != request.user.id:
                return json_error("Report not found", 404)
            if report.status != Report.STATUS_DRAFT:
                return json_error("Submitted reports must be reopened before mutation", 409)
            upload = request.FILES.get("file")
            if upload is None:
                return json_error("A file field is required")
            if upload.size is not None and upload.size > MAX_RECEIPT_SIZE:
                return json_error("Receipt images must be at most 2 MiB")
            try:
                data = upload.read(MAX_RECEIPT_SIZE + 1)
                if len(data) > MAX_RECEIPT_SIZE:
                    raise ValueError("Receipt images must be at most 2 MiB")
                with Image.open(io.BytesIO(data)) as image:
                    image.verify()
                    image_format = image.format
                if image_format not in ("PNG", "JPEG"):
                    raise ValueError("Only PNG and JPEG receipt images are accepted")
            except (ValueError, UnidentifiedImageError, OSError):
                return json_error("Only valid PNG and JPEG receipt images up to 2 MiB are accepted")
            content_type = "image/png" if image_format == "PNG" else "image/jpeg"
            original = re.split(r"[\\/]", str(upload.name or ""))[-1]
            original = "".join(char for char in original if ord(char) >= 32 and char not in "\"\r\n")
            original = original.strip()[:255] or ("receipt.png" if image_format == "PNG" else "receipt.jpg")
            extension = "png" if image_format == "PNG" else "jpg"
            storage_name = f"{uuid.uuid4().hex}.{extension}"
            receipt = Receipt(report=report, filename=original, content_type=content_type, size=len(data))
            receipt.file.save(storage_name, ContentFile(data), save=False)
            receipt.save()
    except Exception:
        if receipt is not None and getattr(receipt.file, "name", None):
            default_storage.delete(receipt.file.name)
        return json_error("Receipt could not be saved")
    return JsonResponse(receipt_payload(receipt, request), status=201)


@api_auth
def receipt_detail_view(request, receipt_id):
    receipt = _authorized_receipt(request, receipt_id)
    if receipt is None:
        return json_error("Receipt not found", 404)
    if request.method == "GET":
        try:
            handle = receipt.file.open("rb")
        except (FileNotFoundError, OSError):
            return json_error("Receipt file not found", 404)
        display_name = re.sub(r"[^A-Za-z0-9._ -]", "_", receipt.filename).strip() or "receipt"
        response = FileResponse(handle, content_type=receipt.content_type)
        response["Content-Disposition"] = f'attachment; filename="{display_name[:200]}"'
        response["X-Content-Type-Options"] = "nosniff"
        return response
    if request.method == "DELETE":
        # Read the relationship before opening the write transaction. The
        # first statement inside the transaction must claim the parent report,
        # so SQLite waits for an existing writer instead of starting a
        # deferred read transaction that cannot be promoted safely.
        parent_id = receipt.report_id
        report_filters = {"pk": parent_id, "status": Report.STATUS_DRAFT}
        if not is_admin(request.user):
            report_filters["owner_id"] = request.user.id
        with transaction.atomic():
            claimed = Report.objects.filter(**report_filters).update(status=F("status"))
            if claimed != 1:
                try:
                    parent = Report.objects.get(pk=parent_id)
                except Report.DoesNotExist:
                    return json_error("Receipt not found", 404)
                if not is_admin(request.user) and parent.owner_id != request.user.id:
                    return json_error("Receipt not found", 404)
                if parent.status != Report.STATUS_DRAFT:
                    return json_error("Submitted reports must be reopened before mutation", 409)
                return json_error("Receipt not found", 404)
            try:
                locked_receipt = Receipt.objects.get(pk=receipt_id)
            except Receipt.DoesNotExist:
                return json_error("Receipt not found", 404)
            if locked_receipt.report_id != parent_id:
                return json_error("Receipt not found", 404)
            path = locked_receipt.file.name
            deleted = Receipt.objects.filter(pk=receipt_id, report_id=parent_id).delete()
            if not deleted[0]:
                return json_error("Receipt not found", 404)
        if path:
            default_storage.delete(path)
        return HttpResponse(status=204)
    return method_error(("GET", "DELETE"))


def index(request):
    if request.method != "GET":
        return method_error(("GET",))
    return render(request, "reports/index.html")
