function initialize!(integrator,cache::AN5ConstantCache)
  integrator.kshortsize = 7
  integrator.k = typeof(integrator.k)(integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  @inbounds for i in 2:integrator.kshortsize-1
    integrator.k[i] = zero(integrator.fsalfirst)
  end
  integrator.k[integrator.kshortsize] = integrator.fsallast
end

@muladd function perform_step!(integrator, cache::AN5ConstantCache, repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack z,l,m,c_LTE,dts,tsit5tab = cache
  # handle callbacks, rewind back to order one.
  if integrator.u_modified
    cache.order = 1
  end
  # Nordsieck form needs to build the history vector
  if cache.order == 1
    # Start the Nordsieck vector in one shot!
    perform_step!(integrator, tsit5tab, repeat_step)
    cache.order = 4
    z[1] = integrator.uprev
    z[2] = integrator.k[1]*dt
    z[3] = ode_interpolant(t,dt,nothing,nothing,integrator.k,tsit5tab,nothing,Val{2})*dt^2/2
    z[4] = ode_interpolant(t,dt,nothing,nothing,integrator.k,tsit5tab,nothing,Val{3})*dt^3/6
    z[5] = ode_interpolant(t,dt,nothing,nothing,integrator.k,tsit5tab,nothing,Val{4})*dt^4/24
    z[6] = zero(cache.z[6])
    fill!(dts, dt)
    perform_predict!(cache)
    cache.Δ = integrator.u - integrator.uprev
    update_nordsieck_vector!(cache)
    if integrator.opts.adaptive && integrator.EEst >= one(integrator.EEst)
      cache.order = 1
    end
  else
    # Reset time
    tmp = dts[6]
    for i in 5:-1:1
      dts[i+1] = dts[i]
    end
    dts[1] = dt
    dt != dts[2] && nordsieck_rescale!(cache)
    integrator.k[1] = z[2]/dt
    # Perform 5th order Adams method in Nordsieck form
    perform_predict!(cache)
    calc_coeff!(cache)
    isucceed = nlsolve_functional!(integrator, cache)
    if !isucceed
      # rewind Nordsieck vector
      integrator.force_stepfail = true
      nordsieck_rewind!(cache)
      return nothing
    end

    ################################### Error estimation

    if integrator.opts.adaptive
      atmp = calculate_residuals(cache.Δ, uprev, integrator.u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
      integrator.EEst = integrator.opts.internalnorm(atmp) * cache.c_LTE
      if integrator.EEst > one(integrator.EEst)
        for i in 1:5
          dts[i] = dts[i+1]
        end
        dts[6] = tmp
      end
    end

    # Correct Nordsieck vector
    cache.order = 5
    update_nordsieck_vector!(cache)

    ################################### Finalize

    integrator.k[2] = cache.z[2]/dt
  end
  return nothing
end

function initialize!(integrator, cache::AN5Cache)
  integrator.kshortsize = 7
  integrator.fsalfirst = cache.tsit5cache.k1; integrator.fsallast = cache.tsit5cache.k7 # setup pointers
  resize!(integrator.k, integrator.kshortsize)
  # Setup k pointers
  integrator.k[1] = cache.tsit5cache.k1
  integrator.k[2] = cache.tsit5cache.k2
  integrator.k[3] = cache.tsit5cache.k3
  integrator.k[4] = cache.tsit5cache.k4
  integrator.k[5] = cache.tsit5cache.k5
  integrator.k[6] = cache.tsit5cache.k6
  integrator.k[7] = cache.tsit5cache.k7
  integrator.f(integrator.fsalfirst, integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
end

@muladd function perform_step!(integrator, cache::AN5Cache, repeat_step=false)
  @unpack t,dt,uprev,u,f,p,uprev2 = integrator
  @unpack z,l,m,c_LTE,dts,tmp,ratetmp,atmp,tsit5cache = cache
  # handle callbacks, rewind back to order one.
  if integrator.u_modified
    cache.order = 1
  end
  # Nordsieck form needs to build the history vector
  if cache.order == 1
    ## Start the Nordsieck vector in two shots!
    perform_step!(integrator, tsit5cache, repeat_step)
    copy!(tmp, integrator.u)
    cache.order = 4
    @. z[1] = integrator.uprev
    @. z[2] = integrator.k[1]*dt
    ode_interpolant!(z[3],t,dt,nothing,nothing,integrator.k,tsit5cache,nothing,Val{2})
    ode_interpolant!(z[4],t,dt,nothing,nothing,integrator.k,tsit5cache,nothing,Val{3})
    ode_interpolant!(z[5],t,dt,nothing,nothing,integrator.k,tsit5cache,nothing,Val{4})
    @. z[3] = z[3]*dt^2/2
    @. z[4] = z[4]*dt^3/6
    @. z[5] = z[5]*dt^4/24
    fill!(z[6], 0)
    fill!(dts, dt)
    perform_predict!(cache)
    @. cache.Δ = integrator.u - integrator.uprev
    update_nordsieck_vector!(cache)
    if integrator.opts.adaptive && integrator.EEst >= one(integrator.EEst)
      cache.order = 1
    end
  else
    # Reset time
    tmp = dts[6]
    for i in 5:-1:1
      dts[i+1] = dts[i]
    end
    dts[1] = dt
    # Rescale
    dt != dts[2] && nordsieck_rescale!(cache)
    @. integrator.k[1] = z[2]/dt
    # Perform 5th order Adams method in Nordsieck form
    perform_predict!(cache)
    calc_coeff!(cache)
    isucceed = nlsolve_functional!(integrator, cache)
    if !isucceed
      integrator.force_stepfail = true
      # rewind Nordsieck vector
      nordsieck_rewind!(cache)
      return nothing
    end

    ################################### Error estimation

    if integrator.opts.adaptive
      calculate_residuals!(atmp, cache.Δ, uprev, integrator.u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
      integrator.EEst = integrator.opts.internalnorm(atmp) * cache.c_LTE
      if integrator.EEst > one(integrator.EEst)
        for i in 1:5
          dts[i] = dts[i+1]
        end
        dts[6] = tmp
      end
    end

    # Correct Nordsieck vector
    cache.order = 5
    update_nordsieck_vector!(cache)

    ################################### Finalize

    @. integrator.k[2] = cache.z[2]/dt
  end
  return nothing
end

function initialize!(integrator,cache::JVODEConstantCache)
  integrator.kshortsize = 7
  integrator.k = typeof(integrator.k)(integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  @inbounds for i in 2:integrator.kshortsize-1
    integrator.k[i] = zero(integrator.fsalfirst)
  end
  integrator.k[integrator.kshortsize] = integrator.fsallast
end

@muladd function perform_step!(integrator, cache::JVODEConstantCache, repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack z,l,m,c_LTE,dts,tsit5tab = cache
  # handle callbacks, rewind back to order one.
  if integrator.u_modified || integrator.iter == 1
    cache.order = 1
    z[1] = integrator.uprev
    z[2] = f(uprev, p, t)*dt
    dts[1] = dt
  end
  # Reset time
  tmp = dts[13]
  for i in 12:-1:1
    dts[i+1] = dts[i]
  end
  dts[1] = dt
  dt != dts[2] && nordsieck_rescale!(cache)
  integrator.k[1] = z[2]/dt
  # Perform 5th order Adams method in Nordsieck form
  perform_predict!(cache)
  cache.order = min(cache.nextorder, 12)
  calc_coeff!(cache)
  isucceed = nlsolve_functional!(integrator, cache)
  if !isucceed
    # rewind Nordsieck vector
    integrator.force_stepfail = true
    nordsieck_rewind!(cache)
    return nothing
  end

  # Correct Nordsieck vector
  update_nordsieck_vector!(cache)

  ################################### Finalize
  cache.n_wait -= 1
  if nordsieck_change_order(cache, 1) && cache.order != 12
    cache.z[end] = cache.Δ
    cache.prev_𝒟 = cache.c_𝒟
  end

  integrator.k[2] = cache.z[2]/dt
  ################################### Error estimation
  if integrator.opts.adaptive
    atmp = calculate_residuals(cache.Δ, uprev, integrator.u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
    integrator.EEst = integrator.opts.internalnorm(atmp) * cache.c_LTE
    if integrator.EEst > one(integrator.EEst)
      for i in 1:12
        dts[i] = dts[i+1]
      end
      dts[13] = tmp
    end
  end
  return nothing
end

function initialize!(integrator, cache::JVODECache)
  integrator.kshortsize = 7
  integrator.fsalfirst = cache.tsit5cache.k1; integrator.fsallast = cache.tsit5cache.k7 # setup pointers
  resize!(integrator.k, integrator.kshortsize)
  # Setup k pointers
  integrator.k[1] = cache.tsit5cache.k1
  integrator.k[2] = cache.tsit5cache.k2
  integrator.k[3] = cache.tsit5cache.k3
  integrator.k[4] = cache.tsit5cache.k4
  integrator.k[5] = cache.tsit5cache.k5
  integrator.k[6] = cache.tsit5cache.k6
  integrator.k[7] = cache.tsit5cache.k7
  integrator.f(integrator.fsalfirst, integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
end

@muladd function perform_step!(integrator, cache::JVODECache, repeat_step=false)
  @unpack t,dt,uprev,u,f,p,uprev2 = integrator
  @unpack z,l,m,c_LTE,dts,tmp,ratetmp,atmp,tsit5cache = cache
  # handle callbacks, rewind back to order one.
  if integrator.u_modified || integrator.iter == 1
    cache.order = 1
    @. z[1] = integrator.uprev
    f(z[2], uprev, p, t)
    @. z[2] = z[2]*dt
    dts[1] = dt
  end
  tmp = dts[13]
  # Reset time
  for i in endof(dts):-1:2
    dts[i] = dts[i-1]
  end
  dts[1] = dt
  # Rescale
  dt != dts[2] && nordsieck_rescale!(cache)
  @. integrator.k[1] = z[2]/dt
  perform_predict!(cache)
  cache.order = min(cache.nextorder, 12)
  calc_coeff!(cache)
  isucceed = nlsolve_functional!(integrator, cache)
  if !isucceed
    integrator.force_stepfail = true
    # rewind Nordsieck vector
    nordsieck_rewind!(cache)
    return nothing
  end

  # Correct Nordsieck vector
  update_nordsieck_vector!(cache)

  ################################### Error estimation

  if integrator.opts.adaptive
    calculate_residuals!(atmp, cache.Δ, uprev, integrator.u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
    integrator.EEst = integrator.opts.internalnorm(atmp) * cache.c_LTE
    if integrator.EEst > one(integrator.EEst)
      for i in 1:12
        dts[i] = dts[i+1]
      end
      dts[13] = tmp
    else
      cache.n_wait -= 1
    end
  end

  ################################### Finalize
  if nordsieck_change_order(cache, 1) && cache.order != 12
    cache.z[end] = cache.Δ
    cache.prev_𝒟 = cache.c_𝒟
  end
  return nothing
end
