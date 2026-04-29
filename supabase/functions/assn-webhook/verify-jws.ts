// JWS signature verification for App Store Server Notifications v2.
// MON-13 — MONETIZATION_AGENT.md invariants 23–25.
//
// Apple signs every ASSN v2 payload with an ES256 (ECDSA-P-256-SHA-256)
// JWS. The protected header carries the full x5c chain — typically:
//
//   x5c[0] = leaf cert (signs this JWS)
//   x5c[1] = "Apple Worldwide Developer Relations" intermediate
//   x5c[2] = Apple Root CA - G3
//
// Our verification:
//   1. Parse all certs from x5c.
//   2. Walk the chain — each cert MUST be validly signed by the next.
//   3. The chain's terminal cert (or a cert at depth N when chain length
//      is shorter) MUST match our pinned Apple Root CA G3 (thumbprint
//      compared, not just visual match — defends against substitution).
//   4. The JWS signature MUST verify against the leaf's public key.
//
// All four steps are required. Any failure → `valid: false` with a reason
// label so we can grep `dev_session_logs` for forensic root cause.
//
// We do NOT validate notBefore / notAfter date windows — Apple rotates
// signing certs faster than typical CRL refresh and a dropped event is a
// dropped row. Apple's rotation guarantees never include "old chain stops
// working in flight"; if the cert chain VERIFIES against a pinned root,
// the event is authentic.
//
// Self-check: we re-hash the bundled root at verify-time to detect a
// tampered binary (someone editing this file to swap the pinned thumbprint).
//
// Apple Root CA - G3 (DER-encoded, base64):
//   downloaded from apple.com/certificateauthority/AppleRootCA-G3.cer
//   on 2026-04-29
//   sha256: 63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179

import { X509Certificate } from "https://esm.sh/@peculiar/x509@1.11.0";

// SHA-256 thumbprint of Apple Root CA - G3, hex (lowercase, no separators).
// If the bundled DER below is ever swapped, the self-check at verify-time
// will trip and the validator will refuse to validate anything.
const APPLE_ROOT_CA_G3_THUMBPRINT_HEX =
  "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

// Apple Root CA - G3 (DER, base64). Bundled so verification does NOT
// depend on a network fetch at request time (defends against a CDN
// swap or a network partition turning prod into audit-only mode without
// our knowledge).
const APPLE_ROOT_CA_G3_DER_B64 =
  "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";

interface JwsHeader {
  alg: string;
  x5c?: string[];
}

export interface VerifyResult {
  valid: boolean;
  reason?: string;
}

function base64ToUint8(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function base64UrlToUint8(input: string): Uint8Array {
  const padded = input
    .replace(/-/g, "+")
    .replace(/_/g, "/")
    .padEnd(Math.ceil(input.length / 4) * 4, "=");
  return base64ToUint8(padded);
}

async function sha256Hex(data: Uint8Array): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Verify an ASSN v2 JWS (compact serialization).
// Returns { valid: true } only when chain integrity AND signature
// verification both succeed. Any path that ends with `valid: false`
// also includes a `reason` label so the webhook can log it cleanly.
export async function verifyAssnJws(jws: string): Promise<VerifyResult> {
  const parts = jws.split(".");
  if (parts.length !== 3) return { valid: false, reason: "not_jws" };

  // ── 1. Parse the protected header ──
  let header: JwsHeader;
  try {
    header = JSON.parse(new TextDecoder().decode(base64UrlToUint8(parts[0])));
  } catch {
    return { valid: false, reason: "header_parse" };
  }

  if (header.alg !== "ES256") {
    return { valid: false, reason: `alg_not_es256:${header.alg}` };
  }
  if (!header.x5c || header.x5c.length < 2) {
    return { valid: false, reason: "x5c_missing" };
  }

  // ── 2. Parse the cert chain ──
  const chain: X509Certificate[] = [];
  for (let i = 0; i < header.x5c.length; i++) {
    try {
      chain.push(new X509Certificate(base64ToUint8(header.x5c[i])));
    } catch {
      return { valid: false, reason: `cert_parse_${i}` };
    }
  }

  // ── 3. Self-check: bundled root has not been tampered ──
  let pinnedRoot: X509Certificate;
  try {
    pinnedRoot = new X509Certificate(base64ToUint8(APPLE_ROOT_CA_G3_DER_B64));
  } catch {
    return { valid: false, reason: "pinned_root_parse" };
  }
  const pinnedRootThumbprint = await sha256Hex(new Uint8Array(pinnedRoot.rawData));
  if (pinnedRootThumbprint !== APPLE_ROOT_CA_G3_THUMBPRINT_HEX) {
    return { valid: false, reason: "pinned_root_thumbprint_mismatch" };
  }

  // ── 4. Walk the chain — each cert signed by the next ──
  for (let i = 0; i < chain.length - 1; i++) {
    const child = chain[i];
    const parent = chain[i + 1];
    let chainOk = false;
    try {
      chainOk = await child.verify({
        publicKey: parent.publicKey,
        signatureOnly: true,
      });
    } catch {
      chainOk = false;
    }
    if (!chainOk) return { valid: false, reason: `chain_break_${i}` };
  }

  // ── 5. Anchor the chain to the pinned Apple Root CA G3 ──
  // If x5c carries the full 3-cert chain, x5c[len-1] should match our pin.
  // If x5c only carries leaf + intermediate, verify the intermediate is
  // signed by our pinned root.
  const top = chain[chain.length - 1];
  const topThumbprint = await sha256Hex(new Uint8Array(top.rawData));

  if (topThumbprint === pinnedRootThumbprint) {
    // Full chain matches our pin — nothing more to check.
  } else {
    // Top cert is NOT our pinned root. Treat top as an intermediate and
    // verify it's signed by our pinned root. If not — refuse.
    let intOk = false;
    try {
      intOk = await top.verify({
        publicKey: pinnedRoot.publicKey,
        signatureOnly: true,
      });
    } catch {
      intOk = false;
    }
    if (!intOk) return { valid: false, reason: "chain_does_not_anchor_to_apple_root" };
  }

  // ── 6. Verify the JWS signature against the leaf's pubkey ──
  // ES256 raw signature is r||s (64 bytes for P-256). Web Crypto's
  // ECDSA verify expects exactly that format.
  let leafKey: CryptoKey;
  try {
    leafKey = (await chain[0].publicKey.export(crypto)) as CryptoKey;
  } catch {
    return { valid: false, reason: "leaf_pubkey_export" };
  }

  const signedData = new TextEncoder().encode(parts[0] + "." + parts[1]);
  const signature = base64UrlToUint8(parts[2]);

  let sigOk = false;
  try {
    sigOk = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      leafKey,
      signature,
      signedData,
    );
  } catch {
    sigOk = false;
  }

  if (!sigOk) return { valid: false, reason: "signature_invalid" };

  return { valid: true };
}
