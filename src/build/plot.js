import { requireNonemptyString } from './validation.js';
import { Area } from './area.js';

export class Plot {
  constructor({ id, name, ground = null, Areas = [] }) {
    requireNonemptyString(id, 'id');
    requireNonemptyString(name, 'name');
    if (ground !== null) requireNonemptyString(ground, 'ground');
    if (!Array.isArray(Areas)) throw new TypeError('Areas must be an array');
    for (const area of Areas) {
      if (!(area instanceof Area)) throw new TypeError('Areas must contain Area instances');
    }
    this.id = id;
    this.name = name;
    this.ground = ground;
    this.Areas = [...Areas];
  }
}
