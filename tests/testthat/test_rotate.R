context("rotate")

dr <- tempdir()
td <- file.path(dr, "rotor")
dir.create(td, recursive = TRUE)

teardown({
  unlink(td, recursive = TRUE)
  if (!length(list.files(dr))) unlink(dr, recursive = TRUE)
})





test_that("backup/rotate happy path", {
  skip_if_not(is_zipcmd_available(), "system zip-command is available")

  tf <- file.path(td, "test.log")
  saveRDS(iris, tf)
  tf_size <- file.size(tf)
  bq <- BackupQueue$new(tf)

  # no backup because dry run
  expect_message(backup(tf, dry_run = TRUE), "dry_run")
  expect_identical(bq$n, 0L)

  # not rotating because file is to small
  backup(tf, size = 1e6)
  expect_identical(bq$n, 0L)

  # backup
  backup(tf, size = 1)
  expect_identical(bq$n, 1L)

  # backup (zip)
  backup(tf, compression = TRUE)
  expect_identical(bq$n, 2L)
  expect_identical(tools::file_ext(bq$files$path[[1]]), "zip")

  # rotating
  rotate(tf, compression = FALSE)
  expect_identical(bq$n, 3L)
  expect_equal(file.size(tf), 0)
  expect_equal(file.size(bq$files$path[[1]]), tf_size)
  expect_equal(bq$files$sfx, as.character(1:3))

  bq$prune(0)
  file.remove(tf)
  expect_length(list.files(td), 0)
})



test_that("backup/rotate works to different directory", {
  tf     <- file.path(td, "test.log")
  bu_dir <- file.path(td, "backups")
  dir.create(bu_dir)
  on.exit(unlink(c(bu_dir, tf)))

  file.create(tf)
  writeLines("foobar", tf)

  # dry run does nothing
  snap <- fileSnapshot(bu_dir)
  expect_message(backup(tf, dir = bu_dir, dry_run = TRUE))
  expect_snapshot_unchanged(snap)

  # create backup in different dir
  backup(tf, dir = bu_dir)
  expect_identical(
    readLines(tf),
    readLines(file.path(dirname(tf), "backups", "test.1.log"))
  )

  expect_identical(n_backups(tf, dir = bu_dir), 1L)
  prune_backups(tf, 0, dir = bu_dir)
  expect_identical(n_backups(tf, dir = bu_dir), 0L)
  expect_length(list.files(bu_dir), 0)
})




test_that("backup/rotate works with size", {
  tf     <- file.path(td, "test.log")
  on.exit(unlink(tf))
  saveRDS(iris, tf)
  size_ori <- file.size(tf)

  # dont rotate if file size is to small
  rotate(tf, size = "5kb")
  expect_identical(n_backups(tf), 0L)
  expect_equal(file.size(tf), size_ori)

  # dry run does nothing
  expect_message(rotate(tf, size = "0.5kb", dry_run = TRUE))
  expect_identical(n_backups(tf), 0L)
  expect_equal(file.size(tf), size_ori)

  # rotate if file size is big enough
  rotate(tf, size = "0.5kb")
  expect_identical(n_backups(tf), 1L)
  expect_equal(file.size(tf), 0)

  prune_backups(tf, 0)
})




test_that("backup/rotate dry_run", {
  tf <- file.path(td, "test.rds")
  on.exit(unlink(tf))
  snap <- utils::fileSnapshot(td)

  saveRDS(cars, tf)
  backup(tf)
  backup(tf)
  expect_message(backup(tf, dry_run = TRUE), "dry_run")
  expect_message(rotate(tf, dry_run = TRUE), "dry_run")

  expect_snapshot_unchanged(snap)
})




test_that("BackupQueueIndex: $prune_identical works", {
  tf <- file.path(td, "test")

  saveRDS(iris, tf)
  iris_md5 <- tools::md5sum(tf)
  bq <- BackupQueueIndex$new(tf)
  on.exit({
    bq$prune(0)
    unlink(tf)
  })
  backup(tf)
  backup(tf)
  rotate(tf)

  saveRDS(cars, tf)
  cars_md5 <- tools::md5sum(tf)
  backup(tf)
  saveRDS(cars, tf)
  rotate(tf)

  saveRDS(iris, tf)

  prune_identical_backups(tf)

  expect_identical(
    unname(tools::md5sum(bq$files$path)),
    unname(c(cars_md5, iris_md5))
  )
})
