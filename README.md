# Linux Security Monitoring Dashboard — Ubuntu 24.04 STIG Hardened

A Linux security monitoring pipeline built on a hardened Ubuntu 24.04 VM with detections mapped to MITRE ATT&CK. The project combines OpenSCAP system hardening with a Splunk SIEM dashboard for continuous visibility into security events.

---

## Project Overview

The starting point is a fresh Ubuntu 24.04 install evaluated against the DoD STIG V1R1 benchmark using OpenSCAP. The benchmark covers hundreds of controls across access control, audit logging, authentication, and network security. After auto-remediation and manual configuration, a Splunk Universal Forwarder ships four live log sources into a dedicated index. An eight-panel dashboard maps that telemetry to specific MITRE ATT&CK techniques.

Configuration drift is then simulated by disabling the firewall and adding a suspicious cron job. Both events surface in the dashboard before a scheduled scan would have caught them. A cron job runs OpenSCAP daily and logs the compliance score automatically so the score history updates without manual intervention.

---

## Architecture

```
Ubuntu 24.04 VM (192.168.10.240)
│
├── OpenSCAP (STIG V1R1 hardening + daily scheduled scan)
│   └── /var/log/openscap/compliance-scores.log
│
├── auditd (kernel-level audit logging)
│   └── /var/log/audit/audit.log
│       ├── USER_CMD events (sudo commands, hex-encoded)
│       └── PATH events (file integrity via watch rules)
│
├── UFW (firewall with SSH rate limiting)
│   └── /var/log/ufw.log
│
├── Chrony (NTP time synchronization)
│   └── /var/log/syslog
│
└── Splunk Universal Forwarder 9.4.0
    └── Forwards to Splunk indexer (192.168.6.60:9997)
                │
                └── index: siem_monitoring
                    └── Eight-panel MITRE ATT&CK dashboard
```

---

## STIG Compliance Score History

| Scan | Score | Description |
|---|---|---|
| stig-baseline | 50.48% | Fresh Ubuntu 24.04 install |
| stig-post-auto-remediation | 76.82% | OpenSCAP auto-remediation applied |
| stig-final | 77.88% | Manual UFW and Chrony fixes |
| stig-drift-ufw-disabled | 76.83% | Drift simulation: UFW disabled |
| stig-recovered | 77.88% | Remediated, score recovered |

---

## Dashboard Panels — MITRE ATT&CK Mapping

| Panel | ATT&CK Technique | Data Source |
|---|---|---|
| Failed SSH Login Attempts | T1110 — Brute Force | auth.log (linux_secure) |
| Sudo / Privilege Escalation | T1548.003 — Sudo and Sudo Caching | audit.log (linux_audit) |
| Log Source Heartbeat | T1562.006 — Indicator Removal on Host | All sourcetypes |
| Authentication Success vs Failure | T1078 — Valid Accounts | auth.log (linux_secure) |
| UFW Blocked Connections | T1046 — Network Service Discovery | ufw.log |
| File Integrity Changes | T1543 — Create or Modify System Process | audit.log PATH records |
| Time Synchronization Integrity | T1070 — Indicator Removal | syslog (Chrony) |
| STIG V1R1 Compliance Score Trend | N/A | compliance-scores.log |

---

## Repository Structure

```
linux-stig-siem-monitoring/
├── README.md
├── openscap/
│   ├── openscap-scan.sh          # Daily automated scan script
│   └── compliance-scores.log     # Example score history log format
├── splunk/
│   ├── dashboard.xml             # Splunk Classic Dashboard XML
│   ├── inputs.conf               # Forwarder input configuration
│   └── props.conf                # Timestamp parsing configuration
├── auditd/
│   └── file-integrity.rules      # auditd watch rules for sensitive paths
└── screenshots/
    └── dashboard.png             # Full dashboard screenshot
```

---

## Setup

### Prerequisites

- Ubuntu 24.04 LTS VM (tested on VMware)
- Splunk Enterprise or Free 9.4.x with a receiving port configured (default 9997)
- Splunk Universal Forwarder 9.4.0
- ComplianceAsCode v0.1.78 SCAP content

### Step 1 — Install OpenSCAP and Download Content

```bash
sudo apt update && sudo apt install -y openscap-scanner unzip
wget https://github.com/ComplianceAsCode/content/releases/download/v0.1.78/scap-security-guide-0.1.78.zip -P ~/
unzip ~/scap-security-guide-0.1.78.zip -d ~/scap-content
```

### Step 2 — Run Baseline Scan

```bash
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_stig \
  --results /tmp/stig-baseline-results.xml \
  --report /tmp/stig-baseline-report.html \
  ~/scap-content/scap-security-guide-0.1.78/ssg-ubuntu2404-ds.xml
```

### Step 3 — Apply Auto-Remediation

```bash
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_stig \
  --remediate \
  ~/scap-content/scap-security-guide-0.1.78/ssg-ubuntu2404-ds.xml
sudo reboot
```

### Step 4 — Run Post-Remediation Scan

```bash
sudo oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_stig \
  --results /tmp/stig-after-results.xml \
  --report /tmp/stig-after-report.html \
  ~/scap-content/scap-security-guide-0.1.78/ssg-ubuntu2404-ds.xml
```

### Step 5 — Install and Configure Splunk Universal Forwarder

```bash
# Install forwarder
sudo dpkg -i splunkforwarder-9.4.0-6b4ebe426ca6-linux-amd64.deb

# Point to Splunk indexer
sudo /opt/splunkforwarder/bin/splunk add forward-server SPLUNK_IP:9997 -auth admin:password

# Copy inputs and props config
sudo cp splunk/inputs.conf /opt/splunkforwarder/etc/system/local/inputs.conf
sudo cp splunk/props.conf /opt/splunkforwarder/etc/system/local/props.conf

# Enable boot start and start
sudo /opt/splunkforwarder/bin/splunk enable boot-start
sudo /opt/splunkforwarder/bin/splunk start
```

### Step 6 — Configure auditd File Integrity Rules

```bash
sudo cp auditd/file-integrity.rules /etc/audit/rules.d/file-integrity.rules
sudo augenrules --load
```

### Step 7 — Deploy the Daily Scan Script

```bash
sudo cp openscap/openscap-scan.sh /usr/local/bin/openscap-scan.sh
sudo chmod +x /usr/local/bin/openscap-scan.sh
echo "0 2 * * * root /usr/local/bin/openscap-scan.sh" | sudo tee /etc/cron.d/openscap-daily
```

### Step 8 — Import the Splunk Dashboard

In Splunk web go to Dashboards, create a new Classic Dashboard, click Edit, then Edit Source, and paste the contents of `splunk/dashboard.xml`.

---

## Key Technical Decisions

**Why ComplianceAsCode instead of apt?** The `ssg-debderived` package does not include a STIG profile for Ubuntu 24.04. ComplianceAsCode v0.1.78 ships the complete STIG V1R1 content for Noble Numbat.

**Why a separate compliance index?** Isolating log sources per project makes Splunk searches faster and keeps compliance telemetry separate from other lab VMs.

**Why log compliance scores to a flat log file instead of indexing XML?** The OpenSCAP result XML files are 8MB each. Splunk's Universal Forwarder ships them as chunked events that cannot be parsed with a single regex across event boundaries. A structured key=value log file solves this cleanly.

**Why decode auditd hex commands in SPL?** Linux auditd hex-encodes command arguments to preserve special characters. The `urldecode(replace())` pattern in SPL decodes them to plain text without requiring a lookup table or external script.

---

## Tools

- OpenSCAP
- ComplianceAsCode STIG V1R1 (v0.1.78)
- Splunk Enterprise 9.4.0
- Splunk Universal Forwarder 9.4.0
- auditd
- UFW
- Chrony
- Ubuntu 24.04 LTS (Noble Numbat)
- VMware Workstation

## Notes

This project was built hands-on in a personal lab environment. Claude (Anthropic) was used as a technical resource during development for troubleshooting, SPL query guidance, and documentation assistance. All configuration, implementation, and testing was performed manually.
