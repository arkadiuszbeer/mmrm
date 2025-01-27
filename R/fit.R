#' Fitting an MMRM with Single Optimizer
#'
#' @description `r lifecycle::badge("experimental")`
#'
#' This function helps to fit an MMRM using `TMB` with a single optimizer,
#' while capturing messages and warnings.
#'
#' @inheritParams mmrm
#' @inheritParams h_mmrm_tmb_control
#'
#' @return The `mmrm_fit` object, with additional attributes containing warnings,
#'   messages, optimizer used and convergence status in addition to the
#'   `mmrm_tmb` contents.
#' @export
#'
#' @examples
#' mod_fit <- fit_single_optimizer(
#'   formula = FEV1 ~ RACE + SEX + ARMCD * AVISIT + us(AVISIT | USUBJID),
#'   data = fev_data,
#'   optimizer = "nlminb"
#' )
#' attr(mod_fit, "converged")
fit_single_optimizer <- function(formula,
                                 data,
                                 reml = TRUE,
                                 start = NULL,
                                 optimizer = c("L-BFGS-B", "BFGS", "CG", "nlminb"),
                                 accept_singular = TRUE) {
  assert_formula(formula)
  assert_data_frame(data)
  optimizer <- match.arg(optimizer)
  control <- h_mmrm_tmb_control(
    optimizer = if (optimizer == "nlminb") stats::nlminb else stats::optim,
    optimizer_control = if (optimizer == "nlminb") list(iter.max = 300, eval.max = 400) else list(),
    optimizer_args = if (optimizer == "nlminb") list() else list(method = optimizer),
    start = start,
    accept_singular = accept_singular
  )
  quiet_fit <- h_record_all_output(
    h_mmrm_tmb(
      formula = formula,
      data = data,
      reml = reml,
      control = control
    ),
    remove = list(
      warning = c("NA/NaN function evaluation") # Transient visit to invalid parameters.
    )
  )
  if (length(quiet_fit$errors)) {
    stop(quiet_fit$errors)
  }
  converged <- (length(quiet_fit$warnings) == 0L) &&
    (length(quiet_fit$messages) == 0L) &&
    (quiet_fit$result$opt_details$convergence == 0)
  structure(
    quiet_fit$result,
    errors = quiet_fit$errors,
    warnings = quiet_fit$warnings,
    messages = quiet_fit$messages,
    optimizer = optimizer,
    converged = converged,
    class = c("mmrm_fit", class(quiet_fit$result))
  )
}

#' Summarizing List of Fits
#'
#' @description `r lifecycle::badge("experimental")`
#'
#' @param all_fits (`list` of `mmrm_fit` or `try-error`)\cr list of fits.
#'
#' @return List with `warnings`, `messages`, `log_liks` and `converged` results.
#' @export
#'
#' @examples
#' mod_fit <- fit_single_optimizer(
#'   formula = FEV1 ~ RACE + SEX + ARMCD * AVISIT + us(AVISIT | USUBJID),
#'   data = fev_data,
#'   optimizer = "nlminb"
#' )
#' mod_fit2 <- fit_single_optimizer(
#'   formula = FEV1 ~ RACE + SEX + ARMCD * AVISIT + us(AVISIT | USUBJID),
#'   data = fev_data,
#'   optimizer = "L-BFGS-B"
#' )
#' all_fits <- list(mod_fit, mod_fit2)
#' h_summarize_all_fits(all_fits)
h_summarize_all_fits <- function(all_fits) {
  assert_list(all_fits, types = c("mmrm_fit", "try-error"))
  is_error <- vapply(all_fits, is, logical(1), class2 = "try-error")

  warnings <- messages <- vector(mode = "list", length = length(all_fits))
  warnings[is_error] <- lapply(all_fits[is_error], as.character)
  warnings[!is_error] <- lapply(all_fits[!is_error], attr, which = "warnings")
  messages[!is_error] <- lapply(all_fits[!is_error], attr, which = "messages")
  log_liks <- as.numeric(rep(NA, length = length(all_fits)))
  log_liks[!is_error] <- vapply(all_fits[!is_error], stats::logLik, numeric(1L))
  converged <- rep(FALSE, length = length(all_fits))
  converged[!is_error] <- vapply(all_fits[!is_error], attr, logical(1), which = "converged")

  list(
    warnings = warnings,
    messages = messages,
    log_liks = log_liks,
    converged = converged
  )
}

#' Refitting MMRM with Multiple Optimizers
#'
#' @description `r lifecycle::badge("experimental")`
#'
#' @param fit (`mmrm_fit`)\cr original model fit from [fit_single_optimizer()].
#' @inheritParams mmrm
#' @param optimizers (`character`)\cr all possible optimizers to be used for fitting.
#' @inheritParams h_mmrm_tmb_control
#'
#' @return The best (in terms of log likelihood) fit which converged.
#'
#' @note For Windows, no parallel computations are currently implemented.
#' @export
#'
#' @examples
#' fit <- fit_single_optimizer(
#'   formula = FEV1 ~ RACE + SEX + ARMCD * AVISIT + us(AVISIT | USUBJID),
#'   data = fev_data,
#'   optimizer = "nlminb"
#' )
#' best_fit <- refit_multiple_optimizers(fit)
refit_multiple_optimizers <- function(fit,
                                      n_cores = 1L,
                                      optimizers = c("L-BFGS-B", "BFGS", "CG", "nlminb"),
                                      accept_singular = TRUE) {
  assert_class(fit, "mmrm_fit")
  assert_int(n_cores, lower = 1L)
  optimizers <- match.arg(optimizers, several.ok = TRUE)

  # Extract the components of the original fit.
  old_formula <- formula(fit)
  old_data <- fit$data
  old_optimizer <- attr(fit, "optimizer")

  # Settings for the new fits.
  optimizers <- setdiff(optimizers, old_optimizer)
  n_cores_used <- ifelse(
    .Platform$OS.type == "windows",
    1L,
    min(
      length(optimizers),
      n_cores
    )
  )

  # Take the results from old fit as starting values for new fits.
  all_fits <- suppressWarnings(parallel::mclapply(
    X = optimizers,
    FUN = fit_single_optimizer,
    formula = old_formula,
    data = old_data,
    reml = fit$reml,
    start = fit$theta_est,
    accept_singular = accept_singular,
    mc.cores = n_cores_used,
    mc.silent = TRUE
  ))
  all_fits <- c(all_fits, list(old_result = fit))
  names(all_fits) <- c(optimizers, old_optimizer)

  # Find the results that are ok and return best in terms of log-likelihood.
  all_fits_summary <- h_summarize_all_fits(all_fits)
  is_ok <- all_fits_summary$converged
  if (!any(is_ok)) {
    stop(
      "No optimizer led to a successful model fit. ",
      "Please try to use a different covariance structure or other covariates."
    )
  }
  best_optimizer <- which.max(all_fits_summary$log_liks[is_ok])
  all_fits[[best_optimizer]]
}


#' Fit an MMRM
#'
#' @description `r lifecycle::badge("experimental")`
#'
#' This is the main function fitting the MMRM.
#'
#' @param formula (`formula`)\cr the model formula, see details.
#' @param data (`data`)\cr the data to be used for the model.
#' @param reml (`flag`)\cr whether restricted maximum likelihood (REML) estimation is used,
#'   otherwise maximum likelihood (ML) is used.
#' @param optimizer (`string`)\cr optimizer to be used to generate the model.
#' @param n_cores (`count`)\cr number of cores which could in principle be used for
#'   parallel computations on Linux or Mac machines.
#' @inheritParams h_mmrm_tmb_control
#'
#' @details
#' The `formula` typically looks like:
#' `FEV1 ~ RACE + SEX + ARMCD * AVISIT + us(AVISIT | USUBJID)`
#' so specifies response and covariates as usual, and exactly one special term
#' defines which covariance structure is used and what are the visit and
#' subject variables.
#'
#' When setting `optimizer = "automatic"`, first the default optimizer
#' (`L-BFGS-B`) is used to fit the model. If that converges, this is returned.
#' If not, the other available optimizers from [refit_multiple_optimizers()] are
#' tried (in parallel if `n_cores` is set and not on Windows).
#' If none of the optimizers converge, then the function fails. Otherwise
#' the best fit is returned.
#'
#' @return An `mmrm` object.
#'
#' @note The `mmrm` object is also an `mmrm_fit` and an `mmrm_tmb` object,
#' therefore corresponding methods also work (see [`mmrm_tmb_methods`]).
#' In addition it contains the Jacobian information `jac_list` and the `call`.
#' Use of the package `emmeans` is supported, see [`emmeans_support`].
#'
#' @export
#'
#' @examples
#' fit <- mmrm(
#'   formula = FEV1 ~ RACE + SEX + ARMCD * AVISIT + us(AVISIT | USUBJID),
#'   data = fev_data
#' )
mmrm <- function(formula,
                 data,
                 reml = TRUE,
                 optimizer = "automatic",
                 n_cores = h_free_cores(),
                 accept_singular = TRUE) {
  assert_string(optimizer)
  use_automatic <- identical(optimizer, "automatic")

  attr(data, which = "dataname") <- toString(match.call()$data)

  fit <- fit_single_optimizer(
    formula = formula,
    data = data,
    reml = reml,
    optimizer = ifelse(use_automatic, "L-BFGS-B", optimizer),
    accept_singular = accept_singular
  )
  if (!attr(fit, "converged")) {
    if (use_automatic) {
      fit <- refit_multiple_optimizers(
        fit,
        n_cores = n_cores,
        accept_singular = accept_singular
      )
    } else {
      all_problems <- unlist(
        attributes(fit)[c("errors", "messages", "warnings")],
        use.names = FALSE
      )
      stop(paste0(
        "Chosen optimizer '", optimizer, "' led to problems during model fit:\n",
        paste(paste0(seq_along(all_problems), ") ", all_problems), collapse = ";\n"), "\n",
        "Consider using the 'automatic' optimizer."
      ))
    }
  }

  covbeta_fun <- h_covbeta_fun(fit)
  fit$jac_list <- h_jac_list(covbeta_fun, fit$theta_est)

  class(fit) <- c("mmrm", class(fit))
  fit
}
