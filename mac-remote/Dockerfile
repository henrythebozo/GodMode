# Mac Remote relay. Build context = the mac-remote folder.
FROM node:22-alpine
WORKDIR /app
COPY package.json ./
COPY lib/ws.js ./lib/ws.js
COPY relay ./relay
ENV NODE_ENV=production PORT=8080
EXPOSE 8080
USER node
CMD ["node", "relay/relay.js"]
