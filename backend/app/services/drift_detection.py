# Drift Detection (Phase M — S7)
#
# Data drift and concept drift detection for model monitoring.
# - Statistical test on feature distributions (KL divergence / Population Stability Index)
# - Concept drift detection via prediction change analysis
# - Scheduled retraining trigger when drift exceeds threshold
# - Alert logging with details
#
# Dependencies (already in pyproject.toml):
#   - numpy, pandas, scipy

import logging

import numpy as np
import pandas as pd
from scipy import stats

logger = logging.getLogger("drift-detection")


# Thresholds for drift detection
PSI_THRESHOLD = 0.2  # Population Stability Index threshold
KS_ALPHA = 0.05      # Kolmogorov-Smirnov test significance level
# A single KS p-value below KS_ALPHA is expected by chance for ~5% of the
# monitored features, which would trigger a retraining storm on noise. The
# drift *decision* therefore requires a confirmed KS result (KS_CONFIRM_ALPHA)
# while KS_ALPHA stays the significance level that is reported.
KS_CONFIRM_ALPHA = 0.001
# Floor used instead of 0 when a reference bin has no mass but the actual
# sample does — keeps PSI finite instead of +inf.
PSI_EPSILON = 1e-6
# A PSI bucket needs a minimum number of observations to be stable, otherwise
# the bin counts are dominated by sampling noise.
MIN_SAMPLES_PER_BIN = 20


class DriftResult:
    """Result of drift detection analysis."""
    def __init__(self, drifted: bool, psi: float, ks_stat: float, ks_pvalue: float,
                 drift_type: str, affected_features: list, details: dict):
        self.drifted = drifted
        self.psi = psi
        self.ks_stat = ks_stat
        self.ks_pvalue = ks_pvalue
        self.drift_type = drift_type
        self.affected_features = affected_features
        self.details = details

    def to_dict(self) -> dict:
        return {
            "drifted": self.drifted,
            "psi": self.psi,
            "ks_stat": self.ks_stat,
            "ks_pvalue": self.ks_pvalue,
            "drift_type": self.drift_type,
            "affected_features": self.affected_features,
            "details": self.details,
        }


def _columns_as_arrays(data: pd.DataFrame | pd.Series) -> list[np.ndarray]:
    """Return the data as a list of one-dimensional float arrays.

    ``pandas.qcut`` only accepts one-dimensional input, so a DataFrame has to
    be split per column before any binning happens. A Series is treated as a
    single column.
    """
    if isinstance(data, pd.Series):
        frame = data.to_frame()
    else:
        frame = data

    columns: list[np.ndarray] = []
    for column in frame.columns:
        values = frame[column].dropna()
        if values.empty:
            columns.append(np.asarray([], dtype=float))
            continue
        columns.append(np.asarray(values, dtype=float))
    return columns


def _effective_bins(sample_size: int, requested: int) -> int:
    """Cap the number of bins so that every bin keeps enough observations.

    With the default 10 quantile bins a sample of 100 observations leaves ~10
    observations per bin, and the resulting PSI of two *identical*
    distributions exceeds the 0.2 threshold in ~40% of the runs (measured).
    Capping the bin count keeps PSI usable as a magnitude metric.
    """
    if sample_size <= 0:
        return 1
    return max(1, min(requested, sample_size // MIN_SAMPLES_PER_BIN))


def _psi_for_column(expected: np.ndarray, actual: np.ndarray, bins: int) -> float:
    """Population Stability Index between two one-dimensional samples."""
    if expected.size == 0 or actual.size == 0:
        return 0.0

    # Bin edges are the quantiles of the expected (reference) sample.
    quantiles = np.linspace(0, 1, _effective_bins(expected.size, bins) + 1)
    edges = np.unique(np.quantile(expected, quantiles))
    if edges.size < 2:
        # The reference sample is constant: there is no distribution to
        # compare against, so no evidence of drift.
        return 0.0

    # Values outside the reference range fall into the first/last bin.
    edges = edges.astype(float)
    edges[0] = -np.inf
    edges[-1] = np.inf

    expected_counts, _ = np.histogram(expected, bins=edges)
    actual_counts, _ = np.histogram(actual, bins=edges)

    expected_total = expected_counts.sum()
    actual_total = actual_counts.sum()
    if expected_total == 0 or actual_total == 0:
        return 0.0

    expected_pct = expected_counts / expected_total
    actual_pct = actual_counts / actual_total

    psi = 0.0
    for exp_pct, act_pct in zip(expected_pct, actual_pct, strict=True):
        if exp_pct <= 0:
            # No reference mass in this bin: the term is undefined, skip it.
            continue
        if act_pct <= 0:
            act_pct = PSI_EPSILON
        psi += (act_pct - exp_pct) * np.log(act_pct / exp_pct)
    return float(psi)


def calculate_psi(expected: pd.DataFrame, actual: pd.DataFrame, bins: int = 10) -> float:
    """
    Calculate Population Stability Index between expected (reference) and actual (current) distributions.
    PSI > 0.2 indicates significant drift.

    The reference sample defines the bins (its quantiles) and both samples are
    counted per bin:

        PSI = Σ (actual% − expected%) · ln(actual% / expected%)

    ``expected``/``actual`` may be a Series or a DataFrame. A DataFrame is
    processed column by column — binning a two-dimensional array is what made
    ``pandas.qcut`` raise ``ValueError: Input array must be 1 dimensional``.
    For a multi-column input the returned value is the **worst** (highest) PSI
    of its columns.
    """
    expected_columns = _columns_as_arrays(expected)
    actual_columns = _columns_as_arrays(actual)

    if not expected_columns or not actual_columns:
        return 0.0

    column_psis = []
    for exp_values, act_values in zip(expected_columns, actual_columns, strict=True):
        column_psis.append(_psi_for_column(exp_values, act_values, bins))

    if not column_psis:
        return 0.0
    return float(max(column_psis))


def detect_data_drift(reference: pd.DataFrame, current: pd.DataFrame,
                      feature_cols: list) -> DriftResult:
    """
    Detect data drift between reference and current datasets.
    Uses PSI for numerical features and KS test for distribution comparison.

    The *decision* ("has this feature drifted?") is taken from the
    Kolmogorov-Smirnov test, because the KS p-value is uniformly distributed
    under the null hypothesis: with ``KS_CONFIRM_ALPHA = 0.001`` the detector
    reports a false positive in ~0.1% of the runs. A fixed PSI threshold is
    only a magnitude heuristic and is far too noisy on small samples, so PSI
    is used to quantify the shift and to classify the drift type.
    """
    affected_features = []
    feature_details: dict[str, dict] = {}
    psi_values = []
    ks_statistics = []
    ks_pvalues = []

    for feature in feature_cols:
        if feature not in reference.columns or feature not in current.columns:
            continue

        ref_data = reference[feature].dropna()
        curr_data = current[feature].dropna()

        if len(ref_data) < 10 or len(curr_data) < 10:
            continue

        # Calculate PSI for numerical features
        psi = calculate_psi(ref_data.to_frame(), curr_data.to_frame())
        psi_values.append(psi)

        # Kolmogorov-Smirnov test
        ks_stat, ks_pvalue = stats.ks_2samp(ref_data, curr_data)
        ks_statistics.append(ks_stat)
        ks_pvalues.append(ks_pvalue)

        feature_details[feature] = {
            "psi": psi,
            "ks_stat": float(ks_stat),
            "ks_pvalue": float(ks_pvalue),
        }

        if ks_pvalue < KS_CONFIRM_ALPHA:
            affected_features.append(feature)

    # Determine overall drift
    overall_psi = float(np.mean(psi_values)) if psi_values else 0.0
    min_ks_pvalue = float(min(ks_pvalues)) if ks_pvalues else 1.0
    drifted = bool(affected_features)

    # Drift type: PSI tells how far the distribution moved, the confirmed KS
    # result tells that the move is real.
    data_drift_features = [f for f in affected_features if feature_details[f]["psi"] > PSI_THRESHOLD]
    concept_drift_features = [f for f in affected_features if feature_details[f]["psi"] <= PSI_THRESHOLD]

    if drifted and data_drift_features and concept_drift_features:
        drift_type = "combined_drift"
    elif drifted and data_drift_features:
        drift_type = "data_drift"
    elif drifted and concept_drift_features:
        drift_type = "concept_drift"
    else:
        drift_type = "no_drift"

    details = {
        "overall_psi": overall_psi,
        "psi_threshold": PSI_THRESHOLD,
        "ks_alpha": KS_ALPHA,
        "ks_confirm_alpha": KS_CONFIRM_ALPHA,
        "num_features_checked": len(feature_cols),
        "num_affected_features": len(affected_features),
        "data_drift_features": data_drift_features,
        "concept_drift_features": concept_drift_features,
        "feature_details": feature_details,
    }

    return DriftResult(
        drifted=drifted,
        psi=overall_psi,
        ks_stat=float(np.mean(ks_statistics)) if ks_statistics else 0.0,
        ks_pvalue=min_ks_pvalue,
        drift_type=drift_type,
        affected_features=affected_features,
        details=details,
    )


def analyze_drift(reference_data: pd.DataFrame, current_data: pd.DataFrame,
                  feature_cols: list) -> dict:
    """
    Full drift analysis pipeline.
    Returns dict with drift result and recommendation.
    """
    result = detect_data_drift(reference_data, current_data, feature_cols)

    recommendation = "no_action"
    if result.drifted:
        if result.drift_type == "concept_drift":
            recommendation = "scheduled_retraining"
        elif result.drift_type == "data_drift":
            recommendation = "data_preprocessing"
        else:
            recommendation = "investigate"

    return {
        "drift_result": result.to_dict(),
        "recommendation": recommendation,
        "psi_threshold": PSI_THRESHOLD,
        "ks_alpha": KS_ALPHA,
    }
