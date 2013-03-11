#' Estimate smoothing RMSE using leave-one-out cross-valdation.
#'
#' @export
#' @examples
#' set.seed(1014)
#' # 1d -----------------------------
#' x <- rchallenge(1e4)
#' xsum <- condense(bin(x, 1 / 10))
#' cvs <- rmse_cvs(xsum)
#'
#' if (require("ggplot2")) {
#' autoplot(xsum)
#' qplot(x, err, data = cvs, geom = "line")
#' xsmu <- smooth(xsum, 1.3)
#' autoplot(xsmu)
#' autoplot(peel(xsmu))
#' }
#'
#' # 2d -----------------------------
#' y <- runif(1e4)
#' xysum <- condense(bin(x, 1 / 10), bin(y, 1 / 100))
#' cvs <- rmse_cvs(xysum, h_grid(xysum, 10))
#' if (require("ggplot2")) {
#' qplot(x, y, data = cvs, size = err)
#' }
rmse_cvs <- function(x, hs = h_grid(x), ...) {
  rmse_1 <- function(i) {
    rmse_cv(x, as.numeric(hs[i, ]), ...)
  }
  err <- vapply(seq_len(nrow(hs)), rmse_1, numeric(1))
  data.frame(hs, err)
}

rmse_cv <- function(x, h, var = summary_vars(x)[1], ...) {
  # can't smooth missing values, so drop.
  x <- x[complete.cases(x), , drop = FALSE]
  gvars <- group_vars(x)

  pred_error <- function(i) {
    out <- as.matrix(x[i, gvars, drop = FALSE])
    smu <- smooth(x[-i, , drop = FALSE], grid = out, h = h, var = var, ...)
    smu[[var]] - x[[var]][i]
  }
  err <- vapply(seq_along(nrow(x)), pred_error, numeric(1))
  sqrt(mean(err ^ 2, na.rm = TRUE))
}

#' Find "best" smoothing parameter using leave-one-out cross validation.
#'
#' Minimises the leave-one-out estimate of root mean-squared error to find
#' find the "optimal" bandwidth for smoothing.
#'
#' L-BFGS-B optimisation is used to constrain the bandwidths to be greater
#' than the binwidths: if the bandwidth is smaller than the binwidth it's
#' impossible to compute the rmse because no smoothing occurs. The tolerance
#' is set relatively high for numerical optimisation since the precise choice
#' of bandwidth makes little difference visually, and we're unlikely to have
#' sufficient data to make a statistically significant choice anyway.
#'
#' @param x condensed summary to smooth
#' @param h initial values of bandwidths to start search out. If not specified
#'  defaults to 5 times the binwidth of each variable.
#' @param ... other arguments (like \code{var}) passed on to
#'  \code{\link{rmse_cv}}
#' @param tol numerical tolerance, defaults to 1\%.
#' @param control additional control parameters passed on to \code{\link{optim}}
#'   The most useful argument is probably trace, which makes it possible to
#'   follow the progress of the optimisation.
#' @export
#' @examples
#' x <- rchallenge(1e4)
#' xsum <- condense(bin(x, 1 / 10))
#' h <- best_h(xsum, control = list(trace = 1, REPORT = 1))
#' h <- best_h(xsum)
#'
#' if (require("ggplot2")) {
#' autoplot(xsum)
#' autoplot(smooth(xsum, h))
#' }
best_h <- function(x, h_init = NULL, ..., tol = 1e-2, control = list()) {
  stopifnot(is.condensed(x))

  gvars <- group_vars(x)
  widths <- vapply(x[gvars], attr, "width", FUN.VALUE = numeric(1))
  h_init <- h_init %||% widths * 5
  stopifnot(is.numeric(h_init), length(h_init) == length(gvars))

  stopifnot(is.list(control))
  control <- modifyList(list(factr = tol / .Machine$double.eps), control)

  # Optimise
  rmse <- function(h) {
    rmse_cv(x, h, ...)
  }
  res <- optim(h_init, rmse, method = "L-BFGS-B", lower = widths,
    control = control)
  h <- unname(res$par)

  # Feedback
  if (res$convergence != 0) {
    warning("Failed to converge: ", res$message, call. = FALSE)
  } else if (rel_dist(h, widths) < 1e-3) {
    warning("h close to lower bound: smoothing not needed", call. = FALSE)
  }
  structure(h, iterations = res$counts[1])
}

rel_dist <- function(x, y) {
  mean(abs(x - y) / abs(x + y))
}

#' Generate grid of plausible bandwidths for condensed summary.
#'
#' @param x a condensed summary
#' @param n number of bandwidths to generate (in each dimension)
#' @param max maximum bandwidth to generate, as multiple of binwidth.
#' @export
#' @examples
#' x <- rchallenge(1e4)
#' xsum <- condense(bin(x, 1 / 10))
#' h_grid(xsum)
#'
#' y <- runif(1e4)
#' xysum <- condense(bin(x, 1 / 10), bin(y, 1 / 100))
#' h_grid(xysum, n = 10)
h_grid <- function(x, n = 50, max = 20) {
  stopifnot(is.condensed(x))
  stopifnot(is.numeric(n), length(n) == 1, n > 0)
  stopifnot(is.numeric(max), length(max) == 1, max > 0)

  gs <- x[group_vars(x)]
  widths <- vapply(gs, attr, "width", FUN.VALUE = numeric(1))

  hs <- lapply(widths, function(w) w * seq(2, max, length = n))
  expand.grid(hs, KEEP.OUT.ATTRS = FALSE)
}
