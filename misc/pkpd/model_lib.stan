int[] count_dose_given(vector time, vector dose_time, vector dose_tau, int[] dose_addl) {
  int dose_count[num_elements(time)];
  int time_rank[num_elements(time)];
  int o;
  int O;
  o <- 1;
  O <- num_elements(time);
  time_rank <- find_interval(time, dose_time);
  dose_count <- rep_array(0, O);
  //print("time_rank = ", time_rank);
  // first skip all dosings before the first time
  while(o < O && time_rank[o] == 0) { o <- o + 1; }
  //print("o = ", o);
  for(i in o:O) {
    int d;
    d <- time_rank[i];
    if(dose_tau[d] > 0)
      dose_count[i] <- min(floor_div_int(time[i] - dose_time[d], dose_tau[d]), dose_addl[d]);
  }
  return dose_count;
}

int[] count_dose_given_blocked(int[] M, vector time, int[] M_dose, vector dose_time, vector dose_tau, int[] dose_addl) {
  int dose_count[num_elements(time)];
  int B;
  int tl;
  int dl;
  B <- num_elements(M);
  tl <- 1;
  dl <- 1;
  for(b in 1:B) {
    int tu;
    int du;
    tu <- tl + M[b] - 1;
    du <- dl + M_dose[b] - 1;
    dose_count[tl:tu] <- count_dose_given(time[tl:tu], dose_time[dl:du], dose_tau[dl:du], dose_addl[dl:du]);
    tl <- tu + 1;
    dl <- du + 1;
  }
  return dose_count;
}

/*
 * Need to define an operator which develops a state forward in time
 * by an amount Dt. Input is the state at t, the log-coefficients of
 * the exponentials and the exponential exponents and Dt. Output is
 * the new state after Dt time units for one of the cmts (depends on
 * given coefs).
 *
 * lstate_ref is the initial
 *
 * coefsN is a 2-row matrix with the first row being the
 * log-coefficients and the second row the exponents.
 */
matrix evolve_lsystem(int S, vector Dt, matrix coefs, int[] coefs_map) {
  matrix[num_elements(Dt),S] lsystem;
  int T;
  T <- num_elements(Dt);
  
  // initialize to zero
  lsystem <- rep_matrix(-500, T, S);
  
  for(o in 1:cols(coefs)) {
    int s;
    vector[T] term;
    s    <- coefs_map[o];
    term <- coefs[1,o] + Dt * coefs[2,o];
    for(t in 1:T)
      lsystem[t,s] <- log_sum_exp(lsystem[t,s], term[t]);
  }
  return(lsystem);
}

real lgeometric_series(real la, real n) {
  return( log1m_exp(la * n) - log1m_exp(la) );
}

/*
 * models 2 cmts 1 and 2 which each have an elimination rate k1 / k2
 * and we have a flow from 1 to 2, k12. This models a 1cmt oral dosing
 * and/or a building block of a metabolite. Finally all mass exiting
 * cmt 2 is recorded in cmt 3.
 */
matrix pk_1cmt_metabolite_depot(vector lref, vector Dt, real lk1, real lk12, real lk20, real tau, real n) {
  matrix[2,8] coefs1;
  int coefs1_map[8];
  int coefs1_zero[8];
  matrix[2,6] coefs2;
  int coefs2_map[6];
  int coefs2_zero[6];
  // positive terms
  matrix[num_elements(Dt),3] lsystem1;
  // negative terms (due to Bateman function)
  matrix[num_elements(Dt),2] lsystem2;
  real ldeltaSq;
  real nk1;
  real nk20;

  coefs1_zero <- rep_array(0, 8);
  coefs2_zero <- rep_array(0, 6);
  
  ldeltaSq <- 2*log_diff_exp_abs(lk1, lk20);

  nk1  <- -exp(lk1);
  nk20 <- -exp(lk20);

  // setup coefficient matrix and coef index vectors
  coefs1_map[1] <- 1;
  coefs1[1,1] <- lref[1];
  coefs1[2,1] <- nk1;
  
  coefs1_map[2] <- 2;
  coefs1[1,2] <- lref[1] + lk12 - ldeltaSq + lk1;
  coefs1[2,2] <- nk20;
  coefs1_map[3] <- 2;
  coefs1[1,3] <- lref[1] + lk12 - ldeltaSq + lk20;
  coefs1[2,3] <- nk1;
  
  coefs1_map[4] <- 2;
  coefs1[1,4] <- lref[2];
  coefs1[2,4] <- nk20;

  // whatever is in the depot cmt doesn´t go away
  coefs1_map[5] <- 3;
  coefs1[1,5] <- log_sum_exp(lref[3], lref[2]);
  coefs1[2,5] <- 0;
  coefs1_zero[5] <- 1;
  
  coefs1_map[6] <- 3;
  coefs1[1,6] <- lref[1] + lk12 + lk20 - ldeltaSq + log_sum_exp(lk1 - lk20, lk20 - lk1);
  coefs1[2,6] <- 0;
  coefs1_zero[6] <- 1;
  
  coefs1_map[7] <- 3;
  coefs1[1,7] <- lref[1] + lk12 + lk20 - ldeltaSq;
  coefs1[2,7] <- nk1;
  
  coefs1_map[8] <- 3;
  coefs1[1,8] <- lref[1] + lk12 + lk20 - ldeltaSq;
  coefs1[2,8] <- nk20;
  
  // for the negative terms we only use a two cmts; hence 2 is
  // relabeled to 1, and 3 to 2
  coefs2_map[1] <- 1;
  coefs2[1,1] <- lref[1] + lk12 - ldeltaSq + lk1;
  coefs2[2,1] <- nk1;
  coefs2_map[2] <- 1;
  coefs2[1,2] <- lref[1] + lk12 - ldeltaSq + lk20;
  coefs2[2,2] <- nk20;

  coefs2_map[3] <- 2;
  coefs2[1,3] <- lref[2];
  coefs2[2,3] <- nk20;
  
  coefs2_map[4] <- 2;
  coefs2[1,4] <- lref[1] + lk12 - ldeltaSq + lk20 + log(2);
  coefs2[2,4] <- 0;
  coefs2_zero[4] <- 1;

  coefs2_map[5] <- 2;
  coefs2[1,5] <- lref[1] + lk12 - ldeltaSq + lk20 + lk1 - lk20;
  coefs2[2,5] <- nk20;
  
  coefs2_map[6] <- 2;
  coefs2[1,6] <- lref[1] + lk12 - ldeltaSq + lk20 + lk20 - lk1;
  coefs2[2,6] <- nk1;
  
  // in case the initial state is dosed in a regular pattern, we can
  // take advantage of the geometric series here by modifing the
  // coefficients
  if(n>1) {
    real logn;
    logn <- log(n);
    for(i in 1:8) {
      if(coefs1_zero[i]) {
        coefs1[1,i] <- coefs1[1,i] + logn;
      } else {
        coefs1[1,i] <- coefs1[1,i] + lgeometric_series(coefs1[2,i] * tau, n);
      }
    }
    for(i in 1:6) {
      if(coefs2_zero[i]) {
        coefs2[1,i] <- coefs2[1,i] + logn;
      } else {
        coefs2[1,i] <- coefs2[1,i] + lgeometric_series(coefs2[2,i] * tau, n);
      }
    }
  }
    
  //print("AFTER: coefs1 = ", coefs1);
  //print("AFTER: coefs2 = ", coefs2);

  lsystem1 <- evolve_lsystem(3, Dt, coefs1, coefs1_map);
  lsystem2 <- evolve_lsystem(2, Dt, coefs2, coefs2_map);

  //print("lsystem1 = ", lsystem1);
  //print("lsystem2 = ", lsystem2);

  // final system is the difference of the two solutions
  for(t in 1:num_elements(Dt)) {
    lsystem1[t,2] <- log_diff_exp(lsystem1[t,2], lsystem2[t,1]);
    lsystem1[t,3] <- log_diff_exp(lsystem1[t,3], lsystem2[t,2]);
  }

  return(lsystem1);
}

matrix pk_1cmt_metabolite(vector lref, vector Dt, real lk1, real lk12, real lk20, real tau, real n) {
  matrix[2,4] coefs1;
  int coefs1_map[4];
  matrix[2,2] coefs2;
  int coefs2_map[2];
  // positive terms
  matrix[num_elements(Dt),2] lsystem1;
  // negative terms (due to Bateman function)
  matrix[num_elements(Dt),1] lsystem2;
  real ldeltaSq;
  real nk1;
  real nk20;

  ldeltaSq <- 2*log_diff_exp_abs(lk1, lk20);

  nk1  <- -exp(lk1);
  nk20 <- -exp(lk20);

  // setup coefficient matrix and coef index vectors
  coefs1_map[1] <- 1;
  coefs1[1,1] <- lref[1];
  coefs1[2,1] <- nk1;
  
  coefs1_map[2] <- 2;
  coefs1[1,2] <- lref[1] + lk12 - ldeltaSq + lk1;
  coefs1[2,2] <- nk20;
  coefs1_map[3] <- 2;
  coefs1[1,3] <- lref[1] + lk12 - ldeltaSq + lk20;
  coefs1[2,3] <- nk1;
  
  coefs1_map[4] <- 2;
  coefs1[1,4] <- lref[2];
  coefs1[2,4] <- nk20;

  // for the negative terms we only use a two cmts; hence 2 is
  // relabeled to 1, and 3 to 2
  coefs2_map[1] <- 1;
  coefs2[1,1] <- lref[1] + lk12 - ldeltaSq + lk1;
  coefs2[2,1] <- nk1;
  coefs2_map[2] <- 1;
  coefs2[1,2] <- lref[1] + lk12 - ldeltaSq + lk20;
  coefs2[2,2] <- nk20;

  // in case the initial state is dosed in a regular pattern, we can
  // take advantage of the geometric series here by modifing the
  // coefficients
  if(n>1) {
    for(i in 1:4) {
      coefs1[1,i] <- coefs1[1,i] + lgeometric_series(coefs1[2,i] * tau, n);
    }
    for(i in 1:2) {
      coefs2[1,i] <- coefs2[1,i] + lgeometric_series(coefs2[2,i] * tau, n);
    }
  }
    
  //print("AFTER: coefs1 = ", coefs1);
  //print("AFTER: coefs2 = ", coefs2);

  lsystem1 <- evolve_lsystem(2, Dt, coefs1, coefs1_map);
  lsystem2 <- evolve_lsystem(1, Dt, coefs2, coefs2_map);

  //print("lsystem1 = ", lsystem1);
  //print("lsystem2 = ", lsystem2);

  // final system is the difference of the two solutions
  for(t in 1:num_elements(Dt)) {
    lsystem1[t,2] <- log_diff_exp(lsystem1[t,2], lsystem2[t,1]);
  }

  return(lsystem1);
}


// forward declare pk system functions
matrix pk_system(vector lref, vector Dt, vector theta, real[] x_r, int[] x_i);


matrix pk_system_addl(vector lref, vector Dt, int cmt, real lamt, real tau, int n, vector theta, real[] x_r, int[] x_i);

// model evaluation function taking dosing (and addl dosing) into
// account for a single patient. The function calculates always with
// respect to a reference state. The initial reference state is the
// initial time and initial_lstate. Upon the first dosing event past
// the initial time, the reference time and state is set to the
// respective dosing event.
matrix pk_model_fast(vector dose_lamt, int[] dose_cmt, vector dose_time, vector dose_tau, int[] dose_addl, int[] dose_next_obs,
                     vector init_lstate, real init_time,
                     vector obs_time, int[] obs_timeRank, int[] obs_dose_given, 
                     vector theta,
                     vector lscale,
                     real[] x_r, int[] x_i)
{
  int D;
  int O;
  int d;
  int o;
  int active_addl;
  int init_ref;
  vector[num_elements(init_lstate)] lstate_ref;
  matrix[num_elements(obs_time),num_elements(init_lstate)] lstate;
  
  D <- num_elements(dose_lamt);
  O <- num_elements(obs_time);

  o <- 1;
  d <- 0;
  init_ref <- 1;
  active_addl <- 0; // 0 = FALSE
  lstate_ref  <- init_lstate;
  // skip all dosing records prior to init_time
  while(d < D && dose_time[d+1] < init_time) { d <- d + 1; }
  // next, process all elements which are past active dosing
  while(o <= O) {
    // first update reference state to be just after the last
    // dosing
    while(d != obs_timeRank[o]) {
      int nd;
      // the dose of the reference state is not yet the very
      // last dose given before this observation, add it
      nd <- d + 1;
      if(init_ref) {
        lstate_ref <- to_vector(pk_system(lstate_ref, rep_vector(dose_time[nd] - init_time, 1), theta,
                                          x_r, x_i)[1]);
      } else if(active_addl) {
        // in case of an active addl record, we have to super-impose
        // the developed reference state with the emerged dosing which
        // is handled by the _addl function
        lstate_ref <- to_vector(pk_system_addl(lstate_ref, rep_vector(dose_time[nd] - dose_time[d], 1), dose_cmt[d], dose_lamt[d], dose_tau[d], dose_addl[d], theta,
                                               x_r, x_i)[1]);
      } else {
          lstate_ref <- to_vector(pk_system(lstate_ref, rep_vector(dose_time[nd] - dose_time[d], 1), theta,
                                            x_r, x_i)[1]);
      }
      // the new reference time point is the dosing event; time is now
      // measure as time-after-dose
      
      // add in the dosing, but only if we have a simple dosing
      // event, i.e. no additional dosings
      active_addl <- dose_addl[nd] > 0;
      if(!active_addl) {
        lstate_ref[dose_cmt[nd]] <- log_sum_exp(lstate_ref[dose_cmt[nd]], dose_lamt[nd]);
      }
      d <- nd;
      // at this point the initial time is not any more the reference
      // state
      init_ref <- 0;
    }
    // ok, evolve from reference (las dose or initial) to current
    // observation...
    if(init_ref) {
      lstate[o] <- pk_system(lstate_ref, segment(obs_time, o, 1) - init_time, theta,
                             x_r, x_i)[1];
      o <- o + 1;
    } else if(active_addl) {
      int ndose;
      int event_free;
      // ...in case of addl dosing, the effect of the multiple
      // dosing has not yet been added
      // number of dosings given from the active addl records
      ndose <- obs_dose_given[o];
      // advance as far as we can by counting the number of
      // observations which have the same number of doses given
      event_free <- 0;
      while((o + event_free) < O && obs_dose_given[o + event_free + 1] == ndose)
        event_free <- event_free + 1;
      
      lstate[o:(o+event_free)] <- pk_system_addl(lstate_ref, segment(obs_time, o, event_free + 1) - dose_time[d], dose_cmt[d], dose_lamt[d], dose_tau[d], ndose, theta,
                                                 x_r, x_i);
      o <- o + event_free + 1;
    } else {
      // ... which is simple for non-addl dosing as dose is
      // already merged, evolve as long as no other dosing occurs
      int event_free;
      event_free <- dose_next_obs[d];
      lstate[o:(o+event_free-1)] <- pk_system(lstate_ref, segment(obs_time, o, event_free) - dose_time[d], theta,
                                              x_r, x_i);
      o <- o + event_free;
    }
  }
  return(lstate - rep_matrix(to_row_vector(lscale), O));
}

matrix pk_model(vector dose_lamt, int[] dose_cmt, vector dose_time, vector dose_tau, int[] dose_addl,
                vector init_lstate, real init_time,
                vector obs_time,
                vector theta,
                vector lscale,
                real[] x_r, int[] x_i) {
  int obs_timeRank[num_elements(obs_time)];
  obs_timeRank <- find_interval(obs_time, dose_time);
  if (init_time > dose_time[1])
    reject("Initial time must be at or before first dose!");
  return(pk_model_fast(dose_lamt, dose_cmt, dose_time, dose_tau, dose_addl, count_obs_event_free(obs_timeRank, size(dose_cmt)),
                       init_lstate, init_time,
                       obs_time, obs_timeRank,
                       count_dose_given(obs_time, dose_time, dose_tau, dose_addl),
                       theta,
                       lscale,
                       x_r, x_i));
}

matrix evaluate_model_fast(int[] dose_M, vector dose_lamt, int[] dose_cmt, vector dose_time, vector dose_tau, int[] dose_addl, int[] dose_next_obs,
                           matrix init_lstate, vector init_time,
                           int[] obs_M, vector obs_time, int[] obs_timeRank, int[] obs_dose_given, 
                           matrix theta,
                           matrix lscale,
                           real[] x_r, int[] x_i) {
  matrix[num_elements(obs_time), cols(init_lstate)] lstate;
  int J;
  int d;
  int o;
  int S;
  
  J <- num_elements(dose_M);
  S <- cols(lscale);
  d <- 1;
  o <- 1;
  for(j in 1:J) {
    matrix[obs_M[j],S] lstate_j;
    int d_m;
    int o_m;
    //print("Processing patient ", j);
    d_m <- dose_M[j];
    o_m <- obs_M[j];
    lstate_j <- pk_model_fast(segment(dose_lamt, d, d_m), segment(dose_cmt, d, d_m), segment(dose_time, d, d_m), segment(dose_tau, d, d_m), segment(dose_addl, d, d_m), segment(dose_next_obs, d, d_m)
                              ,to_vector(init_lstate[j]), init_time[j]
                              ,segment(obs_time, o, o_m), segment(obs_timeRank, o, o_m), segment(obs_dose_given, o, o_m)
                              ,to_vector(theta[j])
                              ,to_vector(lscale[j])
                              ,x_r, x_i);
    
    for(i in 1:o_m)
      lstate[i + o - 1] <- lstate_j[i];
    
    d <- d + d_m;
    o <- o + o_m;
  }
  return(lstate);
}
  
matrix evaluate_model(int[] dose_M, vector dose_lamt, int[] dose_cmt, vector dose_time, vector dose_tau, int[] dose_addl,
                      matrix init_lstate, vector init_time,
                      int[] obs_M, vector obs_time,
                      matrix theta,
                      matrix lscale,
                      real[] x_r, int[] x_i) {
  int obs_timeRank[num_elements(obs_time)];
  obs_timeRank <- find_interval_blocked(obs_M, obs_time, dose_M, dose_time);
  return(evaluate_model_fast(dose_M, dose_lamt, dose_cmt, dose_time, dose_tau, dose_addl, count_obs_event_free_blocked(obs_M, obs_timeRank, dose_M),
                             init_lstate, init_time,
                             obs_M, obs_time, obs_timeRank,
                             count_dose_given_blocked(obs_M, obs_time, dose_M, dose_time, dose_tau, dose_addl),
                             theta,
                             lscale,
                             x_r, x_i));
}

matrix evaluate_model_nm(int[] id, vector time, int[] cmt, int[] evid, vector amt, vector tau, int[] addl, int[] mdv,
                         matrix init_lstate, vector init_time,
                         matrix theta, matrix lscale,
                         real[] x_r, int[] x_i) {
  int dose_ind[count_elem(evid, 1)];
  dose_ind <- which_elem(evid, 1);
  
  return(evaluate_model(rle_int(id[dose_ind]), log(amt[dose_ind]), cmt[dose_ind], time[dose_ind], tau[dose_ind], addl[dose_ind],
                        init_lstate, init_time,
                        rle_int(id), time,
                        theta,
                        lscale,
                        x_r, x_i));
}
