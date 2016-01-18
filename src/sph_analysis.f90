MODULE SPH_ANALYSIS
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
! A module which contains the function
! to perform spherical analysis 
! (generate sph coefficients)
! and its helper functions
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
USE VAND_SPH
IMPLICIT NONE

CONTAINS

SUBROUTINE toab(coef, mean, a, b)
    ! This subroutine takes in a coefficient array
    ! and a function mean and translates it into
    ! coefficient matrices a,b which can be used in spherepack
    !
    ! inputs:
    !   coef -- real, dimension(0:(l+1)**2) --
    !       coefficient array for spherical harmonics
    !
    ! outputs:
    !   a -- allocatable array, can be fed into spherepack
    !   b -- allocatable array, can be fed into spherepack

    ! inputs
    real, dimension(0:),intent(in) :: coef
    real, intent(in) :: mean

    ! outputs
    real, allocatable, dimension(:,:), intent(out) :: a
    real, allocatable, dimension(:,:), intent(out) :: b

    ! helper variables
    integer :: maxl, l, m
    
    ! Since coef is a linear array ranging from 0:(maxl+1)**2
    maxl = int(sqrt(size(coef)-1.0) - 1)

    allocate( a(0:maxl,0:maxl) )
    allocate( b(0:maxl,0:maxl) )

    do l=0,maxl
    do m=0,l
        a(m,l) = coef(ml2sIdx(m,l))
        if (m > 0) then
            b(m,l) = coef(ml2sIdx(-1*m,l))
        else
            b(m,l) = 0
        endif
    end do
    end do
END SUBROUTINE toab

SUBROUTINE scalef(f, mean, scalefact)
    ! Scales f to values of (-1,1)
    !
    ! inputs:
    !   f -- real, dimension(1:nloc) --
    !     input array
    !
    ! outputs:
    !   f -- real, dimension(1:nloc) --
    !     rescaled input array
    !   mean -- real --
    !     mean of input f
    !   scalefact -- real --
    !     scale factor for f
    !
    ! input f can be formed by taking
    ! scalefact*(f + mean)
    
    !inputs
    real, dimension(:), intent(inout) :: f

    !outputs
    real, intent(out) :: mean
    real, intent(out) :: scalefact

    !temporary variables
    integer :: nloc

    ! rescale and save values
    nloc = size(f)
    mean = sum(f)
    mean = mean/float(nloc)
    
    ! TODO: work out if scaling this is a bad idea...
    scalefact = maxval(abs(f))
    f = f/scalefact

END SUBROUTINE scalef

SUBROUTINE analysis(M_T, f_in, coef_out, lambda, tol_in, alpha)
    ! Calculates the spherical analysis of f
    ! This is a spherical harmonic fit to the difference
    ! from the mean, not an interpolation of the function itself
    !
    ! Manipulation of M_T and f_in is not done in place
    !
    ! inputs:
    !   M_T -- real, dimension(lmax**2,nlocs) --
    !       Vandermonde-like matrix for spherical harmonics.
    !       Generated by vand_sph module
    !   f_in   -- real, dimension(nlocs) --
    !       function values
    !
    ! outputs:
    !   coef_out -- real, dimension(lmax**2 + 1) --
    !       coefficients of spherical harmonics
    !   lambda -- real --
    !       value of lambda for the result.
    !       Edge values:
    !            0  -- harm. sph. representation result is constant (mean)
    !            1  -- harm. sph. representation balances lsq and constant fits
    !           inf -- harm. sph. representation is least squares fit
    !
    ! optional inputs:
    !   tol_in -- real -- 1e-06 --
    !       tolerance for convergence.
    !       Defaults to 1e-6
    !   alpha  -- real -- 0.5 --
    !       value by which to scale smoothing factor if it is too large.
    !       Must be between 0 and 1, otherwise defaults to 0.5
    
    !inputs
    real, dimension(:,:), intent(in) :: M_T
    real, dimension(size(M_T,2)), intent(in) :: f_in
    real, optional, intent(in) :: tol_in
    real, optional, intent(in) :: alpha
    
    !outputs
    real, allocatable, dimension(:), intent(out) :: coef_out
    real, intent(out) :: lambda
    
    ! variables used throughout computation
    real :: tol, scale, fscale
    real :: delta_p, delta_n
    integer :: l, c
    real, dimension(size(M_T,1)) :: coef_p, coef_n
    real, dimension(size(M_T,1)) :: BinvMTf
    real, dimension(size(M_T,2), size(M_T,1)) :: M
    real, dimension(size(M_T,1),size(M_T,2)) :: BinvMT
    real, dimension(size(M_T,2)) :: f
   
    ! allocate coef_out
    ALLOCATE(coef_out(0:size(M_T,1)+1))
    ! rescale f
    ! Note that representation within basis functions
    ! is linear, so scaling f down doesn't hurt
    f = f_in
    call scalef(f, coef_out(0), fscale)
    
    ! extract optional inputs
    ! TODO: figure out a good default value for tol
    tol = 1e-6*size(coef_n)
    if (present(tol_in)) tol = tol_in
    scale = 2
    if (present(alpha) .and. alpha .gt. 0 .and. alpha .lt. 1) scale = 1.0/alpha
    
    ! initialize values
    coef_p = 0.0
    M = TRANSPOSE(M_T)
    lambda = SUM(f*f)/SUM(MATMUL(M_T,f)*MATMUL(M_T,f))
    ! update M_T to instead be B^{-1} M_T since we no longer need M_T in the calculation
    BinvMT = M_T
    DO l = 1,int(size(M_T,1)**.5)
        c = ml2sIdx(0,l)
        BinvMT(c-l:c+l,:) = l*(l+1)*BinvMT(c-l:c+l,:)
    END DO
    
    BinvMTf = MATMUL(BinvMT,f)
    coef_n = 2*lambda*BinvMTf
    delta_n = SQRT(SUM((coef_n - coef_p)*( coef_n - coef_p)))
    
    ! loop through and update
    DO WHILE ( delta_n .ge. tol)
        delta_p = delta_n
        coef_p = coef_n
        coef_n = 2*lambda*( BinvMTf - MATMUL( BinvMT , MATMUL(M,coef_p) ) )
        delta_n = SQRT(SUM((coef_n - coef_p)*( coef_n - coef_p)))
        DO WHILE ( delta_n .ge. delta_p)
            lambda = lambda/scale
            coef_n = 2*lambda*( BinvMTf - MATMUL( BinvMT , MATMUL(M,coef_p) ) )
            delta_n = SQRT(SUM((coef_n - coef_p)*( coef_n - coef_p)))
        END DO
    END DO
    
    coef_out(1:) = fscale*coef_n

END SUBROUTINE analysis

SUBROUTINE analysis_lsq(M_T, f_in, coef_out, sv, rank, info, tol_in)
    ! Calculates the spherical analysis of f
    ! This is a spherical harmonic fit to the difference
    ! from the mean, not an interpolation of the function itself
    !
    ! Manipulation of M_T and f_in done in place
    !
    ! inputs:
    !   M_T -- real, dimension(lmax**2,nlocs) --
    !       Vandermonde-like matrix for spherical harmonics.
    !       Generated by vand_sph module
    !   f_in   -- real, dimension(nlocs) --
    !       function values
    !
    ! outputs:
    !   coef_out -- real, dimension(lmax**2 + 1) --
    !       coefficients of spherical harmonics
    !   sv -- real, dimension(min(size(M_T,1) --
    !       singular values of M
    !   rank -- integer --
    !       rank of M
    !   info -- integer --
    !       if info == 0 : successful svd
    !       if info < 0  : svd had illegal argument at -info
    !       if info > 0  : svd failed to converge
    !
    ! optional inputs:
    !   tol_in -- real -- 1e-06 --
    !       tolerance for singular value cutoff
    !       Defaults to 1e-6
 
    !inputs
    real, dimension(:,:), intent(in) :: M_T
    real, dimension(size(M_T,2)), intent(in) :: f_in
    real, optional, intent(in) :: tol_in
    
    !outputs
    real, allocatable, dimension(:), intent(out) :: coef_out
    real, allocatable, dimension(:), intent(out) :: sv
    integer, intent(out) :: rank
    integer, intent(out) :: info
    
    ! variables used throughout computation
    real :: tol, fscale
    integer :: nloc, nbasis, lwork
    real, dimension(size(M_T,2), size(M_T,1)) :: M
    real, dimension( max(size(M_T,1), size(M_T,2)) ) :: f
    real, dimension(:), allocatable :: work

    !computation

    !convenience variables
    nbasis = size(M_T,1)
    nloc = size(M_T,2)
    ! allocate coef_out
    ALLOCATE(coef_out(0:nbasis+1))
    ALLOCATE(sv(1:min(nbasis, nloc)))
    ! rescale f
    ! Note that representation within basis functions
    ! is linear, so scaling f down doesn't hurt
    f(1:nloc) = f_in
    call scalef(f(1:nloc), coef_out(0), fscale)
    
    tol = -1 ! use machine precision by default
    if (present(tol_in)) tol = tol_in

    M = TRANSPOSE(M_T) ! size nloc x nbasis

    ! perform least squares computation
    lwork = -1
    ALLOCATE(work(1))
    call dgelss(&
        nloc, nbasis, 1, M, nloc, f, size(f),&
        sv, tol, rank,&
        work, lwork, info)
    lwork  = work(1)
    DEALLOCATE(work)
    ALLOCATE(work(lwork))
    call dgelss(&
        nloc, nbasis, 1, M, nloc, f, size(f),&
        sv, tol, rank,&
        work, lwork, info)
    
    coef_out(1:) = fscale*f(1:nbasis)
 
END SUBROUTINE analysis_lsq

END MODULE SPH_ANALYSIS
