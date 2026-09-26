# helloworld: check that a host is reachable

Minimal web server for connectivity testing. There is no application: the only
process is `nginx:alpine-slim` reading a config file. Response body and status
code are set from `.env`, served over HTTP and HTTPS at the same time.

Under 50 KB of files and a 21 MB image. No build, no custom image, no
dependencies to install.

## Getting started

```sh
cp env.example .env      # documented template; adjust the ports
docker compose up -d
curl http://127.0.0.1:8080/          # -> Hello World
curl -k https://127.0.0.1:8443/      # -k is only needed for the test certificate
docker compose ps                     # -> Up (healthy)
```

To serve on 80/443, which need root to bind:

```sh
sed -i 's/HTTP_PORT=8080/HTTP_PORT=80/; s/HTTPS_PORT=8443/HTTPS_PORT=443/' .env
docker compose up -d
```

## Changing the response

Edit `.env` and start it again. **`docker compose up -d` is mandatory**:
`restart` restarts the container with its configuration already frozen and does
not read the `.env` again.

```sh
STATUS=500  # in .env
docker compose up -d
curl -i http://127.0.0.1:8080/   # -> HTTP/1.1 500 ... with the BODY text
```

| Variable     | Default        | What it does                          |
|--------------|----------------|---------------------------------------|
| `HTTP_PORT`  | `8080`         | Port published on the host for HTTP   |
| `HTTPS_PORT` | `8443`         | Port published on the host for HTTPS  |
| `STATUS`     | `200`          | Response code, from 200 to 599        |
| `BODY`       | `Hello World`  | Response body                         |

`env.example` documents all four variables. `BODY` accepts no double quotes, no
newlines and no `$`: it goes inside quotes in the nginx config.

## HTTPS

Drop your own pair at `tls/cert.pem` and `tls/key.pem`, then start it again with
`docker compose up -d`. No other file needs to be touched.

```sh
cp my-certificate.pem tls/cert.pem
cp my-private-key.pem tls/key.pem
docker compose up -d
curl https://my-host:8443/    # validates the chain, no -k
```

Out of the box, `tls/` ships a **self-signed test certificate**, generic and valid
for 10 years, so HTTPS starts without requesting anything. It contains no host
name and no IP from any machine: it is the same file on every server.

**That certificate protects nothing.** It is a public key anyone has; its only
purpose is to make port 443 open and testable.

Because the generic certificate only covers `localhost` and `127.0.0.1`, clients
connect like this:

```sh
curl --cacert tls/cert.pem https://localhost:8443/   # validates the chain, no -k
curl -k https://192.0.2.1:8443/                     # by real IP or name, with -k
```

For a certificate that matches your server name, which **you should not commit**
because it embeds the hostname and the machine IPs:

```sh
./scripts/gen-cert.sh --host --force
```

## If something fails

- **`docker compose ps` shows `Restarting`**: check `docker compose logs`.
  `invalid return code` means a `STATUS` outside 100-999 or a non-numeric one.
- **Nothing answers on HTTP either**: if `cert.pem` and `key.pem` are not the same
  pair, nginx does not start and port 80 goes down with it. The log says
  `key values mismatch`.
- **You changed the `.env` and nothing changed**: `restart` does not read it, use
  `up -d`.

## Useful commands

```sh
./scripts/test.sh       # smoke tests: brings the stack up, checks it, tears it down
docker compose ps       # status and health
docker compose logs -f  # access logs live (nginx writes them to stdout)
docker compose restart  # restart WITHOUT re-reading the .env
docker compose down     # stop and remove
```

The technical decisions and their reasons live in the comments of the files
themselves and in `AGENTS.md`.

## License, version and author

- **License**: MIT, see [LICENSE](LICENSE)
- **Version**: [VERSION](VERSION), history in [CHANGELOG.md](CHANGELOG.md)
- **Author**: [kopernix](https://github.com/kopernix)
- **Repository**: <https://github.com/kopernix/hello-world-webserver>
