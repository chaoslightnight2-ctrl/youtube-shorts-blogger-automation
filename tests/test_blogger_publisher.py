from pathlib import Path

from src.blogger_publisher import BloggerPublisher


def test_credentials_from_refresh_token_uses_client_secret_json():
    client_secret = Path(__file__).parent / "fixtures" / "client_secret.json"
    publisher = BloggerPublisher(
        blog_id="123",
        client_secret_file=str(client_secret),
        token_file="unused-token.json",
        refresh_token="refresh-token",
    )

    creds = publisher._credentials_from_refresh_token()

    assert creds.refresh_token == "refresh-token"
    assert creds.client_id == "client-id.apps.googleusercontent.com"
    assert creds.client_secret == "client-secret"
    assert creds.token_uri == "https://oauth2.googleapis.com/token"
