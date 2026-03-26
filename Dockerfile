FROM eclipse-temurin:21-jdk-alpine AS build

WORKDIR /workspace

COPY . .
RUN sed -i 's/\r$//' gradlew && \
    chmod +x gradlew && \
    ./gradlew clean test bootWar --no-daemon

FROM eclipse-temurin:21-jre-alpine AS runtime

WORKDIR /app

COPY --from=build /workspace/build/libs/*.war /app/app.war

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.war"]