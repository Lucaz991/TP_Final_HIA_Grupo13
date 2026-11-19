const aiService = require('../services/ai.service');
const contextService = require('../services/context.service');

const chatCtrl = {};

chatCtrl.sendMessage = async (req, res) => {
    /* #swagger.tags = ['Chat']
       #swagger.summary = 'Consultar al asistente de IA'
       #swagger.description = 'Recibe una consulta, genera un prompt con el contexto del sistema de tutorías y retorna la respuesta de la IA.'
       #swagger.consumes = ['application/json']
       #swagger.parameters['body'] = {
         in: 'body',
         description: 'Mensaje para la IA.',
         required: true,
         schema: { $ref: '#/definitions/ChatRequest' }
       }
       #swagger.responses[200] = {
         description: 'Respuesta generada correctamente por la IA.',
         schema: { $ref: '#/definitions/ChatResponse' }
       }
       #swagger.responses[400] = { description: 'El mensaje no puede estar vacío.' }
       #swagger.responses[500] = { description: 'Error al procesar el mensaje.' }
    */
    try {
        const { message } = req.body;
        if (typeof message !== 'string' || message.trim() === '') {
            return res.status(400).json({ status: 0, msg: 'El mensaje no puede estar vacío' });
        }
        const cleanMessage = message.trim();
        if (cleanMessage.length > 1000) {
            return res.status(400).json({ status: 0, msg: 'El mensaje supera el máximo de 1000 caracteres' });
        }

        // construir contexto desde la BD filtrado por el usuario autenticado
        const systemPrompt = await contextService.buildContext(cleanMessage, req.userId);
        // llamar a la IA
        const response = await aiService.getResponse(systemPrompt, cleanMessage);

        res.json({ status: 1, msg: 'success', data: response });

    } catch (error) {
        console.error('Error en chat:', error);
        res.status(500).json({ status: 0, msg: 'Error al procesar el mensaje' });
    }
};

module.exports = chatCtrl;