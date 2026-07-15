# MySQL

The local MySQL service is used for structured backend data in development.

Use `deploy/.env` based on `deploy/.env.example` for local credentials.
Do not commit real passwords. Business Flyway migrations are intentionally
deferred until the auth foundation task.
