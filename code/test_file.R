packages <- c(
  "tidyverse",
  "here",
  "lubridate",
  "survival",
  "broom",
  "zoo",
  "purrr",
  "scales",
  "ggpubr"
)

invisible(lapply(packages, library, character.only = TRUE))
#### Functions used throughout ####

coalesce_join <- function(x, y,
                          by = NULL, suffix = c(".x", ".y"),
                          join = dplyr::full_join, ...) {
  joined <- join(x, y, by = by, suffix = suffix, ...)
  # names of desired output
  cols <- union(names(x), names(y))

  to_coalesce <- names(joined)[!names(joined) %in% cols]
  suffix_used <- suffix[ifelse(endsWith(to_coalesce, suffix[1]), 1, 2)]
  # remove suffixes and deduplicate
  to_coalesce <- unique(substr(
    to_coalesce,
    1,
    nchar(to_coalesce) - nchar(suffix_used)
  ))

  coalesced <- purrr::map_dfc(to_coalesce, ~dplyr::coalesce(
    joined[[paste0(.x, suffix[1])]],
    joined[[paste0(.x, suffix[2])]]
  ))
  names(coalesced) <- to_coalesce

  dplyr::bind_cols(joined, coalesced)[cols]
}

Biweekly_stratification <- function(Hazard_Periods){ #time stratified approach for 2 week periods

  Year <- as.character(year(Hazard_Periods$date)[1]) #pick out 1 observation to get year
  Dates_in_Year <- seq.Date(from = as.Date(paste0(Year, "-1-1")), to = as.Date(paste0(Year, "-12-31")), by = "day")
  Date_control_match <- tibble(date = Dates_in_Year) %>%
    mutate(Week = week(date),
           Week = if_else(Week == 53, 52, Week),
           Day = row_number(date),
           WkDay = wday(date),
           Strata = ceiling(Day/14),
           Strata = if_else(Strata == 27, 26, Strata))

  Sequence <- tibble(Sequence = rep.int(1:14, 26)) %>%
    add_row(Sequence = 14)

  Date_control_match1 <<- bind_cols(Date_control_match, Sequence) %>%
    group_by(Strata) %>%
    mutate(Control_Period = if_else(Sequence<=7, date + days(7), date - days(7))) %>%
    ungroup() %>%
    rename("Hazard_period" = "date")

  Control_Periods <- Hazard_Periods %>%
    ungroup() %>%
    left_join(., Date_control_match1, by = c("date" = "Hazard_period")) %>%
    dplyr::select(Control_Period, Participant) %>%
    mutate(Case = 0) %>%
    rename("date" = "Control_Period")

  return(Control_Periods)
}

#input will have: date, Participant, Case, Gest_Age

# test_data <- Random_draws(Create_Parameters_for(start = "2018-05-01", end_date = "2018-10-01", Preterms_per_day_all)) %>% filter(Random_draw!=0)%>%
#   uncount(Random_draw) %>%
#   mutate(Participant = row_number(),
#          Case = 1) %>%
#   dplyr::select(date, Participant, Case, Gest_Age)

Month_stratification <- function(Hazard_Periods){

  Hazard_Periods1 <- Hazard_Periods %>% #Hazard_Periods
    mutate(month = month(date),
           wkday = wday(date),
           year = year(date))

  Month_stratified_matches <- tibble(date = seq.Date(from = min(Hazard_Periods$date), to = max(Hazard_Periods$date), by = 1)) %>%
    mutate(wkday = wday(date),
           month = month(date),
           year = year(date),
           wk_of_month = ceiling(day(date)/7)) %>%
    pivot_wider(names_from = wk_of_month, values_from = date)

  Control_Periods <- Hazard_Periods1 %>%
    left_join(., Month_stratified_matches, by = c("month", "wkday", "year")) %>%
    mutate_at(vars(`1`:`5`), ~ as.Date(ifelse(`.`==date, NA, `.`))) %>%
    mutate(gestage_1 = as.numeric(difftime(`1`, date, units = "weeks") + Gest_Age),
           gestage_2 = as.numeric(difftime(`2`, date, units = "weeks") + Gest_Age),
           gestage_3 = as.numeric(difftime(`3`, date, units = "weeks") + Gest_Age),
           gestage_4 = as.numeric(difftime(`4`, date, units = "weeks") + Gest_Age),
           gestage_5 = as.numeric(difftime(`5`, date, units = "weeks") + Gest_Age))

  Control_Periods_a <- Control_Periods %>%
    dplyr::select(Participant, `1`:`5`) %>%
    pivot_longer(-Participant, names_to = "week_of_month", values_to = "date")

  Control_Periods_b <- Control_Periods %>%
    dplyr::select(Participant, gestage_1:gestage_5) %>%
    pivot_longer(-Participant, names_to = "week_of_month", values_to = "Gest_Age") %>%
    mutate(week_of_month = str_sub(week_of_month, -1))

  Control_Periods1 <- Control_Periods_a %>%
    left_join(., Control_Periods_b, by = c("Participant", "week_of_month")) %>%
    mutate(Case = 0) %>%
    filter(!is.na(date)) %>%
    dplyr::select(-week_of_month) %>%
    group_by(Participant) %>%
    slice_sample(n = 1)

  return(Control_Periods1)
}

FourWk_aka28day_stratification <- function(Hazard_Periods){ #time stratified approach for 28 day periods for warm months

  first_year_in_analysis <- min(year(Hazard_Periods$date))
  last_year_in_analysis <- max(year(Hazard_Periods$date))

  all_years <- seq.int(first_year_in_analysis, last_year_in_analysis, by = 1)# years_in_analysis

  All_Warm_Month_Dates <- tibble()
  for (i in 1:length(all_years)) {
    year <- all_years[i] #consider also using April and/or trimming out September
    Warm_Month_Dates_in_Year <- tibble(date = seq.Date(from = as.Date(paste0(year, "-5-1")), to = as.Date(paste0(year, "-9-30")), by = "day"))
    All_Warm_Month_Dates <- bind_rows(All_Warm_Month_Dates, Warm_Month_Dates_in_Year)
  }
  rm(Warm_Month_Dates_in_Year, year)

  Date_control_match <- All_Warm_Month_Dates %>%
    group_by(year(date)) %>%
    mutate(Day = row_number(date),
           WkDay = wday(date),
           Strata = ceiling(Day/28)) %>%
    group_by(Strata, WkDay, .add = T) %>%
    mutate(Sequence = row_number(),
           ctrldate1 = if_else(Sequence == 1, date+days(7),
                               if_else(Sequence==2, date-days(7),
                                       if_else(Sequence==3, date-days(14), date-days(21)))),
           ctrldate2 = if_else(Sequence==1, date+days(14),
                               if_else(Sequence==2, date+days(7),
                                       if_else(Sequence==3, date-days(7), date-days(14)))),
           ctrldate3 = if_else(Sequence==1, date+days(21),
                               if_else(Sequence==2, date+days(14),
                                       if_else(Sequence==3, date+days(7), date-days(7))))) %>%
    rename("hazard_period" = "date") %>%
    ungroup() %>%
    dplyr::select(hazard_period, ctrldate1, ctrldate2, ctrldate3)

  Control_periods <- Hazard_Periods %>%
    left_join(., Date_control_match, by = c("date" = "hazard_period")) %>%
    dplyr::select(Participant, ctrldate1:ctrldate3) %>%
    pivot_longer(-Participant, values_to = "date") %>%
    dplyr::select(-name) %>%
    mutate(Case = 0)

  return(Control_periods)
}


#### Cleaning Temperature Data ####

#Visualize min and max temp at LaGuardia Airport
load_temp <- function(LaGuardiaTemp_file){
  LaGuardiaTemp <- read_csv(LaGuardiaTemp_file, col_types = c("cccddd"))
  LaGuardiaTemp1 <- LaGuardiaTemp %>%
    mutate(date = mdy(DATE)) %>%
    rename("x" = "TMAX") %>%
    dplyr::select(date, x)
  LaGuardiaTemp1
}
# LaGuardiaTemp1 <- load_temp(LaGuardiaTemp_file)

plot_temp <- function(LaGuardiaTemp1){
  ggplot(LaGuardiaTemp1, aes(x = date, y = x)) + geom_point() + geom_smooth(method = "lm", se = FALSE) +
    labs(title = "Observed max temperatures at LaGuardia Airport") +
    ylab("Max temperature (F)") +
    theme(text = element_text(size = 15))
}


### Cleaning CDC Wonder and estimating all preterm births per day NYS   ####

Clean_and_smooth_data <- function(NYBirths_by_Month_plural_file, NYBirths_by_Weekday_file){
  #pulling out annual pattern of proportion births per month
  suppressWarnings(NYBirths_by_Month_plural <- read_tsv(NYBirths_by_Month_plural_file, col_types = cols()))

  suppressWarnings(NYBirths_by_Month1 <- NYBirths_by_Month_plural %>%
                     filter(!is.na(Month),
                            `Plurality or Multiple Birth`=="Single") %>%
                     rename("Month_number" = `Month Code`) %>%
                     select(Year, Month, Month_number, Births) %>%
                     mutate(Month = factor(Month, levels = month.name)) %>%
                     group_by(Year) %>%
                     mutate(Births_Year = sum(Births),
                            Pct_of_total_births = Births/Births_Year) %>%
                     ungroup())

  #get raw number of singleton births per month of each year
  NYBirths_by_MonthYear <- NYBirths_by_Month1 %>%
    distinct(Year, Month_number, Births, Births_Year)

  #Estimate how many births take place in a given week of the year
  NYBirths_by_Month2 <- NYBirths_by_Month1 %>%
    mutate(Week_Births = Births/4, #split by week -- assuming the average is representative of the middle of the series
           FirstWk = week(as.Date(paste(Year, Month_number,"01", sep = "-")))) %>%
    rowwise() %>%
    mutate(Week = sample(1:2, 1)) %>%
    ungroup() %>% #to stop rowwise
    mutate(Wk_of_Year = FirstWk + Week) %>% #randomly selecting either the 2nd or 3rd week to represent middle of time series
    group_by(Year) %>%
    complete(Wk_of_Year = seq(1,52)) %>%
    ungroup() %>%
    mutate(date = as.Date(paste(Year, Wk_of_Year, 1, sep="-"), "%Y-%U-%u"),
           Month_number = if_else(is.na(Month_number), month(date), Month_number)) %>%
    coalesce_join(., NYBirths_by_MonthYear, by = c("Year", "Month_number")) %>%
    rename("Month_Births" = "Births") %>%
    mutate(Week_Births1 = floor(na.approx(Week_Births, rule = 2)), #linear interpolation of births between middle of month estimates
           Week_Births_Pct = Week_Births1/Births_Year) %>%
    dplyr::select(date, Year, Wk_of_Year, Month_number, Week_Births1, Week_Births_Pct)

  #1) Births by day of week
  suppressWarnings(NYBirths_by_Weekday <- read_tsv(NYBirths_by_Weekday_file, col_types = cols()))

  suppressWarnings(NYBirths_by_Weekday1 <- NYBirths_by_Weekday %>%
                     filter(`Plurality or Multiple Birth`=="Single") %>%
                     rename("Month_number" = `Month Code`) %>%
                     select(Year, Month, Month_number, Births, Weekday) %>%
                     mutate(Month = factor(Month, levels = month.name)) %>%
                     group_by(Month_number, Year) %>%
                     mutate(Births_Month = sum(Births),
                            Prop_Births_Wkday = Births/Births_Month))

  #2) use to create a new df for day of year and projected proportion of births
  All_Dates_inTimePeriod <- tibble(date = seq.Date(as.Date("2007-01-01"), as.Date("2018-12-31"), by = "day")) %>%
    mutate(Wk_of_Year = week(date),
           Year = year(date))

  NYBirths_by_Day <- All_Dates_inTimePeriod %>%
    coalesce_join(., NYBirths_by_Month2, by = c("Year", "Wk_of_Year")) %>%
    mutate(Weekday = as.character(wday(date, label = TRUE, abbr = FALSE))) %>%
    left_join(., NYBirths_by_Weekday1, by = c("Year","Month_number","Weekday")) %>%
    mutate(Births_date = floor(Week_Births1 * Prop_Births_Wkday),
           Wk_of_Year = if_else(Wk_of_Year == 53, 52, Wk_of_Year)) %>%
    fill(., Month_number:Week_Births_Pct,Month, Births_Month, .direction = "down") %>%
    mutate(Births_date = na.approx(Births_date, rule = 2))

  return(NYBirths_by_Day)
}

Estimate_all_daily_preterms <- function(NYBirths_by_Day, NYBirths_by_Month_single_file, Births_WklyGestAge_07to18_file, Annual_Singleton_Births_file){

  #now look at singletons by gestational age to get proportion of births
  suppressWarnings(Annual_Singleton_Births <- read_tsv(Annual_Singleton_Births_file, col_types = cols()))
  suppressWarnings(Annual_Singleton_Births1 <- Annual_Singleton_Births %>%
                     filter(is.na(Notes)) %>%
                     rename(Total_Singleton_Births_Year = "Births") %>%
                     select(Year, Total_Singleton_Births_Year))

  suppressWarnings(NYBirths_by_Month_single <- read_tsv(NYBirths_by_Month_single_file, col_types = cols()))
  suppressWarnings(MonthBirths_total <- NYBirths_by_Month_single %>%
                     filter(Notes == "Total" & !is.na(`Month Code`)) %>%
                     rename("Month_number" = `Month Code`) %>%
                     mutate(Births_month = as.numeric(Births)) %>%
                     select(Year, Month_number, Births_month))

  ## All births by gestational age LMP Gestational Age Weekly Code
  suppressWarnings(Births_WklyGestAge_07to18 <- read_tsv(Births_WklyGestAge_07to18_file, col_types = cols()))
  suppressWarnings(Births_WklyGestAge_07to18_a <- Births_WklyGestAge_07to18 %>%
                     filter(is.na(Notes) & "LMP Gestational Age Weekly Code" != 99) %>%
                     rename(Gest_Age = "LMP Gestational Age Weekly Code",
                            Year_Births_perAge = "Births") %>%
                     select(Year, Gest_Age, Year_Births_perAge) %>%
                     left_join(., Annual_Singleton_Births1, by = "Year") %>%
                     mutate(Year_Births_perAge = as.numeric(na_if(Year_Births_perAge, "Suppressed"))))

  Births_WklyGestAge_07to18_b <- Births_WklyGestAge_07to18_a %>%
    group_by(Year) %>%
    summarise(Births_with_GestAge = sum(Year_Births_perAge, na.rm = T))

  #making estimates for all gestational ages
  Births_WklyGestAge_07to18_c <- Births_WklyGestAge_07to18_a %>%
    left_join(., Births_WklyGestAge_07to18_b, by = "Year") %>%
    mutate(Year_Births_perAge = if_else(is.na(Year_Births_perAge),
                                        Total_Singleton_Births_Year - Births_with_GestAge,
                                        Year_Births_perAge)) %>%
    select(-Births_with_GestAge)

  NYBirths_by_Month_single1 <- NYBirths_by_Month_single %>%
    rename("Month_number" = `Month Code`,
           Gest_Age = `LMP Gestational Age Weekly Code`) %>%
    filter(!is.na(Gest_Age)) %>%
    select(Year, Month, Month_number, Gest_Age, Births) %>%
    mutate(Month = factor(Month, levels = month.name)) %>%
    left_join(., MonthBirths_total, by = c("Year", "Month_number")) %>%
    left_join(., Births_WklyGestAge_07to18_c, by = c("Year", "Gest_Age"))

  Lowest_Preterm_Prop_notSuppressed <- NYBirths_by_Month_single1 %>%
    filter(Births != "Suppressed") %>%
    group_by(Year, Month_number) %>%
    slice_min(order_by = Gest_Age) %>%
    ungroup() %>%
    mutate(Prop_of_LowestPreterm = as.numeric(Births)/Year_Births_perAge) %>%
    select(Year, Month_number, Prop_of_LowestPreterm)

  NYBirths_by_Month_preterm_single2 <- NYBirths_by_Month_single1 %>%
    left_join(., Lowest_Preterm_Prop_notSuppressed, by = c("Year", "Month_number")) %>%
    mutate(Births = as.numeric(na_if(Births, "Suppressed")),
           Births = if_else(is.na(Births), floor(Year_Births_perAge*Prop_of_LowestPreterm), Births),
           Prop_Births = Births/Births_month) %>%
    filter(Gest_Age < 37) %>%
    dplyr::select(Year, Month_number, Gest_Age, Prop_Births)

  Preterms_per_day_all <- NYBirths_by_Day %>% #required input for everything below
    dplyr::select(date, Year, Wk_of_Year, Month_number, Births_date) %>%
    full_join(., NYBirths_by_Month_preterm_single2, by = c("Year", "Month_number")) %>%
    mutate(Preterms = floor(Births_date*Prop_Births)) #round(Births_date*Prop_Births, 0)

  return(Preterms_per_day_all)
}


#### Creating Simulations and conducting case crossovers ####

##need to create lambdas ###
Create_Parameters_for <- function(start_date, end_date, Preterms_per_day_df, LaGuardiaTemp1){ ##RR per 10F

  RiskRatios <- tibble(RR_per_10F = seq.default(from = .9, to = 1.25, length.out = 8),
                       Simulated_RR = seq.default(from = .9, to = 1.25, length.out = 8)) %>%
    mutate(lnRR_per_degreeF = log(RR_per_10F)/10)

  Preterms_per_day_indexYear <- Preterms_per_day_df %>%
    filter(date >= start_date & date <= end_date)

  Beta_naughts <- Preterms_per_day_indexYear %>%
    group_by(Gest_Age, Month_number) %>%
    summarise(ln_beta_naught = log(mean(Preterms, na.rm = TRUE)), #calculating as input
              Dispersion = var(Preterms, na.rm = TRUE)) %>%
    crossing(RiskRatios) %>%
    ungroup()

  Parameters <- Preterms_per_day_indexYear %>%
    left_join(., Beta_naughts, by = c("Gest_Age", "Month_number")) %>%
    left_join(., LaGuardiaTemp1, by = "date") %>%
    mutate(lambda = exp(ln_beta_naught + (lnRR_per_degreeF*x)))

  return(Parameters)
}

Random_draws <- function(Parameters_df){ #make a function to repeat x times for monte carlo

  MonteCarlo_df <- Parameters_df %>%
    rowwise() %>%
    mutate(Random_draw = rpois(1, lambda))

  return(MonteCarlo_df)
}


get_end_date <- function(df_with_casedays, control_select = c("28_day", "month", "2_week")) {

  start_date <- min(df_with_casedays$date)
  last_date <- max(df_with_casedays$date)

  max_num_days <- as.numeric(difftime(as.Date(last_date),as.Date(start_date), "day"))+1

  if(control_select == "2_week") {
    end_date <- as.Date(start_date) + days(14*floor((max_num_days/14))-1)
  }

  if(control_select == "28_day") {
    end_date <- as.Date(start_date) + days(28*floor((max_num_days/28))-1)
  }

  if(control_select=="month") {
    elapsed_months <- 12 * (year(as.Date(last_date)) - year(as.Date(start_date))) + (month(as.Date(last_date)) - month(as.Date(start_date)))
    end_date <- as.Date(start_date) + months(elapsed_months)-days(1)
  }

  return(end_date)
}


Case_Crossovers <- function(Params_for_Simulated_Year){

  Simulated_RR <- Params_for_Simulated_Year$Simulated_RR[1]

  CC_Exposures <- Params_for_Simulated_Year %>% #make this swap in
    dplyr::select(date, x) %>%
    distinct(date, x)

  CC_casedays <- Params_for_Simulated_Year %>% filter(Random_draw!=0)%>%
    uncount(Random_draw) %>%
    mutate(Participant = row_number(),
           Case = 1) %>%
    dplyr::select(date, Participant, Case, Gest_Age)

  #Month Stratified Case Crossover dataset
  Simulation_df_MonthStrat <- CC_casedays %>%
    filter(date <= get_end_date(CC_casedays, "month")) %>%
    bind_rows(., Month_stratification(.)) %>%
    left_join(., CC_Exposures, by = "date")


  #clogit regression - no adjustment
  mod.clogit.month <- clogit(Case ~ x + strata(Participant), # each case day is a strata #number of events in each day
                             method = "efron", # the method tells the model how to deal with ties
                             Simulation_df_MonthStrat)

  CCOResults_monthstrat <- broom::tidy(mod.clogit.month, conf.int = TRUE) %>%
    mutate(Analysis = "CCO_Month") %>%
    add_column(Simulated_RR = Simulated_RR)

  ### 28day stratified model ###
  Simulation_df_28dayStrat <- CC_casedays %>%
    filter(date <= get_end_date(CC_casedays, "28_day")) %>%
    bind_rows(., FourWk_aka28day_stratification(.)) %>%
    left_join(., CC_Exposures, by = "date")

  mod.clogit.fourwk <- clogit(Case ~ x + strata(Participant),
                              method = "efron",
                              Simulation_df_28dayStrat)

  CCOResults_28daystrat <- broom::tidy(mod.clogit.fourwk, conf.int = TRUE) %>%
    filter(term == "x") %>%
    mutate(Analysis = "CCO_28day") %>%
    add_column(Simulated_RR = Simulated_RR)

  ### 2 week stratified case crossover ###
  Simulation_df_2WeekStrat <- CC_casedays %>%
    filter(date <= get_end_date(CC_casedays, "2_week")) %>%
    bind_rows(., Biweekly_stratification(.)) %>%
    left_join(., CC_Exposures, by = "date")

  mod.clogit.2wk <- clogit(Case ~ x + strata(Participant), # each case day is a strata #number of events in each day
                           method = "efron", # the method tells the model how to deal with ties
                           Simulation_df_2WeekStrat)

  CCOResults_biweekstrat <- broom::tidy(mod.clogit.2wk, conf.int = TRUE) %>%
    mutate(Analysis = "CCO_2week") %>%
    add_column(Simulated_RR = Simulated_RR)

  RegressionResults <- bind_rows(CCOResults_monthstrat, CCOResults_28daystrat, CCOResults_biweekstrat)

  return(RegressionResults)
}

# Prepare table for CCO, group by splits for later parallel computation of CCO in targets
Bootstrap_params <- function(start_date, end_date, Preterms_per_day_df,
                             number_of_repeats, Temp_df, target_seed,
                             batch_size){
  set.seed(target_seed)
  Parameters <- Create_Parameters_for(start_date, end_date,
                                      Preterms_per_day_df, Temp_df)

  Bootstrapped_counts <- number_of_repeats %>%
    rerun(Random_draws(Parameters)) %>%
    tibble() %>%
    unnest(cols = c(.)) %>%
    dplyr::select(date, Simulated_RR, Gest_Age, x, Random_draw) %>%
    group_by(Simulated_RR, date, Gest_Age) %>%
    mutate(Round_of_Sim = row_number(),
           # creating one variable on which to split for parallelization
           Splits = paste(Simulated_RR, Round_of_Sim, sep = ".")) %>%
    ungroup() %>%
    group_by(Splits) %>%
    mutate(group_id = cur_group_id()) %>%
    mutate(batch = findInterval(group_id, seq(1, max(group_id), batch_size))) %>%
    mutate(group_id = NULL) %>%
    group_by(batch)
  Bootstrapped_counts
}

#### Analyze Results ####
Create_table_of_bias_results <- function(Simulation_results){

  Results_CaseCrossovers <- Simulation_results %>%
    group_by(Analysis, Simulated_RR) %>%
    mutate(Round_of_Sim = row_number()) %>%
    ungroup()

  Bias_Estimates <- Results_CaseCrossovers %>%
    mutate(Bias_per_10F = round((estimate*10) - log(Simulated_RR), 3),
           Analysis = factor(Analysis, levels = c("CCO_2week", "CCO_Month", "CCO_28day"),
                             labels = c("Time stratified: 2 weeks", "Time Stratified: Month", "Time Stratified: 28 days")))
  Bias_Estimates1 <- Bias_Estimates %>%
    group_by(Analysis) %>%
    summarise(bias_median = median(Bias_per_10F),
              bias_IQR = paste0(round(quantile(Bias_per_10F, .25), 3), "-", round(quantile(Bias_per_10F, .75), 3)))

  return(Bias_Estimates1)
}

Create_table_of_coverage_results <- function(Simulation_results, number_of_repeats){

  Results_CaseCrossovers <- Simulation_results %>%
    group_by(Analysis, Simulated_RR) %>%
    mutate(Round_of_Sim = row_number()) %>%
    ungroup()

  Coverage <- Results_CaseCrossovers %>%
    mutate(Exp_ConfLow = exp(conf.low*10),
           Exp_ConfHigh = exp(conf.high*10),
           Exp_Estimate = exp(estimate*10)) %>%
    dplyr::select(Round_of_Sim, Exp_Estimate, Exp_ConfLow, Exp_ConfHigh, Simulated_RR, Analysis)

  Coverage1 <- Coverage %>%
    ungroup() %>%
    mutate(Covered = if_else(Simulated_RR>=Exp_ConfLow & Simulated_RR<=Exp_ConfHigh, 1, 0)) %>%
    group_by(Simulated_RR, Analysis) %>%
    summarise(Coverage = (sum(Covered)/number_of_repeats)) %>%
    ungroup() %>%
    mutate(Analysis = factor(Analysis, levels = c("CCO_2week", "CCO_Month", "CCO_28day"),
                             labels = c("Time stratified: 2 weeks", "Time Stratified: Month", "Time Stratified: 28 days")))

  Coverage2 <- Coverage1 %>%
    group_by(Analysis) %>%
    summarise(min_coverage = min(Coverage),
              max_coverage = max(Coverage))

  return(Coverage2)
}


Visualize_Results <- function(results_df, number_of_repeats){

  Results_CaseCrossovers1 <- results_df %>%
    #filter(Analysis=="CCO_2week" | Analysis=="CCO_Month") %>%
    group_by(Analysis, Simulated_RR) %>%
    mutate(Round_of_Sim = row_number(),
           Analysis = factor(Analysis, levels = c("CCO_2week", "CCO_28day", "CCO_Month"),
                             labels = c("Time stratified: 2 weeks", "Time Stratified: 28 days", "Time Stratified: Month"))) %>%
    ungroup()

  Bias_Estimates <- Results_CaseCrossovers1 %>%
    mutate(Bias_per_10F = (estimate*10)-log(Simulated_RR))

  Bias_plot <- ggplot(Bias_Estimates) +
    geom_boxplot(aes(Simulated_RR, Bias_per_10F, fill = Analysis), width = .5) +
    facet_grid(~Simulated_RR, scales = "free", switch = "x") +
    ylab("Bias") +
    theme_minimal(base_size = 22) +
    scale_x_continuous(breaks = NULL) +
    theme(legend.position = "bottom",
          axis.title.x = element_blank(),
          legend.title = element_blank())

  ##Coverage plots ##
  Coverage <- Results_CaseCrossovers1 %>%
    mutate(Exp_ConfLow = exp(conf.low*10),
           Exp_ConfHigh = exp(conf.high*10),
           Exp_Estimate = exp(estimate*10)) %>%
    dplyr::select(Round_of_Sim, Exp_Estimate, Exp_ConfLow, Exp_ConfHigh, Simulated_RR, Analysis)

  Coverage1 <- Coverage %>%
    ungroup() %>%
    mutate(Covered = if_else(Simulated_RR>=Exp_ConfLow & Simulated_RR<=Exp_ConfHigh, 1, 0)) %>%
    group_by(Simulated_RR, Analysis) %>%
    summarise(Coverage = (sum(Covered)/number_of_repeats)) %>%
    ungroup()

  Coverage_plot <- ggplot() +
    geom_point(data = Coverage1,
               aes(x = as.numeric(Analysis), y = Coverage, shape = Analysis, fill = Analysis), size = 9, shape = 23) + #position=position_dodge(0.05),
    facet_grid(~Simulated_RR, switch = "x") +
    geom_hline(yintercept = .95, linetype = 2) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1, scale = 100), minor_breaks = seq(0 , 1, .05), breaks = seq(0, 1, .20), limits = c(0,1)) +
    scale_x_continuous(breaks = NULL, limits = c(.5, 3.5)) +
    theme_minimal(base_size = 22) +
    theme(legend.position = "none") +
    xlab("Simulated Relative Risk") +
    ylab("Coverage of 95% CI")

  combined_plot <- ggarrange(Bias_plot, Coverage_plot, ncol = 1, nrow = 2, labels = "AUTO")
  return(combined_plot)
}


#look at the temperature and birth data - basis for all simulations
Visualize_Births_and_Temp <- function(Temp_df, Births_df, start_date, end_date){

  year_of_analysis <- year(start_date)

  Temp_plot <- Temp_df %>%
    filter(year(date)==year_of_analysis) %>%
    ggplot() +
    geom_line(aes(x = date, y = x), color = "blue") +
    annotate("rect", fill = "orange", alpha = 0.25,
             xmin = as.Date(start_date), xmax = as.Date(end_date),
             ymin = -Inf, ymax = Inf)+
    theme_minimal() +
    theme(axis.title.x = element_blank()) +
    ylab("Maximum Temperature (F)")

  Preterms_2018_plot <- Births_df %>%
    group_by(date) %>%
    summarise(`Preterm Births` = sum(Preterms)) %>%
    filter(year(date)==year_of_analysis) %>%
    ggplot() +
    geom_line(aes(x = date, y = `Preterm Births`)) +
    annotate("rect", fill = "orange", alpha = 0.25,
             xmin = as.Date(start_date), xmax = as.Date(end_date),
             ymin = -Inf, ymax = Inf) +
    theme_minimal() +
    xlab("Date")

  combined_plot <- ggarrange(Temp_plot, Preterms_2018_plot, ncol = 1, nrow = 2, labels = "AUTO")

  return(combined_plot)
}


#input will have: date, Participant, Case, Gest_Age



date <- seq(as.Date("2007-05-01"), as.Date("2007-05-31"), by="days")
Participant <- seq(1:31)
Gest_Age <- sample(1:100,31,TRUE)
test_df <- data.frame(Participant,date,Gest_Age)

#test_data <- Random_draws(Create_Parameters_for(start = "2018-05-01", end_date = "2018-10-01", Preterms_per_day_all)) %>% filter(Random_draw!=0)%>%
#  uncount(Random_draw) %>%
#  mutate(Participant = row_number(),
#         Case = 1) %>%
#  dplyr::select(date, Participant, Case, Gest_Age)


test_results_2w <- Biweekly_stratification(test_df)
test_results_4w <- FourWk_aka28day_stratification(test_df)
test_results_M <- Month_stratification(test_df)


