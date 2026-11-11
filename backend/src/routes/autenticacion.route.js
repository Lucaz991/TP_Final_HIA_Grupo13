const express = require('express');
const router = express.Router();
const autenticacionCtrl = require('../controllers/autenticacion.controller');
const { body, validationResult } = require('express-validator');
const loginLimiter = require('../middleware/loginIntentos');

const validarRolRegistro = body('rol')
    .isIn(['alumno', 'profesor'])
    .withMessage('El rol debe ser alumno o profesor');

const validarCampos = (req, res, next) => {
    const errores = validationResult(req);
    if (!errores.isEmpty()) {
        return res.status(400).json({ status: 0, msg: "Datos inválidos", errores: errores.array() });
    }
    next();
};
router.post('/signup', [
    validarRolRegistro,
    //  El email debe ser un formato de email válido
    body('email').isEmail().withMessage('Debe ser un email válido'),
    //  La contraseña debe tener al menos 6 caracteres
    body('contrasenia').isLength({ min: 6 }).withMessage('La contraseña es muy corta'),
    //  El nombre no puede estar vacío (y eliminamos espacios extra)
    body('nombre').trim().notEmpty().withMessage('El nombre es obligatorio'),
    validarCampos
], autenticacionCtrl.signUpUsuario);
router.post('/signUp', [validarRolRegistro, validarCampos], autenticacionCtrl.signUpUsuario);
router.post('/login', loginLimiter, autenticacionCtrl.loginUsuario);
router.post('/signUpGoogle', [validarRolRegistro, validarCampos], autenticacionCtrl.signUpGoogle);
router.post('/loginGoogle', autenticacionCtrl.loginGoogle);
//router.post('/vincularGoogle', autenticacionCtrl.vincularGoogle);

module.exports = router;