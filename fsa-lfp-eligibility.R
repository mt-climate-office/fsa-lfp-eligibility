library(tidyverse)
library(magrittr)

fsa_counties <-
  sf::read_sf("/vsizip/fsa-counties/FSA_Counties_dd17.gdb.zip") %>%
  dplyr::filter(!(STPO %in% c("AK", "GU", "HI", "VI", "AS", "MP", "PR"))) %>%
  dplyr::transmute(FSA_CODE = FSA_STCOU,
                   FSA_STATE = paste(FSA_ST, STPO, sep = "-"),
                   FSA_COUNTY_NAME = FSA_Name) %>%
  {
    tmp <- tempfile(fileext = ".geojson")
    sf::write_sf(., tmp,
                 delete_dsn = TRUE)
    sf::read_sf(tmp)
  } %>%
  dplyr::group_by(FSA_CODE, FSA_STATE, FSA_COUNTY_NAME) %>%
  dplyr::summarise(.groups = "drop") %>%
  sf::st_transform("EPSG:5070") %>%
  sf::st_make_valid() %>%
  sf::st_intersection(  
    tigris::counties(cb = TRUE) %>%
      sf::st_union() %>%
      sf::st_transform("EPSG:5070")
  ) %>%
  rmapshaper::ms_simplify(keep = 0.015, keep_shapes = TRUE) %>%
  sf::st_make_valid()

lfp_eligibility <-
  unzip("foia/2023-FSA-00937-F Bocinsky.zip", list = TRUE) %$%
  Name %>%
  purrr::map_dfr(
    ~readxl::read_excel(unzip("foia/2023-FSA-00937-F Bocinsky.zip", .x, 
                              exdir = tempdir()), 
                        col_types = "text")) %>%
  dplyr::select(-`...25`,
                -`...26`) %>%
  dplyr::mutate(dplyr::across(c(D2_START_DATE:D4B_END), 
                              \(x) lubridate::as_date(x)),
                dplyr::across(c(START,END),
                              \(x) lubridate::as_date(x, format = "mdy"),
                              .names = "GROWING_SEASON_{.col}"),
                PROGRAM_YEAR = ifelse(is.na(PROGRAM_YEAR), `PROGRAM YEAR`, PROGRAM_YEAR),
                PROGRAM_YEAR = as.integer(PROGRAM_YEAR),
                PASTURE_TYPE = ifelse(is.na(PASTURE_TYPE), `PASTURE TYPE`, PASTURE_TYPE),
                FSA_CODE = ifelse(is.na(FSA_CODE), `FSA State/County CODE`, FSA_CODE),
                # FACTOR = ifelse(is.na(FACTOR), DROUGHT_FACTOR, FACTOR),
                FACTOR = ifelse(is.na(FACTOR), PAYMENT_FACTOR, FACTOR),
                FACTOR = ifelse(is.na(FACTOR), `Eligible Payment Months`, FACTOR),
                FACTOR = ifelse(is.na(FACTOR), `PAYMENT FACTOR`, FACTOR),
                FACTOR = factor(FACTOR,
                                levels = 0:5,
                                ordered = TRUE),
                FSA_STATE = ifelse(is.na(FSA_STATE), `FSA STATE`, FSA_STATE),
                FSA_COUNTY_NAME = ifelse(is.na(FSA_COUNTY_NAME), `FSA COUNTY NAME`, FSA_COUNTY_NAME),
                FSA_COUNTY_NAME = stringr::str_to_upper(FSA_COUNTY_NAME),
                GROWING_SEASON_START = ifelse(is.na(GROWING_SEASON_START), 
                                              lubridate::as_date(as.numeric(START), 
                                                                 origin = "1900-01-01"), 
                                              GROWING_SEASON_START) %>%
                  lubridate::as_date(),
                GROWING_SEASON_END = ifelse(is.na(GROWING_SEASON_END), 
                                            lubridate::as_date(as.numeric(END), 
                                                               origin = "1900-01-01"), 
                                            GROWING_SEASON_END) %>%
                  lubridate::as_date()
  )%>%
  dplyr::select(-`FSA State/County CODE`,
                -`PROGRAM YEAR`,
                -`PASTURE TYPE`,
                # -DROUGHT_FACTOR,
                -PAYMENT_FACTOR,
                -`Eligible Payment Months`,
                -`PAYMENT FACTOR`,
                -`FSA STATE`,
                -`FSA COUNTY NAME`,
                -FSA_ST_CODE,
                -FSA_CNTY_CODE,
                -START,
                -END
  ) %>%
  dplyr::select(PROGRAM_YEAR, 
                FSA_CODE, 
                FSA_STATE, 
                FSA_COUNTY_NAME,
                PASTURE_TYPE, 
                dplyr::everything()) %>%
  dplyr::mutate(
    FSA_CODE = stringr::str_pad(FSA_CODE, 5, pad = "0"),
    PASTURE_TYPE = 
      ifelse(PASTURE_TYPE == "SHRT SEASON SMALL GRAIN 1",
             "SHORT SEASON SMALL GRAINS",
             PASTURE_TYPE),
    PASTURE_TYPE = 
      ifelse(PASTURE_TYPE == "FULL SEASON IMPROVE MIXED",
             "FULL SEASON IMPROVED (MIXED)",
             PASTURE_TYPE),
    PASTURE_TYPE = 
      ifelse(PASTURE_TYPE == "SHORT SSN SPRING SML GRN",
             "SHORT SEASON SMALL GRAINS (SPRING)",
             PASTURE_TYPE),
    PASTURE_TYPE = 
      ifelse(PASTURE_TYPE == "SHRT SSN FALL_WTR SML GRN",
             "SHORT SEASON SMALL GRAINS (FALL–WINTER)",
             PASTURE_TYPE),
    PASTURE_TYPE = stringr::str_to_title(PASTURE_TYPE),
    FSA_COUNTY_NAME = stringr::str_to_title(FSA_COUNTY_NAME)
  ) %>%
  dplyr::arrange(PROGRAM_YEAR, FSA_CODE, PASTURE_TYPE) %T>%
  readr::write_csv("fsa-lfp-eligibility.csv")

dir.create("maps",
           showWarnings = FALSE)

lfp_eligibility_graphs <- 
  lfp_eligibility %>%
  dplyr::group_by(PROGRAM_YEAR, PASTURE_TYPE) %>%
  tidyr::nest() %>%
  dplyr::arrange(PROGRAM_YEAR, PASTURE_TYPE) %>%
  dplyr::rowwise() %>%
  dplyr::mutate(
    graph = list(
      (
        dplyr::left_join(dplyr::select(fsa_counties, FSA_CODE), data) %>%
          ggplot2::ggplot() +
          geom_sf(aes(fill = FACTOR),
                  col = "white") +
          geom_sf(data = fsa_counties %>%
                    dplyr::group_by(FSA_STATE) %>%
                    dplyr::summarise(),
                  col = "white",
                  fill = NA,
                  linewidth = 0.5) +
          scale_fill_manual(values = c("1" = "#FFFF54",
                                       "2" = "#F3AE3D",
                                       "3" =  "#6D4E16",
                                       "4" = "#EA3323",
                                       "5" =  "#7316A2"),
                            drop = FALSE,
                            name = paste0("Eligible County Payment Months\n", PROGRAM_YEAR, ", ", PASTURE_TYPE),
                            guide = guide_legend(direction = "horizontal",
                                                 title.position = "top"),
                            na.value = "grey80") +
          theme_void(base_size = 24) +
          theme(legend.position = c(0.225,0.125),
                # legend.key.width = unit(0.1, "npc"),
                legend.title = element_text(size = 14),
                legend.text = element_text(size = 12),
                strip.text.x = element_text(margin = margin(b = 5)))
      )
    )
  )

unlink("fsa-lfp-eligibility.pdf")

cairo_pdf(filename = "fsa-lfp-eligibility.pdf",
          width = 10,
          height = 6.86,
          bg = "white",
          onefile = TRUE)

lfp_eligibility_graphs$graph

dev.off()
