function [dr,info] = dyn_first_order_solver(jacobia,M_,dr,options,task)
    
%@info:
%! @deftypefn {Function File} {[@var{dr},@var{info}] =} dyn_first_order_solver (@var{jacobia},@var{M_},@var{dr},@var{options},@var{task})
%! @anchor{dyn_first_order_solver}
%! @sp 1
%! Computes the first order reduced form of the DSGE model
%! @sp 2
%! @strong{Inputs}
%! @sp 1
%! @table @ @var
%! @item jacobia
%! Matrix containing the Jacobian of the model
%! @item M_
%! Matlab's structure describing the model (initialized by @code{dynare}).
%! @item dr
%! Matlab's structure describing the reduced form solution of the model.
%! @item qz_criterium
%! Double containing the criterium to separate explosive from stable eigenvalues
%! @end table
%! @sp 2
%! @strong{Outputs}
%! @sp 1
%! @table @ @var
%! @item dr
%! Matlab's structure describing the reduced form solution of the model.
%! @item info
%! Integer scalar, error code.
%! @sp 1
%! @table @ @code
%! @item info==0
%! No error.
%! @item info==1
%! The model doesn't determine the current variables uniquely.
%! @item info==2
%! MJDGGES returned an error code.
%! @item info==3
%! Blanchard & Kahn conditions are not satisfied: no stable equilibrium.
%! @item info==4
%! Blanchard & Kahn conditions are not satisfied: indeterminacy.
%! @item info==5
%! Blanchard & Kahn conditions are not satisfied: indeterminacy due to rank failure.
%! @item info==7
%! One of the generalized eigenvalues is close to 0/0     
%! @end table
%! @end table
%! @end deftypefn
%@eod:

% Copyright (C) 2001-2012 Dynare Team
%
% This file is part of Dynare.
%
% Dynare is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% Dynare is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with Dynare.  If not, see <http://www.gnu.org/licenses/>.
    
    info = 0;
    
    dr.ghx = [];
    dr.ghu = [];
    
    klen = M_.maximum_endo_lag+M_.maximum_endo_lead+1;
    kstate = dr.kstate;
    kad = dr.kad;
    kae = dr.kae;
    nstatic = dr.nstatic;
    nfwrd = dr.nfwrd;
    npred = dr.npred;
    nboth = dr.nboth;
    order_var = dr.order_var;
    nd = size(kstate,1);
    lead_lag_incidence = M_.lead_lag_incidence;
    nz = nnz(lead_lag_incidence);

    sdyn = M_.endo_nbr - nstatic;

    [junk,cols_b,cols_j] = find(lead_lag_incidence(M_.maximum_endo_lag+1,...
                                                   order_var));
    
    if nstatic > 0
        [Q,R] = qr(jacobia(:,cols_j(1:nstatic)));
        aa = Q'*jacobia;
    else
        aa = jacobia;
    end
    k1 = find([1:klen] ~= M_.maximum_endo_lag+1);
    a = aa(:,nonzeros(lead_lag_incidence(k1,:)'));
    b(:,cols_b) = aa(:,cols_j);
    b10 = b(1:nstatic,1:nstatic);
    b11 = b(1:nstatic,nstatic+1:end);
    b2 = b(nstatic+1:end,nstatic+1:end);
    if any(isinf(a(:)))
        info = 1;
        return
    end

    % buildind D and E
    d = zeros(nd,nd) ;
    e = d ;

    k = find(kstate(:,2) >= M_.maximum_endo_lag+2 & kstate(:,3));
    d(1:sdyn,k) = a(nstatic+1:end,kstate(k,3)) ;
    k1 = find(kstate(:,2) == M_.maximum_endo_lag+2);
    e(1:sdyn,k1) =  -b2(:,kstate(k1,1)-nstatic);
    k = find(kstate(:,2) <= M_.maximum_endo_lag+1 & kstate(:,4));
    e(1:sdyn,k) = -a(nstatic+1:end,kstate(k,4)) ;
    k2 = find(kstate(:,2) == M_.maximum_endo_lag+1);
    k2 = k2(~ismember(kstate(k2,1),kstate(k1,1)));
    d(1:sdyn,k2) = b2(:,kstate(k2,1)-nstatic);

    if ~isempty(kad)
        for j = 1:size(kad,1)
            d(sdyn+j,kad(j)) = 1 ;
            e(sdyn+j,kae(j)) = 1 ;
        end
    end

    % 1) if mjdgges.dll (or .mexw32 or ....) doesn't exit, 
    % matlab/qz is added to the path. There exists now qz/mjdgges.m that 
    % contains the calls to the old Sims code 
    % 2) In  global_initialization.m, if mjdgges.m is visible exist(...)==2, 
    % this means that the DLL isn't avaiable and use_qzdiv is set to 1
    
    [err,ss,tt,w,sdim,dr.eigval,info1] = mjdgges(e,d,options.qz_criterium);
    mexErrCheck('mjdgges', err);

    if info1
        if info1 == -30
            % one eigenvalue is close to 0/0
            info(1) = 7;
        else
            info(1) = 2;
            info(2) = info1;
            info(3) = size(e,2);
        end
        return
    end

    nba = nd-sdim;

    nyf = sum(kstate(:,2) > M_.maximum_endo_lag+1);

    if task == 1
        if rcond(w(1:nyf,nd-nyf+1:end)) < 1e-9
            dr.full_rank = 0;
        else
            dr.full_rank = 1;
        end            
        % Under Octave, eig(A,B) doesn't exist, and
        % lambda = qz(A,B) won't return infinite eigenvalues
        if ~exist('OCTAVE_VERSION')
            dr.eigval = eig(e,d);
        end
        return
    end

    if nba ~= nyf
        temp = sort(abs(dr.eigval));
        if nba > nyf
            temp = temp(nd-nba+1:nd-nyf)-1-options.qz_criterium;
            info(1) = 3;
        elseif nba < nyf;
            temp = temp(nd-nyf+1:nd-nba)-1-options.qz_criterium;
            info(1) = 4;
        end
        info(2) = temp'*temp;
        return
    end

    np = nd - nyf;
    n2 = np + 1;
    n3 = nyf;
    n4 = n3 + 1;
    % derivatives with respect to dynamic state variables
    % forward variables
    w1 =w(1:n3,n2:nd);
    if ~isscalar(w1) && (condest(w1) > 1e9);
        % condest() fails on a scalar under Octave
        info(1) = 5;
        info(2) = condest(w1);
        return;
    else
        gx = -w1'\w(n4:nd,n2:nd)';
    end  

    % predetermined variables
    hx = w(1:n3,1:np)'*gx+w(n4:nd,1:np)';
    hx = (tt(1:np,1:np)*hx)\(ss(1:np,1:np)*hx);

    k1 = find(kstate(n4:nd,2) == M_.maximum_endo_lag+1);
    k2 = find(kstate(1:n3,2) == M_.maximum_endo_lag+2);
    dr.gx = gx;
    dr.ghx = [hx(k1,:); gx(k2(nboth+1:end),:)];

    %lead variables actually present in the model
    j3 = nonzeros(kstate(:,3));
    j4  = find(kstate(:,3));
    % derivatives with respect to exogenous variables
    if M_.exo_nbr
        fu = aa(:,nz+(1:M_.exo_nbr));
        a1 = b;
        aa1 = [];
        if nstatic > 0
            aa1 = a1(:,1:nstatic);
        end
        dr.ghu = -[aa1 a(:,j3)*gx(j4,1:npred)+a1(:,nstatic+1:nstatic+ ...
                                                 npred) a1(:,nstatic+npred+1:end)]\fu;
    else
        dr.ghu = [];
    end

    % static variables
    if nstatic > 0
        temp = -a(1:nstatic,j3)*gx(j4,:)*hx;
        j5 = find(kstate(n4:nd,4));
        temp(:,j5) = temp(:,j5)-a(1:nstatic,nonzeros(kstate(:,4)));
        temp = b10\(temp-b11*dr.ghx);
        dr.ghx = [temp; dr.ghx];
        temp = [];
    end

    if options.use_qzdiv
        %% Necessary when using Sims' routines for QZ
        gx = real(gx);
        hx = real(hx);
        dr.ghx = real(dr.ghx);
        dr.ghu = real(dr.ghu);
    end

    dr.Gy = hx;
