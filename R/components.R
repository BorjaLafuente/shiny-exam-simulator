
# HTML builders for the question cards and the results grid.
# Radio buttons are plain HTML inputs that report back through a single
# Shiny input ("answer"), instead of creating one Shiny input per question.

question_card <- function(q, number, chosen = NA, status = NULL) {
  graded <- !is.null(status)

  options <- lapply(c("a", "b", "c", "d"), function(letter) {
    classes <- "option"
    if (graded && letter == q$answer) {
      classes <- paste(classes, "option-correct")
    } else if (graded && identical(chosen, letter)) {
      classes <- paste(classes, "option-wrong")
    }

    tags$label(
      class = classes,
      tags$input(
        type     = "radio",
        name     = paste0("q", q$qid),
        value    = letter,
        checked  = if (identical(chosen, letter)) NA,
        disabled = if (graded) NA,
        onchange = sprintf(
          "Shiny.setInputValue('answer', {qid: %d, value: this.value}, {priority: 'event'})",
          q$qid
        )
      ),
      tags$span(class = "option-letter", paste0(letter, ")")),
      tags$span(q[[paste0("option_", letter)]])
    )
  })

  div(
    id    = paste0("question-", number),
    class = paste("card question-card", if (graded) paste0("is-", status)),
    div(
      class = "card-body",
      div(class = "question-meta", sprintf("Question %d · %s", number, q$topic)),
      div(class = "question-text", q$question),
      div(class = "options", options)
    )
  )
}

results_grid <- function(status, given) {
  cells <- lapply(seq_along(status), function(i) {
    tags$button(
      type    = "button",
      class   = paste("grid-cell", paste0("is-", status[i])),
      title   = paste("Go to question", i),
      onclick = sprintf(
        "Shiny.setInputValue('goto_question', %d, {priority: 'event'})", i
      ),
      span(class = "cell-number", i),
      span(class = "cell-letter", if (is.na(given[i])) "–" else toupper(given[i]))
    )
  })
  div(class = "results-grid", cells)
}
