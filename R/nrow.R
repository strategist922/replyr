
# Contributed by John Mount jmount@win-vector.com , ownership assigned to Win-Vector LLC.
# Win-Vector LLC currently distributes this code without intellectual property indemnification, warranty, claim of fitness of purpose, or any other guarantee under a GPL3 license.

#' @importFrom dplyr ungroup summarize transmute
NULL

#' Check if a table has rows.
#'
#' @param d tbl or item that can be coerced into such.
#' @return number of rows
#'
#' @examples
#'
#' d <- data.frame(x=c(1,2))
#' replyr_hasrows(d)
#'
#' @export
replyr_hasrows <- function(d) {
  if(is.null(d)) {
    return(FALSE)
  }
  # get empty corner case correct (counting returned NA on PostgreSQL for this)
  # had problems with head(n=1) on sparklyr
  # https://github.com/WinVector/replyr/blob/master/issues/HeadIssue.md
  suppressWarnings(
    dSample <- d %.>%
      dplyr::ungroup(.) %.>%
      head(.) %.>%
      dplyr::collect(.) %.>%
      as.data.frame(.))
  if( is.null(dSample) || is.null(nrow(dSample)) || (nrow(dSample)<1)) {
    return(FALSE)
  }
  return(TRUE)
}

#' Compute number of rows of a tbl.
#'
#' Number of row in a table.  This function is not "group aware" it returns the total number of rows, not rows per dplyr group.
#' Also \code{replyr_nrow} depends on data being returned to count, so some corner cases (such as zero columns) will count as zero rows.
#'
#' @param x tbl or item that can be coerced into such.
#' @return number of rows
#'
#' @examples
#'
#' d <- data.frame(x=c(1,2))
#' replyr_nrow(d)
#'
#' @export
replyr_nrow <- function(x) {
  if(!replyr_hasrows(x)) {
    return(0)
  }
  # try for easy case
  n <- nrow(x)
  if(!is.na(n)) {
    return(n)
  }
  # get rid of raw columns
  # nrow() not supported in dbplyr/sparklyr world: http://www.win-vector.com/blog/2017/08/why-to-use-the-replyr-r-package/
  # previous mutate impl was erroring out: https://github.com/tidyverse/dplyr/issues/3069
  # and using tally directly is bad: https://github.com/tidyverse/dplyr/issues/3070
  # and this issue is a problem: https://github.com/tidyverse/dplyr/issues/3071
  constant <- NULL # make obvious this is not an unbound reference
  ctab <- x %.>%
    dplyr::ungroup(.) %.>%
    dplyr::transmute(., constant = 1.0) %.>%  # collumn we can count, not named n
    dplyr::summarize(., count = sum(constant)) %.>%
    dplyr::collect(.)  %.>% # I forget if pull is in dplyr 0.5.0
    as.data.frame(.)
  ctab[1,1,drop=TRUE]
}

