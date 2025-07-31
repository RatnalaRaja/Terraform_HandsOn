

FROM node:18-alpine AS build
WORKDIR /app
COPY client/package.json client/yarn.lock ./client/
RUN cd client && yarn install
COPY client/ ./client/
RUN cd client && yarn build


FROM node:18-alpine
WORKDIR /app
COPY server/package.json server/yarn.lock ./server/
RUN cd server && yarn install
COPY server/ ./server/


COPY --from=build /app/client/build ./client/build

EXPOSE 3001
CMD ["node", "server/index.js"]

