import sys
import time
import uuid
import jwt
import requests

def main():
    if len(sys.argv) < 5:
        print("Usage: python publish_firefox.py <addon_id> <xpi_path> <jwt_issuer> <jwt_secret>")
        sys.exit(1)

    addon_id = sys.argv[1]
    xpi_path = sys.argv[2]
    issuer = sys.argv[3]
    secret = sys.argv[4]

    def get_headers():
        iat = int(time.time())
        payload = {
            "iss": issuer,
            "jti": str(uuid.uuid4()),
            "iat": iat,
            "exp": iat + 300
        }
        token = jwt.encode(payload, secret, algorithm="HS256")
        return {"Authorization": f"JWT {token}"}

    print("Uploading addon package...")
    upload_url = "https://addons.mozilla.org/api/v5/addons/upload/"
    with open(xpi_path, "rb") as f:
        files = {"upload": f}
        data = {"channel": "listed"}
        response = requests.post(upload_url, headers=get_headers(), files=files, data=data)

    if response.status_code not in (201, 202):
        print(f"Upload failed ({response.status_code}): {response.text}")
        sys.exit(1)

    upload_data = response.json()
    upload_uuid = upload_data["uuid"]
    print(f"Uploaded successfully. UUID: {upload_uuid}")

    status_url = f"https://addons.mozilla.org/api/v5/addons/upload/{upload_uuid}/"
    timeout = 600
    interval = 10
    elapsed = 0

    print("Waiting for validation to complete...")
    while elapsed < timeout:
        status_resp = requests.get(status_url, headers=get_headers())
        if status_resp.status_code == 200:
            status_data = status_resp.json()
            if status_data.get("processed"):
                if status_data.get("valid"):
                    print("Validation successful!")
                    break
                else:
                    print(f"Validation failed: {status_data.get('validation')}")
                    sys.exit(1)
        else:
            print(f"Failed to check status ({status_resp.status_code}): {status_resp.text}")

        time.sleep(interval)
        elapsed += interval
    else:
        print("Timeout waiting for validation.")
        sys.exit(1)

    print("Creating new version...")
    version_url = f"https://addons.mozilla.org/api/v5/addons/addon/{addon_id}/versions/"
    payload = {"upload": upload_uuid}
    version_resp = requests.post(version_url, headers=get_headers(), json=payload)

    if version_resp.status_code == 201:
        print("Successfully published Firefox Add-on version!")
        print(version_resp.json())
    else:
        resp_text = version_resp.text
        if "already exists" in resp_text or version_resp.status_code == 409:
            print("Version already exists on Firefox Add-ons. Skipping gracefully.")
            sys.exit(0)
        print(f"Failed to create version ({version_resp.status_code}): {resp_text}")
        sys.exit(1)

if __name__ == "__main__":
    main()
