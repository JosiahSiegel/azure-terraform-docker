FROM node:15-alpine

ENV USER=node

COPY . /src
RUN chmod -R 777 /src/server.js
RUN cd /src && npm install
EXPOSE 3000

HEALTHCHECK CMD curl --fail http://localhost:3000 || exit 1   

CMD ["node", "/src/server.js"]

USER "${USER}"
