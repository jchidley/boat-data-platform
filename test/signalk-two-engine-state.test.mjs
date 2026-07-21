import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const createPlugin = require('../infra/pi5nvme/signalk-plugins/signalk-two-engine-state/index.js');

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function makeApp() {
  let deltaHandler;
  const messages = [];
  const statuses = [];
  const unsubscribes = [];

  const app = {
    selfId: 'self',
    subscriptionmanager: {
      subscribe(subscription, unsubscribeList, onError, onDelta) {
        deltaHandler = onDelta;
        const unsubscribe = () => {};
        unsubscribeList.push(unsubscribe);
        unsubscribes.push(unsubscribe);
        app.subscription = subscription;
      },
    },
    handleMessage(id, message) {
      messages.push({ id, message });
    },
    setPluginStatus(status) {
      statuses.push(status);
    },
    error(message) {
      throw new Error(message);
    },
    debug() {},
  };

  return {
    app,
    messages,
    statuses,
    unsubscribes,
    send(path, value) {
      assert.equal(typeof deltaHandler, 'function', 'plugin subscribed');
      deltaHandler({ updates: [{ values: [{ path, value }] }] });
    },
  };
}

function emittedValues(messages) {
  return messages.flatMap(({ id, message }) => message.updates.flatMap((update) => update.values.map((value) => ({
    id,
    context: message.context,
    source: update.source.label,
    path: value.path,
    value: value.value,
  }))));
}

test('emits independent port and starboard states after debounce', async () => {
  const fixture = makeApp();
  const plugin = createPlugin(fixture.app);

  plugin.start({ startDebounceSeconds: 0.01, stopDebounceSeconds: 0.01 });

  assert.deepEqual(fixture.app.subscription.subscribe.map((s) => s.path).sort(), [
    'electrical.alternators.alpha-port.senseVoltage',
    'electrical.alternators.alpha-stbd.senseVoltage',
  ].sort());

  fixture.send('electrical.alternators.alpha-port.senseVoltage', 0);
  fixture.send('electrical.alternators.alpha-stbd.senseVoltage', 13.8);
  await delay(25);

  assert.deepEqual(emittedValues(fixture.messages), [
    {
      id: 'signalk-two-engine-state',
      context: 'vessels.self',
      source: 'signalk-two-engine-state',
      path: 'propulsion.port.state',
      value: 'stopped',
    },
    {
      id: 'signalk-two-engine-state',
      context: 'vessels.self',
      source: 'signalk-two-engine-state',
      path: 'propulsion.starboard.state',
      value: 'started',
    },
  ]);

  plugin.stop();
});

test('debounce suppresses short threshold crossings', async () => {
  const fixture = makeApp();
  const plugin = createPlugin(fixture.app);

  plugin.start({ startDebounceSeconds: 0.05, stopDebounceSeconds: 0.01 });

  fixture.send('electrical.alternators.alpha-port.senseVoltage', 12);
  await delay(10);
  fixture.send('electrical.alternators.alpha-port.senseVoltage', 0);
  await delay(70);

  assert.deepEqual(emittedValues(fixture.messages), [
    {
      id: 'signalk-two-engine-state',
      context: 'vessels.self',
      source: 'signalk-two-engine-state',
      path: 'propulsion.port.state',
      value: 'stopped',
    },
  ]);

  plugin.stop();
});

test('supports custom schema-safe input aliases and output paths', async () => {
  const fixture = makeApp();
  const plugin = createPlugin(fixture.app);

  plugin.start({
    threshold: 5,
    startDebounceSeconds: 0.01,
    stopDebounceSeconds: 0.01,
    engines: [
      {
        name: 'port',
        inputPath: 'electrical.alternators.alphaPort.senseVoltage',
        outputPath: 'propulsion.port.state',
      },
    ],
  });

  fixture.send('electrical.alternators.alpha-port.senseVoltage', 12);
  fixture.send('electrical.alternators.alphaPort.senseVoltage', 12);
  await delay(25);

  assert.deepEqual(emittedValues(fixture.messages), [
    {
      id: 'signalk-two-engine-state',
      context: 'vessels.self',
      source: 'signalk-two-engine-state',
      path: 'propulsion.port.state',
      value: 'started',
    },
  ]);

  plugin.stop();
});
