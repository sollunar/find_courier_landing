FROM node:18-alpine AS build
WORKDIR /app

RUN apk add --no-cache git

ARG REPO_URL=https://github.com/username/find_courier_landing.git
ARG REPO_BRANCH=main
RUN git clone --branch $REPO_BRANCH $REPO_URL .

RUN npm install
RUN npm run build

FROM nginx:alpine

COPY --from=build /app/build /usr/share/nginx/html

COPY nginx.conf /etc/nginx/conf.d/default.conf

# Optional: Mount SSL certs via volumes
# /etc/nginx/ssl/findcourier.crt
# /etc/nginx/ssl/findcourier.key

CMD ["nginx", "-g", "daemon off;"]
