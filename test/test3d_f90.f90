! test driver on 3d FFT from FFT library
! for benchmarking, timing purposes
! see test3d.cpp for command-line args

! ---------------------------------------------------------------------
! common data
! ---------------------------------------------------------------------

module data
use iso_c_binding
implicit none

include 'mpif.h'

integer world
integer me,nprocs

integer nx,ny,nz
integer inpx,inpy,inpz,outpx,outpy,outpz
INTEGER nloop
INTEGER mode,iflag,cflag,eflag,pflag,tflag,rflag,oflag,vflag
INTEGER seed,seedinit

integer precision
integer inxlo,inxhi,inylo,inyhi,inzlo,inzhi  ! initial partition of grid
integer outxlo,outxhi,outylo,outyhi,outzlo,outzhi   ! final partition of grid
integer nfft_in              ! # of grid pts I own in initial partition
integer nfft_out             ! # of grid pts I own in final partition
integer fftsize              ! FFT buffer size returned by FFT setup

integer tuneflag,tuneper,tuneextra
REAL*8  tunemax

TYPE(C_ptr) :: fft
real(8) ::  timefft,timeinit,timesetup,timetune
real(8) :: epsmax

integer :: ZERO = 0
integer :: STEP = 1
integer :: INDEX = 2
integer :: RANDOMINIT = 3

integer :: POINT = 0
integer :: ALL2ALL = 1
integer :: COMBO = 2

integer :: PENCIL = 0
integer :: BRICK = 1

integer :: ARRAY = 0
integer :: POINTER = 1
integer :: MEMCPY = 2

integer :: IN = 0
integer :: OUT = 1

integer :: IA = 16807
integer :: IM = 2147483647
REAL*8  :: AM
integer :: IQ = 127773
integer :: IR = 2836

#ifdef FFT_SINGLE
REAL(4), ALLOCATABLE, target :: work(:)
#else
REAL(8), ALLOCATABLE, target :: work(:)
#endif

character (len=256) :: syntax
 
!syntax = "Syntax: test3d_f90 -g Nx Nx Nz -p Px Py Pz -n Nloop -m 0/1/2/3" // &
!        "         -i zero/step/82783 -m 0/1/2/3 -tune nper tmax extra" // &
!        "         -c point/all/combo -e pencil/brick -p array/ptr/memcpy" // &
!        "         -t -r -o -v"

end module data

! ---------------------------------------------------------------------
! main program
! ---------------------------------------------------------------------

program test3d_f90

use data
use iso_c_binding
use fft3d_wrap

implicit none
INTEGER i,ierr
REAL*8 time1,time2

#ifdef FFT_SINGLE
precision = 1;
#else
precision = 2;
#endif

AM = (1.0/IM)

! MPI setup

call MPI_Init(ierr)

world = MPI_COMM_WORLD
call MPI_Comm_rank(world,me,ierr)
call MPI_Comm_size(world,nprocs,ierr)

! parse command-line args

call options()

! partition FFT grid across procs, for both input and output
! create FFT plan, will tune if requested
! allocate grid
! initialize FFT grid
! grid output

call MPI_Barrier(world,ierr)
time1 = MPI_Wtime()

call proc_setup(0)
call proc_setup(1)
call grid_setup()
call plan()
call allocate_mine()
call initialize()

call MPI_Barrier(world,ierr)
time2 = mpi_wtime()
timeinit = time2 - time1

IF (oflag /= 0) CALL output(0,"Initial grid")

! perform FFTs

call MPI_Barrier(world,ierr)
time1 = MPI_Wtime()

if (mode < 2) then
  do i = 1,nloop
    call fft3d_compute(fft,c_loc(work),c_loc(work),1)
!    if (oflag /= 0) call output(1,"Middle grid")
    call fft3d_compute(fft,c_loc(work),c_loc(work),-1)
  enddo
else
  do i = 1,nloop
    call fft3d_compute(fft,c_loc(work),c_loc(work),1)
  enddo
endif

call MPI_Barrier(world,ierr)
time2 = mpi_wtime()
timefft = time2 - time1

! validation check on result
! grid output
! timing results
! deallocate grid and plan

if (vflag == 0) call validate()
IF (oflag /= 0) THEN
   if (mode < 2) then
      call output(0,"Final grid")
   else
      call output(1,"Final grid")
   endif
endif
  
call timing()
call deallocate_mine()
call fft3d_destroy(fft)

call MPI_Finalize(ierr)

end program test3d_f90

! ---------------------------------------------------------------------
! parse command-line options
! all options have defaults
! ---------------------------------------------------------------------

SUBROUTINE options()
use data
implicit none
INTEGER iarg,narg
CHARACTER(len=32) :: arg

! defaults

nx = 8
ny = 8
nz = 8
inpx = 0
inpy = 0
inpz = 0
outpx = 0
outpy = 0
outpz = 0
nloop = 1
iflag = ZERO
tuneflag = 0
mode = 0
cflag = COMBO
eflag = PENCIL
pflag = MEMCPY
tflag = 0
rflag = 0
oflag = 0
vflag = 0

! parse args

narg = command_argument_count()

iarg = 1
do while (iarg < narg)
  call get_command_argument(iarg,arg)
  if (arg == '-h') then
    call error_all(syntax)
  else if (arg == '-g') then
    IF (iarg+3 > narg) call error_all(syntax)
    call get_command_argument(iarg+1,arg)
    read (arg,'(i10)') nx
    call get_command_argument(iarg+2,arg)
    read (arg,'(i10)') ny
    call get_command_argument(iarg+3,arg)
    read (arg,'(i10)') nz
    iarg = iarg + 4
  ELSE IF (arg == "-pin") then
    IF (iarg+4 > narg) call error_all(syntax)
    call get_command_argument(iarg+1,arg)
    read (arg,'(i10)') inpx
    call get_command_argument(iarg+2,arg)
    read (arg,'(i10)') inpy
    call get_command_argument(iarg+3,arg)
    read (arg,'(i10)') inpz
    iarg = iarg + 4
  else if (arg == "-pout") then
    IF (iarg+4 > narg) call error_all(syntax)
    call get_command_argument(iarg+1,arg)
    read (arg,'(i10)') outpx
    call get_command_argument(iarg+2,arg) 
    read (arg,'(i10)') outpy
    call get_command_argument(iarg+3,arg) 
    read (arg,'(i10)') outpz
    iarg = iarg + 4
  else if (arg == '-n') then
    IF (iarg+1 > narg) CALL error_all(syntax)
    CALL GET_COMMAND_ARGUMENT(iarg+1,arg)
    READ (arg,'(i10)') nloop
    iarg = iarg + 2
  ELSE IF (arg == "-i") THEN
    IF (iarg+2 > narg) call error_all(syntax)
    IF (arg == "zero") THEN
      iflag = ZERO
    ELSE IF (arg == "step") then
      iflag = STEP
    ELSE IF (arg == "index") then
      iflag = INDEX
    ELSE
      iflag = RANDOMINIT
      ! per-processor RNG seed
      CALL GET_COMMAND_ARGUMENT(iarg+1,arg)
      READ (arg,'(i10)') seedinit
      seed = seedinit + me
    ENDIF
    iarg = iarg + 2
  ELSE IF (arg == "-tune") THEN
    IF (iarg+4 > narg) call error_all(syntax)
    tuneflag = 1
    CALL GET_COMMAND_ARGUMENT(iarg+1,arg)
    READ (arg,'(i10)') tuneper
    CALL GET_COMMAND_ARGUMENT(iarg+2,arg)
    READ (arg,'(f10.3)') tunemax
    CALL GET_COMMAND_ARGUMENT(iarg+3,arg)
    READ (arg,'(i10)') tuneextra
    iarg = iarg + 4
  ELSE IF (arg == "-m") THEN
    IF (iarg+2 > narg) call error_all(syntax)
    CALL GET_COMMAND_ARGUMENT(iarg+1,arg)
    READ (arg,'(i10)') mode
    iarg = iarg + 2
  ELSE IF (arg == "-c") THEN
    IF (iarg+2 > narg) call error_all(syntax)
    IF (arg == "point") THEN
      cflag = POINT
    ELSE IF (arg == "all") then
      cflag = ALL2ALL
    ELSE IF (arg == "combo") then
      cflag = COMBO
    ELSE 
      CALL error_all(syntax)
    ENDIF
    iarg = iarg + 2
  ELSE IF (arg == "-e") THEN
    IF (iarg+2 > narg) call error_all(syntax)
    IF (arg == "pencil") then
      eflag = PENCIL
    ELSE IF (arg == "brick") then
      eflag = BRICK
    ELSE 
      CALL error_all(syntax)
    endif
    iarg = iarg + 2
  ELSE IF (arg == "-p") THEN
    IF (iarg+2 > narg) call error_all(syntax)
    IF (arg == "array") THEN
      pflag = ARRAY
    ELSE IF (arg == "ptr") THEN 
      pflag = POINTER
    ELSE IF (arg == "memcpy") THEN
      pflag = MEMCPY
    ELSE 
      CALL error_all(syntax)
    ENDIF
    iarg = iarg + 2
  ELSE IF (arg == "-t") THEN
    tflag = 1
    iarg = iarg + 1
  ELSE IF (arg == "-r") THEN
    rflag = 1
    iarg = iarg + 1
  ELSE IF (arg == "-o") THEN
    oflag = 1
    iarg = iarg + 1
  ELSE IF (arg == "-v") THEN
    vflag = 1
    iarg = iarg + 1
  else
    call error_all(syntax)
  endif
enddo

! sanity check on args

if (nx <= 0 .or. ny <= 0 .or. nz <= 0) call error_all("Invalid grid size")

IF (inpx == 0 .and. inpy == 0 .and. inpz == 0) then
ELSE IF (inpx <= 0 .or. inpy <= 0 .OR. inpz <= 0) THEN
  call error_all("Invalid proc grid")
ELSE IF (inpx*inpy*inpz /= nprocs) THEN
  call error_all("Specified proc grid does not match nprocs")
endif

IF (outpx == 0 .and. outpy == 0 .and. outpz == 0) then
ELSE IF (outpx <= 0 .or. outpy <= 0 .OR. outpz <= 0) THEN
  call error_all("Invalid proc grid")
ELSE IF (outpx*outpy*outpz /= nprocs) THEN
  call error_all("Specified proc grid does not match nprocs")
endif

IF (nloop < 0) call error_all("Invalid Nloop")
IF (nloop == 0 .and. tuneflag == 0) call error_all("Invalid Nloop")
IF (iflag == RANDOMINIT .and. seed <= 0) &
        CALL error_all("Invalid initialize setting")
IF (mode < 0 .or. mode > 3) call error_all("Invalid FFT mode")
IF (mode > 1 .AND. vflag /= 0) CALL error_all("Cannot validate forward only FFT")

IF (tuneflag /= 0 .AND. tuneper <= 0) CALL error_all("Invalid tune nper")
IF (tuneflag /= 0 .AND. tunemax < 0.0) CALL error_all("Invalid tune tmax")
IF (tuneflag /= 0 .AND. (tuneextra < 0 .OR. tuneextra > 1)) &
        call error_all("Invalid tune extra")
IF (tuneflag /= 0 .AND. rflag /= 0) CALL error_all("Cannot tune with remap only")

end subroutine options

! ---------------------------------------------------------------------
! partition processors across grid dimensions
! flag = IN for input partitions, or OUT for output partitions
! if user set Px,Py,Pz -> just return
! for IN:
!   assign nprocs as bricks to 3d grid to minimize surface area per proc
!   derived from SPPARKS Domain::procs2domain_3d()
! for OUT:
!   assign nprocs as rectangles to xy grid to minimize surface area per proc
!   derived from SPPARKS Domain::procs2domain_2d()
! ---------------------------------------------------------------------

subroutine proc_setup(flag)
use data
implicit none
INTEGER flag

IF (flag == 0) then
  IF (inpx /= 0 .OR. inpy /= 0 .OR. inpz /= 0) RETURN
  call proc3d(inpx,inpy,inpz)
endif

IF (flag == 1) then
  IF (outpx /= 0 .OR. outpy /= 0 .OR. outpz /= 0) RETURN
  IF (mode == 0 .or. mode == 2) call proc3d(outpx,outpy,outpz)
  IF (mode == 1 .or. mode == 3) call proc2d(outpx,outpy,outpz)
endif

end subroutine proc_setup

! ---------------------------------------------------------------------

SUBROUTINE proc3d(px,py,pz)
use data
implicit none
INTEGER px,py,pz
integer ipx,ipy,ipz,nremain
REAL*8 boxx,boxy,boxz,surf
REAL*8 xprd,yprd,zprd,bestsurf

xprd = nx
yprd = ny
zprd = nz
  
bestsurf = 2.0 * (xprd*yprd + yprd*zprd + zprd*xprd)
  
! loop thru all possible factorizations of nprocs
! surf = surface area of a proc sub-domain
  
ipx = 1
DO WHILE (ipx <= nprocs)
  IF (MOD(nprocs,ipx) == 0) THEN
    nremain = nprocs/ipx
    ipy = 1
    DO WHILE (ipy <= nremain)
      IF (MOD(nremain,ipy) == 0) THEN
        ipz = nremain/ipy
        boxx = xprd/ipx
        boxy = yprd/ipy
        boxz = zprd/ipz
        surf = boxx*boxy + boxy*boxz + boxz*boxx
        IF (surf < bestsurf) THEN
          bestsurf = surf
          px = ipx
          py = ipy
          pz = ipz
        ENDIF
      ENDIF
      ipy = ipy + 1
    ENDDO
  ENDIF
  ipx = ipx + 1
ENDDO
  
IF (px*py*pz /= nprocs) &
        CALL error_all("Computed proc grid does not match nprocs")

end subroutine proc3d

! ---------------------------------------------------------------------

SUBROUTINE proc2d(px,py,pz)
use data
implicit none
INTEGER px,py,pz
integer ipx,ipy
REAL*8 boxx,boxy,surf,xprd,yprd,bestsurf

xprd = nx
yprd = ny
  
bestsurf = 2.0 * (xprd+yprd)
  
! loop thru all possible factorizations of nprocs
! surf = surface area of a proc sub-domain
  
ipx = 1
do while (ipx <= nprocs)
  IF (MOD(nprocs,ipx) == 0) then
    ipy = nprocs/ipx
    boxx = xprd/ipx
    boxy = yprd/ipy
    surf = boxx + boxy
    IF (surf < bestsurf) then
      bestsurf = surf
      px = ipx
      py = ipy
    endif
  endif
  ipx = ipx + 1
enddo
  
pz = 1
IF (px*py*pz /= nprocs) &
        CALL error_all("Computed proc grid does not match nprocs")

end subroutine proc2d

! ---------------------------------------------------------------------
! partition FFT grid
! once for input grid, once for output grid
! use Px,Py,Pz for in/out
! ---------------------------------------------------------------------

SUBROUTINE grid_setup()
use data
implicit none
INTEGER ipx,ipy,ipz

! ipx,ipy,ipz = my position in input 3d grid of procs

ipx = MOD(me,inpx)
ipy = MOD(me/inpx,inpy)
ipz = me / (inpx*inpy)

! nlo,nhi = lower/upper limits of the 3d brick I own

inxlo = 1.0 * ipx * nx / inpx + 1
inxhi = 1.0 * (ipx+1) * nx / inpx

inylo = 1.0 * ipy * ny / inpy + 1
inyhi = 1.0 * (ipy+1) * ny / inpy

inzlo = 1.0 * ipz * nz / inpz + 1
inzhi = 1.0 * (ipz+1) * nz / inpz

nfft_in = (inxhi-inxlo+1) * (inyhi-inylo+1) * (inzhi-inzlo+1)

! ipx,ipy,ipz = my position in output 3d grid of procs

ipx = MOD(me,outpx)
ipy = MOD(me/outpx,outpy)
ipz = me / (outpx*outpy)

! nlo,nhi = lower/upper limits of the 3d brick I own

outxlo = 1.0 * ipx * nx / outpx + 1
outxhi = 1.0 * (ipx+1) * nx / outpx

outylo = 1.0 * ipy * ny / outpy + 1
outyhi = 1.0 * (ipy+1) * ny / outpy

outzlo = 1.0 * ipz * nz / outpz + 1
outzhi = 1.0 * (ipz+1) * nz / outpz

nfft_out = (outxhi-outxlo+1) * (outyhi-outylo+1) * (outzhi-outzlo+1)

end subroutine grid_setup

! ---------------------------------------------------------------------
! creats FFT plan
! ---------------------------------------------------------------------

SUBROUTINE plan()
use data
use fft3d_wrap
implicit none
INTEGER permute,sendsize,recvsize,flag,ierr
REAL*8 time1,time2

call fft3d_create_fortran(world,precision,fft)
CALL fft3d_set(fft,"remaponly",rflag)

CALL fft3d_set(fft,"collective",cflag)
CALL fft3d_set(fft,"exchange",eflag)
CALL fft3d_set(fft,"pack",pflag)

IF (mode == 0 .or. mode == 2) then
  permute = 0
ELSE 
  permute = 2
endif

call MPI_Barrier(world,ierr)
time1 = MPI_Wtime()

! will use fftsize to allocate work buffer
! ignore sendsize, recvsize b/c let FFT allocate remap buffers internally
! set timesetup and timetune
! reset nloop if tuning and user nloop = 0

IF (tuneflag == 0) THEN
  CALL fft3d_setup(fft,nx,ny,nz, &
          inxlo,inxhi,inylo,inyhi,inzlo,inzhi, &
          outxlo,outxhi,outylo,outyhi,outzlo,outzhi, &
          permute,fftsize,sendsize,recvsize)
else
  flag = 0
  IF (mode >= 2) flag = 1
  CALL fft3d_tune(fft,nx,ny,nz, &
          inxlo,inxhi,inylo,inyhi,inzlo,inzhi, &
          outxlo,outxhi,outylo,outyhi,outzlo,outzhi, &
          permute,fftsize,sendsize,recvsize, &
          flag,tuneper,tunemax,tuneextra)
  IF (nloop == 0) nloop = fft3d_get_int(fft,"npertrial")
endif

call MPI_Barrier(world,ierr)
time2 = MPI_Wtime()

IF (tuneflag == 0) then
  timesetup = time2 - time1
  timetune = 0.0
else
  timesetup = fft3d_get_double(fft,"setuptime")
  timetune = time2 - time1
endif

end subroutine plan

! ---------------------------------------------------------------------
! allocate memory for FFT grid
! ---------------------------------------------------------------------

subroutine allocate_mine()
use data
implicit none

ALLOCATE(work(2*fftsize))

end subroutine allocate_mine

! ---------------------------------------------------------------------
! must be called by all procs in world
! shuts down MPI and exits
! ---------------------------------------------------------------------

SUBROUTINE initialize()
use data
implicit none
integer m
integer ilocal,jlocal,klocal,iglobal,jglobal,kglobal
INTEGER nxlocal,nylocal
REAL*8 random

if (iflag == ZERO) then
  DO m = 1,2*nfft_in
    work(m) = 0.0
  ENDDO

ELSE IF (iflag == STEP) THEN
  nxlocal = inxhi - inxlo + 1
  nylocal = inyhi - inylo + 1

  DO m = 0,nfft_in-1
    ilocal = MOD(m,nxlocal)
    jlocal = MOD((m/nxlocal),nylocal)
    klocal = m / (nxlocal*nylocal)
    iglobal = inxlo + ilocal
    jglobal = inylo + jlocal
    kglobal = inzlo + klocal
    IF (iglobal < nx/2 .and. jglobal < ny/2 .and. kglobal < nz/2) THEN
      work(2*m) = 1.0
    ELSE 
      work(2*m) = 0.0
    ENDIF
    work(2*m+1) = 0.0
  ENDDO

ELSE IF (iflag == INDEX) THEN
    nxlocal = inxhi - inxlo + 1;
    nylocal = inyhi - inylo + 1;

    DO m = 0,nfft_in-1
      ilocal = MOD(m,nxlocal)
      jlocal = MOD((m/nxlocal),nylocal)
      klocal = m / (nxlocal*nylocal)
      iglobal = inxlo + ilocal
      jglobal = inylo + jlocal
      kglobal = inzlo + klocal
      work(2*m) = kglobal + jglobal + iglobal + 1
      work(2*m+1) = 0.0
    enddo

ELSE IF (iflag == RANDOMINIT) THEN
  DO m = 1,2*nfft_in
    work(m) = random()
  ENDDO
endif

end subroutine initialize

! ---------------------------------------------------------------------
! output FFT grid values
! flag = 0 for initial partition
! flag = 1 for final partition
! ---------------------------------------------------------------------

SUBROUTINE output(flag, str)
use data
implicit none
INTEGER flag
CHARACTER (len=*) :: str
INTEGER iproc,m,tmp,ierr
integer ilocal,jlocal,klocal,iglobal,jglobal,kglobal
INTEGER nxlocal,nylocal

IF (me == 0) PRINT *,str

DO iproc = 0,nprocs-1
  IF (me /= iproc) CONTINUE
  IF (me >= 1) CALL MPI_Recv(tmp,0,MPI_INT,me-1,0,world,MPI_STATUS_IGNORE,ierr)

  IF (flag == 0) THEN
    nxlocal = inxhi - inxlo + 1
    nylocal = inyhi - inylo + 1
    
    DO m = 0,nfft_in-1
      ilocal = MOD(m,nxlocal)
      jlocal = MOD((m/nxlocal),nylocal)
      klocal = m / (nxlocal*nylocal)
      iglobal = inxlo + ilocal
      jglobal = inylo + jlocal
      kglobal = inzlo + klocal
      PRINT *,"Value (",iglobal,jglobal,kglobal,") on proc",me, &
              "= (",work(2*m),work(2*m+1),")"
    ENDDO
  ELSE
    nxlocal = outxhi - outxlo + 1
    nylocal = outyhi - outylo + 1

    DO m = 0,nfft_in-1
      ilocal = MOD(m,nxlocal)
      jlocal = MOD((m/nxlocal),nylocal)
      klocal = m / (nxlocal*nylocal)
      iglobal = outxlo + ilocal
      jglobal = outylo + jlocal
      kglobal = outzlo + klocal
      PRINT *,"Value (",iglobal,jglobal,kglobal,") on proc",me, &
              "= (",work(2*m),work(2*m+1),")"
    ENDDO
  ENDIF

  IF (me < nprocs-1) CALL MPI_Send(tmp,0,MPI_INT,me+1,0,world,ierr)
ENDDO

end subroutine output

! ---------------------------------------------------------------------
! validation check for correct result
! ---------------------------------------------------------------------

SUBROUTINE validate()
use data
implicit none
integer ilocal,jlocal,klocal,iglobal,jglobal,kglobal
INTEGER nxlocal,nylocal
INTEGER m,ierr
REAL*8 delta,epsilon,VALUE,newvalue
REAL*8 random

epsilon = 0.0

IF (iflag == ZERO) THEN
  DO m = 0,2*nfft_in-1
    delta = abs(work(m))
    IF (delta > epsilon) epsilon = delta
  ENDDO

ELSE IF (iflag == STEP) THEN
  nxlocal = inxhi - inxlo + 1
  nylocal = inyhi - inylo + 1

  DO m = 0,nfft_in-1
    ilocal = MOD(m,nxlocal)
    jlocal = MOD((m/nxlocal),nylocal)
    klocal = m / (nxlocal*nylocal)
    iglobal = inxlo + ilocal
    jglobal = inylo + jlocal
    kglobal = inzlo + klocal
    IF (iglobal < nx/2 .AND. jglobal < ny/2 .AND. kglobal < nz/2) THEN
      VALUE = 1.0
    ELSE
      VALUE = 0.0
    ENDIF
    delta = abs(work(2*m)-VALUE)
    IF (delta > epsilon) epsilon = delta
    delta = abs(work(2*m+1))
    IF (delta > epsilon) epsilon = delta
  ENDDO

ELSE IF (iflag == INDEX) THEN
  nxlocal = inxhi - inxlo + 1
  nylocal = inyhi - inylo + 1

  DO m = 0,nfft_in-1
    ilocal = MOD(m,nxlocal)
    jlocal = MOD((m/nxlocal),nylocal)
    klocal = m / (nxlocal*nylocal)
    iglobal = inxlo + ilocal
    jglobal = inylo + jlocal
    kglobal = inzlo + klocal
    VALUE = kglobal+ jglobal + iglobal + 1
    delta = abs(work(2*m)-VALUE)
    IF (delta > epsilon) epsilon = delta
    delta = abs(work(2*m+1))
    IF (delta > epsilon) epsilon = delta
  ENDDO

ELSE IF (iflag == RANDOMINIT) THEN
  seed = seedinit
  DO m = 0,2*nfft_in-1
    newvalue = random()
    delta = abs(work(m)-newvalue)
    IF (delta > epsilon) epsilon = delta
  ENDDO
ENDIF

CALL MPI_Allreduce(epsilon,epsmax,1,MPI_DOUBLE,MPI_MAX,world,ierr)

end subroutine validate

! ---------------------------------------------------------------------
! output timing data
! ---------------------------------------------------------------------

SUBROUTINE timing()
use data
use iso_c_binding
use fft3d_wrap
implicit none
integer nfft
REAL (kind=8) :: onetime,nsize,log2n,floprate
INTEGER i,nlen,ierr
REAL*8 time1d,time_remap;
REAL*8 time_remap1,time_remap2,time_remap3,time_remap4;
REAL*8 time1,time2,time3,time4,time5
INTEGER*8 gridbytes
INTEGER ntrial,npertrial
INTEGER(8), POINTER :: cflags(:) => NULL()
INTEGER(8), POINTER :: eflags(:) => NULL()
INTEGER(8), POINTER :: pflags(:) => NULL()
REAL(8), POINTER :: tfft(:) => NULL()
REAL(8), POINTER :: t1d(:) => NULL()
REAL(8), POINTER :: tremap(:) => NULL()
REAL(8), POINTER :: tremap1(:) => NULL()
REAL(8), POINTER :: tremap2(:) => NULL()
REAL(8), POINTER :: tremap3(:) => NULL()
REAL(8), POINTER :: tremap4(:) => NULL()
TYPE(C_ptr) :: ptr

! perform only 1d FFTs

IF (tflag /= 0) THEN
  DO i = 0,2*nfft_in-1
    work(i) = 0.0
  ENDDO

  call MPI_Barrier(world,ierr)
  time1 = MPI_Wtime()

  IF (mode < 2) THEN
    DO i = 1,nloop
      call fft3d_only_1d_ffts(fft,c_loc(work),1)
      call fft3d_only_1d_ffts(fft,c_loc(work),-1)
    ENDDO
  ELSE
    DO i = 1,nloop
      call fft3d_only_1d_ffts(fft,c_loc(work),1)
    ENDDO
  ENDIF

  call MPI_Barrier(world,ierr)
  time2 = MPI_Wtime()
  time1d = time2 - time1
ENDIF

! perform all remaps

IF (tflag /= 0) THEN
  DO i = 0,2*nfft_in-1
    work(i) = 0.0
  ENDDO

  call MPI_Barrier(world,ierr)
  time1 = MPI_Wtime()

  IF (mode < 2) THEN
    DO i = 1,nloop
      call fft3d_only_remaps(fft,c_loc(work),c_loc(work),1)
      call fft3d_only_remaps(fft,c_loc(work),c_loc(work),-1)
    ENDDO
  ELSE
    DO i = 1,nloop
      call fft3d_only_remaps(fft,c_loc(work),c_loc(work),1)
    ENDDO
  ENDIF

  call MPI_Barrier(world,ierr)
  time2 = MPI_Wtime()
  time_remap = time2 - time1
ENDIF

! perform only single remaps

IF (tflag /= 0) THEN
  DO i = 0,2*nfft_in-1
    work(i) = 0.0
  ENDDO

  call MPI_Barrier(world,ierr)
  time1 = MPI_Wtime()

  IF (mode < 2) THEN
    DO i = 1,nloop
      call fft3d_only_one_remap(fft,c_loc(work),c_loc(work),1,1)
      call fft3d_only_one_remap(fft,c_loc(work),c_loc(work),-1,1)
    ENDDO
  ELSE
    DO i = 1,nloop
      call fft3d_only_one_remap(fft,c_loc(work),c_loc(work),1,1)
    ENDDO
  ENDIF

  call MPI_Barrier(world,ierr)
  time2 = MPI_Wtime()
  time_remap1 = time2 - time1

  IF (mode < 2) THEN
    DO i = 1,nloop
      call fft3d_only_one_remap(fft,c_loc(work),c_loc(work),1,2)
      call fft3d_only_one_remap(fft,c_loc(work),c_loc(work),-1,2)
    ENDDO
  ELSE
    DO i = 1,nloop
      call fft3d_only_one_remap(fft,c_loc(work),c_loc(work),1,2)
    ENDDO
  ENDIF

  call MPI_Barrier(world,ierr)
  time3 = MPI_Wtime()
  time_remap2 = time3 - time2

  IF (mode < 2) THEN
    DO i = 1,nloop
      call fft3d_only_one_remap(fft,c_loc(work),c_loc(work),1,3)
      call fft3d_only_one_remap(fft,c_loc(work),c_loc(work),-1,3)
    ENDDO
  ELSE
    DO i = 1,nloop
      call fft3d_only_one_remap(fft,c_loc(work),c_loc(work),1,3)
    ENDDO
  ENDIF

  call MPI_Barrier(world,ierr)
  time4 = MPI_Wtime()
  time_remap3 = time4 - time3

  IF (mode < 2) THEN
    DO i = 1,nloop
      call fft3d_only_one_remap(fft,c_loc(work),c_loc(work),1,4)
      call fft3d_only_one_remap(fft,c_loc(work),c_loc(work),-1,5)
    ENDDO
  ELSE
    DO i = 1,nloop
      call fft3d_only_one_remap(fft,c_loc(work),c_loc(work),1,5)
    ENDDO
  ENDIF

  call MPI_Barrier(world,ierr)
  time5 = MPI_Wtime()
  time_remap4 = time5 - time4
ENDIF

! stats output
! nfft = 2x larger for modes 0,1

IF (mode < 2) then
  nfft = 2*nloop
ELSE 
  nfft = nloop
endif

onetime = timefft/nfft
nsize = 1.0 * nx * ny * nz
log2n = log(nsize)/log(2.0)
floprate = 5.0 * nsize * log2n / onetime / (1024*1024*1024)

#ifdef FFT_SINGLE
gridbytes = 4 * 2*fftsize
#else
gridbytes = 8 * 2*fftsize
#endif

nlen = 10

IF (me == 0) THEN
  PRINT *,"3d FFTs with %s library, precision =", &
          fft3d_get_string(fft,"fft1d"),fft3d_get_string(fft,"precision")
  PRINT *,"Grid size:",nx,ny,nz
  PRINT *,"  initial proc grid:",inpx,inpy,inpz
  PRINT *,"  x pencil proc grid:", &
          fft3d_get_int(fft,"npfast1"), &
          fft3d_get_int(fft,"npfast2"), &
          fft3d_get_int(fft,"npfast3")
  PRINT *,"  y pencil proc grid:", &
          fft3d_get_int(fft,"npmid1"), &
          fft3d_get_int(fft,"npmid2"), &
          fft3d_get_int(fft,"npmid3")
  PRINT *,"  z pencil proc grid:", &
          fft3d_get_int(fft,"npslow1"), &
          fft3d_get_int(fft,"npslow2"), &
          fft3d_get_int(fft,"npslow3")
  PRINT *,"  3d brick proc grid:", &
          fft3d_get_int(fft,"npbrick1"), &
          fft3d_get_int(fft,"npbrick2"), &
          fft3d_get_int(fft,"npbrick3")
  PRINT *,"  final proc grid:",outpx,outpy,outpz

  IF (tuneflag /= 0) THEN
    ntrial = fft3d_get_int(fft,"ntrial")
    npertrial = fft3d_get_int(fft,"npertrial")
    PRINT *,"Tuning trials & iterations:",ntrial,npertrial
    ptr = fft3d_get_int_vector(fft,"cflags")
    CALL C_F_POINTER(ptr,cflags,[nlen])
    ptr = fft3d_get_int_vector(fft,"eflags")
    CALL C_F_POINTER(ptr,eflags,[nlen])
    ptr = fft3d_get_int_vector(fft,"pflags")
    CALL C_F_POINTER(ptr,pflags,[nlen])
    ptr = fft3d_get_double_vector(fft,"tfft")
    CALL C_F_POINTER(ptr,tfft,[nlen])
    ptr = fft3d_get_double_vector(fft,"t1d")
    CALL C_F_POINTER(ptr,t1d,[nlen])
    ptr = fft3d_get_double_vector(fft,"tremap")
    CALL C_F_POINTER(ptr,tremap,[nlen])
    ptr = fft3d_get_double_vector(fft,"tremap1")
    CALL C_F_POINTER(ptr,tremap1,[nlen])
    ptr = fft3d_get_double_vector(fft,"tremap2")
    CALL C_F_POINTER(ptr,tremap2,[nlen])
    ptr = fft3d_get_double_vector(fft,"tremap3")
    CALL C_F_POINTER(ptr,tremap3,[nlen])
    ptr = fft3d_get_double_vector(fft,"tremap4")
    CALL C_F_POINTER(ptr,tremap4,[nlen])
    DO i = 1,ntrial
      PRINT *,"  coll exch pack 3dFFT 1dFFT remap r1 r2 r3 r4:", &
              cflags(i),eflags(i),pflags(i),tfft(i),t1d(i),tremap(i), &
              tremap1(i),tremap2(i),tremap3(i),tremap4(i)
    ENDDO
  ENDIF

  IF (mode == 0) THEN
    PRINT *,nloop,"forward and",nloop,"back FFTs on",nprocs,"procs"
  ELSE IF (mode == 1) then
    PRINT *,nloop,"forward and",nloop,"back convolution FFTs on",nprocs,"procs"
  ELSE IF (mode == 2) then
    PRINT *,nloop,"forward FFTs on",nprocs,"procs"
  ELSE IF (mode == 3) then
    PRINT *,nloop,"forward convolution FFTs on",nprocs,"procs"
  ENDIF

  PRINT *,"Collective, exchange, pack methods:", &
          fft3d_get_int(fft,"collective"), &
          fft3d_get_int(fft,"exchange"), &
          fft3d_get_int(fft,"pack")
  PRINT *,"Memory usage (per-proc) for FFT grid =", &
          1.0*gridbytes / 1024/1024,",MBytes"
  PRINT *,"Memory usage (per-proc) by fftMPI =", &
          1.0*fft3d_get_int64(fft,"memusage") / 1024/1024,"MBytes"
  
  IF (vflag /= 0) PRINT *,"Max error =",epsmax
  IF (tuneflag /= 0) THEN
    PRINT *,"Initialize grid =",timeinit-timesetup,"secs"
  ELSE 
    PRINT *,"Initialize grid =",timeinit-timetune,"secs"
  ENDIF
  PRINT *,"FFT setup =",timesetup,"secs"
  PRINT *,"FFT tune =",timetune,"secs"
  PRINT *,"Time for 3d FFTs =",timefft,"secs"
  PRINT *,"  time/fft3d = %g secs",onetime
  PRINT *,"  flop rate for 3d FFTs =",floprate,"Gflops"
  IF (tflag /= 0) THEN
    PRINT *,"Time for 1d FFTs only =",time1d,"secs"
    PRINT *,"  time/fft1d =",time1d/nfft,"secs"
    PRINT *,"  fraction of time in 1d FFTs =",time1d/timefft
  ENDIF
  IF (tflag /= 0) THEN
    PRINT *,"Time for remaps only =",time_remap,"secs"
    PRINT *,"  fraction of time in remaps =",time_remap/timefft
    PRINT *,"Time for remap #1 =",time_remap1,"secs"
    PRINT *,"  fraction of time in remap #1 =",time_remap1/timefft
    PRINT *,"Time for remap #2 =",time_remap2,"secs"
    PRINT *,"  fraction of time in remap #2 =",time_remap2/timefft
    PRINT *,"Time for remap #3 =",time_remap3,"secs"
    PRINT *,"  fraction of time in remap #3 =",time_remap3/timefft
    PRINT *,"Time for remap #4 =",time_remap4,"secs"
    PRINT *,"  fraction of time in remap #4 =",time_remap4/timefft
  ENDIF
ENDIF

end subroutine timing

! ---------------------------------------------------------------------
! deallocate memory for FFT grid
! ---------------------------------------------------------------------

subroutine deallocate_mine()
use data
implicit none

deallocate(work)

end subroutine deallocate_mine

! ---------------------------------------------------------------------
! ---------------------------------------------------------------------
! utility functions
! ---------------------------------------------------------------------
! ---------------------------------------------------------------------

! ---------------------------------------------------------------------
! must be called by all procs in world
! shuts down MPI and exits
! ---------------------------------------------------------------------

SUBROUTINE error_all(str)
use data
implicit none
CHARACTER (len=*) :: str
INTEGER ierr

CALL MPI_Barrier(world,ierr)
if (me == 0) print *,"ERROR:",str
CALL MPI_Finalize(ierr)
call exit()

end subroutine error_all

! ----------------------------------------------------------------------
! simple Park RNG
! pass in non-zero seed
! ----------------------------------------------------------------------

FUNCTION random()
use data
implicit none
integer k
REAL*8 ans,random

k = seed/IQ
seed = IA*(seed-k*IQ) - IR*k
IF (seed < 0) seed = seed + IM
ans = AM*seed
random = ans
return

end function random
