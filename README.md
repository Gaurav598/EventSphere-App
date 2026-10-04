# EventSphere

A production-grade Event Management Platform where organizations create and manage events, and users discover and register for them.

## Architecture Decisions

- **FastAPI**: Selected for its asynchronous capabilities, exceptional performance, and robust type-hinting support via Pydantic, ensuring strong API contracts.
- **MongoDB**: Used as the primary database due to its flexible document schema, making it ideal for storing dynamic event structures and scaling horizontally.
- **Redis**: Provides caching, rate limiting and best-effort realtime event publication. Durable ticket work is persisted in MongoDB and does not depend on Redis Pub/Sub delivery.
- **Flutter**: Chosen for its single-codebase cross-platform capabilities, enabling the creation of performant, natively compiled applications for iOS, Android, and Web from one codebase.
- **Docker**: Containerization ensures absolute consistency across development, testing, and production environments, eliminating "it works on my machine" issues.
- **JWT (JSON Web Tokens)**: Used for stateless, secure authentication. It allows horizontal scaling of the backend API without managing session state in a centralized database.
- **Persistent ticket worker**: Ticket jobs are stored in MongoDB before registration responses return. An in-process worker leases and retries those jobs; FastAPI `BackgroundTasks` is only an immediate fast path.

## Tech Stack
| Layer | Technology |
|---|---|
| Mobile Frontend | Flutter |
| Backend API | FastAPI (Python) |
| Primary Database | MongoDB |
| Cache / Pub-Sub | Redis |
| Containerization | Docker + Docker Compose |
| Testing | Pytest |

## Prerequisites
- Docker and Docker Compose
- Flutter SDK (for mobile/web development)
- Python 3.11+ (for local backend development)

## Installation & Setup

1. **Clone the repository:**
   ```bash
   git clone <repository_url>
   cd eventsphere
   ```

2. **Configure the environment:**
   ```bash
   cp .env.example .env
   ```
   Set a strong `JWT_SECRET` and a private `ORGANIZER_SIGNUP_CODE`. This upgrade is intended for local/manual verification before any production deployment.

3. **Start the application:**
   ```bash
   docker compose up --build -d
   ```

## Local Development
The `docker-compose.override.yml` is automatically used by Docker Compose to bind-mount the backend directory into the container. Code changes to the FastAPI backend will trigger an automatic reload via uvicorn.

- **API Base URL (Docker Compose)**: `http://localhost:8001/api/v1`
- **API Interactive Docs (Swagger)**: `http://localhost:8001/docs`
- **Health Check**: `http://localhost:8001/health`

## Testing

### Backend
To run tests locally within the container:
```bash
docker compose exec fastapi pytest -v
```

### Frontend
```bash
cd frontend
flutter analyze
flutter test
```

## API Documentation
Full API specification and architectural documentation are available in the [`docs/`](./docs) directory.
Upgrade-specific references are in [`ARCHITECTURE.md`](./ARCHITECTURE.md),
[`REGISTRATION_AND_TICKETING.md`](./REGISTRATION_AND_TICKETING.md),
[`API_REFERENCE.md`](./API_REFERENCE.md), and
[`MANUAL_TESTING_GUIDE.md`](./MANUAL_TESTING_GUIDE.md).

## Project Structure
- `/backend`: FastAPI application source code, models, routers, and services.
- `/frontend`: Flutter application, providers, UI screens, and core networking.
- `/docs`: Markdown files for system architecture, database design, and feature requirements.
- `docker-compose.yml`: Production-ready service definitions.
- `docker-compose.override.yml`: Local development overrides (bind mounts).

## Screenshots
*(Insert screenshots of the User and Admin flows here)*
