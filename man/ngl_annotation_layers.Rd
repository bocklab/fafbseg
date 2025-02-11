% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/ng-annotations.R
\name{ngl_annotation_layers}
\alias{ngl_annotation_layers}
\title{Construct one or more neuroglancer annotation layers}
\usage{
ngl_annotation_layers(ann, rawcoords = NA, colpal = NULL)
}
\arguments{
\item{ann}{An annotation dataframe (see details) or any object containing 3D
vertices from which \code{\link{xyzmatrix}} can successfully extract
points.}

\item{rawcoords}{Whether points have been provided in raw (voxel) coordinates
or in calibrated (nm) positions. The default of \code{NA} will try to infer
this based on the coordinate values.}

\item{colpal}{A function or character vector of colour names that will be
used to set the colour for each layer.}
}
\value{
A list of additional class \code{nglayers} which can be added to an
  \code{ngscene} object as produced by \code{\link{ngl_decode_scene}}.
}
\description{
Construct one or more neuroglancer annotation layers
}
\details{
The \code{ann} arguments
}
\examples{
\dontrun{
psp=flywire_cave_query('proofreading_status_public_v1')
fwusers=googlesheets4::read_sheet('1G0zqA5DTrfd-a2LuebV4kcqNfl4q1ehlzHBrwT6ZMoc')
psp2=left_join(psp, fwusers, by=c("user_id"="id"))
psp2$layer=psp2$institution
al=ngl_annotation_layers(psp2[c("pt_position", "layer")])

}
}
\seealso{
\code{\link{ngl_annotations}}
}
