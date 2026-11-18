import { Component, OnInit, inject } from '@angular/core';
import { Solicitud } from '../../../models/solicitud.class';
import { Respuesta } from '../../../models/respuesta.class';
import { ActivatedRoute } from '@angular/router';
import { SolicitudService } from '../../../services/solicitud-ayuda.service';
import { RespuestaAyudaService } from '../../../services/respuesta-ayuda.service';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { MercadoPagoService } from '../../../services/mercadoPago.service';

@Component({
  selector: 'app-respuesta-ayuda.component',
  imports: [CommonModule, FormsModule],
  templateUrl: './respuesta-ayuda.component.html',
  styleUrl: './respuesta-ayuda.component.css',
  standalone: true
})
export class RespuestaAyudaComponent implements OnInit {

  solicitud!: Solicitud;
  respuesta = new Respuesta();
  mensajeFormulario: { tipo: 'success' | 'error' | 'info'; texto: string } | null = null;
  respuestasExpandidas: { [key: number]: boolean } = {};

  private route = inject(ActivatedRoute);
  private solicitudService = inject(SolicitudService);


  ngOnInit() {
    const id = this.route.snapshot.params['id'];
    this.cargarSolicitud(id);
  }

  constructor(
    private respuestaService: RespuestaAyudaService,
    private mercadoPagoService: MercadoPagoService

  ){}

  cargarSolicitud(id: number | undefined) {
    if (id === undefined) return;
    this.solicitudService.getSolicitud(id).subscribe({
      next: (result) => {
        this.solicitud = result.data;
      }
    });
  }

  getPublicadoPorTexto(): string {
    if (!this.solicitud?.usuarioId) {
      return 'No disponible';
    }

    const usuarioClave =
      localStorage.getItem('usuario') ||
      sessionStorage.getItem('usuario') ||
      localStorage.getItem('user') ||
      sessionStorage.getItem('user');

    if (usuarioClave) {
      try {
        const usuario = JSON.parse(usuarioClave);
        const idUsuario = Number(usuario.id || usuario.usuarioId);

        if (idUsuario === Number(this.solicitud.usuarioId)) {
          return usuario.nombre ? `Tú (${usuario.nombre})` : 'Tú';
        }
      } catch {
        // Ignorar y usar el fallback
      }
    }

    return `Usuario #${this.solicitud.usuarioId}`;
  }

  mostrarMensaje(tipo: 'success' | 'error' | 'info', texto: string) {
    this.mensajeFormulario = { tipo, texto };
  }

  limpiarMensaje() {
    this.mensajeFormulario = null;
  }

  alternarRespuesta(idRespuesta?: number) {
    if (!idRespuesta) return;
    this.respuestasExpandidas[idRespuesta] = !this.respuestasExpandidas[idRespuesta];
  }

  esRespuestaExpandida(idRespuesta?: number): boolean {
    return !!(idRespuesta && this.respuestasExpandidas[idRespuesta]);
  }

  esCreadorSolicitud(): boolean {
    const usuarioClave =
      localStorage.getItem('usuario') ||
      sessionStorage.getItem('usuario') ||
      localStorage.getItem('user') ||
      sessionStorage.getItem('user');

    if (!usuarioClave || !this.solicitud?.usuarioId) {
      return false;
    }

    try {
      const usuario = JSON.parse(usuarioClave);
      const idUsuario = Number(usuario.id || usuario.usuarioId);
      return idUsuario === Number(this.solicitud.usuarioId);
    } catch {
      return false;
    }
  }

 pagarRespuesta(respuesta: Respuesta) {

  if (!this.esCreadorSolicitud()) {
    this.mostrarMensaje('error', 'Solo el usuario que creó la solicitud puede comprar una respuesta.');
    return;
  }

  if (!respuesta.id || respuesta.precio === undefined || respuesta.precio === null || respuesta.precio < 0) {
    this.mostrarMensaje('error', 'La respuesta no tiene un ID o precio válido para pagar.');
    return;
  }

  this.mercadoPagoService.crearPreferencia(respuesta.id, 'ayuda').subscribe({

    next: (result: any) => {

      if (result.status === 1 && result.init_point) {
        window.location.href = result.init_point;
      } else {
        this.mostrarMensaje('error', 'No se pudo generar el pago.');
      }

    },

    error: (err) => {
      console.error("Error al crear la preferencia de pago:", err);
      this.mostrarMensaje('error', 'Ocurrió un error al conectar con Mercado Pago.');
    }

  });

}

guardar() {

  this.limpiarMensaje();

  // Validaciones
  if (
    !this.respuesta.respuesta ||
    this.solicitud.id === undefined ||
    this.respuesta.precio === undefined ||
    this.respuesta.precio === null ||
    this.respuesta.precio < 0
  ) {
    this.mostrarMensaje('error', 'Completá la respuesta y un precio válido.');
    return;
  }

  // ID de la solicitud
  this.respuesta.idSolicitud = this.solicitud.id;

  // Obtener usuario logueado
  const usuarioClave =
    localStorage.getItem('usuario') ||
    sessionStorage.getItem('usuario') ||
    localStorage.getItem('user') ||
    sessionStorage.getItem('user');

  if (usuarioClave) {

    try {

      const usuarioLogueado = JSON.parse(usuarioClave);

      this.respuesta.idUsuario =
        usuarioLogueado.id || usuarioLogueado.usuarioId;

    } catch {

      this.respuesta.idUsuario = Number(usuarioClave);

    }

  }

  if (!this.respuesta.idUsuario) {

    this.mostrarMensaje('error', 'No se pudo identificar el usuario.');

    return;

  }

  this.respuestaService.createRespuesta(this.respuesta).subscribe({

    next: (result) => {

      this.mostrarMensaje('success', result.msg || 'Respuesta publicada correctamente. Ahora podrá comprarse desde el botón correspondiente.');

      this.respuesta = new Respuesta();

      this.cargarSolicitud(this.solicitud.id);

    },

    error: (err) => {

      console.error(err);

      this.mostrarMensaje('error', 'Error al guardar la respuesta.');

    }

  });

}}
