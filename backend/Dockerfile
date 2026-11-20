# imagen Node.js basada en Alpine Linux para un contenedor más ligero 
FROM node:20-alpine

# directorio trabajo
WORKDIR /app

COPY package*.json ./

RUN npm install

# copiar el codigo fuente de la aplicación al contenedor
COPY . .

# expone el puerto configurado en index.js
EXPOSE 3000

# iniciar aplicacion
CMD ["npm", "start"]