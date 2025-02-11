check_cave <- memoise::memoise(function(min_version=NULL) {
  check_reticulate()
  tryCatch(
    cv <- reticulate::import("caveclient"),
    error = function(e) {
      stop(
        call. = F,
        "Please install the python caveclient package:\n",
        "This should normally work:\n",
        "fafbseg::simple_python('full')\n",
        "For more details see ?simple_python"
      )
    }
  )
  if(!is.null(min_version)) {
    warning("min_version not yet implemented for caveclient")
  #   cvv=numeric_version(cloudvolume_version())
  #   if(!isTRUE(cvv >= min_version))
  #     stop("You need cloudvolume version: ", min_version, " but you have: ", cvv,
  #          "\n  Please update e.g. using\n",
  #          "fafbseg::simple_python('basic')")
  }
  cv
})



#' Low level access to the Flywire CAVE annotation system
#'
#' @details This depends on installation of the Python caveclient library. See
#'   \code{\link{flywire_cave_query}} for more details.
#' @param datastack_name defaults to "flywire_fafb_production". See
#'   \url{https://global.daf-apis.com/info/} for other options.
#' @return The \code{caveclient.frameworkclient.CAVEclientFull} Python module
#'   wrapped by reticulate.
#' @export
#'
#' @examples
#' \donttest{
#' fac <- flywire_cave_client()
#' fac$annotation$get_tables()
#' fac$annotation$get_table_metadata('nuclei_v1')
#'
#' # annotation tables that have been materialised in order to map XYZ
#' # points onto current root ids (and immutable supervoxel ids)
#' # typically the same as fac$annotation$get_tables()
#' fac$materialize$get_tables()
#'
#' info=fac$info$get_datastack_info()
#' # the default synapse table for the dataset
#' info$synapse_table
#' }
flywire_cave_client <- memoise::memoise(function(datastack_name = getOption("fafbseg.cave.datastack_name", "flywire_fafb_production")) {
  cavec=check_cave()
  client = cavec$CAVEclient(datastack_name)
}, ~memoise::timeout(12*3600))

#' Query the FlyWire CAVE annotation system
#'
#' @details CAVE (Connectome Annotation Versioning Engine) provides a shared
#'   infrastructure for a number of connectomics projects involving Sebastian
#'   Seung's group at Princeton and collaborators at the Allen Institute. There
#'   is both a backend system running on their servers and a Python client for
#'   end users.
#'
#'   You can find out more at \url{https://caveclient.readthedocs.io/} as well
#'   as looking at the Python notebooks on the github repo
#'   \url{https://github.com/seung-lab/CAVEclient}.
#'
#'   The annotation system shares authentication infrastructure with the rest of
#'   the FlyWire API (see \code{\link{flywire_set_token}}).
#'
#'   CAVE has a concept of table snapshots identified by an integer
#'   \code{materialization_version} number. In some cases you may wish to query
#'   a table at this defined version number so that you can avoid root_ids
#'   changing during an analysis. Your calls will also be faster since no root
#'   id updates are required.
#'
#' @param table The name of the table to query
#' @param live Whether to use live query mode, which updates any root ids to
#'   their current value.
#' @param materialization_version An optional CAVE materialisation version
#'   number. See details and examples.
#' @param ... Additional arguments to the query method. See examples and
#'   details.
#' @inheritParams flywire_cave_client
#'
#' @return A \code{tibble}. Note that xyzmatrix can be used on single columns
#'   containing XYZ locations.
#' @export
#' @seealso \code{\link{flywire_cave_client}}
#' @examples
#' \donttest{
#' # note use of limit to restrict the number of rows
#' n10=flywire_cave_query(table = 'nuclei_v1', limit=10)
#' head(as.data.frame(n10))
#' }
#' \dontrun{
#' nuclei_v1=flywire_cave_query(table = 'nuclei_v1')
#' points3d(xyzmatrix(nuclei_v1$pt_position))
#'
#' library(elmr)
#' # calculate signed distance to FAFB surface
#' # NB this surface is not a perfect fit in the optic lobes
#' nuclei_v1$d=pointsinside(xyzmatrix(nuclei_v1$pt_position), FAFB.surf,
#'   rval = 'dist')
#' points3d(xyzmatrix(nuclei_v1$pt_position),
#'   col=matlab::jet.colors(20)[cut(nuclei_v1$d,20)])
#' plot3d(FAFB)
#' }
#'
#' \dontrun{
#' psp_351=flywire_cave_query(table = 'proofreading_status_public_v1',
#'   materialization_version=351)
#' # get the last listed materialisation version
#' fcc=flywire_cave_client()
#' lastv=tail(fcc$materialize$get_versions(), n=1)
#' # pull that
#' psp_last=flywire_cave_query(table = 'proofreading_status_public_v1',
#'   materialization_version=lastv)
#' }
flywire_cave_query <- function(table,
                               datastack_name = getOption("fafbseg.cave.datastack_name", "flywire_fafb_production"),
                               materialization_version=NULL,
                               live=is.null(materialization_version),
                               ...) {
  if(isTRUE(live) && !is.null(materialization_version))
    warning("live=TRUE so ignoring materialization_version")

  check_package_available('arrow')
  fac=flywire_cave_client(datastack_name=datastack_name)
  # Live query updates ids
  # materialization_version=materialization_version
  annotdf <- if(live) {
    ts=format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6", tz="UTC")
    reticulate::py_call(fac$materialize$live_query, table=table, timestamp=ts, ...)
  } else {
    reticulate::py_call(fac$materialize$query_table, table=table,
                        materialization_version=as.integer(materialization_version), ...)
  }
  pandas2df(annotdf)
}

cavedict_rtopy <- function(dict) {
  # CAVE wants each entry should be a list and ids to be by ints
  for (i in seq_along(dict)) {
    if (all(is.integer64(dict[[i]])) || all(valid_id(dict[[i]])))
      dict[[i]]=rids2pyint(unlist(dict[[i]]))
    else if (!is.list(dict[[i]]))
      dict[[i]]=as.list(dict[[i]])
  }
  checkmate::check_names(names(dict), type = 'unique')
  pydict=reticulate::r_to_py(dict, convert = F)
  pydict
}

flywire_partners_cave <- function(rootid, partners=c("outputs", "inputs"),
                                  cleft.threshold=0,
                                  datastack_name = getOption("fafbseg.cave.datastack_name", "flywire_fafb_production"),
                                  synapse_table=NULL,
                                  fafbseg_colnames=TRUE, ...) {
  checkmate::assert_integerish(cleft.threshold,
                               lower = 0L, upper = 255L, len = 1)
  partners=match.arg(partners)
  fac=flywire_cave_client(datastack_name=datastack_name)
  if(is.null(synapse_table)) {
    synapse_table=fac$info$get_datastack_info()[['synapse_table']]
    if(!isTRUE(nzchar(synapse_table)))
      stop("Unable to identify synapse table for datastack: ", datastack_name)
  }
  dict=list(as.list(as.character(rootid)))
  names(dict)=ifelse(partners=="outputs", "pre_pt_root_id", "post_pt_root_id")
  res=flywire_cave_query(datastack_name = datastack_name,
                         table = synapse_table,
                         filter_in_dict=cavedict_rtopy(dict),
                         ...)
  # FIXME - integrate into CAVE query
  if(cleft.threshold>0)
    res=res[res$cleft_score>cleft.threshold,,drop=FALSE]

  if(fafbseg_colnames) {
    colnames(res)[1]='offset'
    colnames(res)=sub("pt_supervoxel_id", "svid", colnames(res))
    colnames(res)=sub("pt_root_id", "id", colnames(res))
    colnames(res)[colnames(res)=='connection_score']='scores'
    colnames(res)[colnames(res)=='cleft_score']='cleft_scores'
  }
  res
}

# retained in case it is useful somewhere else ...
update_rootids <- function(rootids, svids) {
  stopifnot(bit64::is.integer64(rootids))
  stopifnot(bit64::is.integer64(svids))
  outofdate=!flywire_islatest(rootids)
  if(any(outofdate)) {
    rootids[outofdate]=flywire_rootid(svids[outofdate], integer64 = TRUE)
  }
  rootids
}


cave_latestid <- function(rootid, integer64=FALSE,
                           datastack_name = getOption("fafbseg.cave.datastack_name", "flywire_fafb_production")) {
  fac=flywire_cave_client(datastack_name=datastack_name)
  rid=ngl_segments(rootid, as_character=T)
  if(length(rid)!=1 || !valid_id(rid))
    stop("cave_latestid expects a single valid rootid")
  # get a single python int via a python list
  pyids=rids2pyint(rid)
  pyid=pyids[0]
  res=reticulate::py_call(fac$chunkedgraph$get_latest_roots, pyid)
  newids=pyids2bit64(res, as_character = !integer64)
  newids
}


ts2pydatetime <- function(x) {
  dt=reticulate::import('datetime')
  x2=strftime(as.POSIXlt(x, origin='1970-01-01', "UTC"), "%Y-%m-%dT%H:%M:%S")
  reticulate::py_call(dt$datetime$fromisoformat, x2)
}

# a function to return a python function!
# memoisation saves a few ms
pyslice <- memoise::memoise(function() {
  reticulate::py_run_string(local = T, paste0(
    "def pyslice(x,i):\n",
    "  return x[i]\n",
    "\n"))
})

cave_get_delta_roots <- function(timestamp_past, timestamp_future=Sys.time()) {
  fcc = flywire_cave_client()
  if (is.numeric(timestamp_future))
    timestamp_future = Sys.time() + timestamp_future
  if (is.numeric(timestamp_past))
    timestamp_past = timestamp_future + timestamp_past
  res = tryCatch(
    reticulate::py_call(
      fcc$chunkedgraph$get_delta_roots,
      timestamp_past = ts2pydatetime(timestamp_past),
      timestamp_future = ts2pydatetime(timestamp_future)
    ),
    error = function(e) {
      warning(e)
      list(old = character(), new = character())
    }
  )
  pyslice <- pyslice()$pyslice
  resl <- if (is.list(res))
    res
  else
    list(old = pyids2bit64(reticulate::py_call(pyslice, res, 0L)),
         new = pyids2bit64(reticulate::py_call(pyslice, res, 1L)))
  attr(resl, 'timestamp_past') = timestamp_past
  attr(resl, 'timestamp_future') = timestamp_future
  resl
}
