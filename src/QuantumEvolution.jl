###########################################################
# Simple propagators
##

# Hamiltonian propagation
"""
    ham(dt::Float64, H::QOp; ket=false)

Return increment function for Hamiltonian evolution generated
by `H` over a time step `dt`.

Uses an exact matrix exponential, assuming no time-dependence.

### Returns:
  - ket=true  : t::Float64, ψ::QKet -> u * ψ
  - ket=false : t::Float64, ρ::QOp  -> u * ρ * u'

"""
@inline function ham(dt::Float64, H::QOp; ket=false)
    const u::QOp = sparse(expm( -im * dt * full(H)))
    const ut = u'
    if ket
        (t::Float64, ψ::QKet) -> u * ψ
    else
        (t::Float64, ρ::QOp) -> u * ρ * ut
    end
end
@inline function ham(dt::Float64, H::Function; ket=false)
    (t::Float64, state) -> ham(dt, H(t), ket=ket)(t, state)
end

# Superoperator Hamiltonian evolution
"""
    sham(dt::Float64, H::QOp)

Return increment function using a superoperator for Hamiltonian 
evolution generated by `H` over a time step `dt`.

Uses an exact matrix exponential, assuming no time-dependence.

### Returns:
  - t::Float64, ρvec -> u*ρvec : Evolution superoperator

"""
@inline function sham(dt::Float64, H::QOp)
    const u::QOp = sparse(expm( -im * dt * full(H)))
    const l = superopl(u)*superopr(u')
    (t::Float64, ρvec) -> l * ρvec
end
@inline function sham(dt::Float64, H::Function)
    (t::Float64, ρvec) -> sham(dt, H(t))(t, ρvec)
end

# Runge-Kutta Hamiltonian evolution
"""
    ham_rk4(dt::Float64, H::QOp; ket=false)

Return increment function for Hamiltonian evolution generated
by Hamiltonian `H` over a time step `dt`.

Uses a 4th-order Runge-Kutta integration method to construct the state
increment from the first-order differential (master) equation.

### Returns:
  - ket=true  : t::Float64, ψ::QKet -> ψnew
  - ket=false : t::Float64, ρ::QOp  -> ρnew

"""
@inline function ham_rk4(dt::Float64, H::Function; ket=false)
    if ket
        inc(t::Float64, ψ::QKet)::QKet = - im * H(t) * ψ
    else
        inc(t::Float64, ρ::QOp)::QOp = - im * comm(H(t),ρ)
    end
    function rinc(t::Float64, ρ)
        dρ1 = inc(t, ρ)
        dρ2 = inc(t + dt/2, ρ + dρ1*dt/ 2)
        dρ3 = inc(t + dt/2, ρ + dρ2*dt/ 2)
        dρ4 = inc(t + dt, ρ + dρ3*dt)
        dt*(dρ1 + 2*dρ2 + 2*dρ3 + dρ4)/6
    end
    (t::Float64, ρ) -> ρ + rinc(t, ρ)
end
@inline function ham_rk4(dt::Float64, H::QOp, alist::QOp...)
    h(t) = H
    ham_rk4(dt, h, alist...)
end

# Jump-nojump Lindblad propagator
"""
    lind(dt::Float64, H::QOp, alist::QOp...)

Return increment function for Lindblad dissipative evolution generated
by Hamiltonian `H` and list of dissipative operators `alist` over a 
time step `dt`.

Uses the "jump no-jump" method to efficiently approximate the exact
Lindblad propagator as a composition of Hamiltonian evolution, jumps,
and no-jump informational backaction. Assumes no time-dependence,
and small dt.  [Physical Review A **92**, 052306 (2015)]

### Returns:
  - t::Float64, ρ(t)::QOp -> ρ(t+dt)

"""
@inline function lind(dt::Float64, H, alist::QOp...)
    # Rely on Hamiltonian to specify type of H
    h = ham(dt, H)
    # Jump-no-jump only if jumps
    if length(alist) > 0
        const n::QOp = sparse(sqrtm(eye(first(alist)) - 
                       dt * full(mapreduce(a -> a' * a, +, alist))))
        no(ρ::QOp)::QOp = n * ρ * n
        dec(ρ::QOp)::QOp = mapreduce(a -> a * ρ * a', +, alist) * dt
    else
        no(ρ) = ρ
        dec(ρ) = ρ
    end
    (t::Float64, ρ) -> let ρu = h(t, ρ); no(ρu) + dec(ρu) end
end

# Runge-Kutta Lindblad propagator
"""
    lind_rk4(dt::Float64, H::QOp, alist::QOp...)

Return increment function for Lindblad dissipative evolution generated
by Hamiltonian `H` and list of dissipative operators `alist` over a 
time step `dt`.

Uses a 4th-order Runge-Kutta integration method to construct the state
increment from the first-order Lindblad differential (master) equation.

### Returns:
  - t::Float64, ρ(t)::QOp -> ρ(t) + dρ

"""
@inline function lind_rk4(dt::Float64, H::Function, alist::QOp...)
    inc(t::Float64, ρ::QOp)::QOp = - im * comm(H(t),ρ) + sum(map(a -> diss(a)(ρ), alist))
    function rinc(t::Float64, ρ::QOp)::QOp
        dρ1::QOp = inc(t, ρ)
        dρ2::QOp = inc(t + dt/2, ρ + dρ1*dt/ 2)
        dρ3::QOp = inc(t + dt/2, ρ + dρ2*dt/ 2)
        dρ4::QOp = inc(t + dt, ρ + dρ3*dt)
        dt*(dρ1 + 2*dρ2 + 2*dρ3 + dρ4)/6
    end
    (t::Float64, ρ) -> ρ + rinc(t, ρ)
end
@inline function lind_rk4(dt::Float64, H::QOp, alist::QOp...)
    h(t) = H
    lind_rk4(dt, h, alist...)
end

# Superoperator Lindblad propagator
"""
    slind(dt::Float64, H::QOp, alist::QOp...)

Return increment function using a superoperator for Lindblad dissipative 
evolution generated by Hamiltonian `H` and list of dissipative operators 
`alist` over a time step `dt`.

Uses direct matrix exponentiation of the total superoperator for
the increment.

### Returns:
  - t::Float64, ρvec -> u * ρvec : Superoperator for total evolution over dt 

"""
@inline function slind(dt::Float64, H::QOp, alist::QOp...)
    const h = -im*scomm(H)
    const l = mapreduce(sdiss, +, alist) + h
    const u = sparse(expm(dt*full(l)))
    (t::Float64, ρvec) -> u * ρvec
end
@inline function slind(dt::Float64, H::Function, alist::QOp...)
    (t::Float64, ρvec) -> slind(dt, H(t), alist...)(t, ρvec)
end

###
# Crude trajectory integrator
###

# Return trajectory array [f1(now), f2(now), ...] 
"""
    trajectory(inc::Function, init::AbstractArray, tspan::Tuple{Float64,Float64},  
                    fs::Function...; dt::Float64=1/10^4, points::Int=1000)

Compute time-stepped trajectory, starting from state `init`, incrementing with `inc`
by time step `dt` for `t` in `tspan`, keeping `points` intermediate values
of `f(ρ(t))` for each `f` in `fs`.

### Returns:
  - (ts::linspace, vals::[f(ρ(t))]...)

"""
function trajectory(inc::Function, init::AbstractArray, tspan::Tuple{Float64,Float64},  
                    fs::Function...; dt::Float64=1/10^4, points::Int=1000, verbose=true)
    # Constants for integration
    const t0 = first(tspan)              # Initial time
    const tmax = last(tspan)             # Final time
    const N = Int(fld(abs(tmax-t0), dt)) # total num of steps
    if points > N
        const Ns = Int(N)                # reset points if needed
    else
        const Ns = Int(points)           # stored points
    end      
    const Nf = length(fs)                # stored f values per point
    const Nl = Int(cld(N, points))       # steps per stored point
    const Nldt = Nl*dt                   # time-step per stored point
    # Preallocate trajectory arrays for speed
    valtypes = collect(typeof(f(init)) for f in fs)
    traj = map(t->zeros(t, (Ns, 1)), valtypes)
    ts = linspace(t0, tmax, Ns)
    # Function to update values
    function update!(i::Int, ρ)
        for k in 1:Nf
            traj[k][i] = fs[k](ρ)
        end
    end
    # Seed loop
    verbose && info("Trajectory: steps = ",N,", points = ",Ns,", values = ",Nf)
    tic()
    now = init
    tnow = t0
    update!(1, now)
    # loop
    for i in 2:Ns
        # inner loop without storage
        for k in 1:Nl
            tnow += dt
            now = inc(tnow, now)
        end
        # store point
        update!(i, now)
    end
    elapsed = toq()
    # Performance summary
    verbose && info("Time elapsed: ",elapsed," s, Steps per second: ",N/elapsed)
    (ts, traj...)
end
