import { Component, OnInit, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { AutenticacionService } from '../../services/autenticacion.service';
import { TutoriaService } from '../../services/tutoria.service';
import { MercadoPagoService } from '../../services/mercadoPago.service';
import { PrecioService } from '../../services/precio.service';
import { CategoriaService } from '../../services/categoria.service';
import { HorarioDisponibleService } from '../../services/horario-disponible.service';
import Swal from 'sweetalert2';
import { Tutoria } from '../../models/tutoria.class';

@Component({
  selector: 'app-gestion-tutoria',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './gestion-tutoria.component.html',
  styleUrls: ['./gestion-tutoria.component.css']
})
export class GestionTutoriaComponent implements OnInit {

  usuarioId: number = 0;
  alumnoProveedorAuth: string = '';
  alumnoEmail: string = '';
  calendarUrl: SafeResourceUrl | null = null;


  profesorSeleccionado: any = {
    id: 0,
    nombre: '',
    nivelAcademico: 'universitario',
    categoriasEnseniadas: []
  };

  horariosProfesor: any[] = [];
  turnosDisponibles: any[] = [];
  listaPreciosBD: any[] = [];

  solicitud = {
    modalidad: 'virtual',
    fechaSeleccionada: '',
    fechaHora: '',
    duracion: 60,
    mensaje: '',
    categoriaId: ''
  };

  duracionesOpciones = [
    { label: '40 min', value: 40 },
    { label: '1 hora', value: 60 },
    { label: '1.5 horas', value: 90 },
    { label: '2 horas', value: 120 }
  ];

  errorDisponibilidad: string = '';

  fechaMinima: string = '';
  fechaMaxima: string = '';

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private authService: AutenticacionService,
    private tutoriaService: TutoriaService,
    private mpService: MercadoPagoService,
    private precioService: PrecioService,
    private categoriaService: CategoriaService,
    private horarioService: HorarioDisponibleService,
    private cdr: ChangeDetectorRef,
    private sanitizer: DomSanitizer
  ) { }

  ngOnInit() {
    if (!this.authService.userLoggedIn()) {
      this.router.navigate(['/login']);
      return;
    }

    const userStr = sessionStorage.getItem('usuario');
    if (userStr) {
      const user = JSON.parse(userStr);
      this.usuarioId = user.id;
      this.alumnoProveedorAuth = user.proveedorAuth || 'local';
      this.alumnoEmail = user.email || '';
    }
    this.configurarLimitesDeFecha();
    this.cargarPrecios();

    const profesorId = parseInt(this.route.snapshot.queryParams['profesorId'] || '0');
    if (profesorId) {
      this.cargarProfesor(profesorId);
    } else {
      Swal.fire({
        icon: 'error',
        title: 'Error',
        text: 'No se especificó un profesor válido.'
      }).then(() => {
        this.router.navigate(['/solicitar-tutoria']);
      });
    }

    if (this.alumnoProveedorAuth === 'Google' && this.alumnoEmail) {
      const rawUrl = `https://calendar.google.com/calendar/embed?src=${encodeURIComponent(this.alumnoEmail)}&ctz=America/Argentina/Buenos_Aires`;
      this.calendarUrl = this.sanitizer.bypassSecurityTrustResourceUrl(rawUrl);
    }
  }

  configurarLimitesDeFecha() {
    const hoy = new Date();
    hoy.setMinutes(hoy.getMinutes() - hoy.getTimezoneOffset());

    this.fechaMinima = hoy.toISOString().split('T')[0];

    const limiteMaximo = new Date(hoy);
    limiteMaximo.setMonth(limiteMaximo.getMonth() + 3);

    this.fechaMaxima = limiteMaximo.toISOString().split('T')[0];
  }

  cargarPrecios() {
    this.precioService.obtenerPrecios().subscribe({
      next: (res: any) => {
        this.listaPreciosBD = res.data || res;
      },
      error: (err: any) => console.error('Error al cargar precios:', err)
    });
  }

  cargarProfesor(id: number) {
    //  Traemos los datos básicos del usuario
    this.tutoriaService.obtenerUsuarios(id).subscribe({
      next: (res: any) => {
        const listado = res.data || res;
        const userDetail = listado.find((u: any) => u.id === id);
        if (userDetail) {
          this.profesorSeleccionado.id = userDetail.id;
          this.profesorSeleccionado.nombre = `${userDetail.nombre} ${userDetail.apellido}`;
          this.profesorSeleccionado.nivelAcademico = userDetail.nivelAcademico || 'universitario';
          this.cdr.detectChanges();
        }
      },
      error: (err: any) => console.error('Error al cargar nombre del profe:', err)
    });

    //  Traemos las materias
    this.categoriaService.obtenerCategoriasdeProfesor(id).subscribe({
      next: (res: any) => {
        this.profesorSeleccionado.categoriasEnseniadas = res.data || res;
        this.cdr.detectChanges();
      }
    });

    //  Traemos los horarios
    this.horarioService.obtenerHorarios(id).subscribe({
      next: (res: any) => {
        this.horariosProfesor = (res.data || res).map((h: any) => ({
          id: h.id,
          diaSemana: (h.dia_semana || h.diaSemana || '').toLowerCase(),
          modalidad: (h.modalidad || '').toLowerCase(),
          horaInicio: typeof h.horaInicio === 'string' ? h.horaInicio.slice(0, 5) : this.minutesToTime(h.horaInicio * 60 || 0),
          horaFin: typeof h.horaFin === 'string' ? h.horaFin.slice(0, 5) : this.minutesToTime(h.horaFin * 60 || 0)
        }));
        this.cdr.detectChanges();
      }
    });
  }

  get precioFinal(): number {
    if (!this.solicitud.duracion || this.listaPreciosBD.length === 0) return 0;

    const nivel = (this.profesorSeleccionado.nivelAcademico || 'universitario').toLowerCase();
    const modalidad = this.solicitud.modalidad;

    const precioEncontrado = this.listaPreciosBD.find(
      p => (p.nivel || '').toLowerCase() === nivel && (p.modalidad || '').toLowerCase() === modalidad
    );

    const tarifaHora = precioEncontrado ? precioEncontrado.precio : 10000;
    const costoCalculado = (tarifaHora / 60) * this.solicitud.duracion;
    return Math.round(costoCalculado);
  }

  setDuracion(minutos: number) {
    this.solicitud.duracion = minutos;
    this.solicitud.fechaHora = '';
    this.generarTurnos();
  }

  setModalidad(tipo: string) {
    this.solicitud.modalidad = tipo;
    this.solicitud.fechaHora = '';
    this.generarTurnos();
  }
  generarTurnos() {
    this.turnosDisponibles = [];
    this.solicitud.fechaHora = '';

    if (!this.solicitud.fechaSeleccionada || !this.solicitud.duracion) return;

    const fechaElegidaSeguridad = new Date(this.solicitud.fechaSeleccionada + 'T00:00:00');
    const minima = new Date(this.fechaMinima + 'T00:00:00');
    const maxima = new Date(this.fechaMaxima + 'T00:00:00');

    if (fechaElegidaSeguridad < minima || fechaElegidaSeguridad > maxima) {
      this.errorDisponibilidad = 'La fecha seleccionada está fuera del rango permitido (hasta 3 meses).';
      return;
    }

    const dateElegida = new Date(this.solicitud.fechaSeleccionada + 'T00:00:00');
    const diasSemana = ['domingo', 'lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado'];
    const diaString = diasSemana[dateElegida.getDay()];

    const modalidadElegida = (this.solicitud.modalidad || '').toLowerCase();

    const horariosDelDia = this.horariosProfesor.filter(h => {
      const modProfe = (h.modalidad || '').toLowerCase();

      return h.diaSemana === diaString &&
        (modProfe === modalidadElegida || modProfe === 'ambas');
    });

    if (horariosDelDia.length === 0) {
      this.errorDisponibilidad = `El profesor no atiende de forma ${this.solicitud.modalidad} en este día de la semana.`;
      return;
    } else {
      this.errorDisponibilidad = '';
    }

    const tiempoBuffer = modalidadElegida === 'presencial' ? 20 : 10;

    horariosDelDia.forEach(bloque => {
      let minutosActual = this.timeToMinutes(bloque.horaInicio);
      const minutosFin = this.timeToMinutes(bloque.horaFin);

      while (minutosActual + this.solicitud.duracion <= minutosFin) {

        const horaInicioStr = this.minutesToTime(minutosActual);
        const horaFinStr = this.minutesToTime(minutosActual + this.solicitud.duracion);
        const fechaHoraISO = new Date(`${this.solicitud.fechaSeleccionada}T${horaInicioStr}:00`).toISOString();

        this.turnosDisponibles.push({
          inicio: horaInicioStr,
          fin: horaFinStr,
          fechaHora: fechaHoraISO
        });

        minutosActual = minutosActual + this.solicitud.duracion + tiempoBuffer;
      }
    });

    if (this.turnosDisponibles.length === 0) {
      this.errorDisponibilidad = `El profesor trabaja este día, pero no tiene un hueco de ${this.solicitud.duracion} min disponible.`;
    }
  }

  timeToMinutes(time: string): number {
    if (!time || !time.includes(':')) return 0;
    const [h, m] = time.split(':').map(Number);
    return h * 60 + m;
  }

  minutesToTime(minutes: number): string {
    const h = Math.floor(minutes / 60).toString().padStart(2, '0');
    const m = (minutes % 60).toString().padStart(2, '0');
    return `${h}:${m}`;
  }

  solicitarYPagar() {
    if (!this.solicitud.fechaHora) {
      Swal.fire('Atención', 'Debes seleccionar un horario de la lista.', 'warning');
      return;
    }

    const nuevaTutoria = new Tutoria(
      this.usuarioId,
      this.profesorSeleccionado.id,
      parseInt(this.solicitud.categoriaId),
      this.solicitud.fechaHora,
      this.precioFinal,
      this.solicitud.modalidad as 'virtual' | 'presencial',
      this.solicitud.mensaje
    );

    this.tutoriaService.solicitarTutoria(nuevaTutoria).subscribe({
      next: (res: any) => {
        const tutoriaId = res.data?.id || res.id;

        this.mpService.crearPreferencia(tutoriaId).subscribe({
          next: (mpRes: any) => {
            Swal.fire({
              icon: 'success',
              title: 'Tutoría Solicitada',
              text: 'Redirigiéndote a Mercado Pago...',
              timer: 3000,
              showConfirmButton: false
            }).then(() => {
              if (mpRes.init_point) window.location.href = mpRes.init_point;
              else this.router.navigate(['/mis-solicitudes']);
            });
          },
          error: (err: any) => {
            console.error('Error MP:', err);
            this.router.navigate(['/mis-solicitudes']);
          }
        });
      },
      error: (err: any) => {
        Swal.fire('Error', 'No se pudo registrar la solicitud.', 'error');
      }
    });
  }
}