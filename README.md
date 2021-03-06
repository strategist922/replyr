
<!-- README.md is generated from README.Rmd. Please edit that file -->
This document describes `replyr`, an [R](https://cran.r-project.org) package available from [Github](https://github.com/WinVector/replyr) and [CRAN](https://CRAN.R-project.org/package=replyr).

Introduction
------------

It comes as a bit of a shock for [R](https://cran.r-project.org) [`dplyr`](https://CRAN.R-project.org/package=dplyr) users when they switch from using a `tbl` implementation based on R in-memory `data.frame`s to one based on a remote database or service. A lot of the power and convenience of the `dplyr` notation is hard to maintain with these more restricted data service providers. Things that work locally can't always be used remotely at scale. It is emphatically not yet the case that one can practice with `dplyr` in one modality and hope to move to another back-end without significant debugging and work-arounds. The [`replyr`](https://github.com/WinVector/replyr) package attempts to provide practical data manipulation affordances to make code perform similarly on local or remote (big) data.

Note: `replyr` is meant only for "tame data frames" that is data frames with non-duplicate column names that are also valid *simple* (without quotes) `R` variables names and columns that are `R` simple vector types (numbers, strings, and such).

![](https://github.com/WinVector/replyr/raw/master/tools/replyrs.png)

`replyr` supplies methods to get a grip on working with remote `tbl` sources (`SQL` databases, `Spark`) through `dplyr`. The idea is to add convenience functions to make such tasks more like working with an in-memory `data.frame`. Results still do depend on which `dplyr` service you use, but with `replyr` you have fairly uniform access to some useful functions.

`replyr` uniformly uses standard or parametric interfaces (names of variables as strings) in favor of name capture so that you can easily program *over* `replyr`.

Primary `replyr` services include:

-   `wrapr::let`
-   `replyr::replyr_apply_f_mapped`
-   `replyr::replyr_split`
-   `replyr::replyr_bind_rows`
-   `replyr::gapply`
-   `replyr::replyr_summary`
-   `replyr::replyr_moveValuesToRows`
-   `replyr::replyr_moveValuesToColumns`
-   `replyr::replyr_*`

`wrapr::let`
------------

`wrapr::let` allows execution of arbitrary code with substituted variable names (note this is subtly different than binding values for names as with `base::substitute` or `base::with`). This allows the user to write arbitrary `dplyr` code in the case of ["parametric variable names"](http://www.win-vector.com/blog/2016/12/parametric-variable-names-and-dplyr/) (that is when variable names are not known at coding time, but will become available later at run time as values in other variables) without directly using the `dplyr` "underbar forms" (and the direct use of `lazyeval::interp`, `.dots=stats::setNames`, or `rlang`/`tidyeval`).

Example:

``` r
library('dplyr')
```

``` r
# nice parametric function we write
ComputeRatioOfColumns <- function(d,
                                  NumeratorColumnName,
                                  DenominatorColumnName,
                                  ResultColumnName) {
  wrapr::let(
    alias=list(NumeratorColumn=NumeratorColumnName,
               DenominatorColumn=DenominatorColumnName,
               ResultColumn=ResultColumnName),
    expr={
      # (pretend) large block of code written with concrete column names.
      # due to the let wrapper in this function it will behave as if it was
      # using the specified paremetric column names.
      d %>% mutate(ResultColumn = NumeratorColumn/DenominatorColumn)
    })
}

# example data
d <- data.frame(a=1:5, b=3:7)

# example application
d %>% ComputeRatioOfColumns('a','b','c')
 #    a b         c
 #  1 1 3 0.3333333
 #  2 2 4 0.5000000
 #  3 3 5 0.6000000
 #  4 4 6 0.6666667
 #  5 5 7 0.7142857
```

`wrapr::let` makes construction of abstract functions over `dplyr` controlled data much easier. It is designed for the case where the "`expr`" block is large sequence of statements and pipelines.

`wrapr::let` is based on `gtools::strmacro` by Gregory R. Warnes.

`replyr::replyr_apply_f_mapped`
-------------------------------

`wrapr::let` was only the secondary proposal in the original [2016 "Parametric variable names" article](http://www.win-vector.com/blog/2016/12/parametric-variable-names-and-dplyr/). What we really wanted was a stack of view so the data pretended to have names that matched the code (i.e., re-mapping the data, not the code).

With a bit of thought we can achieve this if we associate the data re-mapping with a function environment instead of with the data. So a re-mapping is active as long as a given controlling function is in control. In our case that function is `replyr::replyr_apply_f_mapped()` and works as follows:

Suppose the operation we wish to use is a rank-reducing function that has been supplied as function from somewhere else that we do not have control of (such as a package). The function could be simple such as the following, but we are going to assume we want to use it without alteration (including the without the small alteration of introducing `wrapr::let()`).

``` r
# an external function with hard-coded column names
DecreaseRankColumnByOne <- function(d) {
  d$RankColumn <- d$RankColumn - 1
  d
}
```

To apply this function to `d` (which doesn't have the expected column names!) we use `replyr::replyr_apply_f_mapped()` to create a new parametrized adapter as follows:

``` r
# our data
d <- data.frame(Sepal_Length = c(5.8,5.7),
                Sepal_Width = c(4.0,4.4),
                Species = 'setosa',
                rank = c(1,2))

# a wrapper to introduce parameters
DecreaseRankColumnByOneNamed <- function(d, ColName) {
  replyr::replyr_apply_f_mapped(d, 
                                f = DecreaseRankColumnByOne, 
                                nmap = c(RankColumn = ColName),
                                restrictMapIn = FALSE, 
                                restrictMapOut = FALSE)
}

# use
dF <- DecreaseRankColumnByOneNamed(d, 'rank')
print(dF)
 #    Sepal_Length Sepal_Width Species rank
 #  1          5.8         4.0  setosa    0
 #  2          5.7         4.4  setosa    1
```

`replyr::replyr_apply_f_mapped()` renames the columns to the names expected by `DecreaseRankColumnByOne` (the mapping specified in `nmap`), applies `DecreaseRankColumnByOne`, and then inverts the mapping before returning the value.

`replyr::replyr_split`
----------------------

`replyr::replyr_split` and `replyr::replyr_bind_rows` work over many remote data types including `Spark`. This allows code like the following:

``` r
suppressPackageStartupMessages(library("dplyr"))
library("replyr")
sc <- sparklyr::spark_connect(version='2.0.2', 
                              master = "local")
                              
diris <- copy_to(sc, iris, 'diris')

f2 <- . %>% 
  arrange(Sepal_Length, Sepal_Width, Petal_Length, Petal_Width) %>%
  head(2)

diris %>% 
  replyr_split('Species') %>%
  lapply(f2) %>%
  replyr_bind_rows()

## Source:   query [6 x 5]
## Database: spark connection master=local[4] app=sparklyr local=TRUE
## 
## # A tibble: 6 x 5
##      Species Sepal_Length Sepal_Width Petal_Length Petal_Width
##        <chr>        <dbl>       <dbl>        <dbl>       <dbl>
## 1 versicolor          5.0         2.0          3.5         1.0
## 2 versicolor          4.9         2.4          3.3         1.0
## 3     setosa          4.3         3.0          1.1         0.1
## 4     setosa          4.4         2.9          1.4         0.2
## 5  virginica          4.9         2.5          4.5         1.7
## 6  virginica          5.6         2.8          4.9         2.0

sparklyr::spark_disconnect(sc)
```

`replyr::gapply`
----------------

`replyr::gapply` is a "grouped ordered apply" data operation. Many calculations can be written in terms of this primitive, including per-group rank calculation (assuming your data services supports window functions), per-group summaries, and per-group selections. It is meant to be a specialization of ["The Split-Apply-Combine"](https://www.jstatsoft.org/article/view/v040i01) strategy with all three steps wrapped into a single operator.

Example:

``` r
library('dplyr')
```

``` r
d <- data.frame(group=c(1,1,2,2,2),
                order=c(.1,.2,.3,.4,.5))
rank_in_group <- . %>% mutate(constcol=1) %>%
          mutate(rank=cumsum(constcol)) %>% select(-constcol)
d %>% replyr::gapply('group', rank_in_group, ocolumn='order', decreasing=TRUE)
 #    group order rank
 #  1     1   0.2    1
 #  2     1   0.1    2
 #  3     2   0.5    1
 #  4     2   0.4    2
 #  5     2   0.3    3
```

The user supplies a function or pipeline that is meant to be applied per-group and the `replyr::gapply` wrapper orchestrates the calculation. In this example `rank_in_group` was assumed to know the column names in our data, so we directly used them instead of abstracting through `wrapr::let`. `replyr::gapply` defaults to using `dplyr::group_by` as its splitting or partitioning control, but can also perform actual splits using 'split' ('base::split') or 'extract' (sequential extraction). Semantics are slightly different between cases given how `dplyr` treats grouping columns, the issue is illustrated in the difference between the definitions of `sumgroupS` and `sumgroupG` in [this example](https://github.com/WinVector/replyr/blob/master/checks/gapply.md)).

`replyr::replyr_*`
------------------

The `replyr::replyr_*` functions are all convenience functions supplying common functionality (such as `replyr::replyr_nrow`) that works across many data services providers. These are prefixed (instead of being `S3` or `S4` methods) so they do not interfere with common methods. Many of these functions can expensive (which is why `dplyr` does not provide them as a default), or are patching around corner cases (which is why these functions appear to duplicate `base::` and `dplyr::` capabilities). The issues `replyr::replyr_*` claim to patch around have all been filed as issues on the appropriate `R` packages and are documented [here](https://github.com/WinVector/replyr/tree/master/issues) (to confirm they are not phantoms).

Example: `replyr::replyr_summary` working on a database service (when `base::summary` does not).

``` r
d <- data.frame(x=c(1,2,2),y=c(3,5,NA),z=c(NA,'a','b'),
                stringsAsFactors = FALSE)
if (requireNamespace("RSQLite")) {
  my_db <- dplyr::src_sqlite(":memory:", create = TRUE)
  dRemote <- replyr::replyr_copy_to(my_db,d,'d')
} else {
  dRemote <- d # local stand in when we can't make remote
}
 #  Loading required namespace: RSQLite

summary(dRemote)
 #      Length Class          Mode
 #  src 2      src_dbi        list
 #  ops 2      op_base_remote list

replyr::replyr_summary(dRemote)
 #    column index     class nrows nna nunique min max     mean        sd lexmin lexmax
 #  1      x     1   numeric     3   0      NA   1   2 1.666667 0.5773503   <NA>   <NA>
 #  2      y     2   numeric     3   1      NA   3   5 4.000000 1.4142136   <NA>   <NA>
 #  3      z     3 character     3   1      NA  NA  NA       NA        NA      a      b
```

Data types, capabilities, and row-orders all vary a lot as we switch remote data services. But the point of `replyr` is to provide at least some convenient version of typical functions such as: `summary`, `nrow`, unique values, and filter rows by values in a set.

`replyr` Data services
----------------------

This is a *very* new package with no guarantees or claims of fitness for purpose. Some implemented operations are going to be slow and expensive (part of why they are not exposed in `dplyr` itself).

We will probably only ever cover:

-   Native `data.frame`s (and `tbl`/`tibble`)
-   `sparklyr` (`Spark` 2.0.0 or greater)
-   `RPostgreSQL`
-   `SQLite`
-   `RMySQL` (limited support in some cases)

Additional functions
--------------------

Additional `replyr` functions include:

-   `replyr::replyr_filter`
-   `replyr::replyr_inTest`

These are designed to subset data based on a columns values being in a given set. These allow selection of rows by testing membership in a set (very useful for partitioning data). Example below:

``` r
library('dplyr')
```

``` r
values <- c(2)
dRemote %>% replyr::replyr_filter('x', values)
 #  # Source:   table<replyr_filter_0dn6qn1zs5tap33dwnon_0000000001> [?? x 3]
 #  # Database: sqlite 3.19.3 [:memory:]
 #        x     y     z
 #    <dbl> <dbl> <chr>
 #  1     2     5     a
 #  2     2    NA     b
```

Commentary
----------

I would like this to become a bit of a ["stone soup"](https://en.wikipedia.org/wiki/Stone_Soup) project. If you have a neat function you want to add please contribute a pull request with your attribution and assignment of ownership to [Win-Vector LLC](http://www.win-vector.com/) (so Win-Vector LLC can control the code, which we are currently distributing under a GPL3 license) in the code comments.

There are a few (somewhat incompatible) goals for `replyr`:

-   Providing missing convenience functions that work well over all common `dplyr` service providers. Examples include `replyr_summary`, `replyr_filter`, and `replyr_nrow`.
-   Providing a basis for "row number free" data analysis. SQL back-ends don't commonly supply row number indexing (or even deterministic order of rows), so a lot of tasks you could do in memory by adjoining columns have to be done through formal key-based joins.
-   Providing emulations of functionality missing from non-favored service providers (such as windowing functions, `quantile`, `sample_n`, `cumsum`; missing from `SQLite` and `RMySQL`).
-   Working around corner case issues, and some variations in semantics.
-   Sheer bull-headedness in emulating operations that don't quite fit into the pure `dplyr` formulation.

Good code should fill one important gap and work on a variety of `dplyr` back ends (you can test `RMySQL`, and `RPostgreSQL` using docker as mentioned [here](http://www.win-vector.com/blog/2016/11/mysql-in-a-container/) and [here](http://www.win-vector.com/blog/2016/02/databases-in-containers/); `sparklyr` can be tried in local mode as described [here](http://spark.rstudio.com)). I am especially interested in clever "you wouldn't thing this was efficiently possible, but" solutions (which give us an expanded grammar of useful operators), and replacing current hacks with more efficient general solutions. Targets of interest include `sample_n` (which isn't currently implemented for `tbl_sqlite`), `cumsum`, and `quantile` (currently we have an expensive implementation of `quantile` based on binary search: `replyr::replyr_quantile`).

`replyr` services include:

-   Moving data into or out of the remote data store (including adding optional row numbers), `replyr_copy_to` and `replyr_copy_from`.
-   Basic summary info: `replyr_nrow`, `replyr_dim`, and `replyr_summary`.
-   Random row sampling (like `dplyr::sample_n`, but working with more service providers). Some of this functionality is provided by `replyr_filter` and `replyr_inTest`.
-   Emulating [The Split-Apply-Combine Strategy](https://www.jstatsoft.org/article/view/v040i01), which is the purpose `gapply`, `replyr_split`, and `replyr_bind_rows`.
-   Emulating `tidyr` gather/spread (or pivoting and anti-pivoting).
-   Patching around differences in `dplyr` services providers (and documenting the reasons for the patches).
-   Making use of "parameterized names" much easier (that is: writing code does not know the name of the column it is expected to work over, but instead takes the column name from a user supplied variable).

Additional desired capabilities of interest include:

-   `cumsum` or row numbering (interestingly enough if you have row numbering you can implement cumulative sum in log-n rounds using joins to implement pointer chasing/jumping ideas, but that is unlikely to be practical, `lag` is enough to generate next pointers, which can be boosted to row-numberings).
-   Inserting random values (or even better random unique values) in a remote column. Most service providers have a pseudo-random source you can use.

Conclusion
----------

`replyr` is package for speeding up reliable data manipulation using `dplyr` (especially on databases and `Spark`). It is also a good central place to collect patches and fixes needed to work around corner cases and semantic variations between versions of data sources.

Dev version
-----------

If you want to try the newest version of `replyr` you can use `devtools` to install directly from GitHub with:

``` r
devtools::install_github('WinVector/replyr')
```

Clean up
--------

``` r
rm(list=ls())
gc()
 #  Auto-disconnecting SQLiteConnection
 #            used (Mb) gc trigger (Mb) max used (Mb)
 #  Ncells  684002 36.6    1168576 62.5   940480 50.3
 #  Vcells 1382712 10.6    2552219 19.5  1639813 12.6
```
