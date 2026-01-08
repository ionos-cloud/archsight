// Activity Sparkline - renders commit/issue history as mini bar chart
document.addEventListener('DOMContentLoaded', function() {
  document.querySelectorAll('.activity-sparkline').forEach(function(el) {
    var valuesStr = el.getAttribute('data-values');
    if (!valuesStr || valuesStr.trim() === '') return;

    var values = valuesStr.split(',').map(function(v) {
      return parseInt(v, 10) || 0;
    });
    if (values.length === 0) return;

    var max = Math.max.apply(null, values);
    if (max === 0) max = 1; // Avoid division by zero

    // Use different height based on sparkline size class
    var isSmall = el.classList.contains('sparkline-sm');
    var maxHeight = isSmall ? 24 : 16;

    // Determine type for tooltip and styling
    var dataType = el.getAttribute('data-type') || 'commits';
    var tooltipSuffix = dataType === 'created' ? ' issues created' :
                        dataType === 'resolved' ? ' issues resolved' :
                        ' commits';

    values.forEach(function(val, idx) {
      var bar = document.createElement('div');
      bar.className = 'activity-sparkline-bar';

      if (val === 0) {
        // Zero value: create invisible placeholder to maintain spacing
        bar.classList.add('empty');
        bar.style.height = '0px';
        bar.title = '0' + tooltipSuffix;
      } else {
        var height = Math.max(2, Math.round((val / max) * maxHeight));
        bar.style.height = height + 'px';
        bar.title = val + tooltipSuffix;
      }
      el.appendChild(bar);
    });
  });
});
