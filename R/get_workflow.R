#' Getting the workflow data from a single participation
#'
#' Takes the log data from a single participation and returns a list describing the workflow.
#'
#' @param json_data The log data for a single participation in form of a nested list
#' @param module_specific If TRUE the workflow is split into separate lists for each module element
#' @param idle_time Numeric describing after how many seconds an event is considered as idle.
#' @param mail_recipient_codes A tibble including previously assigned mail recipients and their codes
#' @param event_codes Dataframe with the workflow coding that is used to structure the log data
#' @param tool_codes Dataframe with the tool coding that is used to assign each used tool to a common code
#' @param debug_mode If TRUE the internal hash IDs for the project elements and additional lower level data are included
#'
#' @return A list including the workflow data
#'
#' @examples
#' \dontrun{
#' json_file = "participation_logdata.json"
#' json_data <- rjson::fromJSON(file=json_file)
#' workflow <- get_workflow(json_data)
#' }
#'
#' @importFrom dplyr %>%
#' @importFrom dplyr as_tibble
#' @importFrom dplyr rename_with
#' @importFrom dplyr mutate
#' @importFrom dplyr across
#' @importFrom tidyr unnest_wider
#' @importFrom dplyr left_join
#' @importFrom dplyr select
#' @importFrom lubridate as_datetime
#' @importFrom dplyr filter
#' @importFrom plyr mapvalues
#' @importFrom rlang syms
#' @importFrom dplyr slice
#' @importFrom dplyr arrange
#' @importFrom tibble add_column
#' @importFrom dplyr coalesce
get_workflow <- function (json_data, module_specific=TRUE, idle_time=20, mail_recipient_codes=tibble(recipient=character(), code=character()), event_codes=lucar::event_codes, tool_codes=lucar::tool_codes, debug_mode=FALSE) {


  # TODO: Completing the data column for not yet considered events


  # return empty list if no events were recorded
  if (length(json_data$surveyEvents)==0) {
    return(list(mail_recipient_codes=mail_recipient_codes))
  }

  # formatting the events into a tibble
  participant_events <-
    # transforming nested list into a iibble
    dplyr::as_tibble(data.frame(matrix(unlist(json_data$surveyEvents, recursive=FALSE), nrow=length(json_data$surveyEvents), byrow=TRUE))) %>%
    # retrieving original column names
    dplyr::rename_with(~names(json_data$surveyEvents[[1]])) %>%
    # unnest columns provided in lists
    dplyr::mutate(across(c(timestamp, eventType, index), ~sapply(.x, function(x) x[[1]]))) %>%
    # rename column
    dplyr::mutate(event_type=eventType)

  # get all project modules and the corresponding hash IDs
  project_modules <- get_project_modules(json_data, hash_ids=TRUE)

  # get all project elements and their respective event codes
  project_elements <- get_project_elements(json_data, hash_ids=TRUE)

  # get all mail recipients the participant was starting an email and add them to the received mail_codes if they were not included yet
  mail_recipient_codes <- add_mail_recipients(participant_events, mail_recipient_codes)

  # Construction of a helper dataframe that includes all variables used from the nested JSON data structure
  # it is needed to add missing variables to the temporary dataframe of the workflow (e.g. if some events did not occur for the given participant)
  # without adding the variables the values for the data column prepared later would not run through
  needed_variables <- data.frame(message=NA_character_, content=NA_character_, value=NA_character_, text=NA_character_, mimeType=NA_character_,
                                 spreadsheetTitle=NA_character_, binaryFileTitle=NA_character_, startCellName=NA_character_,
                                 endCellName=NA_character_, cellName=NA_character_, to=NA_character_, cc=NA_character_, subject=NA_character_,
                                 tool=NA_character_, directory=NA_character_, endType=NA_character_, answerPosition=NA_character_,
                                 value=NA_character_, spreadsheetId=NA_character_, occurred=NA_character_, interventionId=NA_character_,
                                 directoryId=NA_character_, textDocumentTitle=NA_character_, tableType=NA_character_, columnName=NA_character_,
                                 rowId=NA_character_, tableName=NA_character_)


  workflow <-
    # match events with the basic_event_codes
    dplyr::left_join(participant_events, event_codes, by="event_type") %>%
    # exclude irrelevant variables
    dplyr::select(invitation_id=invitationId, survey_id=surveyId, timestamp, label, event_type, event_code, data=data, index=index.x) %>%
    # unnest columns with ids
    dplyr::mutate(invitation_id=unlist(invitation_id), survey_id=unlist(survey_id)) %>%
    # format time variable
    dplyr::mutate(time=lubridate::as_datetime(timestamp)) %>%

    dplyr::mutate(data2=data) %>%


    # unnest all variables included in the list variable data
    tidyr::unnest_wider(data) %>%
    # add dummy variables for event data that was not generated for this participant
    tibble::add_column(!!!needed_variables[!names(needed_variables) %in% names(.)]) %>%
    # renaming ID variables according to naming conventions
    dplyr::rename(scenario_id=scenarioId, binary_file_id=binaryFileId, spreadsheet_id=spreadsheetId, file_id=fileId, email_id=emailId) %>%

    # match event ids with the ids of the project elements
    dplyr::left_join(select(project_elements,-c("binary_file_id","spreadsheet_id")), by="id", na_matches="never") %>%
    dplyr::left_join(select(project_elements,-c("id","spreadsheet_id")), by="binary_file_id", na_matches="never") %>%
    dplyr::left_join(select(project_elements,-c("id","binary_file_id")), by="spreadsheet_id", na_matches="never") %>%
    dplyr::left_join(select(project_elements,-c("id","spreadsheet_id")), by=c("file_id"="binary_file_id"), na_matches="never") %>%
    dplyr::left_join(select(project_elements,-c("binary_file_id", "spreadsheet_id")), by=c("email_id"="id"), na_matches="never") %>%

    # merge relevant variables (replacing NAs with values included due to subsequent joins above) and replace NAs by empty string
    dplyr::mutate(name=dplyr::coalesce(!!!syms(grep("^name",names(.), value=TRUE))),
                  usage_type=dplyr::coalesce(!!!syms(grep("^usage_type",names(.), value=TRUE))),
                  element_code=dplyr::coalesce(!!!syms(grep("^element_code",names(.), value=TRUE))),
                  element_code=replace(element_code, is.na(element_code), "")) %>%

    # join basic event codes with individual project element code
    dplyr::mutate(event_code=paste0(event_code, element_code)) %>%

    # Order events according to their time stamps (this step might be unnecessary once the log data generation is corrected in LUCA office)
    arrange(time) %>%

    # calculate variables for project run time and event durations
    dplyr::mutate(project_time = time-time[1], event_duration = dplyr::lead(time)-time) %>%

    # exclude cases with a wf code of "#" (see basic table with event codes)
    dplyr::filter(event_code!="#") %>%

    # integrate tool id into the event_codes were necessary
    dplyr::mutate(event_code=replace(event_code, grepl("^T##", event_code),
                                  paste0("T",
                                         plyr::mapvalues(tool, tool_codes$tool, tool_codes$code, warn_missing = FALSE)[grepl("^T##", event_code)],
                                         substr(event_code[grepl("^T##", event_code)], 4, 10) ))) %>%

    # integrate module id into the event_codes were necessary
    dplyr::mutate(event_code=replace(event_code, grepl("^M##", event_code),
                                  paste0("M",
                                         plyr::mapvalues(scenario_id, project_modules$scenario_id, project_modules$code, warn_missing = FALSE)[grepl("^M##", event_code)],
                                         substr(event_code[grepl("^M##", event_code)], 4, 10) ))) %>%

    # prepare content for the data column depending on the event type
    dplyr::mutate(data=dplyr::case_when(event_type=="StoreParticipantData" ~ paste0("Salutation: ", salutation, "; First name: ", firstName, "; Last name: ", lastName),
                                        event_type=="UpdateNotesText" | event_type=="UpdateEmailText" | event_type=="SendEmail" ~ text,
                                        event_type=="OpenTool" | event_type=="CloseTool" | event_type=="RestoreTool" | event_type=="MinimizeTool" ~ tool,
                                        event_type=="SelectEmailDirectory" ~ directory,
                                        event_type=="EndScenario" ~ endType,
                                        event_type=="OpenSpreadsheet" | event_type=="SelectSpreadsheet" ~ spreadsheetTitle,
                                        event_type=="SelectSpreadsheetCell" ~ cellName,
                                        event_type=="UpdateSpreadsheetCellValue" ~ paste0(cellName, ": ", value),
                                        event_type=="SelectSpreadsheetCellRange" ~ paste0(startCellName, " : ", endCellName),
                                        event_type=="ViewFile" ~ mimeType,
                                        event_type=="ViewDirectory" ~ paste0("Directory ID: ", directoryId),
                                        event_type=="OpenPdfBinary" | event_type=="SelectPdfBinary" | event_type=="SelectImageBinary" | event_type=="OpenImageBinary" | event_type=="OpenVideoBinary" | event_type=="SelectVideoBinary" ~ binaryFileTitle,
                                        event_type=="SendParticipantChatMessage" | event_type=="ReceiveSupervisorChatMessage" ~ message,
                                        event_type=="PasteFromClipboard" ~ content,
                                        event_type=="SelectQuestionnaireAnswer" ~ paste0(answerPosition, " ('", value, "')"),
                                        event_type=="EvaluateIntervention" ~ paste0("Occurred: ", occurred, ", Intervention ID: ", interventionId),
                                        event_type=="OpenTextDocument" ~ textDocumentTitle,
                                        event_type=="UpdateTextDocumentContent" ~ content,
                                        event_type=="ErpSelectCell" ~ paste0("Table type: ", tableType, ", Column: ", columnName, ", Row index: ", rowId, ", Value: ", value),
                                        event_type=="ErpSelectTable" ~ paste0("Table name: ", tableName, ", Table type: ", tableType),
                                        # TODO: Completing the data column for not yet considered events
                                        #event_type=="" ~ value,
                                        event_type=="UpdateEmail" ~ paste0("To: ", to, "; CC: ", cc, "; Subject: ", subject)
                                        )) %>%

    # Fill missings in variable data with the value provided in the variable name (usually the name of the file the participant is working with)
    dplyr::mutate(data=dplyr::coalesce(data, name)) %>%

    # select final set of variables
    dplyr::select(invitation_id, survey_id, scenario_id, time, project_time, event_duration,
           label, event_code, data, event_type, data2, binary_file_id, email_id, spreadsheet_id, file_id) %>%

    # Removing hash IDs and debugging variables if 'debug_mode' is set to `FALSE`
    dplyr::select_if(debug_mode|!grepl("^event_type$|^data2$|^id$|_id$", names(.)))


    # If indicated insert idle events, in which the participant is not doing anything anymore
    if (idle_time) {
      workflow <- insert_idle_events(workflow, idle_time)
    }

    # If indicated, split workflow into multiple lists, one for each module
    if (module_specific){
      full_workflow <- workflow %>%
        dplyr::mutate(module_time=project_time, .after=project_time)
      workflow <- list()
      for (module_code in project_modules$code){
        first_module_event <- grep(paste0("^M",module_code,"STR0000"),full_workflow$event_code)
        last_module_event <- grep(paste0("^M",module_code,"END0000"), full_workflow$event_code)
        # Checking if the participation was interrupted before the regular end and the final ending event is not found
        last_module_event <- ifelse (length(last_module_event)==0, length(full_workflow$event_code), last_module_event)
        # Assigning the events to the given module
        workflow[[module_code]] <- slice(full_workflow, c(first_module_event:last_module_event))

        # Adjusting the run time to be module specific
        workflow[[module_code]]$module_time <- workflow[[module_code]]$module_time - workflow[[module_code]]$module_time[1]
      }
      workflow[["mail_recipient_codes"]] <- mail_recipient_codes
    }

  return(workflow)
}
