module mod_solver
    use mod_read_gmsh,   only: nbelm
    use mod_cell_2D,     only: cell, cell_2D, nbfaces, face
    use mod_fvm_face_2D, only: fvm_face_2D, face_2D
    implicit none
    
    real(8)                              :: r_gaz, invdt, dt, tmax
    real(8), parameter                   :: cfl = 0.9d0
    real(8), dimension(:),   allocatable :: rho, ux, uy, t
    real(8), dimension(:),   allocatable :: p, a, b, e
    real(8), dimension(:,:), allocatable :: vect_u, vect_unew, flux, rhs, rhsdummy_symetrie, rhsdummy_entree, rhsdummy_sortie
    real(8), dimension(:,:), allocatable :: vardummy_symetrie, vardummy_entree, vardummy_sortie
    integer                              :: nb_symmetry = 0, nb_inlet = 0, nb_outlet = 0, nmax
    contains
!----------------------------------------------------------------------    
        subroutine donnee_initiale
        implicit none 
        
        if (.not. allocated(rho)) then
            allocate(rho(1:nbelm))
        endif
        
        if (.not. allocated(ux)) then
            allocate(ux(1:nbelm))
        endif 
        
        if (.not. allocated(uy)) then
            allocate(uy(1:nbelm))
        endif 
        
        if (.not. allocated(t)) then
            allocate(t(1:nbelm))
        endif
        
        if (.not. allocated(p)) then
            allocate(p(1:nbelm))
        endif
        
        if (.not. allocated(a)) then
            allocate(a(1:nbelm))
        endif
        
        if (.not. allocated(b)) then
            allocate(b(1:nbelm))
        endif
        
        if (.not. allocated(e)) then
            allocate(e(1:nbelm))
        endif
        
        if (.not. allocated(vect_u)) then
            allocate(vect_u(1:nbelm,1:4))
        endif
        
        if (.not. allocated(vect_unew)) then
            allocate(vect_unew(1:nbelm,1:4))
        endif
        
        ! hard code, need to be modified
        rho = 0.2d-4 !0.2969689477d-4
        ux  = 500.0d0 !1059.458022d0
        uy  = 0.0d0
        t   = 1000.0d0!1295.646765d0
        
        end subroutine donnee_initiale
!----------------------------------------------------------------------
        subroutine allocate_vardummy
        implicit none 
        
        integer                    :: i
        type(fvm_face_2D), pointer :: pfac
        
        if (nb_symmetry > 0) return 
        
        ! Allocating vardummy
        do i = 1, nbfaces
            pfac => face_2D(i)%f
            if (pfac%bc_typ == 1) then ! Airfoil - symetrie
                nb_symmetry = nb_symmetry + 1
            endif
            if (pfac%bc_typ == 2) then ! Inflow
                nb_inlet    = nb_inlet + 1
            endif
            if (pfac%bc_typ == 3) then ! Outflow
                nb_outlet   = nb_outlet + 1
            endif
        enddo 
        
        if (.not. allocated(vardummy_symetrie)) then
            allocate(vardummy_symetrie(1:nb_symmetry,1:8))
            vardummy_symetrie = 0.0d0
        endif 
        
        if (.not. allocated(vardummy_entree)) then
            allocate(vardummy_entree(1:nb_inlet,1:8))
            vardummy_entree = 0.0d0
        endif
        
        if (.not. allocated(vardummy_sortie)) then
            allocate(vardummy_sortie(1:nb_outlet,1:8))
            vardummy_sortie = 0.0d0
        endif
        
        end subroutine allocate_vardummy
!----------------------------------------------------------------------
        subroutine conditions_aux_limites
        implicit none
        
        integer                    :: icel, ifac, jfac
        integer                    :: cnt_symmetry, cnt_inlet, cnt_outlet
        type(cell_2D),     pointer :: pcel
        type(face),        pointer :: pfac
        
        cnt_symmetry = 0
        cnt_inlet    = 0
        cnt_outlet   = 0
        
        do icel = 1, nbelm
            pcel => cell(icel)%p
            do ifac = 1, 4
                pfac => pcel%faces(ifac)
                
                if (pfac%bc_typ == 1) then ! Airfoil - symetrie
                    cnt_symmetry = cnt_symmetry + 1 
                    vardummy_symetrie(cnt_symmetry, 1) = rho(icel)
                    vardummy_symetrie(cnt_symmetry, 2) = ux(icel)
                    vardummy_symetrie(cnt_symmetry, 3) = -uy(icel)
                    vardummy_symetrie(cnt_symmetry, 4) = t(icel)
                endif 
                
                if (pfac%bc_typ == 2) then ! Inflow
                    cnt_inlet = cnt_inlet + 1 
                    vardummy_entree(cnt_inlet, 1) = 0.2969689477d-4
                    vardummy_entree(cnt_inlet, 2) = 1059.458022d0
                    vardummy_entree(cnt_inlet, 3) = 0.0d0
                    vardummy_entree(cnt_inlet, 4) = 1295.646765d0
                endif 
                
                if (pfac%bc_typ == 3) then ! Outflow
                    cnt_outlet = cnt_outlet + 1
                    vardummy_sortie(cnt_outlet, 1) = rho(icel)
                    vardummy_sortie(cnt_outlet, 2) = ux(icel)
                    vardummy_sortie(cnt_outlet, 3) = uy(icel)
                    vardummy_sortie(cnt_outlet, 4) = t(icel)
                endif 
            enddo 
        enddo 
        end subroutine conditions_aux_limites
!----------------------------------------------------------------------
        !--- calcul des quantit�s d�riv�es
        subroutine calcul_derived_quantities
        implicit none
        
        r_gaz = 1.3806503d-23 / 0.663d-25
        p     = rho * r_gaz * t
        b     = sqrt(3.0d0 * r_gaz * t)
        a     = rho / (8.0d0 * b**3)
        e     = 0.5d0 * rho * (ux**2 + uy**2) + 3.0d0 /2.0d0 * rho * r_gaz * t
        
        vardummy_symetrie(:, 5) = vardummy_symetrie(:, 1) * r_gaz * vardummy_symetrie(:, 4)
        vardummy_symetrie(:, 7) = sqrt(3.0d0 * r_gaz * vardummy_symetrie(:, 4))
        vardummy_symetrie(:, 6) = vardummy_symetrie(:, 1) / (8.0d0 * vardummy_symetrie(:, 7)**3)
        vardummy_symetrie(:, 8) = 0.5d0 * vardummy_symetrie(:, 1) * (vardummy_symetrie(:, 2)**2 + vardummy_symetrie(:, 3)**2) + 3.0d0 /2.0d0 * vardummy_symetrie(:, 1) * r_gaz * vardummy_symetrie(:, 4)
        
        vardummy_entree(:, 5) = vardummy_entree(:, 1) * r_gaz * vardummy_entree(:, 4)
        vardummy_entree(:, 7) = sqrt(3.0d0 * r_gaz * vardummy_entree(:, 4))
        vardummy_entree(:, 6) = vardummy_entree(:, 1) / (8.0d0 * vardummy_entree(:, 7)**3)
        vardummy_entree(:, 8) = 0.5d0 * vardummy_entree(:, 1) * (vardummy_entree(:, 2)**2 + vardummy_entree(:, 3)**2) + 3.0d0 /2.0d0 * vardummy_entree(:, 1) * r_gaz * vardummy_entree(:, 4)
        
        vardummy_sortie(:, 5) = vardummy_sortie(:, 1) * r_gaz * vardummy_sortie(:, 4)
        vardummy_sortie(:, 7) = sqrt(3.0d0 * r_gaz * vardummy_sortie(:, 4))
        vardummy_sortie(:, 6) = vardummy_sortie(:, 1) / (8.0d0 * vardummy_sortie(:, 7)**3)
        vardummy_sortie(:, 8) = 0.5d0 * vardummy_sortie(:, 1) * (vardummy_sortie(:, 2)**2 + vardummy_sortie(:, 3)**2) + 3.0d0 /2.0d0 * vardummy_sortie(:, 1) * r_gaz * vardummy_sortie(:, 4)
        
        end subroutine calcul_derived_quantities
!----------------------------------------------------------------------
        !--- calcul du vecteur des quantit�s conservatives
        subroutine calcul_conservative_vector
        implicit none 
        
        vect_u(:,1) = rho(:)
        vect_u(:,2) = rho(:) * ux(:)
        vect_u(:,3) = rho(:) * uy(:)
        vect_u(:,4) = e(:)
        vect_unew   = vect_u
        end subroutine calcul_conservative_vector
!----------------------------------------------------------------------
        !--- pas de temps et vitesse maximum
        subroutine timestep
        implicit none
        
        real(8)                :: norme_u, perimetre
        integer                :: i, face1, face2, face3, face4
        type(cell_2D), pointer :: pc
        type(face),    pointer :: pf1, pf2, pf3, pf4
        
        invdt = 0.0d0
        
        do i = 1, nbelm
            pc => cell(i)%p
            norme_u = sqrt(ux(i)**2 + uy(i)**2)
            
            pf1 => pc%faces(1)
            pf2 => pc%faces(2)
            pf3 => pc%faces(3)
            pf4 => pc%faces(4)
            
            face1 = pf1%idface
            face2 = pf2%idface
            face3 = pf3%idface
            face4 = pf4%idface
            
            if (face1 == 0) then
                print*, 'face1 = 0'
                print*, 'Please check cell ', i
            endif
            
            if (face2 == 0) then
                print*, 'face2 = 0'
            endif
            
            if (face3 == 0) then
                print*, 'face3 = 0'
            endif
            
            if (face4 == 0) then
                print*, 'face4 = 0'
                print*, 'Please check cell ', i
            endif
            
            perimetre = face_2D(face1)%f%len_nor + face_2D(face2)%f%len_nor + face_2D(face3)%f%len_nor + face_2D(face4)%f%len_nor
            invdt     = max(invdt, (norme_u+b(i)*perimetre / pc%vol))
        enddo 
        dt = cfl / invdt
        
        end subroutine timestep
!----------------------------------------------------------------------
        subroutine assign_lr_cell
        use mod_struct_to_array, only: lr_cell
        implicit none 
        integer                    :: ifac, icel, fac
        integer                    :: cnt_symmetry, cnt_inlet, cnt_outlet
        type(cell_2D), pointer     :: pcel
        type(face), pointer        :: pfac
        type(fvm_face_2D), pointer :: pfac_fvm
        
        cnt_symmetry = 0
        cnt_inlet    = 0
        cnt_outlet   = 0
        
        ! Create left cell - right cell table for boundary faces
        do icel = 1, nbelm
            pcel => cell(icel)%p
            do ifac = 1, 4
                pfac => pcel%faces(ifac)
                if (pfac%bc_typ == 1) then ! Airfoil - symetrie
                    cnt_symmetry = cnt_symmetry + 1
                    fac = pfac%idface
                    lr_cell(fac, 1) = icel
                    lr_cell(fac, 2) = cnt_symmetry ! dummy cell for symmetry bc
                endif
                
                if (pfac%bc_typ == 2) then ! Inflow
                    cnt_inlet = cnt_inlet + 1 
                    fac = pfac%idface
                    lr_cell(fac, 1) = icel
                    lr_cell(fac, 2) = cnt_inlet ! dummy cell for inlet bc
                endif 
                
                if (pfac%bc_typ == 3) then ! Outflow
                    cnt_outlet = cnt_outlet + 1
                    fac = pfac%idface
                    lr_cell(fac, 1) = icel
                    lr_cell(fac, 2) = cnt_outlet ! dummy cell for outlet bc
                endif
            enddo 
        enddo 
        
        ! Create left cell - right cell table for internal faces
        do ifac = 1, nbfaces
            pfac_fvm => face_2D(ifac)%f
            if (associated(pfac_fvm%left_cell) .and. associated(pfac_fvm%right_cell)) then 
                lr_cell(ifac, 1) = pfac_fvm%left_cell%ident
                lr_cell(ifac, 2) = pfac_fvm%right_cell%ident
            endif
        enddo 
        end subroutine assign_lr_cell
!----------------------------------------------------------------------
        subroutine calcul_flux
        use mod_flux
        use mod_struct_to_array
        implicit none 
        integer :: ifac, left_cell, right_cell
        real(8) :: flux_plus(1:4), flux_minus(1:4)
        
        if (.not. allocated(flux)) then
            allocate(flux(1:nbfaces,1:4))
        endif
        
        do ifac = 1, nbfaces
            left_cell  = lr_cell(ifac,1)
            right_cell = lr_cell(ifac,2)
            
            if (bc_typ(ifac) == 0) then
                flux_plus(:)   = fluxp(rho(left_cell), ux(left_cell), uy(left_cell), & 
                & e(left_cell), p(left_cell), t(left_cell), a(left_cell), b(left_cell), & 
                & norm_x(ifac), norm_y(ifac))
                flux_minus(:)  = fluxm(rho(right_cell), ux(right_cell), uy(right_cell), & 
                & e(right_cell), p(right_cell), t(right_cell), a(right_cell), b(right_cell), & 
                & norm_x(ifac), norm_y(ifac))
                flux(ifac,:)   = len_norm(ifac) * (flux_plus(:) + flux_minus(:))
            endif 
            
            if (bc_typ(ifac) == 1) then !symmetry
                flux_plus(:)   = fluxp(rho(left_cell), ux(left_cell), uy(left_cell), & 
                & e(left_cell), p(left_cell), t(left_cell), a(left_cell), b(left_cell), & 
                & norm_x(ifac), norm_y(ifac))
                flux_minus(:)  = fluxm(vardummy_symetrie(right_cell,1), vardummy_symetrie(right_cell,2), vardummy_symetrie(right_cell,3), & 
                & vardummy_symetrie(right_cell,8), vardummy_symetrie(right_cell,5), vardummy_symetrie(right_cell,4), vardummy_symetrie(right_cell,6), vardummy_symetrie(right_cell,7), & 
                & norm_x(ifac), norm_y(ifac))
                flux(ifac,:)   = len_norm(ifac) * (flux_plus(:) + flux_minus(:))
            endif
            
            if (bc_typ(ifac) == 2) then ! Inflow
                flux_plus(:)   = fluxp(rho(left_cell), ux(left_cell), uy(left_cell), & 
                & e(left_cell), p(left_cell), t(left_cell), a(left_cell), b(left_cell), & 
                & norm_x(ifac), norm_y(ifac))
                flux_minus(:)  = fluxm(vardummy_entree(right_cell,1), vardummy_entree(right_cell,2), vardummy_entree(right_cell,3), & 
                & vardummy_entree(right_cell,8), vardummy_entree(right_cell,5), vardummy_entree(right_cell,4), vardummy_entree(right_cell,6), vardummy_entree(right_cell,7), & 
                & norm_x(ifac), norm_y(ifac))
                flux(ifac,:)   = len_norm(ifac) * (flux_plus(:) + flux_minus(:))
            endif
            
            if (bc_typ(ifac) == 3) then ! Outflow
                flux_plus(:)   = fluxp(rho(left_cell), ux(left_cell), uy(left_cell), & 
                & e(left_cell), p(left_cell), t(left_cell), a(left_cell), b(left_cell), & 
                & norm_x(ifac), norm_y(ifac))
                flux_minus(:)  = fluxm(vardummy_sortie(right_cell,1), vardummy_sortie(right_cell,2), vardummy_sortie(right_cell,3), & 
                & vardummy_sortie(right_cell,8), vardummy_sortie(right_cell,5), vardummy_sortie(right_cell,4), vardummy_sortie(right_cell,6), vardummy_sortie(right_cell,7), & 
                & norm_x(ifac), norm_y(ifac))
                flux(ifac,:)   = len_norm(ifac) * (flux_plus(:) + flux_minus(:))
            endif 
        enddo 
        
        end subroutine calcul_flux
!----------------------------------------------------------------------
        subroutine calcul_rhs
        use mod_struct_to_array
        implicit none
        
        integer :: ifac, left_cell, right_cell
        
        if (.not. allocated(rhs)) then 
            allocate(rhs(nbelm,4))
        endif 
        
        rhs = 0.0d0 
        
        do ifac = 1, nbfaces
            left_cell  = lr_cell(ifac,1)
            right_cell = lr_cell(ifac,2)
            
            if (bc_typ(ifac) == 0) then
                rhs(left_cell,:)  = rhs(left_cell,:) - flux(ifac,:)
                rhs(right_cell,:) = rhs(right_cell,:) + flux(ifac,:)
            endif
            
            if (bc_typ(ifac) /= 0) then
                rhs(left_cell,:)  = rhs(left_cell,:) - flux(ifac,:)
            endif
        enddo 
        
        end subroutine calcul_rhs
!----------------------------------------------------------------------
        subroutine euler_time_iteration
        use mod_struct_to_array, only: vol
        implicit none
        integer :: icel
        
        do icel = 1, nbelm
            vect_unew(icel,:) = vect_u(icel,:) + dt / vol(icel) *  rhs(icel,:)
        enddo 
        
        end subroutine euler_time_iteration
!----------------------------------------------------------------------
        subroutine calcul_rho_ux_uy_t
        implicit none
        
        rho(1:nbelm) = vect_u(1:nbelm,1)
        ux(1:nbelm)  = vect_u(1:nbelm,2) / rho(1:nbelm)
        uy(1:nbelm)  = vect_u(1:nbelm,3) / rho(1:nbelm)
        t(1:nbelm)   = 2.0d0/(3.0d0 * r_gaz * rho(1:nbelm)) *(vect_u(1:nbelm,4)-0.5d0*rho(1:nbelm)*(ux(1:nbelm)**2+uy(1:nbelm)**2))
        end subroutine calcul_rho_ux_uy_t
!----------------------------------------------------------------------
end module