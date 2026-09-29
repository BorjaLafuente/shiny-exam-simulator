
# Question bank: reading, validation, exam building and scoring.

required_cols <- c("topic", "question", "option_a", "option_b",
                   "option_c", "option_d", "answer")

# Header names used by the original Spanish spreadsheets. Accepting them
# means older question banks can be uploaded without editing them.
spanish_cols <- c(
  topic    = "Tema",
  question = "Pregunta",
  option_a = "Respuesta a",
  option_b = "Respuesta b",
  option_c = "Respuesta c",
  option_d = "Respuesta d",
  answer   = "Solución"  # escaped so the file sources the same on any locale
)

read_question_bank <- function(path) {
  raw <- readxl::read_excel(path)
  names(raw) <- str_squish(names(raw))

  found <- spanish_cols[spanish_cols %in% names(raw)]
  if (length(found) > 0) {
    raw <- raw %>% rename(all_of(found))
  }

  missing <- setdiff(required_cols, names(raw))
  if (length(missing) > 0) {
    stop("Missing columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }

  bank <- raw %>%
    select(all_of(required_cols)) %>%
    mutate(across(everything(), ~ str_squish(as.character(.x)))) %>%
    mutate(
      # Scanned banks often keep the numbering inside the text ("12. ...", "b) ...")
      question = str_remove(question, "^\\d+\\s*[.)-]\\s*"),
      across(starts_with("option_"), ~ str_remove(.x, "^[a-dA-D]\\)\\s*")),
      answer   = str_to_lower(answer),
      topic    = coalesce(topic, "General")
    ) %>%
    filter(
      !is.na(question),
      answer %in% c("a", "b", "c", "d"),
      if_all(starts_with("option_"), ~ !is.na(.x))
    )

  if (nrow(bank) == 0) {
    stop("No valid questions found in the file.", call. = FALSE)
  }

  bank <- bank %>%
    mutate(
      topic = factor(topic, levels = unique(topic)),  # keep the file's order
      qid   = row_number()
    )

  attr(bank, "n_dropped") <- nrow(raw) - nrow(bank)
  bank
}

# mode = "mock":  n random questions, with at least one from every topic
#                 (as long as n allows it).
# mode = "topic": every question of one topic, in the original order.
build_exam <- function(bank, mode = c("mock", "topic"), n = 20,
                       selected_topic = NULL) {
  mode <- match.arg(mode)

  if (mode == "topic") {
    return(bank %>% filter(topic == selected_topic))
  }

  n <- min(n, nrow(bank))

  one_per_topic <- bank %>%
    group_by(topic) %>%
    slice_sample(n = 1) %>%
    ungroup()

  if (nrow(one_per_topic) > n) {
    one_per_topic <- one_per_topic %>% slice_sample(n = n)
  }

  rest <- bank %>%
    anti_join(one_per_topic, by = "qid") %>%
    slice_sample(n = n - nrow(one_per_topic))

  bind_rows(one_per_topic, rest) %>%
    slice_sample(prop = 1)
}

# `answers` is a named character vector: names are question ids, values are
# the chosen letters. Unanswered questions are simply absent.
get_answer <- function(answers, qid) {
  unname(answers[as.character(qid)])
}

score_exam <- function(exam, answers, penalty = 0) {
  given <- get_answer(answers, exam$qid)

  status <- case_when(
    is.na(given)          ~ "blank",
    given == exam$answer  ~ "correct",
    TRUE                  ~ "wrong"
  )

  n_correct <- sum(status == "correct")
  n_wrong   <- sum(status == "wrong")
  net       <- n_correct - penalty * n_wrong

  by_topic <- exam %>%
    mutate(status = status) %>%
    group_by(Topic = topic) %>%
    summarise(
      Questions = n(),
      Correct   = sum(status == "correct"),
      Wrong     = sum(status == "wrong"),
      Blank     = sum(status == "blank"),
      .groups   = "drop"
    ) %>%
    mutate(`% correct` = round(100 * Correct / Questions))

  list(
    given     = given,
    status    = status,
    n_correct = n_correct,
    n_wrong   = n_wrong,
    n_blank   = sum(status == "blank"),
    score_10  = round(10 * net / nrow(exam), 2),
    by_topic  = by_topic
  )
}
