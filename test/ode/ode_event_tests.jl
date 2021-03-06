using OrdinaryDiffEq, RecursiveArrayTools, Test, StaticArrays


f = function (u,p,t)
  - u + sin(-t)
end


prob = ODEProblem(f,1.0,(0.0,-10.0))

condition= function (u,t,integrator) # Event when event_f(u,t,k) == 0
  - t - 2.95
end

affect! = function (integrator)
  integrator.u = integrator.u + 2
end

callback = ContinuousCallback(condition,affect!)

sol = solve(prob,Tsit5(),callback=callback)

f = function (du,u,p,t)
  du[1] = - u[1] + sin(t)
end


prob = ODEProblem(f,[1.0],(0.0,10.0))

condtion= function (u,t,integrator) # Event when event_f(u,t,k) == 0
  t - 2.95
end

affect! = function (integrator)
  integrator.u = integrator.u .+ 2
end

callback = ContinuousCallback(condtion,affect!)

sol = solve(prob,Tsit5(),callback=callback,abstol=1e-8,reltol=1e-6)

f = function (du,u,p,t)
  du[1] = u[2]
  du[2] = -9.81
end

condtion= function (u,t,integrator) # Event when event_f(u,t,k) == 0
  u[1]
end

affect! = nothing
affect_neg! = function (integrator)
  integrator.u[2] = -integrator.u[2]
end

callback = ContinuousCallback(condtion,affect!,affect_neg!,interp_points=100)

u0 = [50.0,0.0]
tspan = (0.0,15.0)
prob = ODEProblem(f,u0,tspan)


sol = solve(prob,Tsit5(),callback=callback,adaptive=false,dt=1/4)

condtion_single = function (u,t,integrator) # Event when event_f(u,t,k) == 0
  u
end

affect! = nothing
affect_neg! = function (integrator)
  integrator.u[2] = -integrator.u[2]
end

callback_single = ContinuousCallback(condtion_single,affect!,affect_neg!,interp_points=100,idxs=1)

u0 = [50.0,0.0]
tspan = (0.0,15.0)
prob = ODEProblem(f,u0,tspan)

sol = solve(prob,Tsit5(),callback=callback_single,adaptive=false,dt=1/4)

#plot(sol,denseplot=true)

sol = solve(prob,Vern6(),callback=callback)
#plot(sol,denseplot=true)
sol = solve(prob,BS3(),callback=callback)

sol33 = solve(prob,Vern7(),callback=callback)

bounced = ODEProblem(f,sol[8],(0.0,1.0))
sol_bounced = solve(bounced,Vern6(),callback=callback,dt=sol.t[9]-sol.t[8])
#plot(sol_bounced,denseplot=true)
sol_bounced(0.04) # Complete density
@test maximum(maximum.(map((i)->sol.k[9][i]-sol_bounced.k[2][i],1:length(sol.k[9])))) == 0


sol2= solve(prob,Vern6(),callback=callback,adaptive=false,dt=1/2^4)
#plot(sol2)

sol2= solve(prob,Vern6())

sol3= solve(prob,Vern6(),saveat=[.5])

## Saving callback

condtion = function (u,t,integrator)
  true
end
affect! = function (integrator) end

save_positions = (true,false)
saving_callback = DiscreteCallback(condtion,affect!,save_positions=save_positions)

sol4 = solve(prob,Tsit5(),callback=saving_callback)

@test sol2(3) ≈ sol(3)

affect! = function (integrator)
  u_modified!(integrator,false)
end
saving_callback2 = DiscreteCallback(condtion,affect!,save_positions=save_positions)
sol4 = solve(prob,Tsit5(),callback=saving_callback2)

cbs = CallbackSet(saving_callback,saving_callback2)
sol4_extra = solve(prob,Tsit5(),callback=cbs)

@test length(sol4_extra) == 2length(sol4) - 1

condtion= function (u,t,integrator)
  u[1]
end

affect! = function (integrator)
  terminate!(integrator)
end

terminate_callback = ContinuousCallback(condtion,affect!)

tspan2 = (0.0,Inf)
prob2 = ODEProblem(f,u0,tspan2)

sol5 = solve(prob2,Tsit5(),callback=terminate_callback)

@test sol5[end][1] < 3e-12
@test sol5.t[end] ≈ sqrt(50*2/9.81)

affect2! = function (integrator)
  if integrator.t >= 3.5
    terminate!(integrator)
  else
    integrator.u[2] = -integrator.u[2]
  end
end
terminate_callback2 = ContinuousCallback(condtion,nothing,affect2!,interp_points=100)


sol5 = solve(prob2,Vern7(),callback=terminate_callback2)

@test sol5[end][1] < 1.3e-10
@test sol5.t[end] ≈ 3*sqrt(50*2/9.81)

condtion= function (u,t,integrator) # Event when event_f(u,t,k) == 0
  t-4
end

affect! = function (integrator)
  terminate!(integrator)
end

terminate_callback3 = ContinuousCallback(condtion,affect!,interp_points=1000)

bounce_then_exit = CallbackSet(callback,terminate_callback3)

sol6 = solve(prob2,Vern7(),callback=bounce_then_exit)

@test sol6[end][1] > 0
@test sol6[end][1] < 100
@test sol6.t[end] ≈ 4

# Test ContinuousCallback hits values on the steps
t_event = 100.0
f_simple(u,p,t) = 1.00001*u
event_triggered = false
condition_simple(u,t,integrator) = t_event-t
function affect_simple!(integrator)
  global event_triggered
  event_triggered = true
end
cb = ContinuousCallback(condition_simple, nothing, affect_simple!)
prob = ODEProblem(f_simple, [1.0], (0.0, 2.0*t_event))
sol = solve(prob,Tsit5(),callback=cb, adaptive = false, dt = 10.0)
@test event_triggered

# https://github.com/JuliaDiffEq/OrdinaryDiffEq.jl/issues/328
ode = ODEProblem((du, u, p, t) -> (@. du .= -u), ones(5), (0.0, 100.0))
sol = solve(ode, AutoTsit5(Rosenbrock23()), callback=TerminateSteadyState())
sol1 = solve(ode, Tsit5(), callback=TerminateSteadyState())
@test sol.u == sol1.u
