function setPanelExpanded(button, expanded) {
  const content = document.getElementById(button.getAttribute('aria-controls'));
  content.hidden = !expanded;
  button.closest('.panel').classList.toggle('is-collapsed', !expanded);
  button.setAttribute('aria-expanded', String(expanded));
  const label = button.getAttribute('aria-label').replace(/^(Minimize|Expand) /, '');
  button.setAttribute('aria-label', `${expanded ? 'Minimize' : 'Expand'} ${label}`);
}

const viewMenu = document.querySelector('#view-menu');
const viewSummary = viewMenu.querySelector('summary');
const preferencesMenu = document.querySelector('#preferences-menu');
const preferencesSummary = preferencesMenu.querySelector('summary');
const preferencesPanel = document.querySelector('#preferences-panel');
const openPreferences = document.querySelector('#open-preferences');
const panelVisibility = [...document.querySelectorAll('[data-panel-visibility]')];

function setPanelVisible(panel, visible) {
  panel.hidden = !visible;
  const viewOption = panelVisibility.find(input => input.dataset.panelVisibility === panel.id);
  if (viewOption) viewOption.checked = visible;
  if (panel.id === 'layer-settings') {
    if (!visible) hideRename();
    currentLayer.button.setAttribute('aria-expanded', String(visible));
  }
  if (panel === preferencesPanel) openPreferences.setAttribute('aria-expanded', String(visible));
  if (visible) setPanelExpanded(panel.querySelector('[data-panel-toggle]'), true);
}

for (const input of panelVisibility) {
  input.addEventListener('change', () => {
    setPanelVisible(document.getElementById(input.dataset.panelVisibility), input.checked);
  });
}

for (const button of document.querySelectorAll('[data-panel-close]')) {
  button.addEventListener('click', () => {
    if (button.closest('.panel').id === 'layer-settings') {
      closeSettings();
      return;
    }
    const panel = button.closest('.panel');
    setPanelVisible(panel, false);
    if (panel === preferencesPanel) preferencesSummary.focus();
    else viewSummary.focus();
  });
}

const topMenus = document.querySelectorAll('.workspace-bar details');
for (const menu of topMenus) {
  menu.addEventListener('keydown', event => {
    if (event.key !== 'Escape') return;
    event.preventDefault();
    menu.open = false;
    menu.querySelector('summary').focus();
  });
  menu.addEventListener('focusout', event => {
    if (!menu.contains(event.relatedTarget)) menu.open = false;
  });
  menu.addEventListener('toggle', () => {
    if (!menu.open) return;
    for (const other of topMenus) if (other !== menu) other.open = false;
  });
}
document.addEventListener('pointerdown', event => {
  for (const menu of topMenus) if (!menu.contains(event.target)) menu.open = false;
});
openPreferences.addEventListener('click', () => {
  setPanelVisible(preferencesPanel, true);
  preferencesMenu.open = false;
  document.querySelector('#drawing-line-width').focus();
});
preferencesPanel.addEventListener('keydown', event => {
  if (event.key !== 'Escape') return;
  event.preventDefault();
  setPanelVisible(preferencesPanel, false);
  preferencesSummary.focus();
});

for (const button of document.querySelectorAll('[data-panel-toggle]')) {
  button.addEventListener('click', () => {
    setPanelExpanded(button, button.getAttribute('aria-expanded') !== 'true');
  });
}

const tools = document.querySelectorAll('[data-tool]');
const optionPanels = document.querySelectorAll('[data-tool-options]');
const toolContextMenu = document.querySelector('.tool-options');
const toolContextHeading = toolContextMenu.querySelector('legend');

for (const tool of tools) {
  tool.addEventListener('click', () => {
    for (const button of tools) {
      button.setAttribute('aria-pressed', String(button === tool));
    }
    for (const panel of optionPanels) {
      panel.hidden = panel.dataset.toolOptions !== tool.dataset.tool;
    }
    const contextMenuName = tool.dataset.contextMenuName;
    toolContextHeading.textContent = contextMenuName ?? '';
    toolContextMenu.hidden = !contextMenuName;
  });
}

const pointActions = document.querySelectorAll('[data-point-action]');
for (const action of pointActions) {
  action.addEventListener('click', () => {
    for (const button of pointActions) {
      button.setAttribute('aria-pressed', String(button === action));
    }
  });
}

const referenceActions = document.querySelectorAll('[data-reference-action]');
for (const action of referenceActions) {
  action.addEventListener('click', () => {
    for (const button of referenceActions) {
      button.setAttribute('aria-pressed', String(button === action));
    }
  });
}

const settings = document.querySelector('#layer-settings');
const renameButton = document.querySelector('#rename-layer');
const renameForm = document.querySelector('#rename-form');
const nameInput = document.querySelector('#layer-name');
const fieldColor = document.querySelector('#field-color');
const canvasUnits = document.querySelector('#canvas-units');
const canvasSnapping = document.querySelector('#canvas-snapping');
const canvasSnapTarget = document.querySelector('#canvas-snap-target');
const plotColor = document.querySelector('#plot-color');
const plotPattern = document.querySelector('#plot-pattern');
const areaPlantingType = document.querySelector('#area-planting-type');
const referenceTool = document.querySelector('[data-tool="reference"]');
const referenceImage = document.querySelector('#reference-image');
const referenceColor = document.querySelector('#reference-color');
const referenceDistance = document.querySelector('#reference-distance');
const layers = [...document.querySelectorAll('.layer-row')].map(row => ({
  id: row.dataset.layerId,
  name: row.querySelector('.layer-name').textContent,
  kind: row.dataset.kind,
  parent: row.dataset.parent,
  ground: row.dataset.ground,
  row,
  button: row.querySelector('button'),
}));
const plotAppearance = new Map(layers
  .filter(layer => layer.kind === 'Plot')
  .map(layer => [layer.id, { color: '#99a18f', pattern: 'none' }]));
const groundDetails = {
  flat: [],
  row: [
    { key: 'width', label: 'Row width' },
    { key: 'spacing', label: 'Spacing' },
    { key: 'direction', label: 'Direction (°)', max: 360 },
  ],
  mound: [
    { key: 'diameter', label: 'Mound diameter' },
    { key: 'spacing', label: 'Spacing' },
  ],
};
const areaDimensions = new Map(layers
  .filter(layer => layer.kind === 'Area')
  .map(layer => [layer.id, { flat: {}, row: {}, mound: {} }]));
let currentLayer;

function showLayer(layer) {
  hideRename();
  currentLayer = layer;
  setPanelVisible(settings, true);
  settings.querySelector('[data-layer-kind]').textContent = `Properties - ${layer.kind}`;
  settings.querySelector('#properties-heading').textContent = layer.name;

  for (const section of settings.querySelectorAll('[data-layer-context]')) {
    section.hidden = section.dataset.layerContext.toLowerCase() !== layer.kind.toLowerCase();
  }
  for (const item of layers) {
    item.row.classList.toggle('selected', item === layer);
    item.button.setAttribute('aria-expanded', String(item === layer));
  }
  const parent = layers.find(item => item.id === layer.parent);

  if (layer.kind === 'Plot') {
    const appearance = plotAppearance.get(layer.id);
    plotColor.value = appearance.color;
    plotPattern.value = appearance.pattern;
  }
  if (layer.kind === 'Area') {
    areaPlantingType.value = layer.ground;
    renderAreaOptions();
  }
  if (layer.kind === 'Reference') {
    referenceColor.value = layer.color;
    referenceImage.value = '';
    referenceImage.setCustomValidity('');
    document.querySelector('#reference-image-name').textContent = layer.imageName || 'No image chosen';
    referenceDistance.value = layer.distance;
  }
  updateReferenceTool();
  const path = [layer.name];
  let ancestor = parent;
  while (ancestor) {
    path.unshift(ancestor.name);
    ancestor = layers.find(item => item.id === ancestor.parent);
  }
  document.querySelector('#selected-layer').textContent = `Selected: ${path.join(' / ')}`;
}

fieldColor.addEventListener('change', () => {
  document.querySelector('#field-boundary').setAttribute('stroke', fieldColor.value);
});

function updateCanvasUnits() {
  referenceDistance.labels[0].textContent = `Known distance (${canvasUnits.value})`;
  document.querySelector('#grid-scale-label').textContent = `1 grid length = — ${canvasUnits.value}`;
}

canvasUnits.addEventListener('change', updateCanvasUnits);
updateCanvasUnits();

canvasSnapping.addEventListener('change', () => {
  canvasSnapTarget.disabled = !canvasSnapping.checked;
});

const drawing = document.querySelector('.drawing');
const menuScaling = document.querySelector('#menu-scaling');
menuScaling.addEventListener('change', () => {
  const sizes = { small: .85, medium: 1, large: 1.15 };
  document.documentElement.style.setProperty('--menu-scale', sizes[menuScaling.value]);
});

const preferencesForm = document.querySelector('#preferences-content');
const preferenceInputs = {
  lineWidth: document.querySelector('#drawing-line-width'),
  gridThickness: document.querySelector('#grid-thickness'),
  gridColor: document.querySelector('#grid-color'),
  gridOpacity: document.querySelector('#grid-opacity'),
  minZoom: document.querySelector('#viewport-min-zoom'),
  maxZoom: document.querySelector('#viewport-max-zoom'),
};
let viewportPreferences;

function applyPreferences() {
  viewportPreferences = Object.fromEntries(Object.entries(preferenceInputs).map(([key, input]) => [
    key, input.type === 'color' ? input.value : input.valueAsNumber,
  ]));
  for (const shape of drawing.querySelectorAll('#field-boundary, [data-plot-id], [data-area-id]')) {
    shape.style.strokeWidth = `${viewportPreferences.lineWidth}px`;
    shape.style.vectorEffect = 'non-scaling-stroke';
  }
  const gridLine = drawing.querySelector('#grid path');
  gridLine.setAttribute('stroke', viewportPreferences.gridColor);
  gridLine.setAttribute('stroke-width', viewportPreferences.gridThickness);
  gridLine.setAttribute('stroke-opacity', viewportPreferences.gridOpacity / 100);
  gridLine.setAttribute('vector-effect', 'non-scaling-stroke');
}

preferencesForm.addEventListener('submit', event => {
  event.preventDefault();
  if (!preferencesForm.reportValidity()) return;
  applyPreferences();
  document.querySelector('#preferences-status').textContent = 'Applied';
});
preferencesForm.addEventListener('input', () => {
  document.querySelector('#preferences-status').textContent = '';
});
applyPreferences();

new ResizeObserver(() => {
  if (!drawing.getClientRects().length) return;
  const gridWidth = document.querySelector('#grid').width.baseVal.value;
  document.querySelector('#grid-scale-bar').style.width = `${gridWidth * drawing.getScreenCTM().a}px`;
}).observe(drawing);

function renderAreaOptions() {
  settings.querySelector('#area-options-heading').textContent = `${areaPlantingType.selectedOptions[0].textContent} options`;
  const dimensions = settings.querySelector('#area-dimensions');
  const values = areaDimensions.get(currentLayer.id)[currentLayer.ground];
  dimensions.replaceChildren();
  for (const property of groundDetails[currentLayer.ground]) {
    const control = document.createElement('div');
    control.className = 'property-control';
    const label = document.createElement('label');
    const input = document.createElement('input');
    input.id = `area-${property.key}`;
    input.name = property.key;
    input.type = 'number';
    input.step = 'any';
    input.min = '0';
    if (property.max !== undefined) input.max = String(property.max);
    input.value = values[property.key] ?? '';
    label.htmlFor = input.id;
    label.textContent = property.label;
    input.addEventListener('input', () => {
      values[property.key] = input.value;
    });
    control.append(label, input);
    dimensions.append(control);
  }
}

areaPlantingType.addEventListener('change', () => {
  if (currentLayer.kind !== 'Area') return;
  currentLayer.ground = areaPlantingType.value;
  currentLayer.row.dataset.ground = currentLayer.ground;
  const label = areaPlantingType.selectedOptions[0].textContent;
  currentLayer.row.querySelector('small').textContent = label;
  document.querySelector(`[data-ground-label="${currentLayer.id}"]`).textContent = ` · ${label}`;
  const fills = { flat: 'dots', row: 'rows', mound: 'mounds' };
  document.querySelector(`[data-area-id="${currentLayer.id}"]`).setAttribute('fill', `url(#${fills[currentLayer.ground]})`);
  renderAreaOptions();
});

function updatePlotAppearance() {
  if (currentLayer.kind !== 'Plot') return;
  const appearance = plotAppearance.get(currentLayer.id);
  appearance.color = plotColor.value;
  appearance.pattern = plotPattern.value;
  const shape = document.querySelector(`[data-plot-id="${currentLayer.id}"]`);
  shape.setAttribute('stroke', appearance.color);
  shape.setAttribute('fill', appearance.pattern === 'none' ? '#f6f7f0' : `url(#${appearance.pattern})`);
}

plotColor.addEventListener('change', updatePlotAppearance);
plotPattern.addEventListener('change', updatePlotAppearance);

function bindLayer(layer) {
  layer.button.addEventListener('click', () => {
    showLayer(layer);
    renameButton.focus();
  });
  layer.row.querySelector('button.layer-name')?.addEventListener('click', () => showLayer(layer));
}
for (const layer of layers) bindLayer(layer);

function updateReferenceTool() {
  referenceTool.disabled = currentLayer.kind !== 'Reference' || !currentLayer.imageUrl;
  referenceTool.title = referenceTool.disabled ? 'Select a reference layer with an image' : '';
  for (const action of referenceActions) action.disabled = referenceTool.disabled;
  if (referenceTool.disabled && referenceTool.getAttribute('aria-pressed') === 'true') {
    document.querySelector('[data-tool="point"]').click();
  }
}

function addReferenceLayer() {
  const item = document.querySelector('#reference-layer-template').content.firstElementChild.cloneNode(true);
  const row = item.querySelector('.layer-row');
  const number = layers.filter(layer => layer.kind === 'Reference').length + 1;
  const layer = {
    id: `reference-${number}`, name: `Reference ${number}`, kind: 'Reference', parent: '',
    color: '#99a18f',
    row, button: row.querySelector('.icon-button'), imageUrl: '', imageName: '', distance: '', imageRequest: 0,
  };
  row.dataset.layerId = layer.id;
  row.querySelector('.layer-name').textContent = layer.name;
  layer.button.setAttribute('aria-label', `Settings for ${layer.name}`);
  document.querySelector('.layer-tree').append(item);
  layer.image = document.createElementNS('http://www.w3.org/2000/svg', 'image');
  layer.image.dataset.referenceId = layer.id;
  layer.image.setAttribute('x', '310');
  layer.image.setAttribute('y', '155');
  layer.image.setAttribute('width', '740');
  layer.image.setAttribute('height', '575');
  layer.image.setAttribute('preserveAspectRatio', 'xMidYMid meet');
  document.querySelector('#reference-images').prepend(layer.image);
  layers.push(layer);
  bindLayer(layer);
  return layer;
}

document.querySelector('#add-reference').addEventListener('click', () => {
  const layer = addReferenceLayer();
  showLayer(layer);
  layer.row.scrollIntoView({ block: 'nearest' });
  referenceImage.focus();
});

referenceImage.addEventListener('change', async () => {
  const layer = currentLayer;
  const file = referenceImage.files[0];
  if (layer.kind !== 'Reference' || !file) return;
  const request = ++layer.imageRequest;
  referenceImage.setCustomValidity('');
  if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type)) {
    referenceImage.setCustomValidity('Choose a PNG, JPEG, or WebP image.');
    referenceImage.reportValidity();
    return;
  }
  const url = URL.createObjectURL(file);
  const image = new Image();
  image.src = url;
  try {
    await image.decode();
  } catch {
    URL.revokeObjectURL(url);
    if (currentLayer === layer && layer.imageRequest === request) {
      referenceImage.setCustomValidity('This image could not be opened.');
      referenceImage.reportValidity();
    }
    return;
  }
  if (layer.imageRequest !== request) {
    URL.revokeObjectURL(url);
    return;
  }
  if (layer.imageUrl) URL.revokeObjectURL(layer.imageUrl);
  layer.imageUrl = url;
  layer.imageName = file.name;
  layer.image.setAttribute('href', url);
  if (currentLayer === layer) {
    document.querySelector('#reference-image-name').textContent = file.name;
    updateReferenceTool();
  }
});

referenceColor.addEventListener('change', () => {
  if (currentLayer.kind === 'Reference') currentLayer.color = referenceColor.value;
});

referenceDistance.addEventListener('input', () => {
  if (currentLayer.kind === 'Reference') currentLayer.distance = referenceDistance.value;
});

function hideRename() {
  renameForm.hidden = true;
  renameButton.setAttribute('aria-expanded', 'false');
}

renameButton.addEventListener('click', () => {
  setPanelExpanded(settings.querySelector('[data-panel-toggle]'), true);
  renameForm.hidden = false;
  renameButton.setAttribute('aria-expanded', 'true');
  nameInput.value = currentLayer.name;
  nameInput.focus();
  nameInput.select();
});

renameForm.addEventListener('submit', event => {
  event.preventDefault();
  currentLayer.name = nameInput.value;
  currentLayer.row.querySelector('.layer-name').textContent = currentLayer.name;
  currentLayer.button.setAttribute('aria-label', `Settings for ${currentLayer.name}`);
  const canvasLabel = document.querySelector(`[data-layer-label="${currentLayer.id}"]`);
  if (canvasLabel) canvasLabel.textContent = currentLayer.name;
  showLayer(currentLayer);
  renameButton.focus();
});

document.querySelector('#cancel-rename').addEventListener('click', () => {
  hideRename();
  renameButton.focus();
});

settings.addEventListener('keydown', event => {
  if (event.key !== 'Escape') return;
  event.preventDefault();
  if (!renameForm.hidden) {
    hideRename();
    renameButton.focus();
  } else {
    closeSettings();
  }
});

function closeSettings() {
  setPanelVisible(settings, false);
  if (currentLayer.button.getClientRects().length) currentLayer.button.focus();
  else viewSummary.focus();
}

const previewParams = new URLSearchParams(location.search);
const previewKind = previewParams.get('properties');
if (previewKind === 'reference' || previewParams.get('panel') === 'layers') addReferenceLayer();
const previewLayer = layers.find(layer => layer.kind.toLowerCase() === previewKind);
const layersPreview = previewParams.get('panel') === 'layers';
const canvasPreview = previewKind === 'canvas';
if (previewLayer || layersPreview || canvasPreview) {
  document.body.classList.add(canvasPreview ? 'canvas-preview' : layersPreview ? 'layers-preview' : 'properties-preview');
  document.body.inert = true;
}
showLayer(previewLayer ?? layers.find(layer => layer.id === 'area-01'));
