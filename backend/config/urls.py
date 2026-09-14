from django.urls import path
from reports import views

urlpatterns = [
    path("", views.index, name="index"),
    path("api/session/", views.session_view, name="session"),
    path("api/login/", views.login_view, name="login"),
    path("api/logout/", views.logout_view, name="logout"),
    path("api/users/", views.users_view, name="users"),
    path("api/users/<int:user_id>/", views.user_detail_view, name="user-detail"),
    path("api/buses/", views.buses_view, name="buses"),
    path("api/buses/<int:bus_id>/", views.bus_detail_view, name="bus-detail"),
    path("api/buses/<int:bus_id>/oil-change/", views.oil_change_view, name="oil-change"),
    path("api/reports/", views.reports_view, name="reports"),
    path("api/reports/export.csv", views.reports_export_view, name="reports-export"),
    path("api/reports/<int:report_id>/", views.report_detail_view, name="report-detail"),
    path("api/reports/<int:report_id>/submit/", views.report_submit_view, name="report-submit"),
    path("api/reports/<int:report_id>/reopen/", views.report_reopen_view, name="report-reopen"),
    path("api/reports/<int:report_id>/receipts/", views.receipts_view, name="receipts"),
    path("api/receipts/<int:receipt_id>/", views.receipt_detail_view, name="receipt-detail"),
]
