using Random
using Statistics
using Distributed
@everywhere using Agents, Agents.Graphs

# Define the agents, here only firms
@everywhere @agent Firm GraphAgent begin
    u::Float64 # Current capacity utilization
        u₋₁::Float64 # Previous t-1 period's utilization
        u₋₂::Float64 # Previous t-2 period's utilization
        u₋₃::Float64 # Previous t-3 period's utilization
    
    K::Float64 # Current capital stock
    
    α::Float64 # Current animal spirits
    
    α₍ₘᵢₙ₎::Float64 # Minimum animal spirits for this firm
    α₍ₘₐₓ₎::Float64 # Maximum animal spirits for this firm
    κ::Float64 # Current degree of isolation 
    animal_spirits_strategy::Function # Strategy for iterating animal spirits
end

# Define the firm behavior
@everywhere function agent_step!(firm::Firm, model)
    # Determine change in animal spirits
    # Eq. 9
    Δα = firm.animal_spirits_strategy(
        firm.κ, model.ε, model.c, model.ϕ,
        firm.u₋₁,
        (firm.u₋₁ - firm.u₋₂),
        (firm.u₋₂ - firm.u₋₃),
        (model.u₋₁[1] - model.u₋₂[1]),
        (model.u₋₂[1] - model.u₋₃[1]),
        model.random_black_hole,
        model.rng
    )
    firm.α += Δα
    
    # Obey the per firm limits to animal spirits
    if firm.α < firm.α₍ₘᵢₙ₎
        firm.α = firm.α₍ₘᵢₙ₎
    elseif firm.α > firm.α₍ₘₐₓ₎
        firm.α = firm.α₍ₘₐₓ₎
    end
    
    # Calculate planned accumulation
    α = firm.α; gᵤ = model.gᵤ; gᵣ = model.gᵣ; Π = model.Π[1]; ν = model.ν; sₚ = model.sₚ
    gⁱ = α + (gᵤ + gᵣ*Π/ν)*firm.u # Eq. 7

    # Calculate actual accumulation
    if gⁱ >= (sₚ*Π/ν) # Footnote 9
        gᵃ = sₚ*Π/ν 
        # Also need to re-update animal spirits
        firm.α = sₚ*Π/ν - (gᵤ + gᵣ*Π/ν)
        
        # Obey the per firm limits to animal spirits
        if firm.α < firm.α₍ₘᵢₙ₎
            firm.α = firm.α₍ₘᵢₙ₎
        elseif firm.α > firm.α₍ₘₐₓ₎
            firm.α = firm.α₍ₘₐₓ₎
        end
    else
        gᵃ = gⁱ
    end
    
    # Update the capacity histories
    firm.u₋₃ = firm.u₋₂
    firm.u₋₂ = firm.u₋₁
    firm.u₋₁ = firm.u
    
    # Calculate new capacity utilization
    if Π != 0.0
        u = (ν*gᵃ)/(sₚ*Π) # Eq. 8
        
        if u > 1.0
            u = 1.0
        end
    else
        u = 0.0
    end
    firm.u = u
    
    # Update the firm's capital stock accordingly
    K = (1.0+gᵃ)*firm.K
    firm.K = K
    
   # println("Firm $(firm.id) : α-$(firm.α), gⁱ=$gⁱ, gᵃ=$gᵃ, u=$u, K=$K")
    
end
