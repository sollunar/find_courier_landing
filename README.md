# Getting Started with Create React App

This project was bootstrapped with [Create React App](https://github.com/facebook/create-react-app).

## Available Scripts

In the project directory, you can run:

### `npm start`

Runs the app in the development mode.\
Open [http://localhost:3000](http://localhost:3000) to view it in the browser.

The page will reload if you make edits.\
You will also see any lint errors in the console.

### `npm test`

Launches the test runner in the interactive watch mode.\
See the section about [running tests](https://facebook.github.io/create-react-app/docs/running-tests) for more information.

### `npm run build`

Builds the app for production to the `build` folder.\
It correctly bundles React in production mode and optimizes the build for the best performance.

The build is minified and the filenames include the hashes.\
Your app is ready to be deployed!

See the section about [deployment](https://facebook.github.io/create-react-app/docs/deployment) for more information.

## Caddy camouflage deployment for Remnawave

The Caddy deployment builds the same React application without changing its
design. Caddy serves HTTPS only on the local REALITY target port, while Xray
owns public port `443`. Public port `80` remains available to Caddy for ACME
HTTP-01 certificate issuance and renewal.

Prerequisites:

- Docker with Docker Compose v2 (already installed on a Remnawave Node)
- an IPv4 `A` record pointing the camouflage domain directly to the node
- Cloudflare proxying disabled for that record, when Cloudflare DNS is used
- public `80/tcp` available; local port `11120` must not be exposed

Run on each node with that node's own hostname:

```bash
./install-caddy.sh \
  --domain nl1.find-courier.com \
  --email admin@find-courier.com \
  --open-firewall
```

The installer validates DNS and occupied ports, creates the untracked
`.env.caddy`, builds `Dockerfile.caddy`, starts
`docker-compose.caddy.yml`, waits for a valid certificate, and prints the
matching Remnawave REALITY settings.

Useful lifecycle commands:

```bash
CADDY_ENV_FILE=.env.caddy docker compose -f docker-compose.caddy.yml ps
CADDY_ENV_FILE=.env.caddy docker compose -f docker-compose.caddy.yml logs -f
CADDY_ENV_FILE=.env.caddy docker compose -f docker-compose.caddy.yml up -d --build
```

### `npm run eject`

**Note: this is a one-way operation. Once you `eject`, you can’t go back!**

If you aren’t satisfied with the build tool and configuration choices, you can `eject` at any time. This command will remove the single build dependency from your project.

Instead, it will copy all the configuration files and the transitive dependencies (webpack, Babel, ESLint, etc) right into your project so you have full control over them. All of the commands except `eject` will still work, but they will point to the copied scripts so you can tweak them. At this point you’re on your own.

You don’t have to ever use `eject`. The curated feature set is suitable for small and middle deployments, and you shouldn’t feel obligated to use this feature. However we understand that this tool wouldn’t be useful if you couldn’t customize it when you are ready for it.

## Learn More

You can learn more in the [Create React App documentation](https://facebook.github.io/create-react-app/docs/getting-started).

To learn React, check out the [React documentation](https://reactjs.org/).
