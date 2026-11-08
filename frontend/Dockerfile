# ==========================================
# Etapa 1: compilación angular
# ==========================================
FROM node:20-alpine as build
WORKDIR /app

# dependencias de la aplicación
COPY package*.json ./
RUN npm install --legacy-peer-deps

# copiar codigo fuente
COPY . .

# compila el proyecto
RUN npm run build -- --configuration production

# ==========================================
# Etapa 2: servidor web nginx
# ==========================================
FROM nginx:alpine

# copia los archivos compilados en la etapa anterior y los coloca en el directorio de nginx
COPY --from=build /app/dist/proyfrontendgrupo04/browser /usr/share/nginx/html

EXPOSE 80

# iniciar
CMD ["nginx", "-g", "daemon off;"]