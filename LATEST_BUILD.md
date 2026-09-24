# Latest build status

Checked: 2026-09-24

- App: **Finanzas Definitiva**
- Version: **2.6.1**
- Latest successful GitHub Actions run: **35974294929** (run #55)
- Artifact: **Finanzas-Definitiva-v2.6.1-Official**
- APK: **Finanzas-Definitiva-v2.6.1.apk**
- APK SHA-256: `84bd64b0e64ce6c61c133f2c76f1d53e697e644659bb6a8f8eb87a9f90867a01`
- Application ID: `com.angel.finanzas.nueva.finanzas_definitiva`
- Build number: **5055**
- Signing: **persistent**
- Flutter analyze: **success**
- Flutter tests: **success**
- Release APK build: **success**
- APK signature verification: **success**

Remittance rule fix:
- Agent fee below threshold = fixed fee.
- Agent fee above threshold = configurable agent percentage (default 5%).
- Owner share is separate and defaults to 50% of the agent's fee.
- Example: principal 200, agent fee 5% = 10, owner share 50% = 5.
