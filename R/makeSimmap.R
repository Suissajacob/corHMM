# simulate ancestral states at each internal node
simSingleCharHistory<- function(phy, model, cladewise.index, state.probability, state.sample){
  # sample the root state
  anc.index <- phy$edge[cladewise.index[1],1]
  state.sample[anc.index,] <- t(rmultinom(1, 1, state.probability[anc.index,]))
  
  # sample the nodes
  for(i in cladewise.index){
    # A = the probability of transition FROM node i (ancestor)
    anc.index <- phy$edge[i,1]
    dec.index <- phy$edge[i,2]
    A <- state.sample[anc.index,] %*% expm(model * phy$edge.length[i])
    # B = the conditional probability of node j (descendent)
    B <- state.probability[dec.index,]
    # The decendant is sampled from p/sum(p), where p = A * B
    p <- A * B
    state.sample[dec.index,] <- t(rmultinom(1, 1, p))
  }
  return(state.sample)
}


simCharHistory <- function(phy, tip.states, states, model, nSim = 1, nCores = 1, vector.form = FALSE){
  # warnings
  if(!all(round(rowSums(tip.states)) == 1)){
    return(cat("\nWarning: Tip states must be reconstructed to run Simmap.\n"))
  }
  
  # organize
  nTip <- Ntip(phy)
  cladewise.index <- reorder.phylo(phy, "cladewise", index.only = TRUE)
  # combine data in order of the edge matrix
  state.probability <- rbind(tip.states, states)
  state.sample <- matrix(0, dim(state.probability)[1], dim(state.probability)[2])
  
  # single sim function
  state.samples <- mclapply(1:nSim, function(x) simSingleCharHistory(phy, model, cladewise.index, state.probability, state.sample), mc.cores = nCores)
  if(vector.form == FALSE){
    state.samples <- lapply(state.samples, function(x) apply(x, 1, function(y) which(y == 1)))
  }
  return(state.samples)
}

simBranchSubstHistory <- function(init, final, total.bl, model){
  current.bl <- c()
  current.state <- init
  restart <- TRUE
  while(restart == TRUE){
    # draw a rate and waiting time based on init
    rate <- -diag(model)[current.state]
    waiting.time <- rexp(1, rate)
    current.bl <- c(current.bl, waiting.time)
    names(current.bl)[length(current.bl)] <- current.state
    # if the waiting time is smaller than the branch
    if(sum(current.bl) < total.bl){
      # then: a substitution is drawn with probability of leaving that state
      # then: a new wating time is simulated
      p <- model[current.state,]
      p[p < 0] <- 0
      current.state <- which(rmultinom(1, 1, p) == 1)
    }else{
      # if the waiting time is longer than the branch length AND the states are NOT the same
      if(current.state != final){
        current.bl <- c()
        current.state <- init
        # if the waiting time is longer than the branch length AND the states are the same
      }else{
        # if the vector is one current bl is total bl
        if(length(current.bl) == 1){
          current.bl <- total.bl
          names(current.bl) <- current.state
        }else{
          current.bl[length(current.bl)] <- total.bl - sum(current.bl[-length(current.bl)])
        }
        restart <- FALSE
      }
    }
  }
  return(current.bl)
}

simSingleSubstHistory <- function(cladewise.index, CharHistory, phy, model){
  SubstHistory <- vector("list", length(cladewise.index))
  for(i in cladewise.index){
    anc.index <- phy$edge[i,1]
    dec.index <- phy$edge[i,2]
    # init and final
    init <- CharHistory[anc.index]
    final <- CharHistory[dec.index]
    total.bl <- phy$edge.length[i]
    SubstHistory[[i]] <- simBranchSubstHistory(init, final, total.bl, model)
  }
  return(SubstHistory)
}

# simulate a substitution history given the simulations of ancestral states
simSubstHistory <- function(phy, tip.states, states, model, nSim=1, nCores=1){
  # set-up
  cladewise.index <- reorder.phylo(phy, "cladewise", index.only = TRUE)
  # simulate a character history
  CharHistories <- simCharHistory(phy=phy, tip.states=tip.states, states=states, model=model, nSim=nSim, nCores=nCores)
  obj <- mclapply(CharHistories, function(x) simSingleSubstHistory(cladewise.index, x, phy, model), mc.cores = nCores)
  return(obj)
}

# convert a substitution history into a mapped edge
convertSubHistoryToEdge <- function(phy, map){
  Traits <- levels(as.factor(unique(names(unlist(map)))))
  RowNames <- apply(phy$edge, 1, function(x) paste(x[1], x[2], sep = ","))
  obj <- do.call(rbind, lapply(map, function(x) sapply(Traits, function(y) sum(x[names(x) == y]))))
  rownames(obj) <- RowNames
  return(obj)
}

# exported function for use
makeSimmap <- function(tree, tip.states, states, model, nSim=1, nCores=1){
  maps <- simSubstHistory(tree, tip.states, states, model, nSim, nCores)
  mapped.edge <- mclapply(maps, function(x) convertSubHistoryToEdge(tree, x))
  obj <- vector("list", nSim)
  for(i in 1:nSim){
    tree.simmap <- tree
    tree.simmap$maps <- maps[[i]]
    tree.simmap$mapped.edge <- mapped.edge[[i]]
    tree.simmap$Q <- model
    attr(tree.simmap, "map.order") <- "right-to-left"
    if (!inherits(tree.simmap, "simmap")) 
      class(tree.simmap) <- c("simmap", setdiff(class(tree.simmap), "simmap"))
    obj[[i]] <- tree.simmap
  }
  return(obj)
}



