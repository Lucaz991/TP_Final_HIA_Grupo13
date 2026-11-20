const express = require('express');
const router = express.Router();
const categoriaCtrl = require('../controllers/categoria.controller');
const authCtrl = require('../controllers/auth.controller');

router.post('/profesor', authCtrl.verifyToken, categoriaCtrl.asociarProfesor);
router.delete('/profesor', authCtrl.verifyToken, categoriaCtrl.desasociarProfesor);

router.get('/', categoriaCtrl.getCategorias);
router.post('/', authCtrl.verifyToken, authCtrl.verifyAdmin, categoriaCtrl.createCategoria);

router.get('/profesor/:profesorId', categoriaCtrl.getCategoriasProfesor);

router.get('/:id', categoriaCtrl.getCategoria);
router.put('/:id', authCtrl.verifyToken, authCtrl.verifyAdmin, categoriaCtrl.editCategoria);
router.delete('/:id', authCtrl.verifyToken, authCtrl.verifyAdmin, categoriaCtrl.deleteCategoria);



module.exports = router;
