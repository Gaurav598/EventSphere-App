# Stage 1: Build the Flutter app for web
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app
COPY . .
RUN flutter pub get
RUN flutter build web

# Stage 2: Serve with Nginx
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
