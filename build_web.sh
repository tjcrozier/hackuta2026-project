#!/bin/sh
# Builds the web dashboard and copies it into the server, so the server can show it at
#   http://<server>:8000/app/#/dashboard   (supervisor dashboard)
#   http://<server>:8000/app/#/rescue      (rescuer link, no login)
# Run this again after changing the app. Restart the server after the first build.
set -e
cd "$(dirname "$0")/app"
# --no-web-resources-cdn: everything is served by our server, so the dashboard also
# works on a router with no internet.
flutter build web --base-href /app/ --no-web-resources-cdn
mkdir -p ../server/static/app
rsync -a --delete build/web/ ../server/static/app/
echo "Done. Web app copied to server/static/app"
