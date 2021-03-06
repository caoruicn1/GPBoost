## Examples for combining tree-boosting with Gaussian process and random effects models
## for several non-Gaussian likelihoods
## See the examples in GPBoost_algorithm.R for more functionality

library(gpboost)

## Choose likelihood: either "bernoulli_probit" (=default for binary data), "bernoulli_logit",
##                       "poisson", or "gamma"
likelihood <- "bernoulli_probit"

# Non-linear prior mean function for simulation in examples below
f1d <- function(x) 1.5*(1/(1+exp(-(x-0.5)*20))+0.75*x)-1.3
sim_non_lin_f <- function(n){
  X <- matrix(runif(2*n),ncol=2)
  f <- f1d(X[,1])
  return(list(X=X,f=f))
}

# Parameters for gpboost in examples below 
# Note: the tuning parameters are by no means optimal for all situations considered here
if (likelihood %in% c("bernoulli_probit","bernoulli_logit")) {
  params <- list(learning_rate = 0.05, min_data_in_leaf = 20, objective = "binary")
  nrounds = 150
} else {
  params <- list(learning_rate = 0.05, min_data_in_leaf = 20, objective = likelihood)
  nrounds = 75
}


#--------------------Combine tree-boosting and grouped random effects model----------------
# Simulate data
n <- 5000 # number of samples
m <- 500 # number of groups
set.seed(1)
# Simulate random and fixed effects
group <- rep(1,n) # grouping variable
for(i in 1:m) group[((i-1)*n/m+1):(i*n/m)] <- i
b1 <- rnorm(m)
eps <- b1[group]
eps <- eps - mean(eps)
sim_data <- sim_non_lin_f(n=n)
f <- sim_data$f
X <- sim_data$X
# Simulate response variable
if (likelihood == "bernoulli_probit") {
  probs <- pnorm(f+eps)
  y <- as.numeric(runif(n) < probs)
} else if (likelihood == "bernoulli_logit") {
  probs <- 1/(1+exp(-(f+eps)))
  y <- as.numeric(runif(n) < probs)
} else if (likelihood == "poisson") {
  mu <- exp(f+eps)
  y <- qpois(runif(n), lambda = mu)
} else if (likelihood == "gamma") {
  mu <- exp(f+eps)
  y <- qgamma(runif(n), scale = mu, shape = 1)
}
hist(y,breaks=50)# visualize response variable

# Training
# Define random effects model
gp_model <- GPModel(group_data = group, likelihood = likelihood)
bst <- gpboost(data = X, label = y, verbose = 0, 
               gp_model = gp_model,
               monotone_constraints = c(1,0),
               nrounds = nrounds, 
               params = params, 
               train_gp_model_cov_pars = TRUE)
summary(gp_model) # Trained random effects model

# Make predictions
nplot <- 200# number of predictions
X_test_plot <- cbind(seq(from=0,to=1,length.out=nplot),rep(0.5,nplot))
group_data_pred <- rep(-9999,dim(X_test_plot)[1])# only new / unobserved levels
# Predict response variable
pred_prob <- predict(bst, data = X_test_plot, group_data_pred = group_data_pred, rawscore = FALSE)$response_mean
# Predict latent variable including variance
pred <- predict(bst, data = X_test_plot, group_data_pred = group_data_pred,
                predict_var=TRUE, rawscore = TRUE)
# Visualize predictions
x <- seq(from=0,to=1,length.out=200)
plot(x,f1d(x),type="l",lwd=3,col=2,main="Data, true and predicted latent function F")
points(X[,1],y,col=rgb(0,0,0,alpha=0.1))
lines(X_test_plot[,1],pred$fixed_effect,col=4,lwd=3)
legend(legend=c("True F","Pred F"),"bottomright",bty="n",lwd=3,col=c(2,4))

plot(X[,1],y,col=rgb(0,0,0,alpha=0.1),main="Data and predicted response variable")
lines(X_test_plot[,1],pred_prob,col=3,lwd=3)

# Cross-validation for finding number of iterations
dtrain <- gpb.Dataset(data = X, label = y)
gp_model <- GPModel(group_data = group, likelihood = likelihood)
cvbst <- gpb.cv(params = params, data = dtrain, gp_model = gp_model,
                nrounds = 200, nfold = 4, verbose = 1,
                early_stopping_rounds = 5, monotone_constraints = c(1,0),
                use_gp_model_for_validation = TRUE)
print(paste0("Optimal number of iterations: ", cvbst$best_iter))

#--------------------Compare to generalized linear mixed effects model----------------
X_lin <- cbind(rep(1,n),X)# Add intercept column
gp_model <- fitGPModel(group_data = group, likelihood = likelihood, y = y, X = X_lin)
summary(gp_model)

X_test_lin <- cbind(rep(1,dim(X_test_plot)[1]),X_test_plot)
# Predict latent variable
pred_lin <- predict(gp_model, y = y, X_pred = X_test_lin,
                    group_data_pred = group_data_pred, predict_response = FALSE)
# Predict response variable
pred_lin_resp <- predict(gp_model, y = y, X_pred = X_test_lin,
                         group_data_pred = group_data_pred, predict_response = TRUE)

# Plot results
plot(x,f1d(x),type="l",lwd=3,col=2,main="Data, true and fitted function")
points(X[,1],y)
lines(X_test_plot[,1],pred$fixed_effect,col=4,lwd=3)
lines(X_test_plot[,1],pred_lin$mu,col=3,lwd=3)
legend(legend=c("True F","Pred F GPBoost","Pred F linear"),"bottomright",bty="n",lwd=3,col=c(2,4,3))


#--------------------Combine tree-boosting and Gaussian process model----------------
# Simulate data
ntrain <- 500
set.seed(1)
# Training and test locations for GP (exlcude upper right square from training locations)
coords_train <- matrix(runif(2)/2,ncol=2)
while (dim(coords_train)[1]<ntrain) {
  coord_i <- runif(2) 
  if (!(coord_i[1]>=0.7 & coord_i[2]>=0.7)) {
    coords_train <- rbind(coords_train,coord_i)
  }
}
nx <- 30 # test data: number of grid points on each axis
x2 <- x1 <- rep((1:nx)/nx,nx)
for(i in 1:nx) x2[((i-1)*nx+1):(i*nx)]=i/nx
coords_test <- cbind(x1,x2)
coords <- rbind(coords_train, coords_test)
ntest <- nx * nx
n <- ntrain + ntest
# Simulate fixed effects
X_train <- matrix(runif(2*ntrain),ncol=2)
x <- seq(from=0,to=1,length.out=nx^2)
X_test <- cbind(x,rep(0,nx^2))
X <- rbind(X_train,X_test)
f <- f1d(X[,1])
# Simulate spatial Gaussian process
sigma2_1 <- 1 # marginal variance of GP
rho <- 0.1 # range parameter
D <- as.matrix(dist(coords))
Sigma <- sigma2_1 * exp(-D/rho) + diag(1E-20,n)
C <- t(chol(Sigma))
b_1 <- rnorm(n=n)
eps <- as.vector(C %*% b_1)
eps <- eps - mean(eps)
# Simulate response variable
if (likelihood == "bernoulli_probit") {
  probs <- pnorm(f+eps)
  y <- as.numeric(runif(n) < probs)
} else if (likelihood == "bernoulli_logit") {
  probs <- 1/(1+exp(-(f+eps)))
  y <- as.numeric(runif(n) < probs)
} else if (likelihood == "poisson") {
  mu <- exp(f+eps)
  y <- qpois(runif(n), lambda = mu)
} else if (likelihood == "gamma") {
  mu <- exp(f+eps)
  y <- qgamma(runif(n), scale = mu, shape = 1)
}
# Split into training and test data
y_train <- y[1:ntrain]
dtrain <- gpb.Dataset(data = X_train, label = y_train)
y_test <- y[1:ntest+ntrain]
eps_test <- eps[1:ntest+ntrain]
hist(y_train,breaks=50)# visualize response variable

# Train model
gp_model <- GPModel(gp_coords = coords_train, cov_function = "exponential",
                    likelihood = likelihood)
# Takes approx. 1  minute
bst <- gpb.train(data = dtrain, gp_model = gp_model,
                 monotone_constraints = c(1,0),
                 nrounds = nrounds, params = params, verbose = 0)
summary(gp_model)# Trained GP model

# Prediction of latent variable
pred <- predict(bst, data = X_test, gp_coords_pred = coords_test,
                predict_var = TRUE, rawscore = TRUE)
# Predict response variable (label)
pred_resp <- predict(bst, data = X_test, gp_coords_pred = coords_test, rawscore = FALSE)
if (likelihood %in% c("bernoulli_probit","bernoulli_logit")) {
  print("Test error:")
  mean(as.numeric(pred_resp$response_mean>0.5) != y_test)
} else {
  print("Test root mean square error:")
  sqrt(mean((pred_resp$response_mean - y_test)^2))
}
print("Test root mean square error for latent GP:")
sqrt(mean((pred$random_effect_mean - eps_test)^2))

# Visualize predictions and compare to true values
library(ggplot2)
library(viridis)
library(gridExtra)
plot1 <- ggplot(data = data.frame(s_1=coords_test[,1],s_2=coords_test[,2],b=eps_test),aes(x=s_1,y=s_2,color=b)) +
  geom_point(size=4, shape=15) + scale_color_viridis(option = "B") + ggtitle("True latent GP and training locations") + 
  geom_point(data = data.frame(s_1=coords_train[,1],s_2=coords_train[,2],y=y_train),aes(x=s_1,y=s_2),size=3, col="white", alpha=1, shape=43)
plot2 <- ggplot(data = data.frame(s_1=coords_test[,1],s_2=coords_test[,2],b=pred$random_effect_mean),aes(x=s_1,y=s_2,color=b)) +
  geom_point(size=4, shape=15) + scale_color_viridis(option = "B") + ggtitle("Predicted latent GP mean")
plot3 <- ggplot(data = data.frame(s_1=coords_test[,1],s_2=coords_test[,2],b=sqrt(pred$random_effect_cov)),aes(x=s_1,y=s_2,color=b)) +
  geom_point(size=4, shape=15) + scale_color_viridis(option = "B") + labs(title="Predicted latent GP standard deviation", subtitle=" = prediction uncertainty")
plot4 <- ggplot(data=data.frame(x=X_test[,1],f=pred$fixed_effect), aes(x=x,y=f)) + geom_line(size=1) +
  geom_line(data=data.frame(x=x,f=f1d(x)), aes(x=x,y=f), size=1.5, color="darkred") +
  ggtitle("Predicted and true F(X)") + xlab("X") + ylab("y")
grid.arrange(plot1, plot2, plot3, plot4, ncol=2)

# Cross-validation for finding number of iterations (takes some time...)
gp_model <- GPModel(gp_coords = coords_train, cov_function = "exponential",
                    likelihood = likelihood)
cvbst <- gpb.cv(params = params, data = dtrain, gp_model = gp_model,
                nrounds = 200, nfold = 4, verbose = 1,
                early_stopping_rounds = 5, monotone_constraints = c(1,0),
                use_gp_model_for_validation = TRUE)
print(paste0("Optimal number of iterations: ", cvbst$best_iter))

