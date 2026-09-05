# Stage 6 — PostgreSQL Streaming Replica

## Objective

Set up a PostgreSQL streaming replica for the PetClinic application.

The goal was to create a PostgreSQL standby that:

* Receives WAL from the primary PostgreSQL server.
* Continuously applies WAL changes.
* Supports read-only queries through Hot Standby.
* Rejects normal write operations.
* Remains synchronized with the primary database.
* Uses a dedicated replication user.
* Uses a physical replication slot to retain required WAL.
* Provides monitoring information from both the primary and replica.

---

## Architecture

The temporary Docker-based replication topology used for this stage is:

```text
                    WAL Streaming
┌──────────────────────┐
│ PostgreSQL Primary   │
│ petclinic-postgres   │
│ 172.23.0.2           │
└──────────┬───────────┘
           │
           │ TCP 5432
           │
           ▼
┌──────────────────────┐
│ PostgreSQL Replica   │
│ petclinic-postgres-  │
│ replica              │
│ 172.23.0.3           │
└──────────────────────┘
```

Both PostgreSQL containers communicate through the Docker bridge network:

```text
petclinic-repl
```

The host ports are:

```text
Primary  → 127.0.0.1:5432
Replica  → 127.0.0.1:5433
```

These host port mappings are only for local verification. PostgreSQL replication itself uses the Docker network.

---

## PostgreSQL Replication Concepts

### WAL

PostgreSQL uses Write-Ahead Logging (WAL).

Before a database change is considered committed, PostgreSQL records the required information in the WAL.

The WAL can then be used for:

* Crash recovery
* Point-in-time recovery
* Physical replication

In this stage, the replica receives WAL records from the primary and replays them locally.

### Streaming Replication

The primary continuously sends WAL records to the replica over a PostgreSQL connection.

The basic flow is:

```text
Application
    |
    v
Primary PostgreSQL
    |
    | WAL
    v
Replica PostgreSQL
    |
    v
Replay WAL
```

The replication configured in this stage is asynchronous.

This means the primary does not wait for the replica to finish replaying every WAL record before completing normal transactions.

---

## Primary Configuration

The primary PostgreSQL instance uses:

```text
PostgreSQL 16
```

The important replication settings were verified with:

```sql
SHOW wal_level;
SHOW max_wal_senders;
```

The resulting values were:

```text
wal_level = replica
max_wal_senders = 10
```

### wal_level

`wal_level=replica` provides the WAL information required for physical streaming replication.

### max_wal_senders

`max_wal_senders=10` allows the primary to create WAL sender processes for replication connections.

The value is higher than the single replica currently required.

---

## Replication User

A dedicated replication user was created instead of using the normal application database user.

```sql
CREATE ROLE replicator WITH REPLICATION LOGIN;
```

The role has:

```text
LOGIN
REPLICATION
```

This keeps replication credentials separate from the normal PetClinic application credentials.

The replication password is stored in the local `.env` file and is not committed to Git.

---

## pg_hba.conf

The primary PostgreSQL `pg_hba.conf` was configured to allow the replication user to connect from the Docker replication network.

The relevant rule is:

```text
host    replication    replicator    172.23.0.0/16    scram-sha-256
```

This means:

```text
database: replication
user:     replicator
network:  172.23.0.0/16
auth:     scram-sha-256
```

The existing general PostgreSQL authentication rule was kept unchanged.

After changing `pg_hba.conf`, the PostgreSQL configuration was reloaded:

```bash
docker exec petclinic-postgres \
psql -U petclinic -d petclinic \
-c "SELECT pg_reload_conf();"
```

---

## Replica Bootstrap

A separate data directory was created for the replica:

```text
/opt/petclinic/postgres-replica-data
```

The directory was owned by the PostgreSQL container user:

```text
UID 999
```

The replica was bootstrapped using `pg_basebackup`.

The base backup command connected to:

```text
host: petclinic-postgres
port: 5432
user: replicator
```

The important option was:

```text
-R
```

The `-R` option automatically prepares the backup to start as a standby.

As a result, PostgreSQL created:

```text
standby.signal
```

inside the replica data directory.

---

## standby.signal

The `standby.signal` file tells PostgreSQL that this data directory should start in standby mode.

The file does not contain the primary server address.

The connection information is stored separately in the PostgreSQL configuration.

The resulting startup flow is:

```text
standby.signal
      |
      v
PostgreSQL starts as Standby
      |
      v
Read primary_conninfo
      |
      v
Connect to Primary
      |
      v
Receive WAL
      |
      v
Replay WAL
```

---

## primary_conninfo

The replica uses `primary_conninfo` to know how to connect to the primary.

The connection points to the Docker service/container name:

```text
petclinic-postgres
```

rather than relying on a fixed container IP.

This is preferable in Docker because the container IP can change while the container name remains the stable service identity on the Docker network.

---

## Hot Standby

Hot Standby was verified on the replica:

```sql
SHOW hot_standby;
```

The result was:

```text
hot_standby = on
```

This allows the replica to accept read-only queries while it is continuously applying WAL from the primary.

---

## Replication Verification

### Primary-side verification

The following query was used:

```sql
SELECT
    client_addr,
    usename,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication;
```

The replica appeared with:

```text
client_addr = 172.23.0.3
usename     = replicator
state       = streaming
sync_state  = async
```

This proves that the primary has an active streaming replication connection.

The LSN values were also aligned at the time of verification.

---

### Replica-side verification

The replica was checked with:

```sql
SELECT
    status,
    sender_host,
    sender_port,
    slot_name,
    latest_end_lsn
FROM pg_stat_wal_receiver;
```

The result showed:

```text
status       = streaming
sender_host  = petclinic-postgres
sender_port  = 5432
```

This confirms that the replica itself is actively receiving WAL from the primary.

---

## Read-Only Verification

The replica successfully accepted read queries.

For example:

```sql
SELECT count(*) FROM owners;
```

The owner count matched the primary.

A write operation was also attempted on the replica:

```sql
CREATE TABLE replica_write_test(id int);
```

The operation was rejected because the replica is running in read-only standby mode.

This confirms that the replica is not being used as a normal writable PostgreSQL server.

---

## Replication Acceptance Test

A new owner was inserted into the primary database:

```sql
INSERT INTO owners
    (first_name, last_name, address, city, telephone)
VALUES
    ('Replication', 'Test', 'Test Address', 'Baku', '1234567890');
```

The record was then queried on the primary:

```sql
SELECT id, first_name, last_name
FROM owners
WHERE first_name = 'Replication';
```

The same record became visible on the replica:

```sql
SELECT id, first_name, last_name
FROM owners
WHERE first_name = 'Replication';
```

The total number of owners was also compared on both servers.

The counts matched.

Therefore:

```text
INSERT on Primary
       |
       v
      WAL
       |
       v
Streaming Replication
       |
       v
Replay on Replica
       |
       v
Same data visible on Replica
```

---

## Replication Slot

A physical replication slot was created on the primary:

```sql
SELECT *
FROM pg_create_physical_replication_slot('petclinic_replica');
```

The slot was verified with:

```sql
SELECT
    slot_name,
    slot_type,
    active,
    restart_lsn
FROM pg_replication_slots;
```

The resulting slot was:

```text
slot_name = petclinic_replica
slot_type = physical
active    = true
```

The replica was configured with:

```text
primary_slot_name = 'petclinic_replica'
```

### Why use a replication slot?

A replication slot helps the primary retain WAL that a replica may still need.

For example:

```text
Primary
  |
  | WAL
  |
  X  Replica temporarily disconnected
```

The slot prevents PostgreSQL from removing required WAL too early.

When the replica reconnects, it can continue receiving the WAL it still needs.

Replication slots must be monitored because an inactive slot can cause WAL to accumulate on the primary.

---

## Final Verification

The following requirements were successfully verified:

| Requirement                         | Status |
| ----------------------------------- | ------ |
| PostgreSQL 16 primary               | ✅      |
| PostgreSQL 16 replica               | ✅      |
| `wal_level=replica`                 | ✅      |
| `max_wal_senders` configured        | ✅      |
| Dedicated replication user          | ✅      |
| `pg_hba.conf` replication rule      | ✅      |
| `pg_basebackup`                     | ✅      |
| `standby.signal`                    | ✅      |
| `primary_conninfo`                  | ✅      |
| WAL streaming                       | ✅      |
| Hot Standby                         | ✅      |
| Read-only replica                   | ✅      |
| Primary → Replica data replication  | ✅      |
| `pg_stat_replication` verification  | ✅      |
| `pg_stat_wal_receiver` verification | ✅      |
| Physical replication slot           | ✅      |
| Acceptance test                     | ✅      |

---

## Files

The replication setup uses:

```text
postgres-db/
├── docker-compose-primary.yaml
├── docker-compose-replica.yaml
└── docker-compose-basebackup.yaml
```

The PostgreSQL data directories are stored outside the repository:

```text
/opt/petclinic/postgres-data
/opt/petclinic/postgres-replica-data
```

Credentials are stored in:

```text
.env
```

and `.env` is excluded from Git.

---

## Result

Stage 6 was completed successfully.

The PostgreSQL primary is continuously streaming WAL to the PostgreSQL standby. The standby operates in Hot Standby mode, accepts read-only queries, rejects writes, and successfully receives and replays changes from the primary.

The setup also includes a physical replication slot to improve WAL retention behavior when the replica temporarily disconnects.
