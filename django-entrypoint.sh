#!/usr/bin/env sh
set -e

if [ -z "$APP_MODULE" ]; then
  echo "The \$APP_MODULE environment variable must be set to the WSGI application module name"
  exit 1
fi

# Run the migration as the gunicorn user so that if it creates a local DB (e.g.
# when using sqlite in development), that DB is still writable. Ultimately, the
# user shouldn't really be using a local DB and it's difficult to offer support
# for all the cases in which a local DB might be created -- but here we do the
# minimum.
su-exec gunicorn django-admin migrate --noinput

if [ -z "$SUPERUSER_PASSWORD"]; then
  echo "from django.contrib.auth.models import User
if not User.objects.filter(username='admin').exists():
    User.objects.create_superuser('admin', 'admin@example.com', '$SUPERUSER_PASSWORD')
" | su-exec gunicorn django-admin shell
  echo "Created superuser with username 'admin' and password '$SUPERUSER_PASSWORD'"
fi

nginx

# umask working files (worker tmp files & unix socket) as 0o117 (i.e. chmod as
# 0o660) so that they are only read/writable by gunicorn and nginx users.
# FIXME: Have to specify umask as decimal, not octal (0o117 = 79):
# https://github.com/benoitc/gunicorn/issues/1325
exec gunicorn "$APP_MODULE" \
  --user gunicorn --group gunicorn --umask 79 \
  --bind unix:/var/run/gunicorn/gunicorn.sock \
  ${GUNICORN_ACCESS_LOGS:+--access-logfile -} \
  "$@"
