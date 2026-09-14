from django.contrib.auth.models import User
from django.db import models


class Bus(models.Model):
    name = models.CharField(max_length=80)
    plate = models.CharField(max_length=80, unique=True)
    last_oil_change_km = models.PositiveIntegerField(default=0)
    oil_interval_km = models.PositiveIntegerField(default=10000)

    class Meta:
        ordering = ["id"]


class Report(models.Model):
    STATUS_DRAFT = "draft"
    STATUS_SUBMITTED = "submitted"
    STATUS_CHOICES = (
        (STATUS_DRAFT, "Draft"),
        (STATUS_SUBMITTED, "Submitted"),
    )

    owner = models.ForeignKey(User, on_delete=models.CASCADE, related_name="reports")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_DRAFT)
    tanggal_buat = models.DateTimeField(auto_now_add=True)
    hari_tgl_berangkat = models.CharField(max_length=200)
    jam_berangkat = models.CharField(max_length=200)
    hari_tgl_kembali = models.CharField(max_length=200)
    no_polisi = models.CharField(max_length=200)
    pengemudi = models.CharField(max_length=200)
    kernet = models.CharField(max_length=200, blank=True, default="")
    km_awal = models.PositiveIntegerField()
    km_akhir = models.PositiveIntegerField()
    uang_saku = models.PositiveIntegerField()
    bbm = models.PositiveIntegerField()
    uang_makan = models.PositiveIntegerField()
    extra = models.PositiveIntegerField()
    tagihan = models.PositiveIntegerField()
    nama_crew = models.CharField(max_length=200)
    catatan = models.TextField(max_length=4000, blank=True, default="")
    bus = models.ForeignKey(Bus, on_delete=models.PROTECT, related_name="reports")

    class Meta:
        ordering = ["-tanggal_buat", "-id"]


class Receipt(models.Model):
    report = models.ForeignKey(Report, on_delete=models.CASCADE, related_name="receipts")
    file = models.ImageField(upload_to="receipts/")
    filename = models.CharField(max_length=255)
    content_type = models.CharField(max_length=50)
    size = models.PositiveIntegerField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["id"]
