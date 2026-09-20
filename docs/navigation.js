const navigation = document.querySelector('nav');
const articles = [...document.querySelectorAll('main > article')];
const usedIds = new Set([...document.querySelectorAll('[id]')].map(element => element.id));
const nodes = new Map();

function ensureId(element, title, prefix = '') {
  if (element.id) return element.id;

  const slug = title.trim().toLowerCase()
    .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'section';
  const base = `${prefix}${slug}`;
  let id = base;
  let suffix = 2;
  while (usedIds.has(id)) id = `${base}-${suffix++}`;
  element.id = id;
  usedIds.add(id);
  return id;
}

function addNode(element, heading, parentId, prefix = '') {
  const title = heading.textContent.trim();
  const id = ensureId(element, title, prefix);
  const item = document.createElement('li');
  const link = document.createElement('a');
  link.textContent = title;
  link.setAttribute('aria-label', title);
  link.href = `#${id}`;
  const children = document.createElement('ul');
  children.id = `${id}-navigation`;
  item.append(link);
  nodes.set(id, { id, title, parentId, item, link, children });
  return id;
}

for (const article of articles) {
  const articleId = addNode(article, article.querySelector('h1'), article.dataset.parent);
  for (const heading of article.querySelectorAll('h2')) {
    addNode(heading, heading, articleId, `${articleId}-`);
  }
}

const menu = document.createElement('ul');
for (const node of nodes.values()) {
  const parent = nodes.get(node.parentId);
  (parent ? parent.children : menu).append(node.item);
}

const apiPages = [...nodes.values()]
  .filter(node => node.parentId === 'build-api')
  .sort((a, b) => a.title.localeCompare(b.title, 'en'));
for (const page of apiPages) nodes.get(page.parentId).children.append(page.item);

for (const article of articles) {
  const cards = article.querySelector('.section-cards');
  if (!cards) continue;

  for (const item of nodes.get(article.id).children.children) {
    const card = document.createElement('li');
    card.append(item.firstElementChild.cloneNode(true));
    cards.append(card);
  }
}

for (const node of nodes.values()) {
  if (!node.children.childElementCount) continue;
  node.link.setAttribute('aria-controls', node.children.id);
  node.item.append(node.children);
}
navigation.append(menu);

function showSection() {
  let hash;
  try {
    hash = decodeURIComponent(location.hash.slice(1));
  } catch {
    hash = '';
  }
  const target = document.getElementById(hash);
  const active = articles.find(article => article === target || article.contains(target)) || articles[0];
  const selectedId = nodes.has(hash) ? hash : active.id;
  const path = new Set();
  let node = nodes.get(selectedId);
  while (node && !path.has(node.id)) {
    path.add(node.id);
    node = nodes.get(node.parentId);
  }

  for (const article of articles) article.hidden = article !== active;
  for (const node of nodes.values()) {
    if (node.children.childElementCount) {
      const expanded = path.has(node.id);
      node.children.hidden = !expanded;
      node.link.setAttribute('aria-expanded', String(expanded));
    }
    if (node.id === selectedId) node.link.setAttribute('aria-current', 'location');
    else node.link.removeAttribute('aria-current');
  }
  document.title = `${nodes.get(active.id).title} — Garden Gnome`;

  // Hidden articles must be revealed before the browser can scroll to them.
  if (target && active.contains(target)) {
    requestAnimationFrame(() => target.scrollIntoView({ block: 'start' }));
  }
}

document.querySelector('.skip-link').addEventListener('click', event => {
  event.preventDefault();
  const content = document.getElementById('content');
  content.focus({ preventScroll: true });
  content.scrollIntoView({ block: 'start' });
});

window.addEventListener('hashchange', showSection);
showSection();
