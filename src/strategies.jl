using Random
using Statistics
using Distributed
@everywhere using Agents, Agents.Graphs

# Table 3
@everywhere function original_animal_spirits_strategy(
    κ, ε, c, ϕ, u₋₁ʲ, Δu₋₁ʲ, Δu₋₂ʲ, Δu₋₁, Δu₋₂, random_black_hole, rng)
    
    Ω₋₁ʲ = κ*Δu₋₁ʲ + (1-κ)*Δu₋₁
    Ω₋₂ʲ = κ*Δu₋₂ʲ + (1-κ)*Δu₋₂
    
    if ((Ω₋₁ʲ >= c) && ((1-u₋₁ʲ) >= (ϕ*Δu₋₁ʲ))) || 
        ((Ω₋₁ʲ > (-1*c)) && (Ω₋₂ʲ <= (-1*c)) && ((1-u₋₁ʲ) >= (ϕ*Δu₋₁ʲ)))
        
        return ε
    elseif (Ω₋₁ʲ <= (-1*c)) ||
        ((Ω₋₁ʲ < c) && (Ω₋₂ʲ >= c)) ||
        ((1-u₋₁ʲ) < (ϕ*Δu₋₁ʲ))
        
        return (-1*ε)
    else
        # "Black hole", do nothing or something random
        if random_black_hole
            return rand(rng, [0.0, ε, (-1*ε)])
        end
        return 0.0
    end
end

# Table 3: alternate rules
# NOTE: not currently used in paper
@everywhere function new_animal_spirits_strategy(
    κ, ε, c, ϕ, u₋₁ʲ, Δu₋₁ʲ, Δu₋₂ʲ, Δu₋₁, Δu₋₂, random_black_hole, rng)
    
    Ω₋₁ʲ = κ*Δu₋₁ʲ + (1-κ)*Δu₋₁
    Ω₋₂ʲ = κ*Δu₋₂ʲ + (1-κ)*Δu₋₂
    
    if ((Ω₋₁ʲ >= c) && ((1-u₋₁ʲ) >= (ϕ*Δu₋₁ʲ))) || 
        ((Ω₋₁ʲ > Ω₋₂ʲ) && (Ω₋₂ʲ <= (-1*c)) && ((1-u₋₁ʲ) >= (ϕ*Δu₋₁ʲ)))
        
        return ε
    elseif (Ω₋₁ʲ <= (-1*c)) ||
        ((Ω₋₁ʲ < Ω₋₂ʲ) && (Ω₋₂ʲ >= c)) ||
        ((1-u₋₁ʲ) < (ϕ*Δu₋₁ʲ))
        
        return (-1*ε)
    else
        # "Black hole", do nothing or something random
        if random_black_hole
            return rand(rng, [0.0, ε, (-1*ε)])
        end
        return 0.0
    end
end
