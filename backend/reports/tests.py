import csv
import io
import json
import shutil
import sqlite3
import tempfile
import threading
import time
from pathlib import Path

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import connection
from django.db.migrations.executor import MigrationExecutor
from django.test import Client, TestCase, TransactionTestCase, override_settings
from PIL import Image

from .models import Bus, Receipt, Report

User = get_user_model()


class ReportStatusMigrationTest(TransactionTestCase):
    migrate_from = ("reports", "0001_initial")
    migrate_to = ("reports", "0002_report_status")

    def setUp(self):
        executor = MigrationExecutor(connection)
        executor.migrate([self.migrate_from])
        old_apps = executor.loader.project_state([self.migrate_from]).apps
        old_user = old_apps.get_model("auth", "User")
        old_bus = old_apps.get_model("reports", "Bus")
        old_report = old_apps.get_model("reports", "Report")
        owner = old_user.objects.create_user(username="legacy", password="legacy-password")
        bus = old_bus.objects.create(id=1, name="Bus 1", plate="BUS-1")
        self.report_id = old_report.objects.create(
            owner=owner,
            bus=bus,
            no_polisi="BUS-1",
            hari_tgl_berangkat="Senin",
            jam_berangkat="08:00",
            hari_tgl_kembali="Selasa",
            pengemudi="Sopir",
            km_awal=0,
            km_akhir=1,
            uang_saku=0,
            bbm=0,
            uang_makan=0,
            extra=0,
            tagihan=0,
            nama_crew="Crew",
        ).pk
        executor = MigrationExecutor(connection)
        executor.migrate([self.migrate_to])
        self.new_apps = executor.loader.project_state([self.migrate_to]).apps

    def test_existing_report_gets_draft_status(self):
        report = self.new_apps.get_model("reports", "Report").objects.get(pk=self.report_id)
        self.assertEqual(report.status, "draft")


class ReceiptDeleteConcurrencyTest(TransactionTestCase):
    """Exercise receipt deletion against a real SQLite writer on another connection."""

    reset_sequences = True

    def setUp(self):
        self.media_root = Path(tempfile.mkdtemp())
        self.override = override_settings(MEDIA_ROOT=self.media_root)
        self.override.enable()
        self.addCleanup(self.override.disable)
        self.addCleanup(lambda: shutil.rmtree(self.media_root, ignore_errors=True))
        self.owner = User.objects.create_user("receipt_owner", password="owner-password-123")
        self.bus = Bus.objects.create(id=1, name="Bus 1", plate="BUS-1")
        self.report = Report.objects.create(
            owner=self.owner,
            bus=self.bus,
            no_polisi=self.bus.plate,
            hari_tgl_berangkat="Senin",
            jam_berangkat="08:00",
            hari_tgl_kembali="Selasa",
            pengemudi="Sopir",
            km_awal=0,
            km_akhir=1,
            uang_saku=0,
            bbm=0,
            uang_makan=0,
            extra=0,
            tagihan=0,
            nama_crew="Crew",
        )
        self.client = Client()
        self.client.force_login(self.owner)
        uploaded = self.client.post(
            f"/api/reports/{self.report.id}/receipts/",
            {"file": self.png_upload()},
        )
        self.assertEqual(uploaded.status_code, 201, uploaded.content)
        self.receipt_id = uploaded.json()["id"]
        self.receipt = Receipt.objects.get(pk=self.receipt_id)
        self.saved_path = Path(self.receipt.file.path)

    def png_upload(self):
        buffer = io.BytesIO()
        Image.new("RGB", (2, 2), "red").save(buffer, format="PNG")
        return SimpleUploadedFile("receipt.png", buffer.getvalue(), content_type="image/png")

    def test_delete_waits_for_file_backed_sqlite_writer_before_claiming(self):
        database_name = connection.settings_dict["NAME"]
        self.assertNotEqual(database_name, ":memory:")
        self.assertTrue(Path(database_name).exists())
        blocker = sqlite3.connect(database_name, timeout=5, isolation_level=None)
        self.addCleanup(blocker.close)
        blocker.execute("PRAGMA busy_timeout = 5000")
        blocker.execute("BEGIN IMMEDIATE")
        blocker.execute(
            "UPDATE reports_report SET status = status WHERE id = ?",
            (self.report.id,),
        )

        started = threading.Event()
        result = {}

        def delete_receipt():
            started.set()
            client = Client()
            client.cookies = self.client.cookies.copy()
            result["response"] = client.delete(f"/api/receipts/{self.receipt_id}/")

        worker = threading.Thread(target=delete_receipt)
        worker.start()
        self.assertTrue(started.wait(1))
        time.sleep(0.3)
        self.assertTrue(worker.is_alive(), "receipt deletion must wait for the existing writer")
        blocker.commit()
        worker.join(5)
        self.assertFalse(worker.is_alive(), "receipt deletion did not finish after the writer committed")
        response = result["response"]
        self.assertEqual(response.status_code, 204, response.content)
        self.assertFalse(Receipt.objects.filter(pk=self.receipt_id).exists())
        self.assertFalse(self.saved_path.exists())


class HappyBusAPITestCase(TestCase):
    def setUp(self):
        self.media_root = Path(tempfile.mkdtemp())
        self.override = override_settings(MEDIA_ROOT=self.media_root)
        self.override.enable()
        self.addCleanup(self.override.disable)
        self.addCleanup(lambda: shutil.rmtree(self.media_root, ignore_errors=True))
        self.admin = User.objects.create_user("admin", password="admin-password-123", is_staff=True, is_superuser=True)
        self.crew_a = User.objects.create_user("crew_a", password="crew-password-123")
        self.crew_b = User.objects.create_user("crew_b", password="crew-password-123")
        for number in range(1, 7):
            Bus.objects.create(id=number, name=f"Bus {number}", plate=f"BUS-{number}")
        self.client = Client(enforce_csrf_checks=True)

    def json(self, path, method="get", data=None, client=None, **kwargs):
        client = client or self.client
        body = json.dumps(data) if data is not None else None
        return getattr(client, method)(path, data=body, content_type="application/json", **kwargs)

    def login(self, user, client=None):
        client = client or self.client
        session = client.get("/api/session/")
        token = session.json()["csrf_token"]
        response = self.json(
            "/api/login/",
            "post",
            {"username": user.username, "password": "admin-password-123" if user == self.admin else "crew-password-123"},
            client=client,
            HTTP_X_CSRFTOKEN=token,
        )
        self.assertEqual(response.status_code, 200, response.content)
        return response

    def create_report(self, client=None, **overrides):
        values = {
            "bus_id": 1,
            "hari_tgl_berangkat": "Senin, 01/01/2024",
            "jam_berangkat": "08:00",
            "hari_tgl_kembali": "Selasa, 02/01/2024",
            "pengemudi": "Sopir",
            "kernet": "Kernet",
            "nama_crew": "Crew",
            "km_awal": 100,
            "km_akhir": 250,
            "uang_saku": 1000,
            "bbm": 100,
            "uang_makan": 200,
            "extra": 50,
            "tagihan": 25,
            "catatan": "Catatan",
        }
        values.update(overrides)
        token = (client or self.client).get("/api/session/").json()["csrf_token"]
        return self.json("/api/reports/", "post", values, client=client, HTTP_X_CSRFTOKEN=token)

    def stored_report(self, owner, bus_id=1, status=Report.STATUS_DRAFT, **overrides):
        bus = Bus.objects.get(pk=bus_id)
        values = {
            "owner": owner,
            "bus": bus,
            "status": status,
            "no_polisi": bus.plate,
            "hari_tgl_berangkat": "Senin, 01/01/2024",
            "jam_berangkat": "08:00",
            "hari_tgl_kembali": "Selasa, 02/01/2024",
            "pengemudi": "Sopir",
            "kernet": "Kernet",
            "km_awal": 100,
            "km_akhir": 250,
            "uang_saku": 1000,
            "bbm": 100,
            "uang_makan": 200,
            "extra": 50,
            "tagihan": 25,
            "nama_crew": "Crew",
            "catatan": "Catatan",
        }
        values.update(overrides)
        return Report.objects.create(**values)

    def test_session_and_login_require_csrf_and_refresh_session(self):
        response = self.client.get("/api/session/")
        self.assertIsNone(response.json()["user"])
        self.assertTrue(response.json()["csrf_token"])
        self.assertIn("csrftoken", response.cookies)
        missing_csrf = self.json("/api/login/", "post", {"username": "admin", "password": "admin-password-123"})
        self.assertEqual(missing_csrf.status_code, 403)
        logged_in = self.login(self.admin)
        self.assertEqual(logged_in.json()["user"]["role"], "admin")
        self.assertNotIn("password", logged_in.json())
        self.assertTrue(logged_in.json()["csrf_token"])

    def test_crew_isolation_and_admin_access(self):
        crew_client = Client(enforce_csrf_checks=True)
        self.login(self.crew_a, crew_client)
        created = self.create_report(crew_client)
        self.assertEqual(created.status_code, 201)
        report_id = created.json()["id"]
        other_client = Client(enforce_csrf_checks=True)
        self.login(self.crew_b, other_client)
        self.assertEqual(self.json(f"/api/reports/{report_id}/", client=other_client).status_code, 404)
        self.assertEqual(self.json("/api/reports/", client=other_client).json(), [])
        self.assertEqual(self.json("/api/users/", client=other_client).status_code, 403)
        admin_client = Client(enforce_csrf_checks=True)
        self.login(self.admin, admin_client)
        self.assertEqual(len(self.json("/api/reports/", client=admin_client).json()), 1)
        self.assertEqual(self.json(f"/api/reports/{report_id}/", "patch", {"pengemudi": "Admin edit"}, client=admin_client, HTTP_X_CSRFTOKEN=admin_client.get("/api/session/").json()["csrf_token"]).status_code, 200)
        self.assertEqual(Report.objects.get(pk=report_id).owner_id, self.crew_a.id)

    def test_report_calculations_identity_and_atomic_partial_update(self):
        self.login(self.crew_a)
        created = self.create_report(no_polisi="FORGED", owner_id=999, tanggal_buat="bad", total_pengeluaran=1)
        self.assertEqual(created.status_code, 201)
        body = created.json()
        self.assertEqual(body["no_polisi"], "BUS-1")
        self.assertEqual(body["owner_id"], self.crew_a.id)
        self.assertEqual(body["total_pengeluaran"], 375)
        self.assertEqual(body["sisa"], 625)
        self.assertEqual(body["jarak_tempuh"], 150)
        old = Report.objects.get(pk=body["id"])
        token = self.client.get("/api/session/").json()["csrf_token"]
        invalid = self.json(f"/api/reports/{old.id}/", "patch", {"km_awal": 500, "km_akhir": 200}, HTTP_X_CSRFTOKEN=token)
        self.assertEqual(invalid.status_code, 400)
        old.refresh_from_db()
        self.assertEqual((old.km_awal, old.km_akhir), (100, 250))
        valid = self.json(f"/api/reports/{old.id}/", "patch", {"km_awal": 200}, HTTP_X_CSRFTOKEN=token)
        self.assertEqual(valid.status_code, 200)
        self.assertEqual(valid.json()["jarak_tempuh"], 50)

    def test_bus_mileage_and_maintenance_thresholds(self):
        self.login(self.crew_a)
        self.create_report(km_awal=0, km_akhir=9000)
        buses = self.json("/api/buses/").json()
        bus = buses[0]
        self.assertEqual(bus["current_km"], 9000)
        self.assertEqual(bus["maintenance_status"], "soon")
        admin_client = Client(enforce_csrf_checks=True)
        self.login(self.admin, admin_client)
        token = admin_client.get("/api/session/").json()["csrf_token"]
        response = self.json("/api/buses/1/oil-change/", "post", {"km": 7000}, client=admin_client, HTTP_X_CSRFTOKEN=token)
        self.assertEqual(response.json()["maintenance_status"], "healthy")
        self.create_report(km_awal=9000, km_akhir=10000)
        response = self.json("/api/buses/1/oil-change/", "post", {"km": 0}, client=admin_client, HTTP_X_CSRFTOKEN=token)
        self.assertEqual(response.json()["maintenance_status"], "due")
        self.assertEqual(self.json("/api/buses/1/", "patch", {"name": "Renamed", "plate": "new-plate"}, client=admin_client, HTTP_X_CSRFTOKEN=token).status_code, 200)
        self.assertTrue(Report.objects.filter(no_polisi="BUS-1").exists())

    def png_upload(self, name="receipt.png"):
        buffer = io.BytesIO()
        Image.new("RGB", (2, 2), "red").save(buffer, format="PNG")
        return SimpleUploadedFile(name, buffer.getvalue(), content_type="application/octet-stream")

    def test_private_receipt_validation_authorization_and_cleanup(self):
        self.login(self.crew_a)
        report_id = self.create_report().json()["id"]
        token = self.client.get("/api/session/").json()["csrf_token"]
        uploaded = self.client.post(f"/api/reports/{report_id}/receipts/", {"file": self.png_upload("../../unsafe.png")}, HTTP_X_CSRFTOKEN=token)
        self.assertEqual(uploaded.status_code, 201)
        receipt_id = uploaded.json()["id"]
        receipt = Receipt.objects.get(pk=receipt_id)
        saved_path = Path(receipt.file.path)
        self.assertNotIn("unsafe", receipt.file.name)
        self.assertTrue(saved_path.exists())
        self.assertEqual(self.client.get(f"/api/receipts/{receipt_id}/").headers["Content-Type"], "image/png")
        other_client = Client(enforce_csrf_checks=True)
        self.login(self.crew_b, other_client)
        self.assertEqual(other_client.get(f"/api/receipts/{receipt_id}/").status_code, 404)
        self.assertEqual(self.client.delete(f"/api/receipts/{receipt_id}/", HTTP_X_CSRFTOKEN=token).status_code, 204)
        self.assertFalse(saved_path.exists())
        self.assertFalse(Receipt.objects.filter(pk=receipt_id).exists())
        invalid = self.client.post(f"/api/reports/{report_id}/receipts/", {"file": SimpleUploadedFile("not.png", b"not an image", content_type="image/png")}, HTTP_X_CSRFTOKEN=token)
        self.assertEqual(invalid.status_code, 400)
        self.assertFalse(Receipt.objects.filter(report_id=report_id).exists())

    def test_deactivation_blocks_login_and_existing_session(self):
        crew_client = Client(enforce_csrf_checks=True)
        self.login(self.crew_a, crew_client)
        admin_client = Client(enforce_csrf_checks=True)
        self.login(self.admin, admin_client)
        token = admin_client.get("/api/session/").json()["csrf_token"]
        response = self.json(f"/api/users/{self.crew_a.id}/", "patch", {"is_active": False}, client=admin_client, HTTP_X_CSRFTOKEN=token)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(crew_client.get("/api/reports/").status_code, 401)
        fresh = Client(enforce_csrf_checks=True)
        fresh_token = fresh.get("/api/session/").json()["csrf_token"]
        blocked = self.json("/api/login/", "post", {"username": self.crew_a.username, "password": "crew-password-123"}, client=fresh, HTTP_X_CSRFTOKEN=fresh_token)
        self.assertEqual(blocked.status_code, 401)

    def test_admin_can_create_crew_and_duplicate_username_is_conflict(self):
        self.login(self.admin)
        token = self.client.get("/api/session/").json()["csrf_token"]
        created = self.json("/api/users/", "post", {"username": "new crew", "password": "valid-password-123"}, HTTP_X_CSRFTOKEN=token)
        self.assertEqual(created.status_code, 400)
        created = self.json("/api/users/", "post", {"username": "new_crew", "password": "valid-password-123"}, HTTP_X_CSRFTOKEN=token)
        self.assertEqual(created.status_code, 201)
        duplicate = self.json("/api/users/", "post", {"username": "new_crew", "password": "different-password"}, HTTP_X_CSRFTOKEN=token)
        self.assertEqual(duplicate.status_code, 409)
        self.assertEqual(created.json()["role"], "crew")

    def test_report_submission_requires_receipt_and_locks_every_mutation(self):
        self.login(self.crew_a)
        report_id = self.create_report().json()["id"]
        token = self.client.get("/api/session/").json()["csrf_token"]
        submit = self.json(f"/api/reports/{report_id}/submit/", "post", {}, HTTP_X_CSRFTOKEN=token)
        self.assertEqual(submit.status_code, 400)
        self.assertEqual(Report.objects.get(pk=report_id).status, Report.STATUS_DRAFT)

        upload = self.client.post(
            f"/api/reports/{report_id}/receipts/",
            {"file": self.png_upload()},
            HTTP_X_CSRFTOKEN=token,
        )
        self.assertEqual(upload.status_code, 201)
        receipt_id = upload.json()["id"]
        submitted = self.json(f"/api/reports/{report_id}/submit/", "post", {}, HTTP_X_CSRFTOKEN=token)
        self.assertEqual(submitted.status_code, 200)
        self.assertEqual(submitted.json()["status"], Report.STATUS_SUBMITTED)
        for method, path, data in (
            ("patch", f"/api/reports/{report_id}/", {}),
            ("delete", f"/api/reports/{report_id}/", None),
        ):
            response = self.json(path, method, data, HTTP_X_CSRFTOKEN=token)
            self.assertEqual(response.status_code, 409)
        self.assertEqual(
            self.client.post(
                f"/api/reports/{report_id}/receipts/",
                {"file": self.png_upload("locked.png")},
                HTTP_X_CSRFTOKEN=token,
            ).status_code,
            409,
        )
        self.assertEqual(self.client.delete(f"/api/receipts/{receipt_id}/", HTTP_X_CSRFTOKEN=token).status_code, 409)
        self.assertTrue(Receipt.objects.filter(pk=receipt_id).exists())
        self.assertEqual(Report.objects.get(pk=report_id).status, Report.STATUS_SUBMITTED)

    def test_submission_zero_bbm_and_reopen_authorization(self):
        crew_client = Client(enforce_csrf_checks=True)
        self.login(self.crew_a, crew_client)
        report_id = self.create_report(crew_client, bbm=0).json()["id"]
        token = crew_client.get("/api/session/").json()["csrf_token"]
        self.assertEqual(self.json(f"/api/reports/{report_id}/submit/", "post", {}, client=crew_client, HTTP_X_CSRFTOKEN=token).status_code, 200)
        self.assertEqual(self.json(f"/api/reports/{report_id}/reopen/", "post", {}, client=crew_client, HTTP_X_CSRFTOKEN=token).status_code, 403)
        other = Client(enforce_csrf_checks=True)
        self.login(self.crew_b, other)
        other_token = other.get("/api/session/").json()["csrf_token"]
        self.assertEqual(self.json(f"/api/reports/{report_id}/reopen/", "post", {}, client=other, HTTP_X_CSRFTOKEN=other_token).status_code, 404)
        admin = Client(enforce_csrf_checks=True)
        self.login(self.admin, admin)
        admin_token = admin.get("/api/session/").json()["csrf_token"]
        reopened = self.json(f"/api/reports/{report_id}/reopen/", "post", {}, client=admin, HTTP_X_CSRFTOKEN=admin_token)
        self.assertEqual(reopened.status_code, 200)
        self.assertEqual(reopened.json()["status"], Report.STATUS_DRAFT)
        self.assertEqual(self.json(f"/api/reports/{report_id}/reopen/", "post", {}, client=admin, HTTP_X_CSRFTOKEN=admin_token).status_code, 409)

    def test_existing_report_migrates_as_draft(self):
        report = Report.objects.create(
            owner=self.crew_a,
            bus=Bus.objects.get(pk=1),
            no_polisi="BUS-1",
            hari_tgl_berangkat="Senin",
            jam_berangkat="08:00",
            hari_tgl_kembali="Selasa",
            pengemudi="Sopir",
            km_awal=0,
            km_akhir=1,
            uang_saku=0,
            bbm=0,
            uang_makan=0,
            extra=0,
            tagihan=0,
            nama_crew="Crew",
        )
        self.assertEqual(report.status, Report.STATUS_DRAFT)

    def test_ui_and_api_routes_are_available(self):
        page = self.client.get("/")
        self.assertEqual(page.status_code, 200)
        self.assertContains(page, "Happy Bus")
        self.assertContains(page, "Status")
        self.assertContains(page, "Kirim laporan")
        self.assertContains(page, "Buka kembali")
        self.assertContains(page, "Unduh CSV akuntansi")
        self.assertEqual(self.client.get("/api/reports/").status_code, 401)
        self.assertEqual(self.client.get("/api/logout/").status_code, 405)

    def test_report_status_filters_validate_and_export_is_admin_only(self):
        self.assertEqual(self.client.get("/api/reports/export.csv").status_code, 401)
        crew_client = Client(enforce_csrf_checks=True)
        self.login(self.crew_a, crew_client)
        self.assertEqual(crew_client.get("/api/reports/export.csv").status_code, 403)
        self.assertEqual(self.json("/api/reports/?status=unknown", client=crew_client).status_code, 400)
        self.assertEqual(self.json("/api/reports/?bus_id=0", client=crew_client).status_code, 400)

        admin_client = Client(enforce_csrf_checks=True)
        self.login(self.admin, admin_client)
        draft = self.stored_report(self.crew_a, bus_id=1, status=Report.STATUS_DRAFT)
        submitted = self.stored_report(
            self.crew_b,
            bus_id=2,
            status=Report.STATUS_SUBMITTED,
            uang_saku=10,
            bbm=20,
            uang_makan=0,
            extra=0,
            tagihan=0,
        )
        self.assertEqual([item["id"] for item in self.json("/api/reports/?status=draft", client=admin_client).json()], [draft.id])
        self.assertEqual([item["id"] for item in self.json("/api/reports/?status=submitted", client=admin_client).json()], [submitted.id])
        self.assertEqual(
            self.json("/api/reports/?bus_id=2&deficit=1&status=submitted", client=admin_client).json()[0]["id"],
            submitted.id,
        )
        self.assertEqual(self.json("/api/reports/?bus_id=6&deficit=1&status=submitted", client=admin_client).json(), [])
        self.assertEqual(self.json("/api/reports/?status=", client=admin_client).status_code, 400)
        invalid_export = admin_client.get("/api/reports/export.csv?bus_id=nope")
        self.assertEqual(invalid_export.status_code, 400)
        self.assertEqual(invalid_export.json()["error"], "bus_id must be an integer from 1 to 6")

    def test_accounting_export_matches_json_and_preserves_data(self):
        self.login(self.admin)
        first = self.stored_report(
            self.crew_a,
            bus_id=1,
            no_polisi='=BUS,"satu"\nnext-é',
            pengemudi='@Driver, "quoted"\r\nsecond',
        )
        second = self.stored_report(
            self.crew_b,
            bus_id=2,
            status=Report.STATUS_SUBMITTED,
            no_polisi="-TEXT",
            pengemudi="+Crew",
            uang_saku=10,
            bbm=20,
            uang_makan=3,
            extra=4,
            tagihan=5,
            km_awal=10,
            km_akhir=17,
        )
        third = self.stored_report(
            self.crew_a,
            bus_id=1,
            no_polisi="@another",
            pengemudi="normal",
            uang_saku=5,
            bbm=0,
            uang_makan=0,
            extra=0,
            tagihan=0,
        )
        before = self.json("/api/reports/", client=self.client).json()
        exported = self.client.get("/api/reports/export.csv")
        self.assertEqual(exported.status_code, 200)
        self.assertEqual(exported.headers["Content-Type"], "text/csv; charset=utf-8")
        self.assertIn("attachment;", exported.headers["Content-Disposition"])
        rows = list(csv.DictReader(io.StringIO(exported.content.decode("utf-8"))))
        self.assertEqual(rows[0].keys().__iter__().__next__(), "id")
        self.assertEqual(list(rows[0]), [
            "id", "owner_id", "no_polisi", "pengemudi", "status", "uang_saku",
            "total_pengeluaran", "sisa", "jarak_tempuh",
        ])
        self.assertEqual([int(row["id"]) for row in rows], [third.id, second.id, first.id])
        expected_json = {item["id"]: item for item in before}
        for row in rows:
            item = expected_json[int(row["id"])]
            self.assertEqual(int(row["owner_id"]), item["owner_id"])
            self.assertEqual(int(row["uang_saku"]), item["uang_saku"])
            self.assertEqual(int(row["total_pengeluaran"]), item["total_pengeluaran"])
            self.assertEqual(int(row["sisa"]), item["sisa"])
            self.assertEqual(int(row["jarak_tempuh"]), item["jarak_tempuh"])
        self.assertEqual(rows[2]["no_polisi"], "'=BUS,\"satu\"\nnext-é")
        self.assertEqual(rows[2]["pengemudi"], "'@Driver, \"quoted\"\r\nsecond")
        self.assertEqual(rows[1]["sisa"], "-22")
        self.assertEqual(self.json("/api/reports/", client=self.client).json(), before)
        first.refresh_from_db()
        self.assertEqual(first.no_polisi, '=BUS,"satu"\nnext-é')
        self.assertEqual(first.pengemudi, '@Driver, "quoted"\r\nsecond')
        self.assertEqual(first.status, Report.STATUS_DRAFT)
