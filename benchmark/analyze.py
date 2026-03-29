import matplotlib.pyplot as plt
import polars as pl
import seaborn as sns

pl.Config.set_tbl_rows(-1)
pl.Config.set_tbl_cols(-1)

BENCH_CSV = "bench.csv"

METRIC_PAIRS: list[tuple[str, str, str, str]] = [
    ("avg wall (ms)", "sort_avg_wall_ms", "msort_avg_wall_ms", "avg_wall_ms_perf (%)"),
    ("avg user (ms)", "sort_avg_user_ms", "msort_avg_user_ms", "avg_user_ms_perf (%)"),
    ("avg system (ms)", "sort_avg_system_ms", "msort_avg_system_ms", "avg_system_ms_perf (%)"),
]

df = pl.read_csv(BENCH_CSV)

summary = df.sql(
    """
    SELECT
        name,
        sort_avg_wall_ms,
        msort_avg_wall_ms,
        100.0 * (msort_avg_wall_ms - sort_avg_wall_ms) / sort_avg_wall_ms
            AS "avg_wall_ms_perf (%)",
        sort_avg_user_ms,
        msort_avg_user_ms,
        100.0 * (msort_avg_user_ms - sort_avg_user_ms) / sort_avg_user_ms
            AS "avg_user_ms_perf (%)",
        sort_avg_system_ms,
        msort_avg_system_ms,
        100.0 * (msort_avg_system_ms - sort_avg_system_ms) / sort_avg_system_ms
            AS "avg_system_ms_perf (%)"
    FROM (
        SELECT
            name,
            AVG(CASE WHEN which = 'sort' THEN wall_ms END) AS sort_avg_wall_ms,
            AVG(CASE WHEN which = 'msort' THEN wall_ms END) AS msort_avg_wall_ms,
            AVG(CASE WHEN which = 'sort' THEN user_ms END) AS sort_avg_user_ms,
            AVG(CASE WHEN which = 'msort' THEN user_ms END) AS msort_avg_user_ms,
            AVG(CASE WHEN which = 'sort' THEN system_ms END) AS sort_avg_system_ms,
            AVG(CASE WHEN which = 'msort' THEN system_ms END) AS msort_avg_system_ms
        FROM self
        GROUP BY name
    ) AS by_name
    ORDER BY name
    """
).select(pl.col("name"), pl.exclude("name").round(3))

print(summary)

long_parts: list[pl.DataFrame] = []
for label, sort_col, msort_col, _perf in METRIC_PAIRS:
    long_parts.append(
        summary.select(
            pl.col("name"),
            pl.lit(label).alias("metric"),
            pl.lit("sort").alias("tool"),
            pl.col(sort_col).alias("value"),
        )
    )
    long_parts.append(
        summary.select(
            pl.col("name"),
            pl.lit(label).alias("metric"),
            pl.lit("msort").alias("tool"),
            pl.col(msort_col).alias("value"),
        )
    )
plot_df = pl.concat(long_parts).to_pandas()
summary_pd = summary.to_pandas()
name_order = summary.get_column("name").to_list()

sns.set_theme(style="whitegrid")
grid = sns.catplot(
    data=plot_df,
    kind="bar",
    x="name",
    y="value",
    order=name_order,
    hue="tool",
    hue_order=["sort", "msort"],
    col="metric",
    col_order=[p[0] for p in METRIC_PAIRS],
    col_wrap=2,
    sharey=False,
    height=3.5,
    aspect=1.25,
    palette="muted",
    legend_out=False,
)
grid.set_axis_labels("benchmark", "")
grid.set_titles("{col_name}")
for i, ax in enumerate(grid.axes.flat):
    if ax is None:
        continue
    for container in ax.containers:
        ax.bar_label(container, fmt="%.3f", padding=2, fontsize=8)
    metric_label, _, _, perf_col = METRIC_PAIRS[i]
    for x_idx, name in enumerate(name_order):
        pct = float(summary_pd.loc[summary_pd["name"] == name, perf_col].iloc[0])
        sub = plot_df[(plot_df["name"] == name) & (plot_df["metric"] == metric_label)]
        ymax = float(sub["value"].max())
        ax.annotate(
            f"{pct:+.3f}%",
            xy=(x_idx, ymax),
            xytext=(0, 14),
            textcoords="offset points",
            ha="center",
            va="bottom",
            fontsize=7,
            color="#333333",
        )
    ax.margins(y=0.22)
    plt.setp(ax.get_xticklabels(), rotation=40, ha="right")
grid.tight_layout(rect=(0, 0.06, 1, 1))
plt.show()
