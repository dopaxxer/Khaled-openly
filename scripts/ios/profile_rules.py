"""Provisioning checks shared by preparation and exported-IPA verification.

These checks supplement codesign and Apple's distribution validation. Synthetic
test profiles cannot sign an app and are never used as distribution assets.
"""
from datetime import datetime, timezone
from uuid import UUID


class ProfileError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ProfileError(message)


def distribution_method(value):
    require(value in ("testflight", "app-store-connect", "ad-hoc"), "Unknown distribution method")
    return "app-store-connect" if value == "testflight" else value


def permits(allowed, claimed):
    """Profile allowlists may use trailing wildcards; app claims may not."""
    if isinstance(claimed, list):
        return isinstance(allowed, list) and all(any(permits(a, c) for a in allowed) for c in claimed)
    if isinstance(claimed, dict):
        return isinstance(allowed, dict) and all(k in allowed and permits(allowed[k], v) for k, v in claimed.items())
    if isinstance(claimed, str) and isinstance(allowed, str):
        if "*" in claimed:
            return False
        return claimed.startswith(allowed[:-1]) if allowed.endswith("*") else allowed == claimed
    return type(allowed) is type(claimed) and allowed == claimed


def validate_profile(profile, team, bundle, method, *, domain=None, now=None):
    method = distribution_method(method)
    require(bool(team) and bool(bundle), "Expected team and Bundle ID are required")
    ent = profile.get("Entitlements", {})
    require(team in profile.get("TeamIdentifier", []), "Provisioning profile belongs to another team")
    require(ent.get("com.apple.developer.team-identifier") == team, "Profile team entitlement does not match")
    app_id = ent.get("application-identifier")
    require(any(app_id == p + "." + bundle for p in profile.get("ApplicationIdentifierPrefix", [])), "Profile must exactly match the Bundle ID and App ID prefix")
    require("iOS" in profile.get("Platform", []), "An iOS provisioning profile is required")
    require(ent.get("get-task-allow") is False, "A distribution provisioning profile is required")
    require(not profile.get("ProvisionsAllDevices"), "Enterprise profiles are not supported")
    expiry = profile.get("ExpirationDate")
    require(isinstance(expiry, datetime), "Profile expiration is missing")
    expiry = expiry.replace(tzinfo=timezone.utc) if expiry.tzinfo is None else expiry.astimezone(timezone.utc)
    clock = now or datetime.now(timezone.utc)
    clock = clock.replace(tzinfo=timezone.utc) if clock.tzinfo is None else clock.astimezone(timezone.utc)
    require(expiry > clock, "Provisioning profile has expired")
    require(ent.get("aps-environment") == "production", "A production push entitlement is required")
    devices = profile.get("ProvisionedDevices", [])
    if method == "ad-hoc":
        require(isinstance(devices, list) and bool(devices) and all(isinstance(d, str) and d for d in devices), "Ad Hoc profile must include registered devices")
    else:
        require(not devices, "App Store Connect requires an App Store distribution profile")
    certificates = profile.get("DeveloperCertificates", [])
    require(isinstance(certificates, list) and bool(certificates) and all(isinstance(c, bytes) and c for c in certificates), "Profile has no signing certificates")
    try:
        UUID(profile.get("UUID", ""))
    except (ValueError, TypeError, AttributeError):
        raise ProfileError("Profile UUID is invalid") from None
    if domain:
        require(permits(ent.get("com.apple.developer.associated-domains"), ["applinks:" + domain]), "Profile does not permit the configured universal-link domain")
    return {"method": method, "app_id": app_id, "expires": expiry, "device_count": len(devices)}


def validate_signed_app(profile, entitlements, info, certificate, team, bundle, method, version, build, *, domain=None, now=None):
    checked = validate_profile(profile, team, bundle, method, domain=domain, now=now)
    require(info.get("CFBundleIdentifier") == bundle, "Exported Bundle ID does not match the requested app")
    require(info.get("CFBundleShortVersionString") == version, "Exported version does not match the requested version")
    require(info.get("CFBundleVersion") == str(build), "Exported build number does not match the requested build")
    require(entitlements.get("application-identifier") == checked["app_id"], "Signed App ID does not match the profile")
    require(entitlements.get("com.apple.developer.team-identifier") == team, "Signed team does not match the requested team")
    require(entitlements.get("get-task-allow", False) is False, "Exported app has debugging enabled")
    require(entitlements.get("aps-environment") == "production", "Exported app lacks production push entitlement")
    require(certificate in profile["DeveloperCertificates"], "App signing certificate is not permitted by the profile")
    require(permits(profile["Entitlements"], entitlements), "Exported app claims an entitlement not permitted by the profile")
    if domain:
        require("applinks:" + domain in entitlements.get("com.apple.developer.associated-domains", []), "Exported app lacks the configured universal-link domain")
    return checked
