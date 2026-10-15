"""Custom OpenAPI schema generation."""


def custom_openapi(app):
    """Generate custom OpenAPI schema with security definitions."""
    if app.openapi_schema:
        return app.openapi_schema

    from fastapi.openapi.utils import get_openapi

    openapi_schema = get_openapi(
        title="Quản Lý Kho Trà Sữa API",
        version="0.1.0",
        description="API quản lý nhập, xuất và tồn nguyên vật liệu quán trà sữa.",
        routes=app.routes,
    )

    # Add security schemes
    openapi_schema["components"]["securitySchemes"] = {
        "BearerAuth": {
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "JWT",
            "description": "JWT Bearer token for authentication",
        }
    }

    # Public paths theo docs/06:9 — không gắn BearerAuth để Swagger không
    # đòi Authorize cho login/health (test_openapi_security...).
    public_paths = {
        "/auth/login",
        "/auth/register",
        "/auth/refresh",
        "/auth/logout",
        "/auth/google",
        "/me",
        "/health/live",
        "/health/ready",
    }

    # Define security requirements for protected operations only
    for path, methods in openapi_schema["paths"].items():
        if path in public_paths:
            continue
        for method, spec in methods.items():
            if method in ("get", "post", "put", "patch", "delete"):
                spec["security"] = [{"BearerAuth": []}]

    app.openapi_schema = openapi_schema
    return app.openapi_schema
