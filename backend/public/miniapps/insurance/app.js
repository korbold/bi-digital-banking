// Insurance micro-app. Runs inside the bank app's WebView and talks to the
// host only through the BiBridge contract (docs/api-contract.md):
//   BiBridge.postMessage(JSON.stringify({ id, method, params }))
//   host -> window.biBridgeResolve(id, result) | window.biBridgeReject(id, error)
// Opened in a plain browser it falls back to a clearly labelled demo mode.
(function () {
  'use strict';

  // Mirrors backend/src/domain/insurance.ts (used only for the demo estimate).
  var PRODUCTS = {
    travel: { min: 1000, max: 50000, step: 500, value: 5000, baseFee: 2, rate: 0.0006, label: 'Viaje' },
    device: { min: 200, max: 3000, step: 50, value: 800, baseFee: 1.5, rate: 0.006, label: 'Celular' },
    life: { min: 10000, max: 200000, step: 5000, value: 50000, baseFee: 4, rate: 0.00045, label: 'Vida' },
  };
  var BRIDGE_TIMEOUT_MS = 5000;
  var API_TIMEOUT_MS = 8000;

  var $ = function (id) { return document.getElementById(id); };
  var form = $('quote-form');
  var slider = $('coverage');
  var quoteBtn = $('quote-btn');
  var buyBtn = $('buy-btn');
  var lastQuote = null;
  var lastAction = null;

  var money = function (n, decimals) {
    return '$' + Number(n).toLocaleString('en-US', { minimumFractionDigits: decimals, maximumFractionDigits: decimals });
  };

  // ---------------- Bridge ----------------
  var hasBridge = typeof window.BiBridge !== 'undefined' && typeof window.BiBridge.postMessage === 'function';
  var pending = {};
  var seq = 0;

  window.biBridgeResolve = function (id, result) {
    var p = pending[id];
    if (!p) return;
    clearTimeout(p.timer);
    delete pending[id];
    p.resolve(result);
  };
  window.biBridgeReject = function (id, error) {
    var p = pending[id];
    if (!p) return;
    clearTimeout(p.timer);
    delete pending[id];
    p.reject(new Error((error && error.message) || String(error)));
  };

  function call(method, params) {
    if (!hasBridge) return Promise.reject(new Error('bridge_unavailable'));
    return new Promise(function (resolve, reject) {
      var id = 'm' + ++seq;
      pending[id] = {
        resolve: resolve,
        reject: reject,
        timer: setTimeout(function () {
          delete pending[id];
          reject(new Error('bridge_timeout'));
        }, BRIDGE_TIMEOUT_MS),
      };
      window.BiBridge.postMessage(JSON.stringify({ id: id, method: method, params: params || {} }));
    });
  }

  function track(event, params) {
    if (hasBridge) call('track', { event: event, params: params || {} }).catch(function () {});
  }

  // ---------------- UI helpers ----------------
  function selectedProduct() {
    return form.querySelector('input[name="product"]:checked').value;
  }

  function configureSlider(product, keepValue) {
    var p = PRODUCTS[product];
    slider.min = p.min;
    slider.max = p.max;
    slider.step = p.step;
    if (!keepValue) slider.value = p.value;
    $('min-hint').textContent = money(p.min, 0);
    $('max-hint').textContent = money(p.max, 0);
    renderCoverage();
  }

  function renderCoverage() {
    $('coverage-value').textContent = money(slider.value, 0);
    slider.setAttribute('aria-valuetext', money(slider.value, 0) + ' de cobertura');
  }

  function setBusy(button, busy, label) {
    button.disabled = busy;
    button.setAttribute('aria-busy', busy ? 'true' : 'false');
    button.textContent = label;
  }

  function showError(message, retry) {
    lastAction = retry;
    $('error-text').textContent = message;
    $('error').hidden = false;
  }

  function hideError() {
    $('error').hidden = true;
  }

  function showResult(quote, estimate) {
    lastQuote = quote;
    $('result-label').textContent = estimate ? 'Estimación referencial (modo demo)' : 'Tu prima mensual';
    $('premium').textContent = money(quote.monthlyPremium, 2) + ' / mes';
    $('result-coverage').textContent = money(quote.coverage, 0);
    $('result-valid').textContent = new Date(quote.validUntil).toLocaleDateString('es-EC', { day: 'numeric', month: 'short' });
    buyBtn.hidden = estimate;
    $('result').hidden = false;
    $('result').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }

  // ---------------- Quote ----------------
  function errorMessage(err, status) {
    if (status === 401) return 'Tu sesión expiró. Vuelve a abrir Seguros desde la app.';
    if (status === 422 && err && err.message) return err.message;
    if (err && err.name === 'AbortError') return 'El servicio está tardando más de lo normal. Intenta de nuevo.';
    if (!navigator.onLine) return 'Sin conexión. Revisa tu internet e intenta de nuevo.';
    return 'No pudimos cotizar en este momento. Intenta de nuevo.';
  }

  function demoEstimate(product, coverage) {
    var p = PRODUCTS[product];
    return {
      quoteId: 'demo',
      product: product,
      coverage: coverage,
      monthlyPremium: Math.round((p.baseFee + coverage * p.rate) * 100) / 100,
      currency: 'USD',
      validUntil: new Date(Date.now() + 7 * 86400000).toISOString(),
    };
  }

  function requestQuote() {
    hideError();
    var product = selectedProduct();
    var coverage = Number(slider.value);

    if (!hasBridge) {
      showResult(demoEstimate(product, coverage), true);
      return Promise.resolve();
    }

    setBusy(quoteBtn, true, 'Cotizando…');
    var status = 0;
    return call('getAuthToken')
      .then(function (auth) {
        var controller = new AbortController();
        var timer = setTimeout(function () { controller.abort(); }, API_TIMEOUT_MS);
        return fetch('/api/insurance/quote', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + auth.token },
          body: JSON.stringify({ product: product, coverage: coverage }),
          signal: controller.signal,
        }).finally(function () { clearTimeout(timer); });
      })
      .then(function (res) {
        status = res.status;
        return res.json().then(function (body) {
          if (!res.ok) throw (body && body.error) || new Error('HTTP ' + res.status);
          return body;
        });
      })
      .then(function (quote) {
        track('insurance_quoted', { product: product, premium: quote.monthlyPremium });
        showResult(quote, false);
      })
      .catch(function (err) {
        track('insurance_quote_failed', { product: product, status: status });
        showError(errorMessage(err, status), requestQuote);
      })
      .finally(function () {
        setBusy(quoteBtn, false, 'Cotizar');
      });
  }

  function buy() {
    if (!lastQuote || !hasBridge) return;
    setBusy(buyBtn, true, 'Procesando…');
    var label = PRODUCTS[lastQuote.product].label;
    var result = { quoteId: lastQuote.quoteId, product: lastQuote.product, monthlyPremium: lastQuote.monthlyPremium };
    track('insurance_purchase_intent', result);
    call('notifyHost', {
      title: 'Solicitud enviada',
      body: 'Seguro de ' + label + ' por ' + money(lastQuote.monthlyPremium, 2) + '/mes. Un asesor te contactará.',
    })
      .catch(function () {})
      .then(function () { return call('close', { result: result }); })
      .catch(function () {
        setBusy(buyBtn, false, 'Contratar');
        showError('No pudimos completar la solicitud. Intenta de nuevo.', buy);
      });
  }

  // ---------------- Wiring ----------------
  form.addEventListener('change', function (e) {
    if (e.target.name === 'product') {
      configureSlider(e.target.value, false);
      $('result').hidden = true;
    }
  });
  slider.addEventListener('input', function () {
    renderCoverage();
    $('result').hidden = true;
  });
  form.addEventListener('submit', function (e) {
    e.preventDefault();
    requestQuote();
  });
  buyBtn.addEventListener('click', buy);
  $('retry-btn').addEventListener('click', function () {
    if (lastAction) lastAction();
  });

  // Preselect product from ?product=travel|device|life (host passes action params).
  var requested = new URLSearchParams(location.search).get('product');
  if (requested && PRODUCTS[requested]) {
    form.querySelector('input[value="' + requested + '"]').checked = true;
  }
  configureSlider(selectedProduct(), false);

  if (!hasBridge) {
    $('demo-banner').hidden = false;
    return;
  }

  call('getContext')
    .then(function (ctx) {
      if (ctx && ctx.name) $('greeting').textContent = 'Hola ' + String(ctx.name).split(' ')[0] + ', cotiza en segundos, sin papeleo.';
      if (ctx && ctx.theme && (ctx.theme === 'dark' || ctx.theme === 'light')) {
        document.documentElement.setAttribute('data-theme', ctx.theme);
      }
      track('miniapp_opened', { miniapp: 'insurance', segment: (ctx && ctx.segment) || 'unknown' });
    })
    .catch(function () {
      // Context is a nice-to-have: the quote flow still works without it.
    });
})();
