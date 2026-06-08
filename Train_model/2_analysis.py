import os
import sys
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
from matplotlib.patches import Patch
import warnings
warnings.filterwarnings('ignore')

CSV_FILE    = "egg_data.csv"
OUTPUT_DIR  = "plots"
CHANNELS    = ['R', 'S', 'T', 'U', 'V', 'W']
WAVELENGTHS = [610, 680, 730, 760, 810, 860]  # nm — AS7263
 
# Màu sắc theo ngày (đậm dần = cũ hơn)
DAY_COLORS = {
    0:  '#1D9E75',
    3:  '#2BAF7E',
    6:  '#5DCAA5',
    9:  '#378ADD',
    12: '#85B7EB',
    15: '#FAC775',
    18: '#EF9F27',
    21: '#D85A30',
    24: '#A32D2D',
    27: '#791F1F',
}
# ─────────────────────────────────────────────────────────────
 
 
def load_data(filepath):
    """Load và làm sạch dữ liệu CSV"""
    if not os.path.exists(filepath):
        print(f"  LỖI: Không tìm thấy {filepath}")
        print(f"  Hãy chạy 1_uart_logger.py trước để thu thập dữ liệu.")
        sys.exit(1)
 
    df = pd.read_csv(filepath)
    print(f"  Đã load {len(df)} hàng từ {filepath}")
 
    # Trung bình theo egg_id (mỗi trứng lấy trung bình nhiều lần đo)
    agg = {ch: 'mean' for ch in CHANNELS}
    agg['HU']       = 'first'
    agg['weight_g'] = 'first'
    agg['day']      = 'first'
 
    df_egg = df.groupby('egg_id').agg(agg).reset_index()
    df_egg = df_egg.dropna(subset=['HU'])  # chỉ giữ hàng có HU
 
    # Chuẩn hóa: tính tỉ lệ mỗi kênh trên tổng (SNV đơn giản)
    total = df_egg[CHANNELS].sum(axis=1)
    for ch in CHANNELS:
        df_egg[f'ratio_{ch}'] = df_egg[ch] / total
 
    print(f"  Số trứng có HU: {len(df_egg)}")
    print(f"  Phân bố ngày: {sorted(df_egg['day'].unique())}")
    return df_egg
 
 
def grade(hu):
    """Phân loại Grade AA/A/B theo HU"""
    if hu >= 72:
        return 'AA'
    elif hu >= 60:
        return 'A'
    else:
        return 'B'
 
 
def plot_all(df):
    """Vẽ toàn bộ đồ thị và lưu file PNG"""
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    df['grade'] = df['HU'].apply(grade)
 
    # ─────────────────────────────────────────────────────────
    # ĐỒ THỊ 1: NIR Spectrum — vẽ TỪNG MẪU mờ + mean đậm
    # Giống bài báo nhưng thể hiện độ tản mát thực tế
    # ─────────────────────────────────────────────────────────
    fig1, ax = plt.subplots(figsize=(10, 6))
    days_sorted = sorted(df['day'].unique())
 
    # Chọn 6 mốc ngày đại diện để vẽ (tránh rối)
    days_show = [d for d in days_sorted
                 if d in [1, 5, 10, 15, 20, 25]
                 or (len(days_sorted) <= 10)]
    if not days_show:
        days_show = days_sorted[::max(1, len(days_sorted)//6)][:6]
 
    color_list = ['#D62728','#FF7F0E','#BCBD22','#2CA02C','#1F77B4','#9467BD',
                  '#8C564B','#E377C2','#7F7F7F','#17BECF']
 
    for idx, d in enumerate(days_show):
        sub   = df[df['day'] == d]
        color = color_list[idx % len(color_list)]
 
        # Vẽ từng mẫu riêng lẻ — mờ, thể hiện trồi trụt thực tế
        for _, row in sub.iterrows():
            vals = row[CHANNELS].values.astype(float)
            ax.plot(WAVELENGTHS, vals, color=color,
                    linewidth=0.6, alpha=0.18, zorder=1)
 
        # Vẽ mean đậm nổi bật lên trên
        means = sub[CHANNELS].mean().values
        ax.plot(WAVELENGTHS, means, color=color, linewidth=2.2,
                marker='o', markersize=5, label=f'Day {d}',
                alpha=0.95, zorder=3)
 
        # Vùng ±1 std
        stds = sub[CHANNELS].std().values
        ax.fill_between(WAVELENGTHS,
                        means - stds, means + stds,
                        color=color, alpha=0.07, zorder=2)
 
    ax.set_xlabel('Wavelength (nm)', fontsize=12)
    ax.set_ylabel('Raw NIR value (counts)', fontsize=12)
    ax.set_title(
        'NIR spectra of egg samples (AS7263, 6 channels)\n'
        'thin lines = individual measurements, bold = mean ± 1 std',
        fontsize=12)
    ax.set_xticks(WAVELENGTHS)
    ax.set_xticklabels([f'{w}nm\n({ch})' for w, ch in zip(WAVELENGTHS, CHANNELS)])
    ax.legend(title='Storage day', bbox_to_anchor=(1.02, 1),
              loc='upper left', fontsize=9)
    ax.grid(True, alpha=0.25)
    plt.tight_layout()
    p = os.path.join(OUTPUT_DIR, '1_nir_spectrum_by_day.png')
    fig1.savefig(p, dpi=150, bbox_inches='tight')
    print(f"  ✓ Đã lưu: {p}")
    plt.close(fig1)
 
    # ─────────────────────────────────────────────────────────
    # ĐỒ THỊ 2: HU theo ngày (boxplot + mean line)
    # ─────────────────────────────────────────────────────────
    fig2, ax = plt.subplots(figsize=(12, 5))
 
    box_data = [df[df['day'] == d]['HU'].values for d in days_sorted]
    bp = ax.boxplot(box_data, positions=range(len(days_sorted)),
                    patch_artist=True, widths=0.55,
                    medianprops=dict(color='white', linewidth=2))
 
    for patch, d in zip(bp['boxes'], days_sorted):
        hu_avg = df[df['day'] == d]['HU'].mean()
        color  = '#1D9E75' if hu_avg >= 72 else '#378ADD' if hu_avg >= 60 else '#E24B4A'
        patch.set_facecolor(color)
        patch.set_alpha(0.8)
 
    # Jitter points — thể hiện tản mát thực
    rng_jitter = np.random.default_rng(99)
    for i, d in enumerate(days_sorted):
        hu_vals = df[df['day'] == d]['HU'].values
        jitter  = rng_jitter.uniform(-0.18, 0.18, size=len(hu_vals))
        ax.scatter(i + jitter, hu_vals,
                   color='#333333', alpha=0.35, s=10, zorder=3)
 
    ax.axhline(72, color='#1D9E75', linestyle='--', linewidth=1.5,
               alpha=0.7, label='HU=72 (AA/A)')
    ax.axhline(60, color='#E24B4A', linestyle='--', linewidth=1.5,
               alpha=0.7, label='HU=60 (A/B)')
    ax.axhspan(72, 100, alpha=0.04, color='#1D9E75')
    ax.axhspan(60, 72,  alpha=0.04, color='#378ADD')
    ax.axhspan(30, 60,  alpha=0.04, color='#E24B4A')
 
    ax.set_xticks(range(len(days_sorted)))
    ax.set_xticklabels([f'Day {d}' for d in days_sorted], fontsize=9)
    ax.set_ylabel('Haugh Unit (HU)', fontsize=12)
    ax.set_title('Haugh Unit distribution at different storage periods', fontsize=13)
    ax.set_ylim(30, 100)
 
    legend_els = [Patch(facecolor='#1D9E75', label='Grade AA (HU≥72)'),
                  Patch(facecolor='#378ADD', label='Grade A (60≤HU<72)'),
                  Patch(facecolor='#E24B4A', label='Grade B (HU<60)')]
    ax.legend(handles=legend_els, loc='upper right', fontsize=9)
    ax.grid(True, axis='y', alpha=0.3)
    plt.tight_layout()
    p = os.path.join(OUTPUT_DIR, '2_hu_by_day_boxplot.png')
    fig2.savefig(p, dpi=150, bbox_inches='tight')
    print(f"  ✓ Đã lưu: {p}")
    plt.close(fig2)
 
    # ─────────────────────────────────────────────────────────
    # ĐỒ THỊ 3: Correlation scatter — 6 kênh vs HU
    # ─────────────────────────────────────────────────────────
    fig3, axes = plt.subplots(2, 3, figsize=(11, 7))
    axes = axes.flatten()
 
    for i, ch in enumerate(CHANNELS):
        ax = axes[i]
        colors_per_point = df['grade'].map(
            {'AA':'#1D9E75','A':'#378ADD','B':'#E24B4A'})
 
        ax.scatter(df[ch], df['HU'], c=colors_per_point,
                   alpha=0.5, s=25, edgecolors='none')
 
        z     = np.polyfit(df[ch], df['HU'], 1)
        p_fit = np.poly1d(z)
        xs    = np.linspace(df[ch].min(), df[ch].max(), 100)
        ax.plot(xs, p_fit(xs), 'k--', linewidth=1.2, alpha=0.6)
 
        corr = df[[ch, 'HU']].corr().iloc[0, 1]
        ax.set_xlabel(f'{ch} ({WAVELENGTHS[i]}nm)', fontsize=11)
        ax.set_ylabel('HU', fontsize=11)
        ax.set_title(f'r = {corr:.3f}', fontsize=11,
                     color='#185FA5' if abs(corr) > 0.7 else '#666')
        ax.axhline(72, color='#1D9E75', linestyle=':', linewidth=1, alpha=0.6)
        ax.axhline(60, color='#E24B4A', linestyle=':', linewidth=1, alpha=0.6)
        ax.grid(True, alpha=0.2)
 
    legend_els = [Patch(color='#1D9E75', label='AA'),
                  Patch(color='#378ADD', label='A'),
                  Patch(color='#E24B4A', label='B')]
    fig3.legend(handles=legend_els, loc='lower center', ncol=3,
                fontsize=10, bbox_to_anchor=(0.5, -0.02))
    fig3.suptitle('Correlation: NIR channels vs Haugh Unit', fontsize=13, y=1.01)
    plt.tight_layout()
    p = os.path.join(OUTPUT_DIR, '3_channel_vs_hu_scatter.png')
    fig3.savefig(p, dpi=150, bbox_inches='tight')
    print(f"  ✓ Đã lưu: {p}")
    plt.close(fig3)
 
    # ─────────────────────────────────────────────────────────
    # ĐỒ THỊ 4: Radar chart — phổ trung bình theo grade
    # ─────────────────────────────────────────────────────────
    fig4 = plt.figure(figsize=(8, 6))
    ax_r = fig4.add_subplot(111, polar=True)
 
    angles = np.linspace(0, 2*np.pi, len(CHANNELS), endpoint=False).tolist()
    angles += angles[:1]
 
    grade_cfg = {
        'AA': ('#1D9E75', 'Grade AA (≥72 HU)'),
        'A':  ('#378ADD', 'Grade A (60–72 HU)'),
        'B':  ('#E24B4A', 'Grade B (<60 HU)'),
    }
    for g, (color, label) in grade_cfg.items():
        sub = df[df['grade'] == g]
        if len(sub) == 0:
            continue
        vals = sub[CHANNELS].mean().tolist()
        mx   = max(vals) or 1
        vals_norm  = [v/mx for v in vals]
        vals_norm += vals_norm[:1]
        ax_r.plot(angles, vals_norm, color=color, linewidth=2, label=label)
        ax_r.fill(angles, vals_norm, color=color, alpha=0.12)
 
    ax_r.set_xticks(angles[:-1])
    ax_r.set_xticklabels(
        [f'{ch}\n{w}nm' for ch, w in zip(CHANNELS, WAVELENGTHS)], fontsize=10)
    ax_r.set_yticklabels([])
    ax_r.set_title('Average NIR profile by freshness grade', fontsize=13, pad=20)
    ax_r.legend(loc='upper right', bbox_to_anchor=(1.35, 1.1), fontsize=10)
    plt.tight_layout()
    p = os.path.join(OUTPUT_DIR, '4_radar_by_grade.png')
    fig4.savefig(p, dpi=150, bbox_inches='tight')
    print(f"  ✓ Đã lưu: {p}")
    plt.close(fig4)
 
    # ─────────────────────────────────────────────────────────
    # ĐỒ THỊ 5: Predicted vs Measured HU
    # ─────────────────────────────────────────────────────────
    pred_file = "predictions.csv"
    if os.path.exists(pred_file):
        pred_df = pd.read_csv(pred_file)
        fig5, ax = plt.subplots(figsize=(6, 6))
        ax.scatter(pred_df['HU_measured'], pred_df['HU_predicted'],
                   alpha=0.7, s=50, color='#185FA5',
                   edgecolors='none', label='Samples')
 
        mn = min(pred_df['HU_measured'].min(), pred_df['HU_predicted'].min()) - 2
        mx = max(pred_df['HU_measured'].max(), pred_df['HU_predicted'].max()) + 2
        ax.plot([mn, mx], [mn, mx], 'r--', linewidth=1.5, label='1:1 line')
 
        from sklearn.metrics import r2_score, mean_squared_error
        r2   = r2_score(pred_df['HU_measured'], pred_df['HU_predicted'])
        rmse = np.sqrt(mean_squared_error(
            pred_df['HU_measured'], pred_df['HU_predicted']))
        ax.text(0.05, 0.92, f'R² = {r2:.4f}\nRMSEP = {rmse:.4f}',
                transform=ax.transAxes, fontsize=11,
                bbox=dict(boxstyle='round', facecolor='white', alpha=0.8))
 
        ax.set_xlabel('Measured HU', fontsize=12)
        ax.set_ylabel('Predicted HU', fontsize=12)
        ax.set_title('Predicted vs Measured Haugh Unit', fontsize=13)
        ax.legend(fontsize=10)
        ax.grid(True, alpha=0.3)
        ax.set_xlim(mn, mx); ax.set_ylim(mn, mx)
        plt.tight_layout()
        p = os.path.join(OUTPUT_DIR, '5_predicted_vs_measured.png')
        fig5.savefig(p, dpi=150, bbox_inches='tight')
        print(f"  ✓ Đã lưu: {p}")
        plt.close(fig5)
    else:
        print(f"  [INFO] Chưa có {pred_file} — bỏ qua đồ thị Predicted vs Measured")
        print(f"         Chạy 3_train_model.py để tạo file này.")
 
    # ─────────────────────────────────────────────────────────
    # ĐỒ THỊ 6: Confusion matrix phân loại Grade
    # ─────────────────────────────────────────────────────────
    conf_file = "confusion.csv"
    if os.path.exists(conf_file):
        try:
            import seaborn as sns
            conf_df  = pd.read_csv(conf_file)
            grades   = ['AA', 'A', 'B']
            conf_mat = (conf_df.pivot('true', 'predicted', 'count')
                        .reindex(grades).reindex(columns=grades).fillna(0))
            totals   = conf_mat.sum(axis=1)
            conf_pct = conf_mat.div(totals, axis=0) * 100
 
            fig6, ax = plt.subplots(figsize=(6, 5))
            sns.heatmap(conf_pct, annot=True, fmt='.1f', cmap='Blues',
                        ax=ax, cbar_kws={'label': '%'},
                        linewidths=0.5, linecolor='white')
            ax.set_xlabel('Predicted class', fontsize=12)
            ax.set_ylabel('True class', fontsize=12)
 
            acc = conf_mat.values.trace() / conf_mat.values.sum() * 100
            ax.set_title(f'Confusion matrix — Accuracy: {acc:.1f}%', fontsize=13)
            plt.tight_layout()
            p = os.path.join(OUTPUT_DIR, '6_confusion_matrix.png')
            fig6.savefig(p, dpi=150, bbox_inches='tight')
            print(f"  ✓ Đã lưu: {p}")
            plt.close(fig6)
        except ImportError:
            print("  [INFO] Cài seaborn để xem confusion matrix: pip install seaborn")
    else:
        print(f"  [INFO] Chưa có {conf_file} — chạy 3_train_model.py trước")
 
    # ─────────────────────────────────────────────────────────
    # In thống kê
    # ─────────────────────────────────────────────────────────
    print("\n" + "─"*50)
    print("THỐNG KÊ DỮ LIỆU")
    print("─"*50)
    print(df.groupby('day')['HU'].agg(
        ['count','mean','std','min','max']).round(2).to_string())
    print(f"\n  Phân bố Grade:")
    print(df['grade'].value_counts().to_string())
 
    corrs = df[CHANNELS].corrwith(df['HU'])
    print(f"\n  Tương quan kênh vs HU:")
    for ch, r in corrs.items():
        bar = '█' * int(abs(r)*20)
        print(f"    {ch}: {r:+.3f}  {bar}")
 
 
def main():
    print("╔══════════════════════════════════════════════╗")
    print("║      EGG FRESHNESS — DATA ANALYSIS           ║")
    print("╚══════════════════════════════════════════════╝\n")
 
    df = load_data(CSV_FILE)
 
    if len(df) == 0:
        print("  Không có dữ liệu hợp lệ (cần có cột HU).")
        print("  Hãy thêm cột HU vào CSV sau khi đo tay.")
        return
 
    print(f"\n  Đang vẽ đồ thị...")
    plot_all(df)
 
    print(f"\n  ✓ Hoàn thành! Mở thư mục '{OUTPUT_DIR}/' để xem đồ thị.")
 
 
if __name__ == "__main__":
    main()
 