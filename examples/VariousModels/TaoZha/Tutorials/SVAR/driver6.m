%% -------------------- only variances switch model -------------------- %%
%
% Only variances in ALL three equations switch 

%% housekeeping
clear 
close all
clc()

%% Create dataset
clc

do_plot=true;

scale=100;

[db,varlist0]=create_dataset(scale,do_plot);

varlist=fieldnames(varlist0);

%% set up Markov chains

markov_chains=struct('name','syncvol',...
    'number_of_states',3,...
    'controlled_parameters',{{'s'}},...
    'endogenous_probabilities',[],...
    'probability_parameters',[]);

%% Create the VAR

clc

nlags=2;

exog={};

constant=true;

panel=[];

sv0=svar(varlist,exog,nlags,constant,panel,markov_chains);

%% set up restrictions

% syntax is alag(eqtn,vname)
%-------------------------------
lin_restr={
    % first equation or "FFR" equation
    %----------------------------------
    'a1(1,pi)=0'
    'a2(1,pi)=0'
    'a1(1,ygap)=0'
    'a2(1,ygap)=0'
    'a2(1,FFR)=0'
    % second equation or "pi" equation
    %----------------------------------
    'a0(2,FFR)=0'
    'a1(2,FFR)=0'
    'a2(2,FFR)=0'
    'a1(2,ygap)=0'
    'a2(2,ygap)=0'
    % third equation or "ygap" equation
    %-----------------------------------
    'a1(3,FFR)=0'
    'a2(3,FFR)=0'
    'a1(3,pi)=0'
    'a2(3,pi)=0'
    'a0(3,pi)+a0(3,FFR)=0'
    };
nonlin_restr={
    'a0(3,FFR)>=0'
    'a1(1,FFR)>=0'
    'a1(1,FFR)<=1'
    };

restrictions=[lin_restr;nonlin_restr];

%% set priors 

% priors for the VAR coefficients
%--------------------------------
var_prior=svar.prior_template();
var_prior.type='sz';
% priors for the syncvol transition probabilities
%------------------------------------------------
switch_prior=struct();
switch_prior.dirichlet_1={0.1,'syncvol_tp_1_2',0.2,'syncvol_tp_1_3',0.2};
switch_prior.dirichlet_2={0.1,'syncvol_tp_2_1',0.2,'syncvol_tp_2_3',0.2};
switch_prior.dirichlet_3={0.1,'syncvol_tp_3_1',0.2,'syncvol_tp_3_2',0.2};

prior=struct();

prior.var=var_prior;

prior.nonvar=switch_prior;

%% Find posterior mode
clc

sv=estimate(sv0,db,{'1960Q1','2015Q2'},prior,restrictions,'fmincon');

%% estimates
clc

pmode=posterior_mode(sv)

%% Printing estimates
clc

print_structural_form(sv)

%% Printing solution
clc

print_solution(sv)

%% plot smoothed state and regime probabilities
clc

close all

plot_probabilities(sv)

%% plots probabilities against data
close all

plot_data_against_probabilities(sv,'regime')

%% Impulse responses

myirfs=irf(sv);

snames=fieldnames(myirfs);

figure('name','Simple impulse response functions')

iter=0;

jter=0;

for ishk=1:numel(snames)
    
    shk=snames{ishk};
    
    for iv=1:numel(varlist)
        
        v=varlist{iv};
        
        iter=iter+1;
        
        subplot(3,3,iter)
        
        plot(myirfs.(shk).(v),'linewidth',2)
        
        if iter<=3,title(v),end
        
        if any(iter==[1,4,7])
            
            jter=jter+1;
            
            ylabel([shk,'(',varlist{jter},' shock)'])
            
        end
        
    end
       
end

%% Generalized impulse responses

shock_names=[];

irf_periods=[];

params=[];

girf_setup=struct();% girf_setup=struct('nsims',300);

mygirfs=irf(sv,shock_names,irf_periods,params,girf_setup);

figure('name','Generalized impulse response functions')

iter=0;

jter=0;

for ishk=1:numel(snames)
    
    shk=snames{ishk};
    
    for iv=1:numel(varlist)
        
        v=varlist{iv};
        
        iter=iter+1;
        
        subplot(3,3,iter)
        
        plot(mygirfs.(shk).(v),'linewidth',2)
        
        if iter<=3,title(v),end
        
        if any(iter==[1,4,7])
            
            jter=jter+1;
            
            ylabel([shk,'(',varlist{jter},' shock)'])
            
        end
        
    end
       
end

%% Posterior sampling

[ff,lb,ub,x0,vcov,self]=pull_objective(sv);

options=struct();
options.alpha=0.234;
options.burnin=1000;
options.N=10000;

lb(~isfinite(lb))=-500;
ub(~isfinite(ub))=500;

results=mh_sampler(ff,lb,ub,options,x0,vcov)

%% MCMC diagnostics

% obj=mcmc(results.pop,pnames,0,1,1)


%% Marginal data density

obj=mdd(results.pop,ff,lb,ub);

log_mdd=is(obj,[],mdd.global_options)

log_mdd=ris(obj,[],mdd.global_options)

log_mdd=bridge(obj,true,mdd.global_options)

log_mdd=mueller(obj,[],mdd.global_options)

log_mdd=laplace(obj)

log_mdd=swz(obj,[],mdd.global_options)

log_mdd=laplace_mcmc(obj)

log_mdd=cj(obj,[],mdd.global_options)

%% Out-of sample forecasts

%% Conditional forecast


