# Build stage 
FROM eclipse-temurin:17-jdk AS build
WORKDIR /app
COPY . .
RUN ./mvnw -DskipTests package

# Runtime stage 
FROM eclipse-temurin:17-jre
WORKDIR /app

# Create a non-root user
RUN useradd --create-home --shell /bin/bash petclinic
COPY --from=build /app/target/*.jar /app/petclinic.jar
RUN chown -R petclinic:petclinic /app
USER petclinic

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/petclinic.jar"]
