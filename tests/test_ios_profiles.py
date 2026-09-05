"""Synthetic metadata fixtures only: no Apple certificates, private keys or IPAs."""
import copy
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts/ios"))
from profile_rules import ProfileError, validate_profile, validate_signed_app

TEAM = "TESTTEAM01"
BUNDLE = "com.openly.test"
CLOCK = datetime(2030, 1, 1, tzinfo=timezone.utc)


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.profile = {
            "UUID": "00000000-0000-4000-8000-000000000001",
            "TeamIdentifier": [TEAM], "ApplicationIdentifierPrefix": [TEAM],
            "Platform": ["iOS"], "ExpirationDate": CLOCK + timedelta(days=1),
            "DeveloperCertificates": [b"synthetic test certificate bytes, not a certificate"],
            "Entitlements": {
                "application-identifier": TEAM + "." + BUNDLE,
                "com.apple.developer.team-identifier": TEAM, "get-task-allow": False,
                "aps-environment": "production", "keychain-access-groups": [TEAM + ".*"],
                "com.apple.developer.associated-domains": ["*"],
            },
        }
        self.claims = copy.deepcopy(self.profile["Entitlements"])
        self.claims["keychain-access-groups"] = [TEAM + "." + BUNDLE]
        self.claims["com.apple.developer.associated-domains"] = ["applinks:openly.test"]
        self.info = {"CFBundleIdentifier": BUNDLE, "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "7"}

    def check_profile(self, method="testflight", **kwargs):
        return validate_profile(self.profile, TEAM, BUNDLE, method, now=CLOCK, **kwargs)

    def check_app(self, **kwargs):
        return validate_signed_app(self.profile, self.claims, self.info,
            self.profile["DeveloperCertificates"][0], TEAM, BUNDLE, "app-store-connect", "1.0.0", "7", now=CLOCK, **kwargs)

    def test_app_store_profile_and_export_metadata(self):
        self.assertEqual(self.check_profile()["method"], "app-store-connect")
        self.assertEqual(self.check_app(domain="openly.test")["device_count"], 0)

    def test_ad_hoc_requires_registered_devices(self):
        with self.assertRaises(ProfileError): self.check_profile("ad-hoc")
        self.profile["ProvisionedDevices"] = ["synthetic-registered-device"]
        self.assertEqual(self.check_profile("ad-hoc")["device_count"], 1)
        with self.assertRaises(ProfileError): self.check_profile("testflight")

    def test_enterprise_is_rejected_for_both_methods(self):
        self.profile.update(ProvisionsAllDevices=True, ProvisionedDevices=["test-device"])
        for method in ("ad-hoc", "testflight"):
            with self.subTest(method=method), self.assertRaises(ProfileError): self.check_profile(method)

    def test_expiry_including_naive_plist_dates(self):
        self.profile["ExpirationDate"] = (CLOCK + timedelta(days=1)).replace(tzinfo=None)
        self.check_profile()
        for date in (CLOCK, CLOCK.replace(tzinfo=None), CLOCK - timedelta(seconds=1)):
            self.profile["ExpirationDate"] = date
            with self.subTest(date=date), self.assertRaises(ProfileError): self.check_profile()

    def test_wrong_team_and_bundle(self):
        for key, value in (("com.apple.developer.team-identifier", "OTHERTEAM1"), ("application-identifier", TEAM + ".com.other.app")):
            original = self.profile["Entitlements"][key]
            self.profile["Entitlements"][key] = value
            with self.subTest(key=key), self.assertRaises(ProfileError): self.check_profile()
            self.profile["Entitlements"][key] = original

    def test_legacy_app_prefix_can_differ_from_team(self):
        self.profile["ApplicationIdentifierPrefix"] = ["OLDPREFIX1"]
        self.profile["Entitlements"]["application-identifier"] = "OLDPREFIX1." + BUNDLE
        self.check_profile()

    def test_development_and_sandbox_profiles_fail(self):
        for key, value in (("get-task-allow", True), ("aps-environment", "development")):
            original = self.profile["Entitlements"][key]
            self.profile["Entitlements"][key] = value
            with self.subTest(key=key), self.assertRaises(ProfileError): self.check_profile()
            self.profile["Entitlements"][key] = original

    def test_unknown_method_and_unsafe_profile_identifier(self):
        with self.assertRaises(ProfileError): self.check_profile("enterprise")
        self.profile["UUID"] = "../profile\nENV=bad"
        with self.assertRaises(ProfileError): self.check_profile()

    def test_signing_certificate_must_be_allowed(self):
        with self.assertRaises(ProfileError):
            validate_signed_app(self.profile, self.claims, self.info, b"another certificate", TEAM, BUNDLE, "testflight", "1.0.0", "7", now=CLOCK)

    def test_exported_app_identity_version_and_build(self):
        for key in self.info:
            original = self.info[key]
            self.info[key] = "mismatch"
            with self.subTest(key=key), self.assertRaises(ProfileError): self.check_app()
            self.info[key] = original

    def test_unpermitted_keychain_or_extra_entitlements_fail(self):
        self.claims["keychain-access-groups"] = ["OTHERTEAM1.private"]
        with self.assertRaises(ProfileError): self.check_app()
        self.claims["keychain-access-groups"] = [TEAM + "." + BUNDLE]
        self.claims["com.apple.developer.healthkit"] = True
        with self.assertRaises(ProfileError): self.check_app()

    def test_universal_link_domain_must_be_claimed_and_permitted(self):
        with self.assertRaises(ProfileError): self.check_app(domain="other.test")
        self.profile["Entitlements"]["com.apple.developer.associated-domains"] = ["applinks:other.test"]
        with self.assertRaises(ProfileError): self.check_profile(domain="openly.test")


if __name__ == "__main__":
    unittest.main()
