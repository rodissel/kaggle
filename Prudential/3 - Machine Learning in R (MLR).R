###############################
#                             #
#  PRUDENTIAL LIFE INSURANCE  #
#                             #
###############################

# ASSUMPTION: The required data files are downloaded from competition site and made available locally.
# COMPETITION SITE URL: https://www.kaggle.com/c/prudential-life-insurance-assessment

# Perform house-keeping
rm(list=ls())
gc()

# Set working directory
setwd("C:/home/kaggle/Prudential")

# Load required Packages
library(Metrics)
library(Hmisc)
library(xgboost)
library(checkmate)
library(mlr) 

# Set seed for reproducibility
set.seed(23456)

# Load Data files
train 	<- read.csv("train.csv", header = TRUE)
test 	<- read.csv("test.csv", header = TRUE)
test$Response <- 0

# Load custom learner function
source("LearnerFunc.R")

# Introduce Response feature
train$Id <- NULL

# Create Regression Task for Train dataset
trainTask <- makeRegrTask(data = train, target = "Response")

# Create dummy features for Train dataset
trainTask <- createDummyFeatures(trainTask)

# Create Regression Task for Test dataset
testTask <- makeRegrTask(data = test, target = "Response")

# Create dummy features for Test dataset
testTask <- createDummyFeatures(testTask)

# Create Regression Learner object for XGBoost algorithm
lrn <- makeLearner("regr.xgboost")

# Setup parameter values for XGBoost in Learner object
lrn$par.vals <- list(nthread		= 5,
			  nrounds       = 150,  # 500
			  print.every.n = 2,
			  objective	= "count:poisson"  #"reg:linear"
)

# For 'Missing values imputation', configure Learner with 'Median' algorithm.
lrn <- makeImputeWrapper(lrn, classes = list(numeric = imputeMedian(), integer = imputeMedian()))

## Perform Cross-Validation in parallel
# Load Library for parallel run
library(parallelMap)

# Start no of sockets to be run parallel
parallelStartSocket(3)

# Export the objects to slave processes
parallelExport("SQWK", "SQWKfun", "trainLearner.regr.xgboost", "predictLearner.regr.xgboost" , "makeRLearner.regr.xgboost")

# Run Cross-Validation function
cv <- crossval(lrn, trainTask, iter = 3, measures = SQWK, show.info = TRUE)

# Stop parallelization and clean-up loaded objects
parallelStop()


# Determine optimal cut-points based on Cross-Validated predictions
optCuts	<- optim(seq(1.5, 7.5, by = 1), SQWKfun, pred = cv$pred)

# Develop a model on train task using learner
mlrModel <- train(lrn, trainTask)

# Predict the response values on test task
pred 	<- predict(mlrModel, testTask)

# Slice the response using optimal cut-points determined earlier
preds 	<- as.numeric(Hmisc::cut2(pred$data$response, c(-Inf, optCuts$par, Inf)))

# Create submission file
submission		<- read.csv("sample_submission.csv", header = TRUE)
submission$Response 	<- as.integer(preds)
write.csv(submission, "MLR-submission-3.csv", row.names = FALSE)
