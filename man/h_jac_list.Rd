% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/satterthwaite.R
\name{h_jac_list}
\alias{h_jac_list}
\title{Obtain List of Jacobian Matrix Entries for Covariance Matrix}
\usage{
h_jac_list(covbeta_fun, theta_est)
}
\arguments{
\item{covbeta_fun}{(\code{function})\cr function calculating the covariance
matrix of coefficients given variance parameters (\code{theta}), see
\code{\link[=h_covbeta_fun]{h_covbeta_fun()}} to obtain this from a \code{mmrm_tmb} object.}

\item{theta_est}{(\code{numeric})\cr variance parameters point estimate.}
}
\value{
List with one element per variance parameter containing a matrix
of the same dimensions as the covariance matrix. The values are the derivatives
with regards to this variance parameter.
}
\description{
\ifelse{html}{\href{https://lifecycle.r-lib.org/articles/stages.html#experimental}{\figure{lifecycle-experimental.svg}{options: alt='[Experimental]'}}}{\strong{[Experimental]}}
}
\examples{
formula <- FEV1 ~ RACE + us(AVISIT | USUBJID)
model <- h_mmrm_tmb(formula, fev_data)
covbeta_fun <- h_covbeta_fun(model)
h_jac_list(covbeta_fun, model$theta_est)
}
