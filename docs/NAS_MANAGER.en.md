# NAS Management Service

`nas-manager` is an optional LAN web page that controls an iPad running NAS Photo Frame over SSH. It can display status, change photo-frame settings and display/charging policies, turn the screen off or on, and restart the application.

## Security Boundary

The service uses HTTP Basic Authentication but does not include TLS. Run it only on a trusted local network. Access from another network must pass through a reverse proxy with HTTPS and access control. Never expose the container port or the iPad's SSH service to the public internet.

## Configuration

```sh
cd nas-manager
cp .env.example .env
```

Edit `.env`:

```dotenv
PORT=8787
IPAD_HOST=192.168.1.100
IPAD_USER=root
ADMIN_USER=admin
ADMIN_PASSWORD=replace-with-a-long-random-password
```

Both `.env` and `data/` are ignored and will not be committed to Git. Start the service with:

```sh
docker compose up -d --build
docker compose logs -f
```

## Initial SSH Authorization

On its first start, the container generates a dedicated RSA key under `nas-manager/data/ssh/`. Open the management page and sign in to view the public key. Append that key to the iPad root user's `authorized_keys`, then reload the page.

Copy only the contents of the `.pub` public-key file. Never copy the `id_rsa` private key into the project directory, a chat conversation, or Git.

## Updating

```sh
git pull --ff-only
docker compose up -d --build
```

Install the application's `.deb` from the build machine or through your own controlled release process. The repository does not include deployment scripts tied to a personal NAS directory, username, IP address, or fixed package version.

## Data Directory

`data/` contains the SSH private key, `known_hosts`, and the administrator password file updated by the page. Back it up securely and restrict it to administrators. Deleting this directory removes the private key authorized on the iPad and causes a new key to be generated the next time the service starts.
