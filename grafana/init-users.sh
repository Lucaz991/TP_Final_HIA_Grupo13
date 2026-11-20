#!/bin/sh
set -e

echo "Esperando que Grafana este listo..."
until curl -s -f -u admin:admin http://localhost:3000/api/health > /dev/null 2>&1; do
    sleep 2
done

echo "Inicializando usuarios del Grupo 13..."

create_user() {
    name="$1"
    email="$2"
    login="$3"
    password="$4"

    response=$(curl -s -w "%{http_code}" -u admin:admin \
        -X POST http://localhost:3000/api/admin/users \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$name\",\"email\":\"$email\",\"login\":\"$login\",\"password\":\"$password\"}")

    code=$(echo "$response" | tail -c 4)
    if [ "$code" = "200" ]; then
        echo "Usuario $login creado correctamente."
    else
        echo "Usuario $login ya existe o omitido (HTTP $code)."
    fi
}

create_user "Matias Churquina" "matiasdanielchurquina@gmail.com" "matiaschurquina" "matias12345"
create_user "Abigail Teran" "abigail.teran321@gmail.com" "abigailteran" "abigail12345"
create_user "Rodrigo Guanactolay" "guanactolayrodrigo6@gmail.com" "rodrigoguanactolay" "rodrigo12345"
create_user "Lucas Zerpa" "lenkagamine268@gmail.com" "lucaszerpa" "lucas12345"
create_user "Lujan Cansino" "celestelujancansino@gmail.com" "lujancansino" "lujan12345"

echo "Usuarios de Grafana aprovisionados con exito."
