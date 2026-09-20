import test from 'node:test';
import assert from 'node:assert/strict';
import { Area } from '../src/build/area.js';
import { Plot } from '../src/build/plot.js';
import { Field } from '../src/build/field.js';

test('Field exposes exactly id, name, and Plots in serializable nesting', () => {
  const area = new Area({ id: 'shared', name: 'Bed', crop: 'tomato' });
  const plot = new Plot({ id: 'shared', name: 'Plot', ground: 'soil', Areas: [area] });
  for (const children of [undefined, [], [plot, plot]]) {
    const field = new Field({ id: ' field-1 ', name: ' Garden ', Plots: children, ignored: true });
    assert.deepEqual({ ...field }, {
      id: ' field-1 ', name: ' Garden ', Plots: children ?? [],
    });
    assert.deepEqual(JSON.parse(JSON.stringify(field)), {
      id: ' field-1 ', name: ' Garden ',
      Plots: (children ?? []).map(() => ({
        id: 'shared', name: 'Plot', ground: 'soil',
        Areas: [{ id: 'shared', name: 'Bed', crop: 'tomato' }],
      })),
    });
  }
});

test('Plot exposes exactly id, name, nullable ground, and Areas', () => {
  const area = new Area({ id: 'a', name: 'Area' });
  for (const ground of [undefined, null, 'custom growing medium']) {
    for (const Areas of [undefined, [], [area]]) {
      const plot = new Plot({ id: ' plot-1 ', name: ' North ', ground, Areas, ignored: true });
      assert.equal(plot.constructor.name, 'Plot');
      assert.deepEqual({ ...plot }, {
        id: ' plot-1 ', name: ' North ', ground: ground ?? null, Areas: Areas ?? [],
      });
    }
  }
});

test('Parents isolate child membership while retaining child instances', () => {
  const area = new Area({ id: 'a', name: 'Area' });
  const plot = new Plot({ id: 'p', name: 'Plot' });
  for (const [Parent, key, child] of [[Plot, 'Areas', area], [Field, 'Plots', plot]]) {
    const children = [child];
    const parent = new Parent({ id: 'parent', name: 'Parent', [key]: children });
    children.push(child);
    assert.equal(parent[key].length, 1);
    assert.equal(parent[key][0], child);
    parent[key].pop();
    assert.equal(children.length, 2);
    const first = new Parent({ id: 'first', name: 'First' });
    const second = new Parent({ id: 'second', name: 'Second' });
    first[key].push(child);
    assert.deepEqual(second[key], []);
  }
});

for (const Model of [Field, Plot, Area]) {
  test(`${Model.name} requires nonempty string id and name`, () => {
    for (const key of ['id', 'name']) {
      for (const value of [undefined, null, '', 0, false, [], {}, new String('text')]) {
        assert.throws(
          () => new Model({ id: 'id', name: 'Name', [key]: value }),
          TypeError,
          `${key} must reject ${String(value)}`,
        );
      }
    }
    assert.throws(() => new Model(), TypeError);
    assert.throws(() => new Model(null), TypeError);
    const model = new Model({ id: ' ', name: '\t' });
    assert.equal(model.id, ' ');
    assert.equal(model.name, '\t');
  });
}

for (const [Model, key] of [[Plot, 'ground'], [Area, 'crop']]) {
  test(`${Model.name}.${key} rejects values other than null or nonempty strings`, () => {
    for (const value of ['', 0, false, [], {}, new String('text')]) {
      assert.throws(
        () => new Model({ id: 'id', name: 'Name', [key]: value }),
        TypeError,
        `${key} must reject ${String(value)}`,
      );
    }
    for (const value of [null, ' ', ' novel value ']) {
      assert.equal(new Model({ id: 'id', name: 'Name', [key]: value })[key], value);
    }
  });
}

for (const [Parent, key] of [[Field, 'Plots'], [Plot, 'Areas']]) {
  test(`${Parent.name}.${key} requires an array`, () => {
    for (const value of ['', 'text', new Set(), null, false, 0, {}, { length: 0 }]) {
      assert.throws(() => new Parent({ id: 'id', name: 'Name', [key]: value }), TypeError);
    }
  });
}

for (const [Parent, key, Child] of [[Field, 'Plots', Plot], [Plot, 'Areas', Area]]) {
  test(`${Parent.name}.${key} accepts only ${Child.name} instances as children`, () => {
    const child = new Child({ id: 'child', name: 'Child' });
    const wrongModel = new Field({ id: 'wrong', name: 'Wrong' });
    for (const invalid of [{ ...child }, null, undefined, 0, 'child', [], wrongModel]) {
      assert.throws(
        () => new Parent({ id: 'parent', name: 'Parent', [key]: [child, invalid] }),
        TypeError,
      );
    }
    assert.throws(
      () => new Parent({ id: 'parent', name: 'Parent', [key]: Array(1) }),
      TypeError,
    );
    const parent = new Parent({ id: 'parent', name: 'Parent', [key]: [child, child] });
    assert.equal(parent[key][0], child);
    assert.equal(parent[key][1], child);
  });
}

test('Area exposes exactly id, name, and a nullable crop', () => {
  for (const crop of [undefined, null, 'heritage tomato']) {
    const area = new Area({ id: ' area-1 ', name: ' Bed A ', crop, ignored: true });
    assert.deepEqual({ ...area }, {
      id: ' area-1 ',
      name: ' Bed A ',
      crop: crop ?? null,
    });
    assert.equal(JSON.stringify(area), JSON.stringify({ ...area }));
  }
});
