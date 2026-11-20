const auditoriaService = require("../services/auditoria.service");

const registrarAuditoria = async (
    req,
    accion,
    entidad,
    entidadId,
    descripcion,
    usuarioId = null
) => {

    try {

        await auditoriaService.registrar({

            usuario_id:
                usuarioId ||
                req.user?.id ||
                req.usuario?.id ||
                req.body?.id_usuario ||
                null,

            accion,

            entidad,

            entidad_id: entidadId,

            descripcion,

            ip: req.ip,

            user_agent: req.headers["user-agent"]

        });

    } catch (error) {

        console.error("Error registrando auditoría");

        console.error(error);

    }

};

module.exports = registrarAuditoria;