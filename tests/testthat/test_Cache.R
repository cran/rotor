context("Cache")


test_that("Cache works as expected", {
  td <- file.path(tempdir(), "cache-test")
  on.exit(unlink(td, recursive = TRUE))

  # cache can be created
  cache <- Cache$new(td)

  # put elements into the cache
  key1 <- cache$push(iris)
  key2 <- cache$push(cars)
  expect_identical(cache$n, 2L)

  # read elements from the cache
  expect_identical(cache$read(key1), iris)
  expect_identical(cache$read(key2), cars)

  # remove
  cache$remove(key1)
  expect_identical(cache$n, 1L)
  expect_error(cache$read(key1))

  # pop
  expect_error(cache$pop(key1))
  res <- cache$pop(key2)
  expect_identical(cache$n, 0L)
  expect_identical(res, cars)
})




test_that("setting hash functions work", {
  td <- file.path(tempdir(), "cache-test")
  on.exit(unlink(td, recursive = TRUE))

  # When using a real hash function as hashfun, identical objects will only
  # be added to the cache once
  cache_hash <- Cache$new(td, hashfun = digest::digest)
  cache_hash$push(iris)
  cache_hash$push(iris)
  expect_identical(cache_hash$n, 1L)
  cache_hash$purge()
  expect_identical(cache_hash$n, 0L)


  # To override this behaviour use a generate for unique ids, such as
  cache_uid <- Cache$new(td, hashfun = function(x) uuid::UUIDgenerate())
  cache_uid$push(iris)
  cache_uid$push(iris)
  expect_identical(cache_hash$n, 2L)
  cache_hash$purge()

  # ensure hashfun allways returns a scalar
  cache_err <- Cache$new(td, hashfun = function(x) uuid::UUIDgenerate(n = 2))
  expect_error(cache_err$push(iris), class = "ValueError")
})





test_that("pruning works by number of files works", {
  td <- file.path(tempdir(), "cache-test")
  on.exit(unlink(td, recursive = TRUE))

  # When using a real hash function as hashfun, identical objects will only
  # be added to the cache once
  cache <- Cache$new(td, hashfun = function(x) uuid::UUIDgenerate())
  k1 <- cache$push(iris)
  Sys.sleep(0.1)
  k2 <- cache$push(letters)
  Sys.sleep(0.1)
  k3 <- cache$push(cars)
  expect_identical(cache$n, 3L)

  cache$prune(max_files = 2)
  cache$files
  expect_identical(cache$read(cache$files$key[[1]]), letters)
  expect_identical(cache$read(cache$files$key[[2]]), cars)
  cache$purge()
})




test_that("pruning by size works", {
  td <- file.path(tempdir(), "cache-test")
  on.exit(unlink(td, recursive = TRUE))

  # When using a real hash function as hashfun, identical objects will only
  # be added to the cache once
  cache <- Cache$new(td, hashfun = function(x) uuid::UUIDgenerate())
  cache$push(iris)
  Sys.sleep(0.1)
  cache$push(iris)
  Sys.sleep(0.1)
  cache$push(iris)
  Sys.sleep(0.1)
  cache$push(iris)
  Sys.sleep(0.1)
  cache$push(iris)
  Sys.sleep(0.1)
  cache$push(cars)
  expect_identical(cache$n, 6L)

  expect_true(cache$size > 2048)
  cache$prune(max_size = "2kb")
  expect_true(cache$size <= 2048)

  cache$prune(max_files = 2)
  expect_identical(cache$read(cache$files$key[[2]]), cars)
  cache$purge
})




test_that("Inf max_* do not prunes", {
  td <- file.path(tempdir(), "cache-test")
  on.exit(unlink(td, recursive = TRUE))

  # When using a real hash function as hashfun, identical objects will only
  # be added to the cache once
  cache <- Cache$new(td, hashfun = function(x) uuid::UUIDgenerate())
  cache$push(iris)
  Sys.sleep(0.1)
  cache$push(iris)
  Sys.sleep(0.1)
  cache$push(iris)
  Sys.sleep(0.1)
  cache$push(iris)
  Sys.sleep(0.1)
  cache$push(iris)
  Sys.sleep(0.1)
  cache$push(cars)
  expect_identical(cache$n, 6L)

  cache$prune(max_files = Inf, max_age = Inf, max_size = Inf)
  expect_identical(cache$n, 6L)

  cache$prune(max_files = NULL, max_age = NULL, max_size = NULL)
  expect_identical(cache$n, 6L)

  cache$purge()
})




test_that("pruning by age works", {
  td <- file.path(tempdir(), "cache-test")
  on.exit(unlink(td, recursive = TRUE))


  # create mock class that always
  MockCache <-  R6::R6Class(
    inherit = Cache,

    public = list(
      mock_timestamp = NULL
    ),

    active = list(
      files = function(){
        files <- list.files(self$dir, full.names = TRUE)

        if (!length(files)){
          return(EMPTY_CACHE_INDEX)
        }

        finfo <- file.info(files)

        res <- cbind(
          data.frame(path = rownames(finfo), stringsAsFactors = FALSE),
          data.frame(key = basename(rownames(finfo)), stringsAsFactors = FALSE),
          finfo
        )

        if (!is.null(self$mock_timestamp)){
          assert(length(self$mock_timestamp) >= nrow(res))
          res$atime <- res$ctime <- res$mtime <- self$mock_timestamp[1:nrow(res)]
        }

        row.names(res) <- NULL

        res[order(res$mtime), ]
      }
    )
  )

  cache <- MockCache$new(td, hashfun = function(x) uuid::UUIDgenerate())
  on.exit(cache$purge, add = TRUE)
  cache$push(iris)
  Sys.sleep(0.1)
  cache$push(iris)
  Sys.sleep(0.1)
  cache$push(iris)
  Sys.sleep(0.1)
  cache$push(iris)
  Sys.sleep(0.1)
  cache$push(iris)
  Sys.sleep(0.1)

  cache$mock_timestamp <- as.POSIXct(c(
    "2020-01-01",
    "2020-01-02",
    "2020-01-03",
    "2020-01-04",
    "2020-01-05"
  ))
  keep <- cache$files$key[2:5]
  cache$prune(max_age = "2020-01-02")
  expect_setequal(cache$files$key, keep)

  cache$mock_timestamp <- as.POSIXct(c(
    Sys.Date() - 0:4
  ))

  keep <- cache$files$key[3:4]
  cache$prune(max_age = "2 days", now = max(cache$files$mtime))
  expect_setequal(cache$files$key, keep)

  expect_error(
    cache$prune(max_age = "2 foos", now = max(cache$files$mtime)),
    class = "ValueError"
  )
})



test_that("$destroy works as expected", {
  td <- file.path(tempdir(), "cache-test")
  on.exit(unlink(td, recursive = TRUE))

  # cache can be created
  cache <- Cache$new(td)

  # put elements into the cache
  key1 <- cache$push(iris)
  key2 <- cache$push(cars)
  expect_identical(cache$n, 2L)

  expect_error(cache$destroy(), class = "DirIsNotEmptyError")
  cache$purge()$destroy()
  expect_false(dir.exists(cache$dir))
  expect_error(cache$push(iris), class = "DirDoesNotExistError")
})
