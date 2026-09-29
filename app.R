library(shiny)
library(bslib)
library(dplyr)
library(stringr)
library(readxl)

# Files in R/ are sourced automatically by Shiny.

demo_bank <- read_question_bank("data/demo_questions.xlsx")
questions_per_page <- 10

ui <- page_sidebar(
  title = "Exam Simulator",
  fillable = FALSE,  # let the page scroll instead of squeezing cards into the window height
  theme = bs_theme(
    version   = 5,
    primary   = "#2c5d8f",
    base_font = font_collection("system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif")
  ),
  sidebar = sidebar(
    width = 300,
    radioButtons(
      "source", "Question bank",
      choices = c("Demo questions (statistics)" = "demo",
                  "Upload my own (.xlsx)"       = "upload")
    ),
    conditionalPanel(
      "input.source == 'upload'",
      fileInput("file", NULL, accept = ".xlsx"),
      helpText("Columns: topic, question, option_a to option_d, answer. See the README.")
    ),
    selectInput("mode", "Mode",
                choices = c("Mock exam" = "mock", "Study one topic" = "topic"),
                selectize = FALSE),
    conditionalPanel(
      "input.mode == 'mock'",
      numericInput("n_questions", "Number of questions", value = 20, min = 1, step = 1)
    ),
    conditionalPanel(
      "input.mode == 'topic'",
      selectInput("topic", "Topic", choices = NULL, selectize = FALSE)
    ),
    selectInput("penalty", "Penalty per wrong answer",
                choices = c("None" = 0, 
                            "1/2 of a correct answer" = 1/2,
                            "1/3 of a correct answer" = 1/3,
                            "1/4 of a correct answer" = 1/4),
                selectize = FALSE),
    actionButton("new_exam", "New exam", class = "btn-outline-primary"),
    actionButton("grade", "Grade exam", class = "btn-primary")
  ),
  tags$head(
    tags$link(rel = "stylesheet", href = "styles.css"),
    tags$script(src = "app.js")
  ),
  uiOutput("summary"),
  uiOutput("questions"),
  uiOutput("pager")
)

server <- function(input, output, session) {

  bank <- reactive({
    if (input$source == "demo") return(demo_bank)
    req(input$file)
    tryCatch(
      read_question_bank(input$file$datapath),
      error = function(e) {
        showNotification(conditionMessage(e), type = "error", duration = 8)
        NULL
      }
    )
  })

  observeEvent(bank(), {
    b <- bank()
    updateSelectInput(session, "topic", choices = levels(b$topic))
    updateNumericInput(session, "n_questions",
                       value = min(isolate(input$n_questions), nrow(b)),
                       max = nrow(b))
    dropped <- attr(b, "n_dropped")
    if (!is.null(dropped) && dropped > 0) {
      showNotification(sprintf("%d incomplete rows were skipped.", dropped),
                       type = "warning")
    }
  })

  # ---- Exam state --------------------------------------------------------

  exam    <- reactiveVal(NULL)
  answers <- reactiveVal(character())
  graded  <- reactiveVal(FALSE)
  page    <- reactiveVal(1)

  n_pages <- reactive(ceiling(nrow(req(exam())) / questions_per_page))

  observeEvent(list(bank(), input$mode, input$topic, input$new_exam), {
    b <- req(bank())
    if (input$mode == "topic") {
      req(input$topic %in% levels(b$topic))
      new_exam <- build_exam(b, "topic", selected_topic = input$topic)
    } else {
      req(input$n_questions >= 1)
      new_exam <- build_exam(b, "mock", n = input$n_questions)
    }
    exam(new_exam)
    answers(character())
    graded(FALSE)
    page(1)
    session$sendCustomMessage("scroll-to", "#questions")
  })

  observeEvent(input$answer, {
    if (graded()) return()
    current <- answers()
    current[as.character(input$answer$qid)] <- input$answer$value
    answers(current)
  })

  observeEvent(input$grade, {
    req(exam())
    graded(TRUE)
    session$sendCustomMessage("scroll-to", ".summary-card")
  })

  result <- reactive({
    req(graded())
    score_exam(exam(), answers(), penalty = as.numeric(input$penalty))
  })

  # ---- Navigation --------------------------------------------------------

  observeEvent(input$prev_page, page(max(1, page() - 1)))
  observeEvent(input$next_page, page(min(n_pages(), page() + 1)))

  observeEvent(input$goto_question, {
    i <- input$goto_question
    page(ceiling(i / questions_per_page))
    session$sendCustomMessage("scroll-to-question", i)
  })

  # ---- Output ------------------------------------------------------------

  output$summary <- renderUI({
    req(graded())
    r <- result()

    card(
      class = "summary-card",
      fill = FALSE,
      card_header("Results"),
      layout_column_wrap(
        width = "140px",
        value_box("Correct", r$n_correct, theme = "text-success"),
        value_box("Wrong", r$n_wrong, theme = "text-danger"),
        value_box("Blank", r$n_blank, theme = "text-warning"),
        value_box("Score (out of 10)", r$score_10, theme = "text-primary")
      ),
      p(class = "grid-hint", "Click a number to jump to that question."),
      results_grid(r$status, r$given),
      if (nrow(r$by_topic) > 1) {
        tagList(h6("By topic"), tableOutput("by_topic"))
      }
    )
  })

  output$by_topic <- renderTable(result()$by_topic, digits = 0)

  output$questions <- renderUI({
    ex <- req(exam())
    if (nrow(ex) == 0) {
      return(p("There are no questions to show."))
    }

    first <- (page() - 1) * questions_per_page + 1
    last  <- min(page() * questions_per_page, nrow(ex))
    status <- if (graded()) result()$status

    # answers() is isolated so that ticking an option does not redraw the page;
    # the radio button already shows the choice in the browser.
    chosen <- isolate(answers())

    lapply(first:last, function(i) {
      question_card(ex[i, ], i,
                    chosen = get_answer(chosen, ex$qid[i]),
                    status = status[i])
    })
  })

  output$pager <- renderUI({
    req(exam(), nrow(exam()) > 0)
    answered <- sum(exam()$qid %in% names(answers()))

    div(
      class = "pager",
      actionButton("prev_page", "Previous", class = "btn-sm btn-outline-secondary",
                   disabled = if (page() == 1) NA),
      span(sprintf("Page %d of %d · %d of %d answered",
                   page(), n_pages(), answered, nrow(exam()))),
      actionButton("next_page", "Next", class = "btn-sm btn-outline-secondary",
                   disabled = if (page() == n_pages()) NA)
    )
  })
}

shinyApp(ui, server)
