import { requireNonemptyString } from './validation.js';

export class Area {
  constructor({ id, name, crop = null }) {
    requireNonemptyString(id, 'id');
    requireNonemptyString(name, 'name');
    if (crop !== null) requireNonemptyString(crop, 'crop');
    this.id = id;
    this.name = name;
    this.crop = crop;
  }
}
