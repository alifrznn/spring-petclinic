# Stage 07 — Containerize the Application

## Objective

The goal of this stage was to containerize the Spring PetClinic application and make sure that the application can run inside a Docker container and connect to the PostgreSQL database.

The containerized application must:

* Use a suitable Java base image.
* Run as a non-root user.
* Receive database configuration through environment variables.
* Provide a health check.
* Keep the final image reasonably small.
* Successfully connect to PostgreSQL.

---

## Dockerfile

A multi-stage Dockerfile was created.

### Build stage

The build stage uses Java 17 JDK and Maven Wrapper to compile and package the application.

```dockerfile
FROM eclipse-temurin:17-jdk AS build

WORKDIR /app

COPY . .

RUN ./mvnw -DskipTests package
```

The JDK is required during the build because Maven needs the Java compiler to create the application JAR file.

### Runtime stage

The runtime stage uses a Java 17 JRE image.

```dockerfile
FROM eclipse-temurin:17-jre

WORKDIR /app

RUN useradd --create-home --shell /bin/bash petclinic

COPY --from=build /app/target/*.jar /app/petclinic.jar

RUN chown -R petclinic:petclinic /app

USER petclinic

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/petclinic.jar"]
```

The final image contains only the JRE and the generated application JAR instead of the complete Maven build environment.

This reduces the size and attack surface of the runtime container.

---

## Non-Root User

The application does not run as root.

A dedicated user named `petclinic` was created:

```dockerfile
RUN useradd --create-home --shell /bin/bash petclinic
```

The application directory is owned by this user:

```dockerfile
RUN chown -R petclinic:petclinic /app
```

Then Docker switches to the user:

```dockerfile
USER petclinic
```

This follows the principle of least privilege and reduces the impact of a potential application compromise.

---

## Docker Build

The image was built with:

```bash
docker build -t petclinic:1.0 .
```

The image was successfully created with the tag:

```text
petclinic:1.0
```

---

## Database Configuration

The application uses the PostgreSQL Spring profile:

```text
SPRING_PROFILES_ACTIVE=postgres
```

The database connection is configured using environment variables.

The application container was tested with:

```bash
docker run --rm \
  --name petclinic-app \
  --network petclinic-repl \
  -p 8080:8080 \
  -e SPRING_PROFILES_ACTIVE=postgres \
  -e POSTGRES_URL=jdbc:postgresql://petclinic-postgres:5432/petclinic \
  -e POSTGRES_USER=petclinic \
  -e POSTGRES_PASS=petclinic \
  petclinic:1.0
```

The application successfully started and connected to PostgreSQL.

### Why `petclinic-postgres` instead of `localhost`?

Inside a Docker container, `localhost` refers to the container itself.

Therefore, the application cannot use:

```text
jdbc:postgresql://localhost:5432/petclinic
```

to reach the PostgreSQL container.

Both containers are connected to the Docker network:

```text
petclinic-repl
```

Therefore, the PostgreSQL container can be reached using its Docker container name:

```text
petclinic-postgres
```

The connection path is:

```text
PetClinic container
       |
       | Docker network: petclinic-repl
       |
       v
petclinic-postgres:5432
       |
       v
PostgreSQL
```

---

## Environment Variables with Docker Compose

The Docker Compose configuration uses the project's `.env` file instead of hard-coding database credentials.

Example:

```yaml
environment:
  SPRING_PROFILES_ACTIVE: postgres
  POSTGRES_URL: jdbc:postgresql://petclinic-postgres:5432/${POSTGRES_DB}
  POSTGRES_USER: ${POSTGRES_USER}
  POSTGRES_PASS: ${POSTGRES_PASSWORD}
```

The `.env` file contains the database configuration and is excluded from Git using `.gitignore`.

This prevents database credentials from being committed to the repository.

---

## Health Check

Spring Boot Actuator is available in the application.

The health endpoint was tested from inside the container:

```bash
curl http://localhost:8080/actuator/health
```

The application returned:

```json
{
  "groups": [
    "liveness",
    "readiness"
  ],
  "status": "UP"
}
```

Docker Compose uses this endpoint for the container health check:

```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -fsS http://localhost:8080/actuator/health || exit 1"]
  interval: 30s
  timeout: 10s
  retries: 5
  start_period: 60s
```

This checks the actual Spring Boot application health rather than only checking whether port `8080` is open.

---

## Docker Compose

The application can also be started through Docker Compose.

The Compose service uses:

```text
petclinic:1.0
```

and connects to the existing:

```text
petclinic-repl
```

Docker network.

The database credentials are loaded from `.env`.

The application can therefore be started using:

```bash
docker compose up -d
```

Its status can be checked using:

```bash
docker ps
```

A healthy container should show:

```text
(healthy)
```

---

## Dockerignore

A `.dockerignore` file was created to prevent unnecessary files from being sent to the Docker build context.

Files and directories excluded include:

* Git files
* IDE files
* Maven/Gradle build output
* `.env` files
* Documentation
* PostgreSQL infrastructure files
* Docker Compose files
* Development configuration
* Logs

The Docker build only needs the application source, Maven configuration, Maven Wrapper, and Dockerfile.

---

## Multi-Stage Build

The Dockerfile uses two stages:

```text
Build Stage
eclipse-temurin:17-jdk
        |
        | Maven build
        v
   PetClinic JAR
        |
        v
Runtime Stage
eclipse-temurin:17-jre
        |
        v
PetClinic application
```

The build environment is not included in the final runtime image.

This provides:

* Smaller runtime image
* Fewer unnecessary tools
* Reduced attack surface
* Separation between build and runtime environments

---

## Verification

The following tests were successfully completed:

### Image build

```bash
docker build -t petclinic:1.0 .
```

Result:

```text
SUCCESS
```

### Application startup

The container successfully started the Spring Boot application.

### PostgreSQL connection

The application successfully connected to:

```text
petclinic-postgres:5432
```

using the PostgreSQL Spring profile.

### Application endpoint

PetClinic was accessible on:

```text
http://localhost:8080
```

### Health endpoint

```bash
curl http://localhost:8080/actuator/health
```

returned:

```json
{
  "status": "UP"
}
```

### Non-root execution

The application runs as:

```text
petclinic
```

instead of root.

---

## Result

Stage 07 is complete.

The PetClinic application is now packaged as a Docker image and can run as a non-root container.

The application receives its PostgreSQL configuration through environment variables, connects to the PostgreSQL primary through the Docker network, and exposes a Spring Boot health endpoint that is used by Docker Compose for health monitoring.

Image:

```text
petclinic:1.0
```

Application port:

```text
8080
```

Database:

```text
PostgreSQL
```

Docker network:

```text
petclinic-repl
```

Health endpoint:

```text
/actuator/health
```

Status:

```text
COMPLETE
```
