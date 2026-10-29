import test from 'node:test';
import assert from 'node:assert/strict';
import { elementTypes } from './elementDefinitions.js';
import { generateJSON } from '../utils/jsonGenerator.js';

test('Resolve color dial is an inline Resolve-only control with Lift Y defaults', () => {
  const definition = elementTypes.resolveColorDial;
  assert.equal(definition.type, 'resolveColorDial');
  assert.equal(definition.defaultProps.parameter, 'lift');
  assert.equal(definition.defaultProps.channel, 'Y');
  assert.equal(definition.defaultProps.sensitivity, 'fine');
  assert.equal(definition.defaultProps.width, 90);
  assert.match(definition.defaultProps.matchAppId, /DaVinciResolve/);
});

test('Resolve color dial keeps selected control and channel in the saved native configuration', () => {
  const result = JSON.parse(generateJSON([{id:'dial-1',type:'resolveColorDial',parameter:'gain',channel:'B',width:90,matchAppId:'^com\\.blackmagic-design\\.DaVinciResolve$'}]));
  assert.deepEqual(result[0], {
    type:'resolveColorDial', parameter:'gain', channel:'B', width:90,
    align:'center', matchAppId:'^com\\.blackmagic-design\\.DaVinciResolve$',
  });
});

test('Resolve timeline jog stays relative and defaults to fine sensitivity', () => {
  const definition = elementTypes.resolveTimelineJog;
  assert.equal(definition.defaultProps.sensitivity, 'fine');
  assert.equal(definition.defaultProps.width, 140);
  const result = JSON.parse(generateJSON([{id:'jog-1',type:'resolveTimelineJog',sensitivity:'coarse',width:90,matchAppId:'^com\\.blackmagic-design\\.DaVinciResolve$'}]));
  assert.equal(result[0].type,'resolveTimelineJog');
  assert.equal(result[0].sensitivity,'coarse');
  assert.equal('position' in result[0],false);
});
