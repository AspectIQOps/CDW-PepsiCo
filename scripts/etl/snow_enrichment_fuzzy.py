#!/usr/bin/env python3
"""
ServiceNow Enrichment with Fuzzy Matching - Phase 2
Implements SOW Section 2.4.3 - Fuzzy matching algorithms
Uses PostgreSQL pg_trgm for trigram similarity matching
"""
import requests
import psycopg2
from psycopg2.extras import execute_values
import os
from datetime import datetime, timedelta
import sys

# Configuration - credentials loaded from SSM via entrypoint.sh
DB_HOST = os.getenv('DB_HOST')
DB_NAME = os.getenv('DB_NAME')
DB_USER = os.getenv('DB_USER')
DB_PASSWORD = os.getenv('DB_PASSWORD')

SN_INSTANCE = os.getenv('SN_INSTANCE')
SN_CLIENT_ID = os.getenv('SN_CLIENT_ID')
SN_CLIENT_SECRET = os.getenv('SN_CLIENT_SECRET')

# Fallback to basic auth if OAuth not available
SN_USER = os.getenv('SN_USER')
SN_PASS = os.getenv('SN_PASS')

# Safety limits
REQUEST_TIMEOUT = 60
MAX_BATCH_SIZE = 50

# Fuzzy matching configuration (SOW Section 2.4.3)
FUZZY_MATCH_THRESHOLD = 0.80  # 80% confidence minimum

# OAuth token cache
_oauth_token_cache = {'token': None, 'expires_at': None}

def get_oauth_token():
    """Get OAuth 2.0 access token with caching"""
    now = datetime.now()

    if _oauth_token_cache['token'] and _oauth_token_cache['expires_at']:
        if now < _oauth_token_cache['expires_at'] - timedelta(seconds=30):
            return _oauth_token_cache['token']

    token_url = f"https://{SN_INSTANCE}.service-now.com/oauth_token.do"

    try:
        response = requests.post(
            token_url,
            auth=(SN_CLIENT_ID, SN_CLIENT_SECRET),
            data={'grant_type': 'client_credentials'},
            timeout=30
        )
        response.raise_for_status()

        token_data = response.json()
        access_token = token_data.get('access_token')
        expires_in = token_data.get('expires_in', 1800)

        if not access_token:
            raise ValueError("No access_token in response")

        _oauth_token_cache['token'] = access_token
        _oauth_token_cache['expires_at'] = now + timedelta(seconds=expires_in)

        return access_token

    except Exception as e:
        print(f"ERROR: OAuth authentication failed: {e}")
        raise

def get_auth_headers():
    """Get authentication headers (OAuth or Basic)"""
    if SN_CLIENT_ID and SN_CLIENT_SECRET:
        token = get_oauth_token()
        return {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json"
        }
    elif SN_USER and SN_PASS:
        import base64
        creds = base64.b64encode(f"{SN_USER}:{SN_PASS}".encode()).decode()
        return {
            "Authorization": f"Basic {creds}",
            "Content-Type": "application/json",
            "Accept": "application/json"
        }
    else:
        raise ValueError("No ServiceNow credentials configured")

def get_conn():
    """Establish database connection with autocommit enabled"""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD
        )
        # CRITICAL: Enable autocommit using psycopg2's isolation level method
        # This ensures all queries see committed data, preventing "Database returned: None"
        # followed by UniqueViolation errors
        conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
        return conn
    except Exception as e:
        print(f"❌ Database connection failed: {e}")
        raise

def extract_sys_id(item):
    """
    Extract sys_id from dict, string, tuple, or list (with recursive unwrapping)
    ServiceNow API can return fields in various formats, sometimes nested

    CRITICAL: This function MUST return either a plain string or None.
    Never return a tuple/list, as psycopg2 will try to unpack it as query parameters.
    """
    if item is None:
        return None

    # Handle dict: extract 'value' or 'sys_id' key
    if isinstance(item, dict):
        result = item.get('value') or item.get('sys_id')
        # Recursively process in case the dict value is itself nested
        if result is not None and result != item:  # Avoid infinite recursion
            return extract_sys_id(result)
        return None

    # Handle list/tuple: unwrap recursively until we get a non-collection type
    if isinstance(item, (list, tuple)):
        if len(item) == 0:
            return None
        # Keep unwrapping until we get something that's not a list/tuple
        result = item[0]
        while isinstance(result, (list, tuple)) and len(result) > 0:
            result = result[0]
        # Now recursively process the unwrapped value
        return extract_sys_id(result)

    # For any other type (str, int, bool, etc.), convert to string
    # This ensures we NEVER return a tuple/list
    str_value = str(item) if item else None

    # Final safety check: if somehow we still have a stringified tuple/list,
    # try to clean it up (edge case: str representation like "('value',)")
    if str_value and (str_value.startswith('(') or str_value.startswith('[')):
        # This is a stringified tuple/list - try to extract the actual value
        try:
            # Remove parentheses/brackets and quotes, split by comma, take first item
            cleaned = str_value.strip('()[]').replace("'", "").replace('"', '').split(',')[0].strip()
            return cleaned if cleaned else None
        except:
            # If cleaning fails, return the original string
            return str_value

    return str_value

def safe_truncate(value, max_length, field_name="field"):
    """Safely truncate string values"""
    if not value:
        return None
    s = str(value)
    if len(s) > max_length:
        return s[:max_length]
    return s

def load_all_snow_applications(conn):
    """
    Load all ServiceNow CMDB application records into temp table
    for fuzzy matching using PostgreSQL trigram similarity
    """
    print("\n[Phase 2.1] Loading ServiceNow CMDB Applications")
    print("-" * 70)

    cursor = conn.cursor()

    # Create temporary table for SNOW apps
    cursor.execute("""
        DROP TABLE IF EXISTS temp_snow_apps;
        CREATE TEMP TABLE temp_snow_apps (
            sys_id VARCHAR(50),
            name VARCHAR(255),
            short_description TEXT,
            operational_status VARCHAR(100),
            owned_by VARCHAR(255),
            business_service VARCHAR(255),
            support_group VARCHAR(255)
        );
    """)

    # Fetch all CMDB applications from ServiceNow
    base_url = f"https://{SN_INSTANCE}.service-now.com/api/now/table/cmdb_ci_service"
    headers = get_auth_headers()

    all_records = []
    offset = 0
    limit = 1000

    print(f"  SEARCH: Fetching all CMDB applications from ServiceNow...")

    while True:
        params = {
            "sysparm_fields": "sys_id,name,short_description,operational_status,owned_by,business_service,support_group",
            "sysparm_exclude_reference_link": "true",
            "sysparm_limit": limit,
            "sysparm_offset": offset
        }

        try:
            response = requests.get(base_url, headers=headers, params=params, timeout=REQUEST_TIMEOUT)
            response.raise_for_status()

            records = response.json().get("result", [])
            if not records:
                break

            all_records.extend(records)
            offset += limit

            if offset % 5000 == 0:
                print(f"    Fetched {offset} records...")

        except Exception as e:
            print(f"    ⚠️  Fetch failed at offset {offset}: {e}")
            break

    print(f"  ✅ Retrieved {len(all_records)} CMDB applications")

    # Insert into temp table
    if all_records:
        records_data = []
        for record in all_records:
            records_data.append((
                extract_sys_id(record.get('sys_id')),
                safe_truncate(extract_sys_id(record.get('name')), 255),
                safe_truncate(extract_sys_id(record.get('short_description')), 1000),
                safe_truncate(extract_sys_id(record.get('operational_status')), 100),
                safe_truncate(extract_sys_id(record.get('owned_by')), 255),
                safe_truncate(extract_sys_id(record.get('business_service')), 255),
                safe_truncate(extract_sys_id(record.get('support_group')), 255)
            ))

        execute_values(cursor, """
            INSERT INTO temp_snow_apps
            (sys_id, name, short_description, operational_status, owned_by, business_service, support_group)
            VALUES %s
        """, records_data)

        conn.commit()
        print(f"  ✅ Loaded {len(records_data)} records into temp table")

    cursor.close()
    return len(all_records)

def fuzzy_match_applications(conn):
    """
    Fuzzy match AppDynamics applications to ServiceNow CMDB
    Uses PostgreSQL pg_trgm SIMILARITY function (SOW Section 2.4.3)

    Matching Algorithm:
    1. Exact match (case-insensitive) - 100% confidence
    2. Trigram similarity >= 80% - fuzzy match
    3. No match if similarity < 80%
    """
    print("\n[Phase 2.2] Fuzzy Matching AppDynamics to ServiceNow")
    print("-" * 70)

    cursor = conn.cursor()

    # Get AppDynamics applications that need matching
    cursor.execute("""
        SELECT app_id, appd_application_name, appd_application_id
        FROM applications_dim
        WHERE appd_application_id IS NOT NULL
    """)

    appd_apps = cursor.fetchall()

    if not appd_apps:
        print("  ⚠️  No AppDynamics applications found")
        cursor.close()
        return 0

    print(f"  INFO:  Matching {len(appd_apps)} AppDynamics applications...")
    print(f"  INFO:  Fuzzy match threshold: {FUZZY_MATCH_THRESHOLD * 100}% (SOW requirement)")

    exact_matches = 0
    fuzzy_matches = 0
    no_matches = 0

    for app_id, appd_name, appd_id in appd_apps:
        # Try fuzzy matching using PostgreSQL SIMILARITY
        # SIMILARITY uses trigram matching (pg_trgm extension)
        cursor.execute("""
            SELECT
                sys_id,
                name,
                support_group,
                SIMILARITY(%s, name) as match_score
            FROM temp_snow_apps
            WHERE SIMILARITY(%s, name) >= %s
            ORDER BY match_score DESC
            LIMIT 1
        """, (appd_name, appd_name, FUZZY_MATCH_THRESHOLD))

        match = cursor.fetchone()

        if match:
            sys_id, sn_name, support_group, match_score = match

            # Ensure we have plain strings (PostgreSQL should return strings, but double-check)
            # If any value is still a tuple/list, extract the first element
            if isinstance(sys_id, (list, tuple)):
                sys_id = extract_sys_id(sys_id)
            if isinstance(sn_name, (list, tuple)):
                sn_name = extract_sys_id(sn_name)
            if isinstance(support_group, (list, tuple)):
                support_group = extract_sys_id(support_group)

            # Determine match type
            if appd_name.lower() == sn_name.lower():
                match_type = 'exact'
                confidence = 100
                exact_matches += 1
            else:
                match_type = 'fuzzy'
                confidence = int(match_score * 100)
                fuzzy_matches += 1

            # Update applications_dim with matched CMDB data
            # Handle duplicate sn_sys_id gracefully (multiple AppD apps can map to same SNOW CI)
            try:
                cursor.execute("""
                    UPDATE applications_dim
                    SET sn_sys_id = %s,
                        sn_service_name = %s,
                        support_group = %s,
                        updated_at = NOW()
                    WHERE app_id = %s
                """, (sys_id, sn_name, support_group, app_id))
            except psycopg2.errors.UniqueViolation:
                # Another AppD app already matched to this SNOW CI - skip and continue
                # This is expected when multiple AppD apps (e.g., -prod, -test) map to same SNOW CI
                cursor.execute("ROLLBACK")
                conn.commit()  # Start fresh transaction
                no_matches += 1  # Count as no match since we couldn't update
                continue

            # Log match in reconciliation_log with confidence score
            cursor.execute("""
                INSERT INTO reconciliation_log
                (source_a, source_b, match_key_a, match_key_b, confidence_score,
                 match_status, resolved_app_id)
                VALUES ('AppDynamics', 'ServiceNow', %s, %s, %s, %s, %s)
                ON CONFLICT DO NOTHING
            """, (appd_name, sn_name, confidence, match_type, app_id))

            if match_type == 'fuzzy':
                print(f"  SEARCH: Fuzzy match: '{appd_name}' → '{sn_name}' ({confidence}%)")
        else:
            no_matches += 1
            # Log failed match
            cursor.execute("""
                INSERT INTO reconciliation_log
                (source_a, source_b, match_key_a, match_key_b, confidence_score,
                 match_status, resolved_app_id)
                VALUES ('AppDynamics', 'ServiceNow', %s, NULL, 0, 'no_match', %s)
                ON CONFLICT DO NOTHING
            """, (appd_name, app_id))

    conn.commit()
    cursor.close()

    total_matched = exact_matches + fuzzy_matches
    match_rate = (total_matched / len(appd_apps) * 100) if appd_apps else 0

    print(f"\n  ✅ Matching Complete:")
    print(f"     • Exact matches: {exact_matches} (100% confidence)")
    print(f"     • Fuzzy matches: {fuzzy_matches} (≥{FUZZY_MATCH_THRESHOLD * 100}% confidence)")
    print(f"     • No matches: {no_matches}")
    print(f"     • Total match rate: {match_rate:.1f}%")

    if match_rate < 80:
        print(f"  ⚠️  Match rate below 80% - review unmatched applications")
        print(f"     Check reconciliation_log for match_status='no_match'")

    return total_matched

def enrich_servers_from_snow(conn):
    """
    Enrich servers_dim with ServiceNow CMDB server data
    Uses the server hostnames discovered from AppDynamics to query SNOW efficiently
    """
    print("\n[Phase 2.3] Enriching Servers from ServiceNow CMDB")
    print("-" * 70)

    # Connection already has autocommit enabled in get_conn()
    cursor = conn.cursor()

    # Get all servers discovered from AppDynamics
    cursor.execute("""
        SELECT server_id, server_name, sn_sys_id
        FROM servers_dim
        WHERE sn_sys_id LIKE 'appd-%'
    """)

    appd_servers = cursor.fetchall()

    if not appd_servers:
        print("  INFO:  No AppDynamics servers to enrich")
        return 0

    print(f"  SEARCH: Found {len(appd_servers)} servers from AppDynamics")

    # Extract hostnames for SNOW query
    try:
        server_names = [server[1] for server in appd_servers]
    except Exception as e:
        print(f"  ⚠️  Failed to extract server names: {e}")
        print(f"     Sample appd_server record: {appd_servers[0] if appd_servers else 'None'}")
        print(f"     Record type: {type(appd_servers[0]) if appd_servers else 'None'}")
        return 0

    # Batch query ServiceNow for these specific servers
    # Build query filter: name IN (host1, host2, ...)
    base_url = f"https://{SN_INSTANCE}.service-now.com/api/now/table/cmdb_ci_server"
    headers = get_auth_headers()

    # ServiceNow query: name^ORname=value for OR conditions
    # Due to URL length limits, we'll query in batches of 100
    enriched_count = 0
    skipped_duplicate_ci = 0
    skipped_missing_data = 0
    db_errors = 0
    batch_size = 100

    # Track sn_sys_id values we've already processed to prevent within-batch duplicates
    processed_sys_ids = set()

    for i in range(0, len(server_names), batch_size):
        batch = server_names[i:i + batch_size]

        # Build query string: nameIN host1,host2,host3
        name_query = ','.join(batch)

        params = {
            "sysparm_query": f"nameIN{name_query}",
            "sysparm_fields": "sys_id,name,ip_address,os,virtual,operational_status",
            "sysparm_exclude_reference_link": "true",
            "sysparm_limit": batch_size
        }

        try:
            response = requests.get(base_url, headers=headers, params=params, timeout=REQUEST_TIMEOUT)
            response.raise_for_status()

            servers = response.json().get("result", [])

            print(f"  SEARCH: ServiceNow returned {len(servers)} servers for batch {i // batch_size + 1}")

            # Update servers_dim with SNOW data
            for server in servers:
                try:
                    # Extract fields with better error handling and null checks
                    sys_id = extract_sys_id(server.get('sys_id'))
                    name = extract_sys_id(server.get('name'))
                    ip = extract_sys_id(server.get('ip_address'))
                    os = extract_sys_id(server.get('os'))
                    virtual_value = extract_sys_id(server.get('virtual'))
                    is_virtual = str(virtual_value).lower() == 'true' if virtual_value else False

                    # Safety check: ensure ALL fields are plain strings, not tuples (psycopg2 requirement)
                    # Check all fields that will be passed to cursor.execute()
                    tuple_fields = []
                    if isinstance(sys_id, (list, tuple)): tuple_fields.append(f"sys_id={type(sys_id).__name__}")
                    if isinstance(name, (list, tuple)): tuple_fields.append(f"name={type(name).__name__}")
                    if isinstance(ip, (list, tuple)): tuple_fields.append(f"ip={type(ip).__name__}")
                    if isinstance(os, (list, tuple)): tuple_fields.append(f"os={type(os).__name__}")

                    if tuple_fields:
                        print(f"  ⚠️  Skipping server with tuple/list fields: {', '.join(tuple_fields)}")
                        continue

                    # Skip if required fields are missing
                    if not sys_id or not name:
                        continue

                except Exception as field_error:
                    print(f"  ⚠️  Field extraction failed for server: {field_error}")
                    print(f"     Server keys: {list(server.keys())}")
                    print(f"     sys_id type: {type(server.get('sys_id'))}")
                    print(f"     name type: {type(server.get('name'))}")
                    print(f"     ip_address type: {type(server.get('ip_address'))}")
                    print(f"     os type: {type(server.get('os'))}")
                    print(f"     virtual type: {type(server.get('virtual'))}")
                    continue

                try:
                    # Ensure all values are properly typed (not tuples)
                    # Convert None to None (passthrough), everything else to string/bool
                    safe_sys_id = str(sys_id) if sys_id is not None else None
                    safe_ip = str(ip) if ip is not None else None
                    safe_os = str(os) if os is not None else None
                    safe_is_virtual = bool(is_virtual)  # Ensure boolean
                    safe_name = str(name) if name is not None else None

                    # Validate that we have the minimum required data
                    if not safe_sys_id or safe_sys_id == 'None':
                        print(f"  ⚠️  Skipping server '{safe_name}': missing sys_id")
                        print(f"     Raw sys_id: {sys_id!r}")
                        skipped_missing_data += 1
                        continue

                    if not safe_name or safe_name == 'None':
                        print(f"  ⚠️  Skipping server with sys_id '{safe_sys_id}': missing name")
                        skipped_missing_data += 1
                        continue

                    # Check if this sys_id was already used (in this batch OR database)
                    if safe_sys_id in processed_sys_ids:
                        skipped_duplicate_ci += 1
                        continue

                    # Check if sys_id already exists in database (even with different server_name)
                    cursor.execute("""
                        SELECT server_name FROM servers_dim
                        WHERE sn_sys_id = %s AND sn_sys_id NOT LIKE 'appd-%%'
                    """, (safe_sys_id,))

                    existing = cursor.fetchone()
                    if existing:
                        skipped_duplicate_ci += 1
                        continue

                    # Mark as processed before UPDATE
                    processed_sys_ids.add(safe_sys_id)

                    # Update the server
                    cursor.execute("""
                        UPDATE servers_dim
                        SET sn_sys_id = %s,
                            ip_address = %s,
                            os = %s,
                            is_virtual = %s,
                            updated_at = NOW()
                        WHERE server_name = %s
                          AND sn_sys_id LIKE 'appd-%%'
                    """, (safe_sys_id, safe_ip, safe_os, safe_is_virtual, safe_name))

                    if cursor.rowcount > 0:
                        enriched_count += cursor.rowcount
                except psycopg2.errors.UniqueViolation:
                    # Race condition: another process updated this sys_id between our check and UPDATE
                    # This is expected with concurrent ETL runs - just skip
                    skipped_duplicate_ci += 1
                    continue
                except psycopg2.Error as db_error:
                    # Other database errors (non-duplicate related)
                    error_type = type(db_error).__name__
                    print(f"  ❌ Database error updating server '{safe_name}':")
                    print(f"     Error type: {error_type}")
                    print(f"     Error message: {db_error}")
                    db_errors += 1
                    continue
                except ValueError as ve:
                    # Tuple detected in parameters - log details and skip
                    print(f"  ⚠️  Tuple in parameters: {ve}")
                    print(f"     sys_id={sys_id!r}, ip={ip!r}, os={os!r}, is_virtual={is_virtual!r}, name={name!r}")
                    continue
                except Exception as e:
                    # Non-database errors (shouldn't happen, but catch anyway)
                    if 'tuple index' in str(e).lower():
                        print(f"  ⚠️  Tuple index error at cursor.execute")
                        print(f"     sys_id={sys_id!r} (type: {type(sys_id).__name__})")
                        print(f"     ip={ip!r} (type: {type(ip).__name__})")
                        print(f"     os={os!r} (type: {type(os).__name__})")
                        print(f"     is_virtual={is_virtual!r} (type: {type(is_virtual).__name__})")
                        print(f"     name={name!r} (type: {type(name).__name__})")
                        continue
                    else:
                        print(f"  ⚠️  Unexpected error: {e}")
                        continue

        except Exception as e:
            import traceback
            print(f"  ⚠️  Batch {i // batch_size + 1} failed: {e}")
            print(f"     Error type: {type(e).__name__}")
            print(f"     Full traceback:")
            traceback.print_exc()
            # In autocommit mode, just continue to next batch
            continue

    cursor.close()

    print(f"\n  SUMMARY: Server Enrichment Summary:")
    print(f"     ✅ Successfully enriched: {enriched_count}")
    print(f"     INFO:  Skipped (duplicate SNOW CI): {skipped_duplicate_ci}")
    print(f"     ⚠️  Skipped (missing data): {skipped_missing_data}")
    print(f"     ❌ Database errors: {db_errors}")
    print(f"     TOTAL: Total servers processed: {len(appd_servers)}")

    if db_errors > 0:
        print(f"\n  ⚠️  WARNING: {db_errors} database errors occurred during enrichment")
        print(f"     Review error messages above for root cause analysis")

    return enriched_count

def run_snow_enrichment():
    """Phase 2: Enrich AppD apps with ServiceNow CMDB data using fuzzy matching"""
    print("=" * 70)
    print("ServiceNow Enrichment - Phase 2: Fuzzy Matching (SOW 2.4.3)")
    print("=" * 70)

    # Validate credentials
    if not SN_INSTANCE:
        print("⚠️  SN_INSTANCE not configured - skipping ServiceNow enrichment")
        print("   Pipeline will continue without CMDB data")
        print("   Applications will use AppDynamics data only")
        sys.exit(0)  # Exit success - this is optional enrichment

    if not (SN_CLIENT_ID and SN_CLIENT_SECRET) and not (SN_USER and SN_PASS):
        print("⚠️  No ServiceNow authentication credentials configured - skipping enrichment")
        print("   Pipeline will continue without CMDB data")
        print("   Applications will use AppDynamics data only")
        sys.exit(0)  # Exit success - this is optional enrichment

    print(f"ServiceNow Instance: {SN_INSTANCE}")
    print(f"Authentication: {'OAuth 2.0' if SN_CLIENT_ID else 'Basic Auth'}")
    print(f"Fuzzy Match Threshold: {FUZZY_MATCH_THRESHOLD * 100}% (SOW requirement)")
    print()

    # Connect to database
    try:
        conn = get_conn()
        print("✅ Database connected")
    except Exception as e:
        print(f"⚠️  Database connection failed: {e}")
        print("   ServiceNow enrichment skipped - pipeline will continue")
        sys.exit(0)  # Exit success - enrichment is optional

    try:
        # Load all SNOW apps into temp table
        snow_count = load_all_snow_applications(conn)

        if snow_count == 0:
            print("\n⚠️  No ServiceNow applications found")
            print("   Check ServiceNow instance and permissions")
            print("   Pipeline will continue without CMDB enrichment")
            conn.close()
            sys.exit(0)  # Exit success - enrichment is optional

        # Fuzzy match AppDynamics apps to SNOW
        matched_count = fuzzy_match_applications(conn)

        # Enrich servers with ServiceNow CMDB data
        server_count = enrich_servers_from_snow(conn)

        # Summary
        print("\n" + "=" * 70)
        print("✅ Phase 2 Complete: ServiceNow CMDB Enrichment")
        print("=" * 70)
        print(f"  ServiceNow CI Services loaded: {snow_count}")
        print(f"  AppDynamics apps matched: {matched_count}")
        print(f"  Servers enriched with CMDB data: {server_count}")
        print(f"  Matching algorithm: PostgreSQL SIMILARITY (pg_trgm)")
        print(f"  Confidence threshold: {FUZZY_MATCH_THRESHOLD * 100}% (SOW 2.4.3)")
        print()
        print("INFO:  Next: Run appd_finalize.py to generate chargeback and forecasts")
        print("=" * 70)

    except Exception as e:
        print("\n" + "=" * 70)
        print(f"⚠️  ServiceNow Enrichment Error: {e}")
        print("=" * 70)
        import traceback
        traceback.print_exc()
        print("\n⚠️  ServiceNow enrichment failed - pipeline will continue")
        print("   Applications will use AppDynamics data only")
        print("   You can re-run enrichment later with:")
        print("   python3 scripts/etl/snow_enrichment_fuzzy.py")
        print("=" * 70)
        sys.exit(0)  # Exit success - enrichment is optional

    finally:
        conn.close()


if __name__ == "__main__":
    run_snow_enrichment()
