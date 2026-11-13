import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../environments/environment';

@Injectable({
  providedIn: 'root'
})
export class TutoriaService {
  private urlHost = environment.urlHost;
  private apiUrl = this.urlHost + 'api/tutoria'; 

  constructor(private http: HttpClient) { }

  obtenerProfesores(page = 1, categoriaId = '', orden = 'predeterminado', lat: number | null = null, lng: number | null = null): Observable<any> {
    const params: Record<string, string | number> = { rol: 'profesor', page, limit: 12 };
    if (categoriaId) params['categoriaId'] = categoriaId;
    if (orden === 'cercania' && lat !== null && lng !== null) {
      Object.assign(params, { orden, lat, lng });
    }
    return this.http.get(this.urlHost + 'api/usuario', { params });
  }

  obtenerUsuarios(id?: number): Observable<any> {
    return this.http.get(this.urlHost + 'api/usuario', { params: id ? { id } : {} });
  }

  obtenerCategorias(): Observable<any> {
    return this.http.get(this.urlHost + 'api/categoria');
  }

  solicitarTutoria(datosTutoria: any): Observable<any> {
    return this.http.post(this.apiUrl, datosTutoria);
  }

  obtenerTutorias(page = 1): Observable<any> {
    return this.http.get(this.apiUrl, { params: { page, limit: 50 } });
  }

  responderTutoria(id: number, estadoActualizado: any): Observable<any> {
    return this.http.put(`${this.apiUrl}/${id}`, estadoActualizado);
  }

  asociarProfesorCategoria(profesorId: number, categoriaId: number): Observable<any> {
    return this.http.post(this.urlHost + 'api/categoria/profesor', { profesorId: profesorId, categoriaId: categoriaId });
  }

  desasociarProfesorCategoria(profesorId: number, categoriaId: number): Observable<any> {
    return this.http.delete(this.urlHost + 'api/categoria/profesor', {
      body: { profesorId: profesorId, categoriaId: categoriaId }
    });
  }

  agregarHorario(usuarioId: number, diaSemana: string, horaInicio: string, horaFin: string): Observable<any> {
    return this.http.post(this.urlHost + 'api/usuario/horario', { usuarioId: usuarioId, diaSemana, horaInicio, horaFin });
  }

  eliminarHorario(horarioId: number): Observable<any> {
    return this.http.delete(`${this.urlHost}api/usuario/horario/${horarioId}`);
  }
}
