import os

from django.contrib.auth.models import User
from django.core.management.base import BaseCommand, CommandError
from reports.models import Bus


class Command(BaseCommand):
    help = "Create an administrator and initialize the six fixed bus slots."

    def add_arguments(self, parser):
        parser.add_argument("--username", required=True)

    def handle(self, *args, **options):
        username = options["username"].strip()
        password = os.environ.get("HAPPYBUS_ADMIN_PASSWORD")
        if not password:
            raise CommandError("HAPPYBUS_ADMIN_PASSWORD must be set")
        if len(password) < 10:
            raise CommandError("New passwords must be at least 10 characters")
        if not username:
            raise CommandError("Username must not be empty")
        user, created = User.objects.get_or_create(username=username, defaults={"is_staff": True, "is_superuser": True})
        if created:
            user.set_password(password)
            user.save(update_fields=["password"])
            self.stdout.write(self.style.SUCCESS(f"Created admin {username}"))
        else:
            if not user.is_staff or not user.is_superuser:
                user.is_staff = True
                user.is_superuser = True
                user.save(update_fields=["is_staff", "is_superuser"])
            self.stdout.write(f"Admin {username} already exists; password and data were preserved")
        for slot in range(1, 7):
            Bus.objects.get_or_create(
                id=slot,
                defaults={"name": f"Bus {slot}", "plate": f"BUS-{slot}", "last_oil_change_km": 0, "oil_interval_km": 10000},
            )
        self.stdout.write("Six bus slots are ready")
