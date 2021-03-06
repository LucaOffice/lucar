% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/get_participant_summary.R
\name{get_participant_summary}
\alias{get_participant_summary}
\title{Getting the General Participation Information}
\usage{
get_participant_summary(json_data, workflow, debug_mode = FALSE)
}
\arguments{
\item{json_data}{The log data for a single participation in form of a json object}

\item{workflow}{The prepared data from the workflow of the participant}

\item{debug_mode}{If TRUE the internal hash IDs for the project elements are included and no module specific data is returned.}
}
\value{
A dataframe (consisting of one row) including general information for a single participation
}
\description{
Takes the log data and the already prepared workflow data from a single participant
and returns a dataframe including a single line with general information of the participation.
}
\examples{
\dontrun{
json_file = "participation_logdata.json"
json_data <- rjson::fromJSON(json_file)
workflow <- get_workflow(json_data, module_specific=TRUE)
participation_data <- get_participation_data(json_data, workflow)
}

}
