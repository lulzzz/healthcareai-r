#' print method for model_list
#'
#' @param x model_list
#'
#' @export
#' @noRd
print.model_list <- function(x, ...) {
  if (length(x)) {
    x <- change_pr_metric(x)
    rinfo <- extract_model_info(x)
    out <- paste0(
      "Algorithms Trained: ", paste(rinfo$algs, collapse = ", "),
      "\nTarget: ", rinfo$target,
      "\nClass: ", rinfo$m_class,
      "\nPerformance Metric: ", rinfo$metric,
      "\nNumber of Observations: ", rinfo$ddim[1],
      "\nNumber of Features: ", rinfo$ddim[2] - 1L,
      "\nModels Trained: ", rinfo$timestamp
    )
    out <- paste(
      out,
      if (rinfo$tuned) {
        paste0("\n\nModels tuned via ", x[[1]]$control$number, "-fold cross validation ",
               "over ", nrow(x[[1]]$results), " combinations of hyperparameter values.",
               "\nBest model: ", rinfo$best_model_name,
               "\n", rinfo$metric, " = ", round(rinfo$best_model_perf, 2),
               "\nOptimal hyperparameter values:", "\n  ", format_tune(rinfo$best_model_tune)
        )
      } else {
        paste0("\n\nModels have not been tuned. Performance estimated via ",
               x[[1]]$control$number, "-fold cross validation at fixed hyperparameter values.",
               "\nBest model: ", rinfo$best_model_name,
               "\n", rinfo$metric, " = ", round(rinfo$best_model_perf, 2),
               "\nUser-selected hyperparameter values:", "\n  ", format_tune(rinfo$best_model_tune)
        )
      }
    )
  } else {
    out <- paste("Empty", class(x)[1], "object.")
  }
  cat(out, "\n")
  return(invisible(x))
}

#' summary method for model_list
#'
#' @param x model_list
#' @return list of tuning performance data frames, invisibly
#' @importFrom dplyr %>%
#'
#' @export
#' @noRd
summary.model_list <- function(object, ...) {
  if (!length(object))
    stop("object is empty.")
  object <- change_pr_metric(object)
  rinfo <- extract_model_info(object)
  out <-
    if (rinfo$tuned) {
      paste0("Models trained: ", rinfo$timestamp,
             "\n\nModels tuned via ", object[[1]]$control$number, "-fold cross validation ",
             "over ", nrow(object[[1]]$results), " combinations of hyperparameter values.",
             "\nBest performance: ", rinfo$metric, " = ", round(rinfo$best_model_perf, 2),
             "\nBy ", rinfo$best_model_name, " with hyperparameters:\n  ",
             format_tune(rinfo$best_model_tune))
    } else {
      paste0("Models trained: ", rinfo$timestamp,
             "\n\nModels have not been tuned. Performance estimated via ",
             object[[1]]$control$number, "-fold cross validation at fixed hyperparameter values.",
             "\nBest algorithm: ", rinfo$best_model_name, " with ",
             rinfo$metric, " = ", round(rinfo$best_model_perf, 2))
    }
  cat(out)
  cat("\n\nOut-of-fold performance of all trained models:\n\n")
  perf <- lapply(object, function(xx) {
    ord <- order(xx$results[[rinfo$metric]])
    if (object[[1]]$maximize) ord <- rev(ord)
    tibble::as_tibble(xx$results[ord, ])
  })
  names(perf) <- rinfo$algs
  print(perf)
  return(invisible(perf))
}

#' Plot performance of models
#'
#' @param x modellist object as returned by \code{\link{tune_models}} or
#'   \code{\link{machine_learn}}
#' @param print If TRUE (default) plot is printed
#' @param ... generic compatability
#'
#' @return Plot of model performance as a function of algorithm and
#'   hyperparameter values tuned over. Generally called for the side effect of
#'   printing a plot, but the plot is also invisibly returned. The
#'   best-performing model within each algorithm will be plotted as a triangle.
#'
#' @importFrom cowplot plot_grid
#' @importFrom purrr map_df
#' @export
#' @examples
#' models <- tune_models(mtcars, mpg, models = "knn", tune_depth = 5)
#' plot(models)
plot.model_list <- function(x, print = TRUE, ...) {
  if (!length(x))
    stop("x is empty.")
  if (!inherits(x, "model_list"))
    stop("x is class ", class(x)[1], ", but needs to be model_list")
  if (!attr(x, "tuned"))
    message("No tuning was done, so there's not much to plot. Use `tune_models` tune hyperparameters, ",
            "or use `plot(predict(x))` to plot predictions on training data.")
  x <- change_pr_metric(x)
  params <- purrr::map(x, ~ as.character(.x$modelInfo$parameters$parameter))
  bounds <- purrr::map_df(x, function(m) range(m$results[[m$metric]]))
  y_range <- c(min(bounds[1, ]), max(bounds[2, ]))
  gg_list <-
    # Loop over algorithms
    lapply(x, function(mod) {
      # optimum is min or max depending on metric
      optimum <- if (mod$maximize) max else min
      mod$results$id <- as.character(sample(nrow(mod$results)))
      mod$results$best <- mod$results[[mod$metric]] == optimum(mod$results[[mod$metric]])
      hps <- as.character(mod$modelInfo$parameters$parameter)
      plots <-
        # Loop over hyperparameters
        purrr::map(hps, ~ {
          to_plot <- mod$results[, which(names(mod$results) %in% c(.x, mod$metric, "best", "id"))]
          # Add column with a unique identifier for each row to color by
          if (!is.numeric(to_plot[[.x]]))
            to_plot[[.x]] <- reorder(to_plot[[.x]], to_plot[[mod$metric]], FUN = optimum)
          p <-
            ggplot(to_plot, aes_string(x = .x, y = mod$metric,
                                     color = "id", shape = "best")) +
            geom_point() +
            coord_flip() +
            scale_y_continuous(limits = y_range) +
            scale_color_discrete(guide = FALSE) +
            scale_shape_manual(values = c("TRUE" = 17, "FALSE" = 16), guide = FALSE) +
            xlab(NULL) +
            labs(title = .x)
          p <-
            if (.x != hps[length(hps)]) {
            p + theme(axis.title.x = element_blank(),
                           axis.text.x = element_blank(),
                           axis.ticks.x = element_blank())
          } else {
            p + theme(axis.title.x = element_text(face = "bold"))
          }
          return(p)
        })
      title <-
        cowplot::ggdraw() +
        cowplot::draw_label(mod$modelInfo$label, fontface = "bold")
      plot_grid(title, cowplot::plot_grid(plotlist = plots, ncol = 1, align = "v"),
                ncol = 1, rel_heights = c(0.1, 1.9))
    })
  gg <- cowplot::plot_grid(plotlist = gg_list)
  if (print)
    print(gg)
  return(invisible(gg))
}

if (FALSE) {
  # This is tricky because finalModel is a ranger (or whatever) class object,
  # not a train object.
  evaluate.model_list <- function(x) {
    f <- if (x[[1]]$maximize) max else min
    each_best <- purrr::map_dbl(x, ~ f(.x$results[[.x$metric]]))
    which_best <- which(f(each_best) == each_best)[1]
    message("Returning the best model, a ", names(which_best))
    out <- x[[which_best]]$finalModel
    return(out)
  }
}

#' Get info from a model_list
#'
#' @param x model_list
#' @importFrom purrr map_chr
#' @return list of statistics
#' @noRd
extract_model_info <- function(x) {
  # optimum is min or max depending on metric
  optimum <- if (x[[1]]$maximize) max else min
  metric <- x[[1]]$metric
  best_metrics <- purrr::map_dbl(x, ~ optimum(.x$results[[metric]]))
  best_model <- which(best_metrics == optimum(best_metrics))[1] # 1 in case tie
  algs <- purrr::map_chr(x, ~ .x$modelInfo$label)
  m_class <- x[[1]]$modelType
  target <- attr(x, "target")
  ddim <- dim(x[[1]]$trainingData)
  best_model_name <- algs[[best_model]]
  best_model_perf <- best_metrics[[best_model]]
  best_model_tune <-
    x[[best_model]]$bestTune
  list(
    m_class = m_class,
    algs = algs,
    target = target,
    metric = metric,
    best_model_name = best_model_name,
    best_model_perf = best_model_perf,
    best_model_tune = best_model_tune,
    ddim = ddim,
    tuned = attr(x, "tuned"),
    timestamp = attr(x, "timestamp")
  )
}

#' Format extract_model_info()$best_model_tune for printing
#'
#' @param best_tune character vector
#' @importFrom purrr map_chr
#' @return character vector for printing
#' @noRd
format_tune <- function(best_tune) {
  best_tune %>%
    purrr::map_chr(as.character) %>%
    paste(names(.), ., sep = " = ", collapse = "\n  ")
}

#' Class check
#' @param x object
#' @return logical
#' @export
is.model_list <- function(x) "model_list" %in% class(x)
#' Class check
#' @param x object
#' @return logical
#' @export
is.classification_list <- function(x) "classification_list" %in% class(x)
#' Class check
#' @param x object
#' @return logical
#' @export
is.regression_list <- function(x) "regression_list" %in% class(x)
