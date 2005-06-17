function yf=forcst2(y0,horizon,dr,n)
  global Sigma_e_ endo_nbr exo_nbr options_ ykmin_
  
  options_ = set_default_option(options_,'simul_seed',0);
  order = options_.order;
  seed = options_.simul_seed;

  k1 = [ykmin_:-1:1];
  k2 = dr.kstate(find(dr.kstate(:,2) <= ykmin_+1),[1 2]);
  k2 = k2(:,1)+(ykmin_+1-k2(:,2))*endo_nbr;

  it_ = ykmin_ + 1 ;

  % eliminate shocks with 0 variance
  i_exo_var = setdiff([1:exo_nbr],find(diag(Sigma_e_) == 0));
  nxs = length(i_exo_var);

  chol_S = chol(Sigma_e_(i_exo_var,i_exo_var));

  if seed == 0
    randn('state',sum(100*clock));
  else
    randn('state',seed);
  end
  
  if ~isempty(Sigma_e_)
    e = randn(nxs,n,horizon);
  end
  
  B1 = dr.ghu(:,i_exo_var)*chol_S';

  ys0 = repmat(dr.ys(dr.order_var),1,n);
  ys1 = repmat(dr.ys(dr.order_var),1,ykmin_);
  ys1 = ys1(k2);
  ys1 = repmat(ys1,1,n);
  
  yf = zeros(horizon+ykmin_,endo_nbr,n);
  yf(1:ykmin_,:,:) = repmat(y0',[1,1,n]);
  
  j = ykmin_*endo_nbr;
  for i=2:horizon+1
    tempx1 = reshape(yf(k1,:,:),[j,n]);
    tempx = tempx1(k2,:)-ys1;
    yf(i,:,:) = ys0+dr.ghx*tempx+B1*squeeze(e(:,:,i-1));
    k1 = k1+1;
  end
  
  yf(:,dr.order_var,:) = yf;
    