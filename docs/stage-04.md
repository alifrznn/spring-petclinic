# Stage 4 — Run the Application

## Environment
- Java: 17
- Build tool: Maven Wrapper

## Default Database
- H2

## Application Port
- 8080

## PostgreSQL
- Spring Profile: postgres
- Configuration: application-postgres.properties
- Default URL: jdbc:postgresql://localhost/petclinic

## Verification
Application successfully started with:
./mvnw spring-boot:run

Application was accessible at:
http://localhost:8080
