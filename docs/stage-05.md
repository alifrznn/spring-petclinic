# Stage 05 — PostgreSQL Primary

## Objective

Deploy PostgreSQL for the PetClinic application with persistent storage, a dedicated database and user, initial application data, restricted network access, and protected credentials.

---

## Requirements

### 1. Persistent Storage

PostgreSQL uses a host bind mount instead of the container's ephemeral filesystem.

The PostgreSQL data directory is stored at:

```text
/opt/petclinic/postgres-data
```

It is mounted into the container at:

```text
/var/lib/postgresql/data
```

This ensures that PostgreSQL data survives container recreation.

The PostgreSQL container is configured with:

```yaml
volumes:
  - /opt/petclinic/postgres-data:/var/lib/postgresql/data
```

---

### 2. Dedicated Database and User

A dedicated PostgreSQL database and user were created for PetClinic.

```text
Database: petclinic
User: petclinic
```

The application connects to PostgreSQL using these credentials.

---

### 3. Non-Ephemeral PostgreSQL Filesystem

PostgreSQL does not rely on the container's writable filesystem for database persistence.

The data is stored on the host filesystem:

```text
/opt/petclinic/postgres-data
```

The directory is owned by the PostgreSQL container user (UID/GID 999), allowing PostgreSQL to read and write its database files correctly.

---

### 4. Restricted Network Access

For the current local development environment, PostgreSQL is bound only to the local loopback interface:

```yaml
ports:
  - "127.0.0.1:5432:5432"
```

This prevents PostgreSQL from being directly exposed on all host network interfaces.

The current architecture is temporary because the final deployment will use dedicated Linux nodes and a private network.

In the final infrastructure, PostgreSQL access will be restricted to the required application and replication nodes.

---

### 5. Database and Schema

The `petclinic` database was created successfully.

The application initialized the required PostgreSQL schema.

The following tables were verified:

```text
owners
pets
specialties
types
vet_specialties
vets
visits
```

---

### 6. Initial / Sample Data

The application's initial/sample data was successfully loaded into PostgreSQL.

The following records were verified:

```text
owners:  10
pets:    13
vets:     6
visits:   4
```

The PetClinic application was successfully connected to this PostgreSQL database and the web application was verified to work.

---

### 7. Secret Management

PostgreSQL credentials are provided through environment variables rather than being embedded directly in the Docker Compose configuration.

The credentials are stored in a `.env` file.

Example:

```dotenv
POSTGRES_DB=petclinic
POSTGRES_USER=petclinic
POSTGRES_PASSWORD=<secret>
```

The `.env` file is excluded from Git using `.gitignore` so that production credentials are not committed to the repository.

---

## Verification

The PostgreSQL container was verified to be running and accepting connections.

The database connection was tested using:

```bash
docker exec -it petclinic-postgres psql -U petclinic -d petclinic
```

The application was also successfully started using the PostgreSQL Spring profile:

```bash
./mvnw spring-boot:run -Dspring-boot.run.profiles=postgres
```

The PetClinic application successfully connected to PostgreSQL and served the web interface on port `8080`.

---

## Final Status

All requirements for Stage 05 have been implemented and verified.

| Requirement                      | Status |
| -------------------------------- | ------ |
| Persistent storage               | ✅      |
| Dedicated database/user          | ✅      |
| Non-ephemeral PostgreSQL storage | ✅      |
| Restricted network access        | ✅      |
| Database and schema              | ✅      |
| Initial/sample data              | ✅      |
| Secret management                | ✅      |

**Stage 05 — PostgreSQL Primary: COMPLETE ✅**
