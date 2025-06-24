# Instal dan load package
library(dplyr)

# Data
fitted <- prediction$Fitted;fitted
actual <- prediction$Actual;actual

#### UJI HOSMER LEMESHOW ####
hosmer_lemeshow <- function(y_true, y_prob, g = 10) {
  
  data <- data.frame(y = y_true, prob = y_prob)
  data$bin <- ntile(data$prob, g)
  
  obs <- data %>%
    group_by(bin) %>%
    summarise(
      observed = sum(y),
      total = n(),
      expected = sum(prob)
    ) %>%
    mutate(
      not_observed = total - observed,
      not_expected = total - expected,
      chi = ((observed - expected)^2 / expected) + 
        ((not_observed - not_expected)^2 / not_expected)
    )
  
  chi2_stat <- sum(obs$chi)
  df <- g - 2
  p_value <- 1 - pchisq(chi2_stat, df)
  
  list(chi2 = chi2_stat, df = df, p.value = p_value, table = obs)
}
# Menampilkan hasil
result <- hosmer_lemeshow(actual, fitted, g = 10)
cat("Hosmer-Lemeshow Chi² =", round(result$chi2, 3), "\n")
cat("df =", result$df, ", p-value =", round(result$p.value, 4), "\n")
print(result$table)

#### Calibration curve ####
# Membuat data frame
df <- data.frame(actual = actual, prob = fitted)

# Membagi data ke dalam 10 bin berdasarkan peluangnya
df <- df %>%
  mutate(bin = ntile(prob, 10)) %>%
  group_by(bin) %>%
  summarise(
    predicted_prob = mean(prob),
    observed_prob = mean(actual)
  )

# Plot calibration curve
ggplot(df, aes(x = predicted_prob, y = observed_prob)) +
  geom_point(size = 2) +
  geom_line() +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "gray") +
  labs(
    title = "Calibration Curve",
    x = "Predicted Probability",
    y = "Observed Probability"
  ) +
  theme_minimal()

#### Cut-off skor untuk expected default ≤ 5 % ####
# Mendefinisikan batas kepercayaan
cutoff <- 0.05

# Menentukan grup aman (<= 5%)
safe_group <- fitted <= cutoff
default_risk_group <- fitted > cutoff

# Menghitung jumlah dan default rate
total_safe <- sum(safe_group)
default_rate_safe <- mean(actual[safe_group])

cat("Total data dengan risiko default <= 5%:", total_safe, "\n")
cat("Actual default rate dalam grup ini:", round(default_rate_safe, 4), "\n")
