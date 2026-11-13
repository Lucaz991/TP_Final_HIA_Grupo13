import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { PaginatedResponse, FullTutorial, FullUsuarioDashboard } from '../models/dashboard.class';

import { environment } from '../../environments/environment';

export interface AdminTableQuery {
  start: number; limit: number; search: string; sort: string; direction: string;
}

@Injectable({
  providedIn: 'root'
})
export class AdminService {

  urlHost: string = environment.urlHost;
  private apiUrl = this.urlHost + 'api/admin';

  constructor(private http: HttpClient) { }

  // Obtiene los contadores generales para las KPI cards
  getSummary(): Observable<any> {
    return this.http.get(`${this.apiUrl}/summary`);
  }

  // Obtiene usuarios agrupados por rol y estado — datos para el gráfico de barras apilado
  getUsersByRole(): Observable<any> {
    return this.http.get(`${this.apiUrl}/users-by-role`);
  }

  // Obtiene solicitudes de ayuda agrupadas por estado — datos para el gráfico de torta
  getHelpRequestsByState(): Observable<any> {
    return this.http.get(`${this.apiUrl}/requests-by-state`);
  }

  // Obtiene tutorías agrupadas por estado — datos para el gráfico de torta de tutorías
  getTutorialsByState(): Observable<any> {
    return this.http.get(`${this.apiUrl}/tutorials-by-state`);
  }

  // Obtiene tutorías agrupadas por mes — datos para el gráfico de línea
  getTutorialsByMonth(): Observable<any> {
    return this.http.get(`${this.apiUrl}/tutorials-by-month`);
  }

  // Obtiene una página del listado de tutorías para la tabla
  getFullTutorials(query: AdminTableQuery): Observable<PaginatedResponse<FullTutorial>> {
    return this.http.get<PaginatedResponse<FullTutorial>>(`${this.apiUrl}/full-tutorials`, { params: { ...query } });
  }

  // Obtiene una página del listado de usuarios para la tabla
  getUsers(query: AdminTableQuery): Observable<PaginatedResponse<FullUsuarioDashboard>> {
    return this.http.get<PaginatedResponse<FullUsuarioDashboard>>(`${this.apiUrl}/users`, { params: { ...query } });
  }

  // Actualiza los datos principales de un usuario (admin)
  updateUser(id: number, data: any): Observable<any> {
    return this.http.put(`${this.apiUrl}/users/${id}`, data);
  }

  deleteUser(id: number): Observable<any> {
    return this.http.delete(`${this.apiUrl}/users/${id}`);
  }

  // --- Tutorías ---
  updateTutorial(id: number, data: any): Observable<any> {
    return this.http.put(`${this.apiUrl}/tutorials/${id}`, data);
  }

  deleteTutorial(id: number): Observable<any> {
    return this.http.delete(`${this.apiUrl}/tutorials/${id}`);
  }

  // --- Categorías ---
  getCategoriesList(): Observable<any> {
    return this.http.get(`${this.apiUrl}/categories-list`);
  }

  updateCategory(id: number, data: any): Observable<any> {
    return this.http.put(`${this.apiUrl}/categories/${id}`, data);
  }

  deleteCategory(id: number): Observable<any> {
    return this.http.delete(`${this.apiUrl}/categories/${id}`);
  }
}
