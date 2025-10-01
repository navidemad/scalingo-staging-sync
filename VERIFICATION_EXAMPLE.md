# Anonymization Verification - Usage Examples

This document demonstrates how to use the new anonymization verification features in scalingo-staging-sync.

## Configuration

Add these settings to your `config/initializers/scalingo_staging_sync.rb`:

```ruby
ScalingoStagingSync.configure do |config|
  # Existing configuration
  config.clone_source_scalingo_app_name = "my-production-app"
  config.slack_webhook_url = "https://hooks.slack.com/..."
  config.slack_channel = "#deployments"

  # Anonymization Verification Settings
  config.verify_anonymization = true                    # Enable verification (default: true)
  config.fail_on_verification_error = true              # Fail if verification finds issues (default: true)
  config.run_pii_scan = true                            # Scan for unanonymized PII columns (default: true)
  config.anonymization_audit_file = "tmp/anonymization_audit" # Save audit report

  # Custom PII Detection Patterns (optional)
  config.pii_detection_patterns = {
    identity: /\b(ssn|social_security|tax_id|passport|driver_license|national_id)\b/i,
    contact: /\b(email|phone|mobile|fax|address|street|city|postal|zip|country)\b/i,
    personal: /\b(first_name|last_name|full_name|name|birth|dob|age|gender|maiden)\b/i,
    financial: /\b(credit_card|card_number|cvv|iban|account_number|routing|salary|income)\b/i,
    auth: /\b(password|token|secret|api_key|oauth|credential)\b/i,
    medical: /\b(diagnosis|medical|prescription|health|insurance)\b/i,
    biometric: /\b(fingerprint|retina|face|dna|biometric)\b/i
  }
end
```

## What Gets Verified

### 1. Pre-Anonymization Column Checks

Before anonymization runs, the system verifies:
- All required columns exist in the database
- The `anonymized_at` column exists (if used in queries)
- All columns referenced in anonymization queries are present

**Example Output:**
```
[DatabaseAnonymizerService] Running pre-anonymization column validation...
[DatabaseAnonymizerService] ✓ All required columns exist
```

**If columns are missing:**
```
[DatabaseAnonymizerService] Column validation failed!
  Table users: Missing columns in users: anonymized_at, stripe_customer_id
```

### 2. Post-Anonymization Verification

After each table is anonymized, the system checks:

**For Users Table:**
- No production email addresses (gmail, yahoo, hotmail, etc.)
- No real names (checks that first_name = 'Demo')
- No real credit card numbers (checks card_last4 = '0000')
- No real IBAN numbers (checks iban_last4 = '0000')
- No authentication tokens remain (google_token, facebook_token, etc.)
- No birth dates or birth places remain

**For Phone Numbers Table:**
- No real phone number patterns (US, French, UK, Indian formats)
- All phones follow anonymized format (060XXXXXXX)

**For Payment Methods Table:**
- All card_last4 values are '0000'

**Example Output:**
```
[DatabaseAnonymizerService] ✓ Anonymized users - 1523 rows in 2.45s
[DatabaseAnonymizerService] ✅ All tables passed verification
```

**If verification fails:**
```
[DatabaseAnonymizerService] ❌ Verification failed for users:
  ISSUE: Found 5 users with production-like email addresses
  ISSUE: Found 3 users with non-anonymized IBAN numbers
  WARNING: Found 12 users with potentially real names
```

### 3. PII Scanner

Scans all tables in the database to detect columns that might contain PII but aren't configured for anonymization:

**Example Output:**
```
[DatabaseAnonymizerService] Scanning for unanonymized PII columns...
[DatabaseAnonymizerService] PII scan found potential issues:
  - Table 'customer_notes' has potential PII columns but is not configured for anonymization: customer_email, phone_number
  - Table 'audit_logs' has potential PII columns but is not configured for anonymization: user_email
```

### 4. Anonymization Audit Report

Generates a comprehensive report of the anonymization process:

**JSON Report (`tmp/anonymization_audit.json`):**
```json
{
  "generated_at": "2025-09-30T10:15:23Z",
  "summary": {
    "total_tables": 3,
    "total_rows_affected": 2547,
    "verification_passed": true,
    "pii_warnings_count": 0
  },
  "tables": [
    {
      "before": {
        "table": "users",
        "timestamp": "2025-09-30T10:15:20Z",
        "row_count": 1523,
        "sample_hash": "a3f5b8c9d2e1...",
        "column_stats": {
          "email": {"null_count": 0, "distinct_count": 1523},
          "first_name": {"null_count": 45, "distinct_count": 892}
        }
      },
      "after": {
        "table": "users",
        "timestamp": "2025-09-30T10:15:22Z",
        "rows_affected": 1523,
        "row_count": 1523,
        "sample_hash": "f7d2e9a4b1c8...",
        "column_stats": {
          "email": {"null_count": 0, "distinct_count": 1523},
          "first_name": {"null_count": 0, "distinct_count": 1}
        }
      }
    }
  ],
  "verification": {
    "users": {
      "success": true,
      "issues": [],
      "warnings": []
    }
  },
  "pii_scan": {
    "potential_pii": {},
    "warnings": []
  },
  "metadata": {
    "gem_version": "0.1.0",
    "environment": "staging"
  }
}
```

**Text Report (`tmp/anonymization_audit.txt`):**
```
================================================================================
ANONYMIZATION AUDIT REPORT
================================================================================

Generated: 2025-09-30T10:15:23Z
Environment: staging
Gem Version: 0.1.0

SUMMARY
--------------------------------------------------------------------------------
Total Tables Anonymized: 3
Total Rows Affected: 2547
Verification Passed: YES
PII Scan Warnings: 0

TABLE DETAILS
--------------------------------------------------------------------------------
Table: users
  Before: 1523 rows (hash: a3f5b8c9d2e1f...)
  After:  1523 rows (hash: f7d2e9a4b1c8a...)
  Rows Affected: 1523
  Data Changed: YES

Table: phone_numbers
  Before: 856 rows (hash: b2c8d5e9f1a3c...)
  After:  856 rows (hash: e9f3a7b2c5d1f...)
  Rows Affected: 856
  Data Changed: YES

Table: payment_methods
  Before: 168 rows (hash: c4d1e7f9a2b5c...)
  After:  168 rows (hash: a5f2c9e3b7d1a...)
  Rows Affected: 168
  Data Changed: YES

VERIFICATION RESULTS
--------------------------------------------------------------------------------
users:
  Status: PASSED

phone_numbers:
  Status: PASSED

payment_methods:
  Status: PASSED

================================================================================
```

## Disabling Verification

If you need to disable verification (not recommended for production):

```ruby
ScalingoStagingSync.configure do |config|
  config.verify_anonymization = false       # Disable all verification
  config.run_pii_scan = false              # Disable PII scanning
  config.fail_on_verification_error = false # Don't fail on issues (just warn)
end
```

## Verification in Logs

The verification process provides detailed logging:

```
[DatabaseAnonymizerService] Running pre-anonymization column validation...
[DatabaseAnonymizerService] ✓ All required columns exist
[DatabaseAnonymizerService] Scanning for unanonymized PII columns...
[DatabaseAnonymizerService] ✓ No unanonymized PII columns detected
[DatabaseAnonymizerService] Starting parallel anonymization with 3 connections...
[DatabaseAnonymizerService] Starting anonymization of table: users
[DatabaseAnonymizerService] Anonymizing users table...
[DatabaseAnonymizerService] Users table: 1523 rows anonymized
[DatabaseAnonymizerService] ✓ Anonymized users - 1523 rows in 2.45s
[DatabaseAnonymizerService] Running final anonymization verification...
[DatabaseAnonymizerService] ✅ All tables passed verification
[DatabaseAnonymizerService] Generating anonymization audit report...
[DatabaseAnonymizerService] ✅ Audit report saved:
  JSON: tmp/anonymization_audit.json
  Text: tmp/anonymization_audit.txt
[DatabaseAnonymizerService] ✅ Parallel anonymization completed in 8.73s
```

## Slack Notifications

When Slack is enabled, verification results are included in notifications:

- ✓ Validation des colonnes réussie
- ⚠️ PII détecté dans 2 table(s)
- ✓ utilisateurs: 1523 lignes anonymisées
- ✅ Vérification réussie pour toutes les tables
- ✅ Rapport d'audit généré
- ✅ Anonymisation terminée (8.73s)

## Error Handling

If verification fails and `fail_on_verification_error` is true, the anonymization will fail with a detailed error:

```ruby
# Error raised:
PG::Error: Verification failed for users: Found 5 users with production-like email addresses, Found 3 users with non-anonymized IBAN numbers
```

This ensures that data leaks are caught before the cloned database is used in staging/demo environments.

## Best Practices

1. **Always enable verification** in staging/demo environments
2. **Review audit reports** regularly to ensure anonymization is working correctly
3. **Add new columns to anonymization** when schema changes
4. **Monitor PII scan warnings** to catch newly added sensitive columns
5. **Keep audit reports** for compliance and debugging purposes
