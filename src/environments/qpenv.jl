#=
nothing fancy - only used internally (and therefore cryptic) - stores some partially contracted things
seperates out this bit of logic from effective_excitation_hamiltonian (now more readable)
can also - potentially - partially reuse this in other algorithms
=#
struct QPEnv{A,B} <: Cache
    lBs::PeriodicArray{A,1}
    rBs::PeriodicArray{A,1}

    lenvs::B
    renvs::B
end

function environments(exci::InfiniteQP, H::MPOHamiltonian; solver=Defaults.solver)
    # Explicitly define optional arguments as these depend on solver,
    # which needs to come after these arguments.
    lenvs = environments(exci.left_gs, H; solver=solver)

    return environments(exci, H, lenvs; solver=solver)
end

function environments(exci::InfiniteQP, H::MPOHamiltonian, lenvs; solver=Defaults.solver)
    # Explicitly define optional arguments as these depend on solver,
    # which needs to come after these arguments.
    renvs = exci.trivial ? lenvs : environments(exci.right_gs, H; solver=solver)

    return environments(exci, H, lenvs, renvs; solver=solver)
end

function environments(exci::InfiniteQP, ham::MPOHamiltonian, lenvs, renvs;solver=Defaults.solver)
    ids = collect(Iterators.filter(x->isid(ham,x),2:ham.odim-1));

    #build lBs(c)
    lB_cur = [ TensorMap(zeros,eltype(exci),
                    virtualspace(exci.left_gs,0)*ham.domspaces[1,k]',
                    space(exci[1],3)'*virtualspace(exci.right_gs,0)) for k in 1:ham.odim]
    lBs = typeof(lB_cur)[]

    for pos = 1:length(exci)
        lB_cur = exci_transfer_left(lB_cur,ham[pos],exci.right_gs.AR[pos],exci.left_gs.AL[pos])*exp(conj(1im*exci.momentum))
        lB_cur += exci_transfer_left(leftenv(lenvs,pos,exci.left_gs),ham[pos],exci[pos],exci.left_gs.AL[pos])*exp(conj(1im*exci.momentum))

        exci.trivial && for i in ids
            @plansor lB_cur[i][-1 -2;-3 -4] -= lB_cur[i][1 4;-3 2]*r_RL(exci.left_gs,pos)[2;3]*τ[3 4;5 1]*l_RL(exci.left_gs,pos+1)[-1;6]*τ[5 6;-4 -2]
        end


        push!(lBs,lB_cur)
    end

    #build rBs(c)
    rB_cur = [ TensorMap(zeros,eltype(exci),
                    virtualspace(exci.left_gs,length(exci))*ham.imspaces[length(exci),k]',
                    space(exci[1],3)'*virtualspace(exci.right_gs,length(exci))) for k in 1:ham.odim]
    rBs = typeof(rB_cur)[]

    for pos=length(exci):-1:1
        rB_cur = exci_transfer_right(rB_cur,ham[pos],exci.left_gs.AL[pos],exci.right_gs.AR[pos])*exp(1im*exci.momentum)
        rB_cur += exci_transfer_right(rightenv(renvs,pos,exci.right_gs),ham[pos],exci[pos],exci.right_gs.AR[pos])*exp(1im*exci.momentum)

        exci.trivial && for i in ids
            @plansor rB_cur[i][-1 -2;-3 -4] -= τ[6 4;1 3]*rB_cur[i][1 3;-3 2]*l_LR(exci.left_gs,pos)[2;4]*r_LR(exci.left_gs,pos-1)[-1;5]*τ[-2 -4;5 6]
        end

        push!(rBs,rB_cur)
    end
    rBs = reverse(rBs)

    lBE::typeof(rB_cur) = left_excitation_transfer_system(lB_cur,ham,exci,solver=solver)
    rBE::typeof(rB_cur) = right_excitation_transfer_system(rB_cur,ham,exci, solver=solver)

    lBs[end] = lBE;

    for i=1:length(exci)-1
        lBE = exci_transfer_left(lBE,ham[i],exci.right_gs.AR[i],exci.left_gs.AL[i])*exp(conj(1im*exci.momentum))

        exci.trivial && for k in ids
            @plansor lBE[k][-1 -2;-3 -4] -= lBE[k][1 4;-3 2]*r_RL(exci.left_gs,i)[2;3]*τ[3 4;5 1]*l_RL(exci.left_gs,i+1)[-1;6]*τ[5 6;-4 -2]
        end

        lBs[i] += lBE;
    end

    rBs[1] = rBE;

    for i=length(exci):-1:2
        rBE = exci_transfer_right(rBE,ham[i],exci.left_gs.AL[i],exci.right_gs.AR[i])*exp(1im*exci.momentum)

        exci.trivial && for k in ids
            @plansor rBE[k][-1 -2;-3 -4] -= τ[6 4;1 3]*rBE[k][1 3;-3 2]*l_LR(exci.left_gs,i)[2;4]*r_LR(exci.left_gs,i-1)[-1;5]*τ[-2 -4;5 6]
        end

        rBs[i] += rBE
    end

    return QPEnv(PeriodicArray(lBs),PeriodicArray(rBs),lenvs,renvs)
end

function environments(exci::FiniteQP,ham::MPOHamiltonian,lenvs=environments(exci.left_gs,ham),renvs=exci.trivial ? lenvs : environments(exci.right_gs,ham))
    #construct lBE
    lB_cur = [ TensorMap(zeros,eltype(exci),
                    virtualspace(exci.left_gs,0)*ham.domspaces[1,k]',
                    space(exci[1],3)'*virtualspace(exci.left_gs,0)) for k in 1:ham.odim]
    lBs = typeof(lB_cur)[]
    for pos = 1:length(exci)
        lB_cur = exci_transfer_left(lB_cur,ham[pos],exci.right_gs.AR[pos],exci.left_gs.AL[pos])
        lB_cur += exci_transfer_left(leftenv(lenvs,pos,exci.left_gs),ham[pos],exci[pos],exci.left_gs.AL[pos])
        push!(lBs,lB_cur)
    end

    #build rBs(c)
    rB_cur = [ TensorMap(zeros,eltype(exci),
                    virtualspace(exci.right_gs,length(exci))*ham.imspaces[length(exci),k]',
                    space(exci[1],3)'*virtualspace(exci.right_gs,length(exci))) for k in 1:ham.odim]
    rBs = typeof(rB_cur)[]
    for pos=length(exci):-1:1
        rB_cur = exci_transfer_right(rB_cur,ham[pos],exci.left_gs.AL[pos],exci.right_gs.AR[pos])
        rB_cur += exci_transfer_right(rightenv(renvs,pos,exci.right_gs),ham[pos],exci[pos],exci.right_gs.AR[pos])
        push!(rBs,rB_cur)
    end
    rBs=reverse(rBs)

    return QPEnv(PeriodicArray(lBs),PeriodicArray(rBs),lenvs,renvs)
end
