import urllib.request
import urllib.parse
import json
import os
from datetime import datetime, timedelta, timezone

email = os.environ.get("EVENTSPHERE_TEST_EMAIL")
password = os.environ.get("EVENTSPHERE_TEST_PASSWORD")
if not email or not password:
    raise SystemExit(
        "Set EVENTSPHERE_TEST_EMAIL and EVENTSPHERE_TEST_PASSWORD before running this helper."
    )

base_url = os.environ.get("EVENTSPHERE_API_URL", "http://localhost:8001/api/v1")
url = f"{base_url}/auth/login"
data = json.dumps({
    "email": email,
    "password": password,
}).encode('utf-8')
req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
try:
    with urllib.request.urlopen(req) as res:
        token = json.loads(res.read().decode())["data"]["accessToken"]
except urllib.error.HTTPError as e:
    print("Login failed", e.code)
    print(e.read().decode())
    exit(1)

url2 = f"{base_url}/admin/events"
event_start = datetime.now(timezone.utc) + timedelta(days=30)
event_data = {
    "name": "Test Event",
    "description": "Test Description",
    "category": "conference",
    "location": "Test Location",
    "eventDate": event_start.isoformat(),
    "eventEndDate": (event_start + timedelta(hours=2)).isoformat(),
    "registrationDeadline": (event_start - timedelta(days=1)).isoformat(),
    "capacity": 100,
    "isPrivate": False
}
req2 = urllib.request.Request(url2, data=json.dumps(event_data).encode('utf-8'), headers={
    "Content-Type": "application/json",
    "Authorization": f"Bearer {token}"
})
try:
    with urllib.request.urlopen(req2) as res2:
        print(res2.status)
        print(res2.read().decode())
except urllib.error.HTTPError as e:
    print(e.code)
    print(e.read().decode())
