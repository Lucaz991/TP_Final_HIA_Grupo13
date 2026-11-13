export interface DashboardSummary {
    totalUsers: number;
    totalTutorials: number;
    totalHelpRequests: number;
    totalCategories: number;
    avgRating: string;
    totalRevenue?: number;
    pendingRevenue?: number;
    averagePrice?: number;
    paymentRate?: number;
}

export interface RoleCount {
    rol: string;
    count: string;
}

export interface RoleStateCount {
    rol: string;
    estado: string;
    count: string;
}

export interface StateCount {
    estado: string;
    count: string;
}

export interface MonthCount {
    month: string;
    count: string;
}

export interface FullUsuarioDashboard {
    id: number;
    nombre: string;
    apellido: string;
    email: string;
    rol: 'alumno' | 'profesor' | 'admin';
    estado: 'activo' | 'inactivo';
    universidad: string;
    carrera: string;
    genero: string;
    ubicacion: string;
    createdAt: string;
}

export interface FullCategoryDashboard {
    id: number;
    nombre: string;
    nivel: string;
    descripcion: string;
    createdAt: string;
}

export interface TutorialUser {
    id: number;
    nombre: string;
    apellido: string;
    email: string;
}

export interface TutorialCategory {
    id: number;
    nombre: string;
}

export interface CalificacionData {
    calificacion: number;
    comentario: string | null;
}

export interface FullTutorial {
    id: number;
    estado: string;
    modalidad: string;
    precioAcordado: number;
    fechaHora: string;
    enlaceMeet?: string;
    preferenceId?: string;
    paymentId?: string;
    pagada: boolean;
    createdAt: string;
    alumno?: TutorialUser;
    profesor?: TutorialUser;
    categoria?: TutorialCategory;
    calificacion?: CalificacionData;
}

export interface PaginatedResponse<T> {
    status: number;
    data: T[];
    recordsTotal: number;
    recordsFiltered: number;
    pagination: { page: number; limit: number; total: number; totalPages: number };
}
