library(targets)
library(tarchetypes)
library(future)
library(future.callr)
source("code/simulation_unconditional.R")
plan(callr)

tar_option_set(
  packages = c(
    "tidyverse",
    "here",
    "lubridate",
    "survival",
    "broom",
    "zoo",
    "purrr",
    "scales",
    "ggpubr"
  ),
  format = 'qs',
  workspace_on_error = TRUE
)
list(
  # INPUT DATA ####
  tar_target(Births_WklyGestAge_07to18_file, "data/Births_NYS_Year_SingletonGestAge.txt", format = "file"),
  tar_target(NYBirths_by_Weekday_file, "data/Day_of_Wk_Natality_NY_2007to18.txt", format = "file"),
  tar_target(NYBirths_by_Month_plural_file, "data/Plurality_by_MonthYear_CDCWONDER.txt", format = "file"),
  tar_target(NYBirths_by_Month_single_file, "data/Births_NYS_YrMonth_SingletonGestAge.txt", format = "file"),
  tar_target(Annual_Singleton_Births_file, "data/Annual_Singleton_NYS.txt", format = "file"),
  tar_target(LaGuardiaTemp_file ,"data/LGATemp_2007to2018.csv", format = "file"),

  # DATA PREPARATION ####
  tar_target(LaGuardiaTemp1, load_temp(LaGuardiaTemp_file)),
  tar_target(NYBirths_by_Day,
             Clean_and_smooth_data(NYBirths_by_Month_plural_file,
                                   NYBirths_by_Weekday_file)),
  tar_target(Preterms_per_day_all,
             Estimate_all_daily_preterms(NYBirths_by_Day,
                                         NYBirths_by_Month_single_file,
                                         Births_WklyGestAge_07to18_file,
                                         Annual_Singleton_Births_file)),

  # SIMULATIONS ####
  tar_target(repeats, 10), # 1000 in publication, shorter for quick demonstration
  tar_target(batch_size, max(as.integer(repeats/10), 1)),
  tar_target(input_simulation_2007,
             Bootstrap_params(start_date = "2007-05-01", end_date = "2007-10-01",
                              Preterms_per_day_all, number_of_repeats = repeats,
                              LaGuardiaTemp1, target_seed = 1, batch_size) %>%
               tar_group(),
             iteration = 'group'),
  #tar_target(CCO_simulation_2007,
  #           purrr::map_dfr(input_simulation_2007 %>% split(.$Splits),
  #                          ~Case_Crossovers(.x)),
  #           pattern = map(input_simulation_2007)),
  tar_target(CCO_simulation_2007_unconditional,
             purrr::map_dfr(input_simulation_2007 %>% split(.$Splits),
                            ~Case_Crossovers_Sample(.x)),
             pattern = map(input_simulation_2007)),

  tar_target(input_simulation_2018,
             Bootstrap_params(start_date = "2018-05-01", end_date = "2018-10-01",
                              Preterms_per_day_all, number_of_repeats = repeats,
                              LaGuardiaTemp1, target_seed = 0, batch_size) %>%
               tar_group(),
             iteration = 'group'),
  #tar_target(CCO_simulation_2018,
  #           purrr::map_dfr(input_simulation_2018 %>% split(.$Splits),
  #                          ~Case_Crossovers(.x)),
  #           pattern = map(input_simulation_2018)),
  tar_target(CCO_simulation_2018_unconditional,
             purrr::map_dfr(input_simulation_2018 %>% split(.$Splits),
                            ~Case_Crossovers_Sample(.x)),
             pattern = map(input_simulation_2018)),
  tar_target(control_check,
             Check_Control_DF(input_simulation_2018 %>%
                                split(.$Splits) %>%
                                .[[1]])),

  #### TABLES AND PLOTS ####

  ## Temperature
  tar_target(laguardia_temp_plot,
              plot_temp(LaGuardiaTemp1)),

  ## Conditional
  tar_target(table_bias_2007,
             Create_table_of_bias_results(CCO_simulation_2007_unconditional$conditional)),
  tar_target(table_bias_2018,
              Create_table_of_bias_results(CCO_simulation_2018_unconditional$conditional)),
  tar_target(table_coverage_2007,
              Create_table_of_coverage_results(CCO_simulation_2007_unconditional$conditional, number_of_repeats = repeats)),
  tar_target(table_coverage_2018,
              Create_table_of_coverage_results(CCO_simulation_2018_unconditional$conditional, number_of_repeats = repeats)),
  tar_target(vis_2007,
             Visualize_Results(CCO_simulation_2007_unconditional$conditional, number_of_repeats = repeats)),
  tar_target(vis_2018,
              Visualize_Results(CCO_simulation_2018_unconditional$conditional, number_of_repeats = repeats)),

  ## Sample Unconditional
  tar_target(table_bias_2007_unconditional,
             Create_table_of_bias_results(CCO_simulation_2007_unconditional$unconditional)),
  tar_target(table_bias_2018_unconditional,
             Create_table_of_bias_results(CCO_simulation_2018_unconditional$unconditional)),
  tar_target(table_coverage_2007_unconditional,
             Create_table_of_coverage_results(CCO_simulation_2007_unconditional$unconditional, number_of_repeats = repeats)),
  tar_target(table_coverage_2018_unconditional,
             Create_table_of_coverage_results(CCO_simulation_2018_unconditional$unconditional, number_of_repeats = repeats)),
  tar_target(vis_2007_unconditional,
             Visualize_Results(CCO_simulation_2007_unconditional$unconditional, number_of_repeats = repeats)),
  tar_target(vis_2018_unconditional,
             Visualize_Results(CCO_simulation_2018_unconditional$unconditional, number_of_repeats = repeats)),

  ## Comparison Visualizations
  tar_target(bias_comparison_plot_2018,
             bias_comparison_visualization(CCO_simulation_2018_unconditional$conditional,CCO_simulation_2018_unconditional$unconditional)),
  tar_target(coverage_comparison_plot_2018,
             coverage_comparison_visualization(CCO_simulation_2018_unconditional$conditional,CCO_simulation_2018_unconditional$unconditional,number_of_repeats =repeats)),
  tar_target(power_comparison_plot_2018,
             power_comparison_visualization(CCO_simulation_2018_unconditional$conditional,CCO_simulation_2018_unconditional$unconditional,number_of_repeats =repeats)),
  tar_target(fp_comparison_plot_2018,
             fp_comparison_visualization(CCO_simulation_2018_unconditional$conditional,CCO_simulation_2018_unconditional$unconditional,number_of_repeats =repeats)),

  ## Birth Temp
  tar_target(vis_birth_temp_2007,
              Visualize_Births_and_Temp(LaGuardiaTemp1, Preterms_per_day_all, "2007-05-01", "2007-10-01")),
  tar_target(vis_birth_temp_2018,
              Visualize_Births_and_Temp(LaGuardiaTemp1, Preterms_per_day_all, "2018-05-01", "2018-10-01")),

  ## Export Results
  tar_target(result_export_status_2018unc, export_results(CCO_simulation_2018_unconditional$unconditional,
                                                  '2018 Unconditional Simulation Results')),
  tar_target(result_export_status_2018con, export_results(CCO_simulation_2018_unconditional$conditional,
                                                  '2018 Conditional Simulation Results')),
  tar_target(result_export_status_2007unc, export_results(CCO_simulation_2007_unconditional$unconditional,
                                                  '2007 Unconditional Simulation Results')),
  tar_target(result_export_status_2007con, export_results(CCO_simulation_2007_unconditional$unconditional,
                                                  '2007 Conditional Simulation Results')),

  tar_render(report, 'code/report.Rmd')
)
