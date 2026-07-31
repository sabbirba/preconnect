const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

function generateJWT(issuer, secret) {
  const header = { alg: "HS256", typ: "JWT" };
  const iat = Math.floor(Date.now() / 1000);
  const payload = {
    iss: issuer,
    jti: crypto.randomUUID(),
    iat: iat,
    exp: iat + 300,
  };

  const base64UrlEncode = (obj) => {
    return Buffer.from(JSON.stringify(obj)).toString("base64url");
  };

  const headerPart = base64UrlEncode(header);
  const payloadPart = base64UrlEncode(payload);

  const signature = crypto
    .createHmac("sha256", secret)
    .update(`${headerPart}.${payloadPart}`)
    .digest("base64url");

  return `${headerPart}.${payloadPart}.${signature}`;
}

async function main() {
  const [, , addonId, xpiPath, issuer, secret] = process.argv;
  if (!addonId || !xpiPath || !issuer || !secret) {
    console.error(
      "Usage: node publish_firefox.js <addon_id> <xpi_path> <jwt_issuer> <jwt_secret>",
    );
    process.exit(1);
  }

  const token = generateJWT(issuer, secret);
  const authHeader = `JWT ${token}`;

  console.log("Uploading addon package...");
  const formData = new FormData();
  formData.append("channel", "listed");

  const fileBuffer = fs.readFileSync(xpiPath);
  const fileBlob = new Blob([fileBuffer], { type: "application/zip" });
  formData.append("upload", fileBlob, "extension.zip");

  const uploadResp = await fetch(
    "https://addons.mozilla.org/api/v5/addons/upload/",
    {
      method: "POST",
      headers: {
        Authorization: authHeader,
      },
      body: formData,
    },
  );

  const uploadData = await uploadResp.json();
  if (!uploadResp.ok) {
    console.error(
      `Upload failed (${uploadResp.status}):`,
      JSON.stringify(uploadData),
    );
    process.exit(1);
  }

  const uploadUuid = uploadData.uuid;
  console.log(`Uploaded successfully. UUID: ${uploadUuid}`);

  const statusUrl = `https://addons.mozilla.org/api/v5/addons/upload/${uploadUuid}/`;
  const timeout = 600000;
  const interval = 10000;
  const startTime = Date.now();

  console.log("Waiting for validation to complete...");
  while (Date.now() - startTime < timeout) {
    const freshToken = generateJWT(issuer, secret);
    const statusResp = await fetch(statusUrl, {
      headers: { Authorization: `JWT ${freshToken}` },
    });

    if (statusResp.ok) {
      const statusData = await statusResp.json();
      if (statusData.processed) {
        if (statusData.valid) {
          console.log("Validation successful!");
          break;
        } else {
          console.error(
            "Validation failed:",
            JSON.stringify(statusData.validation),
          );
          process.exit(1);
        }
      }
    } else {
      console.error(
        `Failed to check status (${statusResp.status}):`,
        await statusResp.text(),
      );
    }
    await new Promise((resolve) => setTimeout(resolve, interval));
  }

  if (Date.now() - startTime >= timeout) {
    console.error("Timeout waiting for validation.");
    process.exit(1);
  }

  console.log("Creating new version...");
  let releaseNotes =
    "We update PreConnect regularly to make your academic experience smoother and faster. This release includes performance improvements, bug fixes, and general stability enhancements.";
  const notesPath = path.join(
    __dirname,
    "..",
    "ios",
    "fastlane",
    "metadata",
    "en-US",
    "release_notes.txt",
  );
  if (fs.existsSync(notesPath)) {
    const rawNotes = fs.readFileSync(notesPath, "utf8").trim();
    if (rawNotes.length > 0) {
      releaseNotes = rawNotes;
    }
  }

  const versionUrl = `https://addons.mozilla.org/api/v5/addons/addon/${addonId}/versions/`;
  const freshToken = generateJWT(issuer, secret);
  const versionResp = await fetch(versionUrl, {
    method: "POST",
    headers: {
      Authorization: `JWT ${freshToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      upload: uploadUuid,
      release_notes: {
        "en-US": releaseNotes,
      },
    }),
  });

  const versionData = await versionResp.json();
  if (versionResp.status === 201) {
    console.log("Successfully published Firefox Add-on version!");
    console.log(JSON.stringify(versionData));
  } else if (
    versionResp.status === 409 ||
    JSON.stringify(versionData).includes("already exists")
  ) {
    console.log(
      `Version already exists on Firefox Add-ons (Status: ${versionResp.status}, Response: ${JSON.stringify(versionData)}). Skipping gracefully.`,
    );
    process.exit(0);
  } else {
    console.error(
      `Failed to create version (${versionResp.status}):`,
      JSON.stringify(versionData),
    );
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
