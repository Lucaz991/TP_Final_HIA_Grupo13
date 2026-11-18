// Montado SOLO por compose.security-test.yaml. No contiene clientes de Google.
module.exports = {
    async agendarTutoria(tutoria) {
        console.log('H24: Calendar simulado para tutoria', tutoria.id);
        return {
            exito: true,
            idEvento: `h24-simulated-${tutoria.id}`,
            linkCalendario: null,
            linkMeet: null
        };
    },
    async cancelarTutoria() {
        console.log('H24: cancelacion de Calendar simulada');
        return { exito: true };
    }
};
