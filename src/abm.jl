using Statistics
using Random
using Distributed
@everywhere using Agents, Agents.Graphs

@everywhere function initialize_model(;
        n_firms = 2,
        
        κ = 1.0, # the degree of isolation
        het_κ = false, # flag to set heterogeneous κ
        γ = 0.5, # the initial shock magnitude
        σᵤ = 0.03976, # the "conventional" standard deviation of utilization
        β = 0.09, # reactivity parameter to "conventional" standard deviation utilization
        ε = 0.00075, # the step change in animal spirits each iteration
        α₀ = 0.0075, # the starting animal spirits
        het_α_lims = false, # flag to set heterogeneous limits to animal spirits
        random_black_hole = false, # flag to do something random in "black hole" animal spirits case
        gᵣ = 0.49, # the partial derivative of rate of accumulation with respect to profit rate
        gᵤ = 0.025, # the partial derivative of rate of accumulation with respect to utilization rate
        Π = 0.33, # the aggregate profit share
        reserve_army_effect = false, # reserve army effect flag which endogenizes Π based on ̇ω = ω(-v₁ + v₂u - v₃ω)
            v₁ = 0.0,
            v₂ = 0.0,
            v₃ = 0.0,
        sₚ = 0.80, # profit savings rate
        ν = 3.0, # the fixed full-capacity capital-output ratio,
        ϕ = 2.0,
        ψ = 1.0, # the ratio of firms which follow original Table 3 behavior vs new "second differences" behavior
        
        seed = 23182
    )
    
    rng = MersenneTwister(seed)
    
    # This model does not use a network, but in future could be extended simply through this space variable
    space = GraphSpace(SimpleGraph(1))

    # Model properties
    properties = (
        # Variable over simulation
        # TODO: using 1-element array as hack to get around immutability - should figure out appropriate way to do this in Julia
        K = [0.0], # the aggregate capital stock
        g = [0.0], # the aggregate accumulation rate
        u = [0.0], # the aggregate capacity utilization rate
            u₋₁ = [0.0], # previous period's agg. utilization
            u₋₂ = [0.0], 
            u₋₃ = [0.0],
        
        # Either variable or static (depending on flags)
        Π = [Π],
        
        # Static over simulation
        κ = κ,
        het_κ = het_κ,
        γ = γ,
        σᵤ = σᵤ,
        β = β,
        ε = ε,
        α₀ = α₀,
        gᵣ = gᵣ, 
        gᵤ = gᵤ,
        sₚ = sₚ,
        ν = ν,
        ϕ = ϕ,
        ψ = ψ,
        c = β*σᵤ,
        reserve_army_effect = reserve_army_effect,
        random_black_hole = random_black_hole,
        v₁ = v₁,
        v₂ = v₂,
        v₃ = v₃,
        
        # Error flag (can emit a single error msg for a run, but let it continue)
        error_flag = [true]
    )
    
    model = ABM(Firm, space;
        properties, rng, scheduler = Schedulers.Randomly(), warn=false
    )
    
    # Add the firms, with initial shocks
    u₀ = (ν*α₀)/(Π*(sₚ-gᵣ)-gᵤ*ν) # Eq. 12 from Setterfield and Suresh 2015, see Table 2
    K₀ = 1.0 # agent starting capital stock
    if n_firms == 2
        # 2 firm case is unique, we apply the γ shock symmetrically to each
        u¹ = u₀ + γ*σᵤ
        u² = u₀ - γ*σᵤ
        
        add_agent!(Firm, model, u¹, u₀, u₀, u₀, K₀, α₀)
        add_agent!(Firm, model, u², u₀, u₀, u₀, K₀, α₀)
    else
        # n firm case, we apply the shock using a random normal draw
        ψ_cutoff = floor(ψ*n_firms)
        for i in 1:n_firms
            Δu = γ*σᵤ*randn(rng, Float64)
            uˢ = u₀ + Δu
            uˢ >= 1.0 ? uˢ = 1.0 : uˢ = uˢ
            uˢ <= 0.0 ? uˢ = 0.0 : uˢ = uˢ
            
            if i < (ψ_cutoff + 1)
                animal_spirits_strategy = original_animal_spirits_strategy
            else
                animal_spirits_strategy = new_animal_spirits_strategy
            end
            
            if het_κ
                # Random draw from buckets of isolation parameter
                κ₀ = rand(rng, [0.1, 0.2, 0.3, 0.4, 0.5])
            else
                κ₀ = κ
            end
            
            if het_α_lims
                # Random draw of limits from buckets
                α₍ₘᵢₙ₎ = rand(rng, [0.000, 0.001, 0.002, 0.003, 0.004])
                α₍ₘₐₓ₎ = rand(rng, [0.015, 0.014, 0.013, 0.012, 0.011])
            else
                α₍ₘᵢₙ₎ = 0.0
                α₍ₘₐₓ₎ = 0.015
            end
            
            add_agent!(Firm, model, uˢ, u₀, u₀, u₀, K₀, α₀, α₍ₘᵢₙ₎, α₍ₘₐₓ₎, κ₀, animal_spirits_strategy)
        end
    end
    
    # Update and set model properties
    model.K[1] = n_firms*K₀
    model.u[1] = u₀
        model.u₋₁[1] = u₀
        model.u₋₂[1] = u₀
        model.u₋₃[1] = u₀ 
    return model
end

# Define the model behavior, which runs in aggregate after firm actions
@everywhere function model_step!(model)
    ν = model.ν; sₚ = model.sₚ; gᵤ = model.gᵤ; gᵣ = model.gᵣ
    
    K₋₁ = model.K[1]
    K = 0.0
    for firm in model.agents
        K += firm[2].K
    end
    model.K[1] = K
    
    g = (K - K₋₁)/K₋₁
    model.g[1] = g
    
    # Update agg. capacity history
    model.u₋₃[1] = model.u₋₂[1]
    model.u₋₂[1] = model.u₋₁[1]
    model.u₋₁[1] = model.u[1]
    
    # If profit share endogenous, update it
    Π = model.Π[1]; u = model.u[1]
    v₁ = model.v₁; v₂ = model.v₂; v₃ = model.v₃
    if model.reserve_army_effect
        Π = Π - (1 - Π)*(-1*v₁ + v₂*u - v₃*(1 - Π))
        if Π > 1.0
            Π = 1.0
        elseif model.error_flag[1] && (Π <= ((gᵤ * ν)/(sₚ - gᵣ))) # Keynesian stability condition
            @error "The Keynesian stability condition has been violated."
            model.error_flag[1] = false # prevent future msgs for this run
        end
    end
    model.Π[1] = Π
    
    if Π != 0.0
        u = (ν*g)/(sₚ*Π) # Eq. 8
        if u > 1.0
            u = 1.0
        elseif u < 0.0
            u = 0.0
        end
    else
        u = 0.0
    end
    model.u[1] = u
end
