import { Component, OnInit, OnDestroy, ChangeDetectorRef } from '@angular/core';
import { Subscription } from 'rxjs';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterModule } from '@angular/router';
import { TutoriaService } from '../../services/tutoria.service';
import { AutenticacionService } from '../../services/autenticacion.service';
import { CategoriaService } from '../../services/categoria.service';
import { HorarioDisponibleService } from '../../services/horario-disponible.service';

@Component({
  selector: 'app-galeria-profesores',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule],
  templateUrl: './galeria-profesores.component.html',
  styleUrls: ['./galeria-profesores.component.css']
})
export class GaleriaProfesoresComponent implements OnInit, OnDestroy {

  pagina = 1;
  totalPaginas = 0;
  totalProfesores = 0;
  cargando = false;
  errorCarga = '';
  private peticion?: Subscription;
  ngOnDestroy() { this.peticion?.unsubscribe(); }
  rol: string = '';
  categorias: any[] = [];
  profesores: any[] = [];
  filtroCategoria: string = '';
  profesorSeleccionado: any = null;
  alumnoNivelAcademico: string = 'universitario';
  perfilIncompleto: boolean = false;
  criterioOrden: string = 'predeterminado';
  alumnoLat: number | null = null;
  alumnoLng: number | null = null;

  constructor(
    private tutoriaService: TutoriaService,
    private autenticacionService: AutenticacionService,
    private categoriaService: CategoriaService,
    private horarioService: HorarioDisponibleService,
    private cdr: ChangeDetectorRef
  ) { }

  ngOnInit() {
    const userStr = sessionStorage.getItem('usuario');
    if (userStr) {
      const user = JSON.parse(userStr);

      this.rol = user.rol || user.perfil || '';
      this.alumnoNivelAcademico = user.nivelAcademico || 'universitario';
      this.alumnoLat = user.lat || null;
      this.alumnoLng = user.lng || null;

      if ((this.rol || '').toLowerCase() === 'profesor') {
        const profesorId = user.id;

        this.perfilIncompleto = true;

        this.categoriaService.obtenerCategoriasdeProfesor(profesorId).subscribe({
          next: (resCat: any) => {
            const tieneCategorias = resCat.data && resCat.data.length > 0;

            this.horarioService.obtenerHorarios(profesorId).subscribe({
              next: (resHor: any) => {
                const tieneHorarios = resHor.data && resHor.data.length > 0;

                if (tieneCategorias && tieneHorarios) {
                  this.perfilIncompleto = false;
                }

                // Actualizamos la vista
                this.cdr.detectChanges();
              }
            });
          }
        });
      }
    }

    this.cargarCategorias();
    this.cargarProfesores();
  }

  cargarCategorias() {
    this.categoriaService.obtenerCategorias().subscribe({
      next: (res: any) => {
        this.categorias = res.data || res;
      },
      error: (err: any) => console.error('Error al cargar categorías:', err)
    });
  }

  cargarProfesores(pagina = 1) {
    this.peticion?.unsubscribe();
    this.pagina = pagina;
    this.cargando = true;
    this.errorCarga = '';
    this.profesorSeleccionado = null;
    this.peticion = this.tutoriaService.obtenerProfesores(pagina, this.filtroCategoria,
      this.criterioOrden, this.alumnoLat, this.alumnoLng).subscribe({
      next: (res: any) => {
        this.profesores = res.data || [];
        this.totalPaginas = res.pagination.totalPages;
        this.totalProfesores = res.pagination.total;
        this.cargando = false;
        this.cdr.detectChanges();
      },
      error: (err: any) => {
        console.error('Error al cargar profesores:', err);
        this.profesores = [];
        this.cargando = false;
        this.errorCarga = 'No se pudieron cargar los profesores. Intentá nuevamente.';
        this.cdr.detectChanges();
      }
    });
  }

  calcularDistancia(lat1: number | null | undefined, lon1: number | null | undefined, lat2: number | null | undefined, lon2: number | null | undefined): number {
    if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) {
      return Infinity;
    }
    const R = 6371;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
      Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  detectarUbicacionGPSAlumno() {
    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          this.alumnoLat = position.coords.latitude;
          this.alumnoLng = position.coords.longitude;
          this.cargarProfesores();
          this.cdr.detectChanges();
        },
        (error) => {
          alert('No se pudo obtener tu ubicación para calcular la distancia.');
          this.criterioOrden = 'predeterminado';
          this.cdr.detectChanges();
        }
      );
    } else {
      alert('Tu navegador no soporta geolocalización.');
      this.criterioOrden = 'predeterminado';
    }
  }

  ordenarCambio() {
    if (this.criterioOrden === 'cercania' && (!this.alumnoLat || !this.alumnoLng)) {
      this.detectarUbicacionGPSAlumno();
    } else {
      this.cargarProfesores();
    }
  }

  get profesoresFiltrados() { return this.profesores; }

  toggleProfesor(profesor: any) {
    if (this.profesorSeleccionado?.id === profesor.id) {
      this.profesorSeleccionado = null;
    } else {
      this.profesorSeleccionado = profesor;
    }
  }

  getOpiniones(profesor: any): { id: number, alumno: string, calificacion: number, comentario: string }[] {
    if (!profesor.opiniones) return [];
    return profesor.opiniones.slice(0, 2);
  }

  esNivelCompatible(profesor: any): boolean {
    if (!profesor.nivelAcademico) return true;

    const nivelProfe = profesor.nivelAcademico.toLowerCase();
    const nivelAlumno = this.alumnoNivelAcademico.toLowerCase();

    const niveles = ['primario', 'secundario', 'terciario', 'universitario', 'doctorado'];
    return niveles.indexOf(nivelProfe) >= niveles.indexOf(nivelAlumno);
  }
}