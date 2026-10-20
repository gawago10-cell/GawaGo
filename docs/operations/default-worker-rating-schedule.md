# Default Worker Rating Schedule

The Django command below assigns the documented default 3.5-star rating when a household has not reviewed a completed worker service after 72 hours:

```powershell
python manage.py assign_default_worker_ratings --after-hours 72
```

For the Windows development or demonstration server, install the hourly scheduled task once:

```powershell
.\scripts\install_default_rating_task.ps1 -AfterHours 72
```

The command is idempotent: it does not create a second default rating when a household review already exists.
