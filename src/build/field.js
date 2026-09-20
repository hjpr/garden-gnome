import { requireNonemptyString } from './validation.js';
import { Plot } from './plot.js';

export class Field {
  constructor({ id, name, Plots = [] }) {
    requireNonemptyString(id, 'id');
    requireNonemptyString(name, 'name');
    if (!Array.isArray(Plots)) throw new TypeError('Plots must be an array');
    for (const plot of Plots) {
      if (!(plot instanceof Plot)) throw new TypeError('Plots must contain Plot instances');
    }
    this.id = id;
    this.name = name;
    this.Plots = [...Plots];
  }
}
