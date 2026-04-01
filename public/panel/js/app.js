(function () {
  const byId = (id) => document.getElementById(id);
  const money = (v) => `${Number(v || 0).toLocaleString("ru-RU", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ₽`;
  const pct = (v) => `${(Number(v || 0) * 100).toFixed(2)}%`;
  const num = (v) => Number(v || 0);

  function toIso(d) {
    return d.toISOString().slice(0, 10);
  }

  function parseIso(s) {
    return new Date(`${s}T00:00:00`);
  }

  function defaultDates() {
    const to = new Date();
    const from = new Date();
    from.setDate(to.getDate() - 30);
    byId("from").value = toIso(from);
    byId("to").value = toIso(to);
  }

  function currentRange() {
    return { from: byId("from").value, to: byId("to").value };
  }

  function previousRange() {
    const { from, to } = currentRange();
    const fromDate = parseIso(from);
    const toDate = parseIso(to);
    const days = Math.max(1, Math.round((toDate - fromDate) / 86400000) + 1);
    const prevTo = new Date(fromDate);
    prevTo.setDate(prevTo.getDate() - 1);
    const prevFrom = new Date(prevTo);
    prevFrom.setDate(prevFrom.getDate() - (days - 1));
    return { from: toIso(prevFrom), to: toIso(prevTo) };
  }

  function setStatus(msg) {
    if (byId("status")) byId("status").textContent = msg;
  }

  async function jget(url) {
    const res = await fetch(url, { credentials: "same-origin" });
    if (res.status === 401) {
      window.location.href = "/login";
      throw new Error("Unauthorized");
    }
    if (!res.ok) throw new Error(`${res.status} ${url}`);
    return res.json();
  }

  async function jpost(url, body) {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "same-origin",
      body: JSON.stringify(body),
    });
    if (res.status === 401) {
      window.location.href = "/login";
      throw new Error("Unauthorized");
    }
    if (!res.ok) throw new Error(`${res.status} ${url}`);
    return res.json();
  }

  function qs() {
    const { from, to } = currentRange();
    return `from=${from}&to=${to}`;
  }

  function renderRows(selector, html, colspan = 6) {
    const el = document.querySelector(selector);
    if (!el) return;
    el.innerHTML = html || `<tr><td colspan="${colspan}" class="tiny">Нет данных</td></tr>`;
  }

  function markActiveRow(containerSelector, keyAttr, keyValue) {
    const container = document.querySelector(containerSelector);
    if (!container) return;
    container.querySelectorAll(".row-clickable").forEach((row) => {
      if (row.getAttribute(keyAttr) === keyValue) row.classList.add("active-row");
      else row.classList.remove("active-row");
    });
  }

  function ensureChartTooltip() {
    let tooltip = byId("chart-tooltip-global");
    if (tooltip) return tooltip;
    tooltip = document.createElement("div");
    tooltip.id = "chart-tooltip-global";
    tooltip.className = "chart-tooltip";
    document.body.appendChild(tooltip);
    return tooltip;
  }

  function ensureKpiModal() {
    let backdrop = byId("kpi-modal-backdrop");
    if (backdrop) return backdrop;
    backdrop = document.createElement("div");
    backdrop.id = "kpi-modal-backdrop";
    backdrop.className = "modal-backdrop";
    backdrop.innerHTML = `
      <div class="modal-box">
        <div class="modal-title" id="kpi-modal-title"></div>
        <div class="modal-content" id="kpi-modal-content"></div>
        <div class="actions" style="margin-top:10px;">
          <button id="kpi-modal-close">Закрыть</button>
        </div>
      </div>
    `;
    document.body.appendChild(backdrop);
    backdrop.addEventListener("click", (e) => {
      if (e.target === backdrop) backdrop.classList.remove("open");
    });
    backdrop.querySelector("#kpi-modal-close")?.addEventListener("click", () => backdrop.classList.remove("open"));
    return backdrop;
  }

  function bindKpiExplainers() {
    const modal = ensureKpiModal();
    const title = byId("kpi-modal-title");
    const content = byId("kpi-modal-content");
    const defs = {
      revenue: {
        title: "Выручка",
        text: "Сумма всех оплаченных заказов за выбранный период. Формула: сумма amount_rub по paid-заказам."
      },
      profit: {
        title: "Прибыль (оценка)",
        text: "Консервативная оценка прибыли: выручка минус себестоимость и явные расходы (скидки/бонусы, где доступны)."
      },
      orders_created: {
        title: "Создано заказов",
        text: "Количество заказов, созданных в выбранном периоде, независимо от финального статуса оплаты."
      },
      orders_paid: {
        title: "Оплачено заказов",
        text: "Количество заказов, которые перешли в статус успешной оплаты по маппингу статусов."
      },
      payment_conversion: {
        title: "Конверсия оплаты",
        text: "Доля оплаченных заказов от созданных. Формула: orders_paid / orders_created."
      },
      repeat_rate: {
        title: "Доля повторных покупок",
        text: "Доля повторных покупателей среди уникальных покупателей периода. Формула: число повторных покупателей / число уникальных покупателей."
      }
    };
    document.querySelectorAll("[data-kpi-key]").forEach((card) => {
      card.onclick = () => {
        const key = card.getAttribute("data-kpi-key");
        const d = defs[key];
        if (!d) return;
        if (title) title.textContent = d.title;
        if (content) content.textContent = d.text;
        modal.classList.add("open");
      };
    });
  }

  function bindReferralExplainer() {
    const btn = byId("ref-help-btn");
    if (!btn) return;
    const modal = ensureKpiModal();
    const title = byId("kpi-modal-title");
    const content = byId("kpi-modal-content");
    btn.onclick = () => {
      if (title) title.textContent = "Пояснение реферальных метрик";
      if (content) {
        content.innerHTML = `
          <div><strong>Новых:</strong> сколько новых пользователей пришло по реф-связи в этот день.</div>
          <div><strong>Создано / Оплачено / Неуспешно:</strong> статусы заказов рефералов за день.</div>
          <div><strong>Платежные события:</strong> все обновления платежных статусов (может быть много на 1 заказ).</div>
          <div><strong>Платежные заказы:</strong> число уникальных заказов, у которых были платежные транзакции.</div>
          <div><strong>Конверсия создано→оплачено:</strong> оплачено / создано.</div>
          <div><strong>Конверсия платежные заказы→оплачено:</strong> оплачено / уникальные платежные заказы.</div>
          <div><strong>Прибыль:</strong> выручка рефералов минус реферальные бонусы (оценка).</div>
        `;
      }
      modal.classList.add("open");
    };
  }

  function aggregate(items, key, numericKeys) {
    const out = {};
    items.forEach((row) => {
      const k = row[key] || "unknown";
      if (!out[k]) out[k] = { [key]: k };
      numericKeys.forEach((nk) => {
        out[k][nk] = num(out[k][nk]) + num(row[nk]);
      });
    });
    return Object.values(out);
  }

  function renderBars(elId, rows, labelKey, valKey) {
    const root = byId(elId);
    if (!root) return;
    const max = Math.max(...rows.map((r) => num(r[valKey])), 1);
    root.innerHTML = rows.map((r) => {
      const value = num(r[valKey]);
      const width = (value / max) * 100;
      return `<div class="bar-row">
        <div class="tiny">${r[labelKey]}</div>
        <div class="bar-bg"><div class="bar-fg" style="width:${width}%"></div></div>
        <div class="tiny">${money(value)}</div>
      </div>`;
    }).join("");
  }

  function linePath(points) {
    if (!points.length) return "";
    let d = `M ${points[0][0]} ${points[0][1]}`;
    for (let i = 1; i < points.length; i += 1) d += ` L ${points[i][0]} ${points[i][1]}`;
    return d;
  }

  function alignPreviousSeries(previousItems, targetLength, valueKey) {
    const vals = (previousItems || []).map((x) => num(x[valueKey]));
    if (vals.length === targetLength) return vals;
    if (vals.length > targetLength) return vals.slice(vals.length - targetLength);
    const pad = Array(Math.max(0, targetLength - vals.length)).fill(0);
    return pad.concat(vals);
  }

  function renderLineChart(svgId, currentItems, valueKey, previousItems, legendCurrent, legendPrevious) {
    const svg = byId(svgId);
    if (!svg) return;

    const w = 1000;
    const h = 320;
    const p = { l: 62, r: 18, t: 20, b: 44 };
    const currVals = (currentItems || []).map((x) => num(x[valueKey]));
    const dates = (currentItems || []).map((x) => x.date || "");
    const prevVals = alignPreviousSeries(previousItems, currVals.length, valueKey);
    const max = Math.max(...currVals, ...prevVals, 1);
    const plotW = w - p.l - p.r;
    const plotH = h - p.t - p.b;
    const toX = (i) => p.l + (plotW * (i / Math.max(currVals.length - 1, 1)));
    const toY = (v) => p.t + plotH * (1 - v / max);

    const currPts = currVals.map((v, i) => [toX(i), toY(v)]);
    const prevPts = prevVals.map((v, i) => [toX(i), toY(v)]);

    const gridLines = [];
    for (let i = 0; i <= 4; i += 1) {
      const y = p.t + (plotH * i) / 4;
      const val = Math.round(max * (1 - i / 4));
      gridLines.push(`<line x1="${p.l}" y1="${y}" x2="${w - p.r}" y2="${y}" stroke="rgba(139,148,158,.24)" stroke-width="1"/>`);
      gridLines.push(`<text x="${p.l - 8}" y="${y + 4}" fill="#8b949e" font-size="11" text-anchor="end">${val.toLocaleString("ru-RU")}</text>`);
    }

    const ticks = Math.min(7, dates.length);
    const xLabels = [];
    for (let i = 0; i < ticks; i += 1) {
      const idx = Math.round((dates.length - 1) * (i / Math.max(ticks - 1, 1)));
      const x = toX(idx);
      const d = (dates[idx] || "").slice(5);
      xLabels.push(`<text x="${x}" y="${h - 12}" fill="#8b949e" font-size="11" text-anchor="middle">${d}</text>`);
      xLabels.push(`<line x1="${x}" y1="${h - p.b}" x2="${x}" y2="${h - p.b + 5}" stroke="rgba(139,148,158,.24)"/>`);
    }

    svg.setAttribute("viewBox", `0 0 ${w} ${h}`);
    svg.innerHTML = `
      <defs>
        <linearGradient id="${svgId}-grad" x1="0" x2="1" y1="0" y2="0">
          <stop offset="0%" stop-color="#22d3ee"/>
          <stop offset="100%" stop-color="#06b6d4"/>
        </linearGradient>
      </defs>
      ${gridLines.join("")}
      <path d="${linePath(prevPts)}" fill="none" stroke="#6e7681" stroke-width="2" stroke-dasharray="6 5" opacity="0.9"/>
      <path d="${linePath(currPts)}" fill="none" stroke="url(#${svgId}-grad)" stroke-width="3"/>
      ${currPts.map((p2) => `<circle cx="${p2[0]}" cy="${p2[1]}" r="3.4" fill="#dff9ff"/>`).join("")}
      <line id="${svgId}-cross" x1="0" y1="${p.t}" x2="0" y2="${h - p.b}" stroke="rgba(34,211,238,.35)" stroke-width="1" style="display:none"/>
      ${xLabels.join("")}
      <g transform="translate(${w - 280}, ${p.t + 8})">
        <rect x="0" y="-12" width="10" height="3" fill="url(#${svgId}-grad)"/>
        <text x="14" y="-8" fill="#c9d1d9" font-size="11">${legendCurrent || "Текущий период"}</text>
        <line x1="120" y1="-10" x2="136" y2="-10" stroke="#6e7681" stroke-width="2" stroke-dasharray="5 4"/>
        <text x="142" y="-8" fill="#8b949e" font-size="11">${legendPrevious || "Предыдущий период"}</text>
      </g>
    `;

    const tooltip = ensureChartTooltip();
    const cross = byId(`${svgId}-cross`);
    svg.onmousemove = (e) => {
      if (!currVals.length) return;
      const rect = svg.getBoundingClientRect();
      const relX = ((e.clientX - rect.left) / rect.width) * w;
      const idx = Math.min(currVals.length - 1, Math.max(0, Math.round(((relX - p.l) / plotW) * Math.max(currVals.length - 1, 1))));
      const date = dates[idx] || "-";
      const curr = currVals[idx] || 0;
      const prev = prevVals[idx] || 0;
      const diff = curr - prev;
      const sign = diff > 0 ? "+" : "";
      const isMoneySeries = valueKey.includes("revenue") || valueKey.includes("profit") || valueKey.includes("_rub");
      const fmt = (v) => isMoneySeries ? money(v) : v.toLocaleString("ru-RU");

      if (cross) {
        cross.setAttribute("x1", toX(idx));
        cross.setAttribute("x2", toX(idx));
        cross.style.display = "block";
      }

      tooltip.style.display = "block";
      tooltip.innerHTML = `
        <div><strong>${date}</strong></div>
        <div>Текущий: ${fmt(curr)}</div>
        <div>Предыдущий: ${fmt(prev)}</div>
        <div>Δ: ${sign}${fmt(diff)}</div>
      `;
      tooltip.style.left = `${e.clientX + 14}px`;
      tooltip.style.top = `${e.clientY + 14}px`;
    };
    svg.onmouseleave = () => {
      tooltip.style.display = "none";
      if (cross) cross.style.display = "none";
    };
  }

  function renderCohortHeatmap(elId, rows) {
    const root = byId(elId);
    if (!root) return;
    const items = rows || [];
    if (!items.length) {
      root.innerHTML = '<div class="tiny">Нет данных для тепловой карты когорт</div>';
      return;
    }

    const byWeek = {};
    const ages = new Set();
    items.forEach((r) => {
      byWeek[r.cohort_week] ||= {};
      byWeek[r.cohort_week][r.age_week] = num(r.retention_rate);
      ages.add(num(r.age_week));
    });
    const weeks = Object.keys(byWeek).sort().slice(-8);
    const ageList = Array.from(ages).sort((a, b) => a - b).slice(0, 8);

    function cell(rate) {
      const alpha = Math.max(0.08, Math.min(0.75, rate * 1.4));
      return `background: rgba(34, 211, 238, ${alpha});`;
    }

    const table = `
      <table class="heatmap-table">
        <thead>
          <tr><th>Неделя когорты</th>${ageList.map((a) => `<th>${a} нед.</th>`).join("")}</tr>
        </thead>
        <tbody>
          ${weeks.map((w) => `
            <tr>
              <td>${w}</td>
              ${ageList.map((a) => {
                const rate = byWeek[w][a] || 0;
                return `<td style="${cell(rate)}">${(rate * 100).toFixed(0)}%</td>`;
              }).join("")}
            </tr>
          `).join("")}
        </tbody>
      </table>
    `;
    root.innerHTML = table;
  }

  function renderHourlyHeatmap(elId, rows) {
    const root = byId(elId);
    if (!root) return;
    const data = rows || [];
    if (!data.length) {
      root.innerHTML = '<div class="tiny">Нет данных</div>';
      return;
    }

    const maxVal = Math.max(...data.map((x) => num(x.paid_orders_count)), 1);
    const map = {};
    data.forEach((r) => {
      map[`${r.iso_dow}-${r.hour}`] = num(r.paid_orders_count);
    });
    const dayLabels = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"];
    const hours = Array.from({ length: 24 }, (_, h) => h);

    const rowsHtml = dayLabels.map((day, idx) => {
      const dow = idx + 1;
      const cells = hours.map((h) => {
        const value = map[`${dow}-${h}`] || 0;
        const alpha = Math.max(0.06, Math.min(0.86, value / maxVal));
        return `<td class="hourly-cell" style="background: rgba(34, 211, 238, ${alpha.toFixed(2)});">${value}</td>`;
      }).join("");
      return `<tr><td>${day}</td>${cells}</tr>`;
    }).join("");

    root.innerHTML = `
      <table class="hourly-table">
        <thead><tr><th></th>${hours.map((h) => `<th>${h}</th>`).join("")}</tr></thead>
        <tbody>${rowsHtml}</tbody>
      </table>
    `;
  }

  async function fetchDailyWithPrevious() {
    const { from, to } = currentRange();
    const prev = previousRange();
    const [currDaily, prevDaily] = await Promise.all([
      jget(`/metrics/daily?from=${from}&to=${to}`),
      jget(`/metrics/daily?from=${prev.from}&to=${prev.to}`),
    ]);
    return { currDaily: currDaily.items || [], prevDaily: prevDaily.items || [] };
  }

  async function pageOverview() {
    const [summary, providers, products, dailyPack, insights] = await Promise.all([
      jget(`/metrics/summary?${qs()}`),
      jget(`/metrics/providers?${qs()}`),
      jget(`/metrics/products?${qs()}`),
      fetchDailyWithPrevious(),
      jget(`/metrics/insights?${qs()}`),
    ]);

    byId("kpi-revenue").textContent = money(summary.revenue_total_rub);
    byId("kpi-profit").textContent = money(summary.profit_total_rub);
    byId("kpi-created").textContent = num(summary.orders_created_count).toLocaleString("ru-RU");
    byId("kpi-paid").textContent = num(summary.orders_paid_count).toLocaleString("ru-RU");
    byId("kpi-conv").textContent = pct(summary.paid_conversion_rate);
    byId("kpi-repeat").textContent = pct(summary.repeat_purchase_rate);
    byId("kpi-avg").textContent = money(summary.avg_check_rub);
    byId("top-provider").textContent = summary.top_provider ? `${summary.top_provider} · ${money(summary.top_provider_revenue_rub)}` : "-";
    byId("top-product").textContent = summary.top_product ? `${summary.top_product} · ${money(summary.top_product_revenue_rub)}` : "-";

    renderLineChart("revenue-chart", dailyPack.currDaily, "revenue_rub", dailyPack.prevDaily, "Текущий период", "Предыдущий");

    const provAgg = aggregate(providers.items || [], "payment_provider", ["orders_created_count", "orders_paid_count", "revenue_rub"])
      .sort((a, b) => b.revenue_rub - a.revenue_rub);
    renderRows("#providers-table", provAgg.map((r) =>
      `<tr><td><span class="pill">${r.payment_provider}</span></td><td>${r.orders_created_count}</td><td>${r.orders_paid_count}</td><td>${money(r.revenue_rub)}</td><td>${pct(r.orders_created_count ? r.orders_paid_count / r.orders_created_count : 0)}</td></tr>`
    ).join(""), 5);
    renderBars("providers-bars", provAgg.slice(0, 6), "payment_provider", "revenue_rub");

    const prodAgg = aggregate(products.items || [], "product_type", ["orders_paid_count", "revenue_rub", "profit_rub"])
      .sort((a, b) => b.revenue_rub - a.revenue_rub);
    renderRows("#products-table", prodAgg.map((r) =>
      `<tr><td><span class="pill">${r.product_type}</span></td><td>${r.orders_paid_count}</td><td>${money(r.revenue_rub)}</td><td>${money(r.profit_rub)}</td></tr>`
    ).join(""), 4);

    renderRows("#daily-drill-table", (dailyPack.currDaily || []).map((r) =>
      `<tr class="row-clickable" data-day="${r.date}">
        <td>${r.date}</td>
        <td>${r.orders_created_count}</td>
        <td>${r.orders_paid_count}</td>
        <td>${money(r.revenue_rub)}</td>
        <td>${money(r.profit_rub)}</td>
        <td>${pct(r.pay_conversion_rate)}</td>
      </tr>`
    ).join(""), 6);

    const drillRows = document.querySelectorAll("#daily-drill-table tr.row-clickable");
    drillRows.forEach((row) => {
      row.addEventListener("click", async () => {
        const date = row.getAttribute("data-day");
        try {
          const details = await jget(`/metrics/daily/details?date=${date}`);
          if (byId("day-selected-label")) byId("day-selected-label").textContent = `День: ${date}`;
          if (byId("dd-revenue")) byId("dd-revenue").textContent = money(details.breakdown.revenue_rub);
          if (byId("dd-cost")) byId("dd-cost").textContent = money(details.breakdown.cost_rub);
          if (byId("dd-net-profit")) byId("dd-net-profit").textContent = money(details.breakdown.net_profit_estimate_rub);
          if (byId("dd-turnover")) byId("dd-turnover").textContent = money(details.breakdown.turnover_rub);
          if (byId("dd-formula")) byId("dd-formula").textContent = `${details.breakdown.formula}; скидки по промокодам=${money(details.breakdown.promo_discount_rub)}, реферальные бонусы=${money(details.breakdown.referral_bonus_rub)}`;

          renderRows("#dd-buyers-table", (details.buyers || []).map((b) =>
            `<tr><td>${b.username} <span class="tiny">(${b.user_id})</span></td><td>${b.paid_orders_count}</td><td>${money(b.revenue_rub)}</td><td>${money(b.cost_rub)}</td><td>${money(b.gross_profit_rub)}</td></tr>`
          ).join(""), 5);
          markActiveRow("#daily-drill-table", "data-day", date);
        } catch (e) {
          setStatus(e.message);
        }
      });
    });

    const k = insights.kpis || {};
    if (byId("ins-arppu")) byId("ins-arppu").textContent = money(k.arppu_rub);
    if (byId("ins-ltv")) byId("ins-ltv").textContent = money(k.ltv_30d_proxy_rub);
    if (byId("ins-cac")) byId("ins-cac").textContent = money(k.cac_proxy_rub);
    if (byId("ins-r7")) byId("ins-r7").textContent = pct(k.retention_d7_rate);
    if (byId("ins-r30")) byId("ins-r30").textContent = pct(k.retention_d30_rate);
    if (byId("ins-margin")) byId("ins-margin").textContent = pct(k.gross_margin_rate);

    renderRows("#anomalies-table", (insights.anomalies || []).map((a) =>
      `<tr><td>${a.date}</td><td><span class="pill">${a.metric}</span></td><td>${a.metric === "revenue_rub" ? money(a.value) : a.value}</td><td class="${a.z_score < 0 ? "warn" : "danger"}">${a.z_score}</td></tr>`
    ).join(""), 4);

    renderHourlyHeatmap("hourly-heatmap", insights.hourly_heatmap || []);
    bindKpiExplainers();
  }

  async function pageRevenue() {
    const [referrals, promos, dailyPack] = await Promise.all([
      jget(`/metrics/referrals?${qs()}`),
      jget(`/metrics/promos?${qs()}`),
      fetchDailyWithPrevious(),
    ]);

    renderLineChart("revenue-chart", dailyPack.currDaily, "revenue_rub", dailyPack.prevDaily, "Текущая выручка", "Прошлый период");
    renderLineChart("profit-chart", dailyPack.currDaily, "profit_rub", dailyPack.prevDaily, "Текущая прибыль", "Прошлый период");

    const refTotals = referrals.totals || {};
    if (byId("ref-kpi-new-users")) byId("ref-kpi-new-users").textContent = num(refTotals.new_referred_users_count).toLocaleString("ru-RU");
    if (byId("ref-kpi-paid")) byId("ref-kpi-paid").textContent = num(refTotals.referred_orders_paid_count).toLocaleString("ru-RU");
    if (byId("ref-kpi-revenue")) byId("ref-kpi-revenue").textContent = money(refTotals.referred_revenue_rub);
    if (byId("ref-kpi-profit")) byId("ref-kpi-profit").textContent = money(refTotals.referral_profit_rub);

    renderRows("#referrals-table", (referrals.items || []).slice(-31).reverse().map((r) =>
      `<tr>
        <td>${r.date}</td>
        <td>${r.new_referred_users_count}</td>
        <td>${r.referred_orders_created_count}</td>
        <td>${r.referred_orders_paid_count}</td>
        <td>${r.referred_orders_failed_count}</td>
        <td>${r.referred_payment_attempts_count}</td>
        <td>${r.referred_payment_orders_count}</td>
        <td>${pct(r.referred_created_to_paid_rate)}</td>
        <td>${pct(r.referred_attempt_to_paid_rate)}</td>
        <td>${r.referred_unique_buyers_count}</td>
        <td>${money(r.referred_avg_check_rub)}</td>
        <td>${money(r.referred_revenue_rub)}</td>
        <td>${money(r.referral_bonus_cost_rub)}</td>
        <td class="${num(r.referral_profit_rub) < 0 ? "danger" : "ok"}">${money(r.referral_profit_rub)}</td>
      </tr>`
    ).join(""), 14);

    const promoAgg = aggregate(promos.items || [], "promo_code", ["redemptions_count", "paid_orders_count", "discount_total_rub", "revenue_after_discount_rub", "profit_after_discount_rub"])
      .sort((a, b) => b.revenue_after_discount_rub - a.revenue_after_discount_rub);
    renderRows("#promos-table", promoAgg.map((r) =>
      `<tr><td><span class="pill">${r.promo_code}</span></td><td>${r.redemptions_count}</td><td>${r.paid_orders_count}</td><td>${money(r.discount_total_rub)}</td><td>${money(r.revenue_after_discount_rub)}</td><td>${money(r.profit_after_discount_rub)}</td></tr>`
    ).join(""), 6);
    bindReferralExplainer();
  }

  async function pageUsers() {
    const [summary, cohorts, dailyPack] = await Promise.all([
      jget(`/metrics/summary?${qs()}`),
      jget(`/metrics/cohorts?from_cohort_week=${currentRange().from}&to_cohort_week=${currentRange().to}`),
      fetchDailyWithPrevious(),
    ]);
    byId("u-unique").textContent = num(summary.unique_buyers_count).toLocaleString("ru-RU");
    byId("u-repeat").textContent = num(summary.repeat_buyers_count).toLocaleString("ru-RU");
    byId("u-rate").textContent = pct(summary.repeat_purchase_rate);
    renderLineChart("buyers-chart", dailyPack.currDaily, "unique_buyers_count", dailyPack.prevDaily, "Уникальные покупатели", "Прошлый период");
    renderRows("#cohorts-table", (cohorts.items || []).slice(0, 40).map((r) =>
      `<tr><td>${r.cohort_week}</td><td>${r.age_week}</td><td>${r.users_count}</td><td>${r.repeat_buyers_count}</td><td>${pct(r.retention_rate)}</td><td>${money(r.period_revenue_rub)}</td></tr>`
    ).join(""), 6);
    renderCohortHeatmap("cohort-heatmap", cohorts.items || []);

    async function loadUsersList() {
      const q = byId("users-search")?.value?.trim() || "";
      const list = await jget(`/metrics/users?${qs()}&limit=300&q=${encodeURIComponent(q)}`);
      renderRows("#users-table", (list.items || []).map((u) =>
        `<tr class="row-clickable" data-user-id="${u.user_id}">
          <td>${u.username} <span class="tiny">(${u.user_id})</span></td>
          <td>${u.orders_paid_count}</td>
          <td>${money(u.revenue_rub)}</td>
          <td>${money(u.gross_profit_rub)}</td>
          <td>${u.last_paid_date || "-"}</td>
        </tr>`
      ).join(""), 5);

      document.querySelectorAll("#users-table tr.row-clickable").forEach((row) => {
        row.addEventListener("click", async () => {
          const userId = row.getAttribute("data-user-id");
          try {
            const details = await jget(`/metrics/users/details?user_id=${encodeURIComponent(userId)}&${qs()}`);
            const p = details.profile || {};
            const s = details.summary || {};
            if (byId("user-selected-label")) byId("user-selected-label").textContent = `Пользователь: ${p.username} (${p.user_id})`;
            if (byId("ud-created")) byId("ud-created").textContent = num(s.orders_created_count).toLocaleString("ru-RU");
            if (byId("ud-paid")) byId("ud-paid").textContent = num(s.orders_paid_count).toLocaleString("ru-RU");
            if (byId("ud-revenue")) byId("ud-revenue").textContent = money(s.revenue_rub);
            if (byId("ud-profit")) byId("ud-profit").textContent = money(s.gross_profit_rub);

            renderRows("#user-orders-table", (details.orders || []).map((o) =>
              `<tr>
                <td>${o.order_id}</td>
                <td>${o.status}</td>
                <td>${o.product_type || "-"}</td>
                <td>${o.payment_provider}</td>
                <td>${money(o.amount_rub)}</td>
                <td>${money(o.cost_rub)}</td>
                <td>${(o.timestamp_msk || "").replace("T", " ").slice(0, 16)}</td>
              </tr>`
            ).join(""), 7);
            markActiveRow("#users-table", "data-user-id", userId);
          } catch (e) {
            setStatus(e.message);
          }
        });
      });
    }

    await loadUsersList();
    if (byId("users-search-btn")) {
      byId("users-search-btn").onclick = () => loadUsersList().catch((e) => setStatus(e.message));
    }
  }

  async function pagePayments() {
    const [payments, funnel, prevPack] = await Promise.all([
      jget(`/metrics/payments?${qs()}`),
      jget(`/metrics/funnel?${qs()}`),
      fetchDailyWithPrevious(),
    ]);

    const summary = payments.summary || {};
    byId("p-created").textContent = num(summary.orders_created_count).toLocaleString("ru-RU");
    byId("p-paid").textContent = num(summary.orders_paid_count).toLocaleString("ru-RU");
    byId("p-attempts").textContent = num(summary.payment_attempts_count).toLocaleString("ru-RU");
    if (byId("p-events")) byId("p-events").textContent = num(summary.payment_events_count).toLocaleString("ru-RU");
    byId("p-success-rate").textContent = pct(summary.payment_success_rate);
    byId("p-paid-rate").textContent = pct(summary.paid_order_rate);
    byId("p-revenue").textContent = money(summary.revenue_rub);

    renderLineChart(
      "payments-paid-chart",
      payments.daily || [],
      "orders_paid_count",
      prevPack.prevDaily || [],
      "Оплаченные заказы",
      "Оплаченные (пред. период)"
    );

    renderLineChart(
      "funnel-chart",
      funnel.items || [],
      "order_paid_count",
      (funnel.items || []).map((i) => ({ date: i.date, order_paid_count: i.order_created_count })),
      "Оплачено",
      "Создано"
    );

    renderRows("#payments-providers-table", (payments.providers || []).map((r) => {
      const successRate = num(r.payment_attempts_count) > 0 ? num(r.payment_success_count) / num(r.payment_attempts_count) : 0;
      return `<tr><td><span class="pill">${r.provider}</span></td><td>${r.payment_attempts_count}</td><td>${r.payment_events_count || 0}</td><td>${r.payment_success_count} (${pct(successRate)})</td><td>${r.payment_failed_count}</td><td>${money(r.revenue_rub)}</td></tr>`;
    }).join(""), 6);

    renderRows("#payments-failures-table", (payments.failure_reasons || []).map((r) =>
      `<tr><td><span class="pill">${r.provider}</span></td><td>${r.status}</td><td>${r.failures_count}</td></tr>`
    ).join(""), 3);
  }

  async function pageOps() {
    const [jobs, dq] = await Promise.all([
      jget("/ops/jobs?limit=80"),
      jget("/ops/data-quality?limit=80"),
    ]);

    byId("ops-running").textContent = jobs.summary.running;
    byId("ops-failed").textContent = jobs.summary.failed_last_24h;
    byId("ops-open-dq").textContent = dq.summary.open_issues;
    byId("ops-critical-dq").textContent = dq.summary.critical_open_issues;

    const statusRu = (status) => {
      if (status === "failed") return "ошибка";
      if (status === "success") return "успешно";
      if (status === "running") return "в работе";
      return status || "-";
    };
    const severityRu = (severity) => {
      if (severity === "critical") return "критично";
      if (severity === "warning") return "предупреждение";
      if (severity === "info") return "инфо";
      return severity || "-";
    };

    renderRows("#jobs-table", (jobs.items || []).map((r) =>
      `<tr><td>${r.job_name}</td><td class="${r.status === "failed" ? "danger" : "ok"}">${statusRu(r.status)}</td><td>${r.range_start || "-"}..${r.range_end || "-"}</td><td>${r.finished_at || "-"}</td><td>${r.error_text || "-"}</td></tr>`
    ).join(""), 5);

    renderRows("#dq-table", (dq.items || []).map((r) =>
      `<tr><td class="${r.severity === "critical" ? "danger" : "warn"}">${severityRu(r.severity)}</td><td>${r.issue_code}</td><td>${r.message}</td><td>${r.detected_at}</td></tr>`
    ).join(""), 4);
  }

  function buildExportLinks() {
    const q = qs();
    [
      ["exp-daily", "daily"],
      ["exp-providers", "providers"],
      ["exp-products", "products"],
      ["exp-referrals", "referrals"],
      ["exp-promos", "promos"],
      ["exp-cohorts", "cohorts"],
    ].forEach(([id, kind]) => {
      const a = byId(id);
      if (a) a.href = `/exports/metrics?kind=${kind}&${q}`;
    });
  }

  async function runBackfill(mode) {
    const { from, to } = currentRange();
    await jpost("/ops/backfill", { from, to, async: true, mode });
    setStatus(mode === "full_suite" ? "Полный пересчет поставлен в очередь" : "Пересчет поставлен в очередь");
  }

  async function runDQ() {
    const { from, to } = currentRange();
    await jpost("/ops/data-quality/run", { from, to, async: true });
    setStatus("Проверка качества данных поставлена в очередь");
  }

  async function loadCurrentPage() {
    const page = document.body.dataset.page;
    buildExportLinks();
    if (page === "overview") return pageOverview();
    if (page === "revenue") return pageRevenue();
    if (page === "users") return pageUsers();
    if (page === "payments") return pagePayments();
    if (page === "ops") return pageOps();
  }

  function injectLogoutButton() {
    const controls = document.querySelector(".controls");
    if (!controls || byId("logout")) return;
    const btn = document.createElement("button");
    btn.id = "logout";
    btn.className = "alt";
    btn.textContent = "Выйти";
    btn.addEventListener("click", async () => {
      try {
        await jpost("/auth/logout", {});
      } catch (_e) {
      }
      window.location.href = "/login";
    });
    controls.appendChild(btn);
  }

  function init() {
    defaultDates();
    injectLogoutButton();
    byId("refresh")?.addEventListener("click", () => loadCurrentPage().catch((e) => setStatus(e.message)));
    byId("run-backfill")?.addEventListener("click", () => runBackfill("full_suite").catch((e) => setStatus(e.message)));
    byId("run-daily-backfill")?.addEventListener("click", () => runBackfill("daily").catch((e) => setStatus(e.message)));
    byId("run-dq")?.addEventListener("click", () => runDQ().catch((e) => setStatus(e.message)));
    window.addEventListener("resize", () => loadCurrentPage().catch(() => {}));
    loadCurrentPage().catch((e) => setStatus(e.message));
  }

  document.addEventListener("DOMContentLoaded", init);
})();
