# fit_single_optimizer ----

test_that("fit_single_optimizer works as expected with defaults", {
  dat <- fev_data
  form <- FEV1 ~ ARMCD * RACE + us(AVISIT | USUBJID)
  result <- fit_single_optimizer(
    formula = form,
    data = dat
  )
  expect_identical(class(result), c("mmrm_fit", "mmrm_tmb"))
  expect_identical(attr(result, "optimizer"), "L-BFGS-B")
  expect_identical(attr(result, "messages"), NULL)
  expect_identical(attr(result, "warnings"), NULL)
  expect_true(attr(result, "converged"))
})

test_that("fit_single_optimizer works as expected with optimizer inputted but no starting values", {
  dat <- fev_data
  form <- FEV1 ~ SEX + us(AVISIT | USUBJID)
  result <- fit_single_optimizer(
    formula = form,
    data = dat,
    optimizer = "BFGS"
  )
  expect_identical(class(result), c("mmrm_fit", "mmrm_tmb"))
  expect_identical(attr(result, "optimizer"), "BFGS")
  expect_identical(attr(result, "messages"), NULL)
  expect_identical(attr(result, "warnings"), NULL)
  expect_true(attr(result, "converged"))
})

test_that("fit_single_optimizer works as expected with starting values and optimizer inputted", {
  dat <- fev_data
  form <- FEV1 ~ RACE + ARMCD + us(AVISIT | USUBJID)
  result <- fit_single_optimizer(
    formula = form,
    data = dat,
    optimizer = "BFGS",
    start = 1:10
  )
  expect_identical(class(result), c("mmrm_fit", "mmrm_tmb"))
  expect_identical(attr(result, "optimizer"), "BFGS")
  expect_identical(attr(result, "messages"), NULL)
  expect_identical(attr(result, "warnings"), NULL)
  expect_true(attr(result, "converged"))
})

test_that("fit_single_optimizer gives error messages", {
  formula <- FEV1 ~ bla
  expect_error(
    h_mmrm_tmb(formula, fev_data),
    "Assertion on 'identical(sum(cov_selected), 1L)' failed",
    fixed = TRUE
  )
  expect_error(
    fit_single_optimizer(formula, fev_data),
    "Assertion on 'identical(sum(cov_selected), 1L)' failed",
    fixed = TRUE
  )
})

# h_summarize_all_fits ----

test_that("h_summarize_all_fits works as expected", {
  mod_fit <- fit_single_optimizer(
    formula = FEV1 ~ RACE + SEX + ARMCD * AVISIT + us(AVISIT | USUBJID),
    data = fev_data,
    optimizer = "nlminb"
  )
  mod_fit2 <- fit_single_optimizer(
    formula = FEV1 ~ RACE + SEX + ARMCD * AVISIT + us(AVISIT | USUBJID),
    data = fev_data,
    optimizer = "L-BFGS-B"
  )
  all_fits <- list(mod_fit, mod_fit2)
  result <- expect_silent(h_summarize_all_fits(all_fits))
  expected <- list(
    warnings = list(NULL, NULL),
    messages = list(NULL, NULL),
    log_liks = c(-1693.22493558573, -1693.22493812251),
    converged = c(TRUE, TRUE)
  )
  expect_equal(result, expected)
})

test_that("h_summarize_all_fits works when some list elements are try-error objects", {
  mod_fit <- fit_single_optimizer(
    formula = FEV1 ~ RACE + SEX + ARMCD * AVISIT + us(AVISIT | USUBJID),
    data = fev_data,
    optimizer = "nlminb"
  )
  mod_fit2 <- try(stop("bla"), silent = TRUE)
  mod_fit3 <- fit_single_optimizer(
    formula = FEV1 ~ RACE + SEX + ARMCD * AVISIT + us(AVISIT | USUBJID),
    data = fev_data,
    optimizer = "L-BFGS-B"
  )
  all_fits <- list(mod_fit, mod_fit2, mod_fit3)
  result <- expect_silent(h_summarize_all_fits(all_fits))
  expected <- list(
    warnings = list(NULL, "Error in try(stop(\"bla\"), silent = TRUE) : bla\n", NULL),
    messages = list(NULL, NULL, NULL),
    log_liks = c(-1693.22493558573, NA, -1693.22493812251),
    converged = c(TRUE, FALSE, TRUE)
  )
  expect_equal(result, expected)
})

# refit_multiple_optimizers ----

test_that("refit_multiple_optimizers works as expected with default arguments", {
  fit <- fit_single_optimizer(
    formula = FEV1 ~ RACE + SEX + ARMCD * AVISIT + us(AVISIT | USUBJID),
    data = fev_data,
    optimizer = "nlminb"
  )

  # Mock here that it did not converge.
  attr(fit, "converged") <- FALSE
  fit$neg_log_lik <- fit$neg_log_lik + 10

  result <- expect_silent(refit_multiple_optimizers(fit = fit))
  expect_class(result, "mmrm_fit")

  expect_true(attr(result, "converged"))
  expect_false(identical("nlminb", attr(result, "optimizer")))
  expect_true(logLik(result) > logLik(fit))
})

test_that("refit_multiple_optimizers works with parallel computations and selected optimizers", {
  skip_on_cran()

  fit <- fit_single_optimizer(
    formula = FEV1 ~ RACE + SEX + ARMCD * AVISIT + us(AVISIT | USUBJID),
    data = fev_data,
    optimizer = "nlminb"
  )

  # Mock here that it did not converge.
  attr(fit, "converged") <- FALSE
  fit$neg_log_lik <- fit$neg_log_lik + 10

  result <- expect_silent(refit_multiple_optimizers(
    fit = fit,
    n_cores = h_free_cores(),
    optimizers = c("BFGS", "CG")
  ))
  expect_class(result, "mmrm_fit")

  expect_true(attr(result, "converged"))
  expect_subset(attr(result, "optimizer"), choices = c("BFGS", "CG"))
  expect_true(logLik(result) > logLik(fit))
})

# mmrm ----

## unstructured ----

test_that("mmrm works as expected for unstructured", {
  formula <- FEV1 ~ RACE + SEX + ARMCD * AVISIT + us(AVISIT | USUBJID)
  result <- expect_silent(mmrm(formula, fev_data, reml = FALSE))
  expect_class(result, c("mmrm", "mmrm_fit", "mmrm_tmb"))
  expect_true(attr(result, "converged"))
  expect_list(result$jac_list, types = "matrix")
  expect_class(result$call, "call")
  expect_false(result$reml)
})

test_that("mmrm works as expected for antedependence", {
  formula <- FEV1 ~ RACE + SEX + ARMCD * AVISIT + ad(AVISIT | USUBJID)
  result <- expect_silent(mmrm(formula, fev_data, reml = TRUE))
  expect_class(result, c("mmrm", "mmrm_fit", "mmrm_tmb"))
  expect_true(attr(result, "converged"))
  expect_list(result$jac_list, types = "matrix")
  expect_class(result$call, "call")
  expect_true(result$reml)
})

test_that("mmrm works as expected for toeplitz", {
  formula <- FEV1 ~ RACE + SEX + ARMCD * AVISIT + toep(AVISIT | USUBJID)
  result <- expect_silent(mmrm(formula, fev_data, reml = TRUE))
  expect_class(result, c("mmrm", "mmrm_fit", "mmrm_tmb"))
  expect_true(attr(result, "converged"))
  expect_list(result$jac_list, types = "matrix")
  expect_class(result$call, "call")
  expect_true(result$reml)
})

## general ----

test_that("mmrm falls back to other optimizers if default does not work", {
  formula <- FEV1 ~ RACE + SEX + ARMCD * AVISIT + us(AVISIT | USUBJID)
  data_small <- fev_data[1:50, ]
  # Default does not work.
  expect_error(
    mmrm(formula, data_small, optimizer = "L-BFGS-B"),
    "Model convergence problem"
  )
  # But another one works.
  # Note: We disable parallel processing here to comply with CRAN checks.
  result <- expect_silent(mmrm(formula, data_small, n_cores = 1L))
  expect_true(attr(result, "converged"))
  expect_false(identical(attr(result, "optimizer"), "L-BFGS-B"))
})

test_that("mmrm fails if no optimizer works", {
  skip_on_ci()
  skip_on_cran()
  # We skip this test on CI and CRAN since it can be flaky on different platforms.

  formula <- FEV1 ~ RACE + SEX + ARMCD * AVISIT + us(AVISIT | USUBJID)
  data_small <- fev_data[1:30, ]
  # Note: Here we are using parallel computations.
  expect_error(
    mmrm(formula, data_small, reml = FALSE),
    "No optimizer led to a successful model fit"
  )
})

test_that("mmrm works for rank deficient original design matrix by default", {
  formula <- FEV1 ~ RACE + SEX + SEX2 + ARMCD * AVISIT + us(AVISIT | USUBJID)
  dat <- fev_data
  dat$SEX2 <- dat$SEX # nolint
  result <- expect_silent(mmrm(formula, dat))
  expect_true(attr(result, "converged"))
})
