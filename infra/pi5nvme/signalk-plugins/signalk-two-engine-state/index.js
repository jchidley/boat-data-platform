'use strict';

const DEFAULT_ENGINES = [
  {
    name: 'port',
    inputPath: 'electrical.alternators.alpha-port.senseVoltage',
    outputPath: 'propulsion.port.state',
  },
  {
    name: 'starboard',
    inputPath: 'electrical.alternators.alpha-stbd.senseVoltage',
    outputPath: 'propulsion.starboard.state',
  },
];

function secondsToMs(value, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0) {
    return fallback * 1000;
  }
  return n * 1000;
}

function numericOption(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function normalizeEngines(configured) {
  const engines = Array.isArray(configured) && configured.length > 0 ? configured : DEFAULT_ENGINES;
  return engines
    .map((engine) => ({
      name: String(engine.name || '').trim(),
      inputPath: String(engine.inputPath || '').trim(),
      outputPath: String(engine.outputPath || '').trim(),
    }))
    .filter((engine) => engine.name && engine.inputPath && engine.outputPath);
}

module.exports = (app) => {
  const plugin = {};
  const setStatus = app.setPluginStatus || app.setProviderStatus || (() => {});

  let unsubscribes = [];
  let engineStates = new Map();
  let stopped = true;
  let activeOptions = {};

  plugin.id = 'signalk-two-engine-state';
  plugin.name = 'Two Engine State';
  plugin.description = 'Derives port and starboard engine state from alternator sense voltage';

  function clearPending(engineState) {
    if (engineState.timer) {
      clearTimeout(engineState.timer);
      engineState.timer = null;
    }
    engineState.pendingState = null;
  }

  function emitState(engineConfig, engineState, state) {
    if (stopped) {
      return;
    }

    engineState.currentState = state;
    engineState.pendingState = null;
    engineState.timer = null;

    app.handleMessage(plugin.id, {
      context: `vessels.${app.selfId}`,
      updates: [
        {
          source: { label: plugin.id },
          timestamp: new Date().toISOString(),
          values: [
            {
              path: engineConfig.outputPath,
              value: state,
            },
          ],
        },
      ],
    });

    setStatus(`${engineConfig.name}: ${state}`);
  }

  function scheduleState(engineConfig, desiredState) {
    const engineState = engineStates.get(engineConfig.name);
    if (!engineState || stopped) {
      return;
    }

    if (engineState.currentState === desiredState) {
      clearPending(engineState);
      return;
    }

    if (engineState.pendingState === desiredState && engineState.timer) {
      return;
    }

    clearPending(engineState);
    engineState.pendingState = desiredState;

    const debounceMs = desiredState === 'started'
      ? activeOptions.startDebounceMs
      : activeOptions.stopDebounceMs;

    engineState.timer = setTimeout(() => {
      emitState(engineConfig, engineState, desiredState);
    }, debounceMs);
  }

  function handleValue(path, value) {
    const engineConfig = activeOptions.enginesByInputPath.get(path);
    if (!engineConfig) {
      return;
    }

    const n = Number(value);
    if (!Number.isFinite(n)) {
      app.debug?.(`${plugin.id}: ignoring non-numeric value for ${path}: ${value}`);
      return;
    }

    const engineState = engineStates.get(engineConfig.name);
    if (engineState) {
      engineState.lastValue = n;
      engineState.lastUpdate = Date.now();
    }

    scheduleState(engineConfig, n > activeOptions.threshold ? 'started' : 'stopped');
  }

  plugin.start = (options = {}) => {
    stopped = false;
    const engines = normalizeEngines(options.engines);
    if (engines.length === 0) {
      throw new Error(`${plugin.id}: at least one engine must be configured`);
    }

    activeOptions = {
      threshold: numericOption(options.threshold, 13.25),
      startDebounceMs: secondsToMs(options.startDebounceSeconds, 10),
      stopDebounceMs: secondsToMs(options.stopDebounceSeconds, 30),
      engines,
      enginesByInputPath: new Map(),
    };

    engineStates = new Map(engines.map((engine) => [
      engine.name,
      {
        currentState: null,
        pendingState: null,
        timer: null,
        lastValue: null,
        lastUpdate: null,
      },
    ]));

    engines.forEach((engine) => {
      activeOptions.enginesByInputPath.set(engine.inputPath, engine);
    });

    const subscription = {
      context: 'vessels.self',
      subscribe: Array.from(activeOptions.enginesByInputPath.keys()).map((path) => ({
        path,
        period: numericOption(options.subscriptionPeriodMs, 1000),
      })),
    };

    app.subscriptionmanager.subscribe(
      subscription,
      unsubscribes,
      (subscriptionError) => {
        app.error(`${plugin.id}: subscription error: ${subscriptionError}`);
      },
      (delta) => {
        if (!delta || !Array.isArray(delta.updates)) {
          return;
        }
        delta.updates.forEach((update) => {
          if (!Array.isArray(update.values)) {
            return;
          }
          update.values.forEach((v) => handleValue(v.path, v.value));
        });
      },
    );

    setStatus(`Waiting for ${engines.length} engine sense-voltage paths`);
  };

  plugin.stop = () => {
    stopped = true;
    engineStates.forEach((engineState) => clearPending(engineState));
    unsubscribes.forEach((unsubscribe) => unsubscribe());
    unsubscribes = [];
    engineStates = new Map();
    activeOptions = {};
  };

  plugin.schema = {
    type: 'object',
    properties: {
      threshold: {
        type: 'number',
        default: 13.25,
        title: 'Sense voltage threshold above which an engine is considered charging/started',
      },
      startDebounceSeconds: {
        type: 'number',
        default: 10,
        title: 'Seconds above threshold before emitting started',
      },
      stopDebounceSeconds: {
        type: 'number',
        default: 30,
        title: 'Seconds at or below threshold before emitting stopped',
      },
      subscriptionPeriodMs: {
        type: 'number',
        default: 1000,
        title: 'Signal K subscription period in milliseconds',
      },
      engines: {
        type: 'array',
        title: 'Engines',
        default: DEFAULT_ENGINES,
        items: {
          type: 'object',
          required: ['name', 'inputPath', 'outputPath'],
          properties: {
            name: {
              type: 'string',
              title: 'Engine name',
            },
            inputPath: {
              type: 'string',
              title: 'Signal K sense-voltage input path',
            },
            outputPath: {
              type: 'string',
              title: 'Signal K engine-state output path',
            },
          },
        },
      },
    },
  };

  return plugin;
};

module.exports.DEFAULT_ENGINES = DEFAULT_ENGINES;
