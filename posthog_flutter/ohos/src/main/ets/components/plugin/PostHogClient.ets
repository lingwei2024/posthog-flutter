import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { Context } from '@kit.AbilityKit';

const TAG = 'PostHogClient';
const DOMAIN = 0x0001;
const DEFAULT_HOST = 'https://us.i.posthog.com';
const PREFS_STORE_NAME = 'posthog_flutter_prefs';

class PostHogEvent {
  event: string;
  properties: Map<string, Object>;
  timestamp: string;

  constructor(event: string, properties: Map<string, Object>, timestamp: string) {
    this.event = event;
    this.properties = properties;
    this.timestamp = timestamp;
  }

  toRecord(): Record<string, Object> {
    const propsRecord: Record<string, Object> = {};
    this.properties.forEach((value: Object, key: string) => {
      propsRecord[key] = value;
    });
    const result: Record<string, Object> = {
      'event': this.event as Object,
      'properties': propsRecord as Object,
      'timestamp': this.timestamp as Object,
    };
    return result;
  }
}

export class FeatureFlagResult {
  key: string;
  enabled: boolean;
  variant: string | null;
  payload: Object | null;

  constructor(key: string, enabled: boolean, variant: string | null, payload: Object | null) {
    this.key = key;
    this.enabled = enabled;
    this.variant = variant;
    this.payload = payload;
  }
}

export class PostHogClient {
  private static instance: PostHogClient | null = null;

  private apiKey: string = '';
  private host: string = DEFAULT_HOST;
  private debugEnabled: boolean = false;
  private optedOut: boolean = false;
  private currentDistinctId: string = '';
  private anonymousId: string = '';
  private superProperties: Map<string, Object> = new Map();
  private featureFlags: Map<string, Object> = new Map();
  private featureFlagPayloads: Map<string, Object> = new Map();
  private eventQueue: PostHogEvent[] = [];
  private flushAt: number = 20;
  private maxQueueSize: number = 1000;
  private maxBatchSize: number = 50;
  private flushIntervalSeconds: number = 30;
  private sendFeatureFlagEvent: boolean = true;
  private preloadFeatureFlagsEnabled: boolean = true;
  private personProfiles: string = 'identifiedOnly';
  private sessionReplay: boolean = false;
  private appContext: Context | null = null;
  private flushTimer: number | null = null;
  private onFeatureFlagsCallback: (() => void) | null = null;
  private sdkName: string = 'posthog-flutter';
  private sdkVersion: string = '5.18.0';

  private constructor() {
  }

  static getInstance(): PostHogClient {
    if (!PostHogClient.instance) {
      PostHogClient.instance = new PostHogClient();
    }
    return PostHogClient.instance!;
  }

  async setup(config: Record<string, Object>, context: Context): Promise<void> {
    this.appContext = context;

    this.apiKey = (config['apiKey'] as string) || '';
    this.host = (config['host'] as string) || DEFAULT_HOST;
    this.debugEnabled = (config['debug'] as boolean) || false;
    this.optedOut = (config['optOut'] as boolean) || false;
    this.flushAt = (config['flushAt'] as number) || 20;
    this.maxQueueSize = (config['maxQueueSize'] as number) || 1000;
    this.maxBatchSize = (config['maxBatchSize'] as number) || 50;
    this.flushIntervalSeconds = (config['flushInterval'] as number) || 30;
    this.sendFeatureFlagEvent = (config['sendFeatureFlagEvents'] as boolean) ?? true;
    this.preloadFeatureFlagsEnabled = (config['preloadFeatureFlags'] as boolean) ?? true;
    this.personProfiles = (config['personProfiles'] as string) || 'identifiedOnly';
    this.sessionReplay = (config['sessionReplay'] as boolean) || false;
    this.sdkName = (config['sdkName'] as string) || 'posthog-flutter';
    this.sdkVersion = (config['sdkVersion'] as string) || '5.18.0';

    if (this.apiKey === '') {
      this.logError('apiKey is missing!');
      return;
    }

    await this.loadPersistedState();

    if (this.anonymousId === '') {
      this.anonymousId = util.generateRandomUUID();
      await this.persistState();
    }

    if (this.currentDistinctId === '') {
      this.currentDistinctId = this.anonymousId;
      await this.persistState();
    }

    this.startFlushTimer();

    if (this.preloadFeatureFlagsEnabled) {
      this.reloadFeatureFlags();
    }

    this.logInfo('PostHog initialized with host: ' + this.host);
  }

  setOnFeatureFlagsCallback(callback: (() => void) | null): void {
    this.onFeatureFlagsCallback = callback;
  }

  async identify(userId: string, userProperties?: Record<string, Object>,
    userPropertiesSetOnce?: Record<string, Object>): Promise<void> {
    if (this.optedOut) return;

    const previousDistinctId = this.currentDistinctId;
    this.currentDistinctId = userId;
    await this.persistState();

    const properties: Map<string, Object> = new Map();
    properties.set('$anon_distinct_id', previousDistinctId);
    if (userProperties) {
      properties.set('$set', userProperties);
    }
    if (userPropertiesSetOnce) {
      properties.set('$set_once', userPropertiesSetOnce);
    }

    await this.enqueueEvent('$identify', properties);
  }

  async setPersonProperties(userPropertiesToSet?: Record<string, Object>,
    userPropertiesToSetOnce?: Record<string, Object>): Promise<void> {
    if (this.optedOut) return;

    const properties: Map<string, Object> = new Map();
    if (userPropertiesToSet) {
      properties.set('$set', userPropertiesToSet);
    }
    if (userPropertiesToSetOnce) {
      properties.set('$set_once', userPropertiesToSetOnce);
    }

    await this.enqueueEvent('$set', properties);
  }

  async capture(eventName: string, properties?: Record<string, Object>,
    userProperties?: Record<string, Object>,
    userPropertiesSetOnce?: Record<string, Object>): Promise<void> {
    if (this.optedOut) return;

    const eventProperties: Map<string, Object> = new Map();
    if (properties) {
      const keys = Object.keys(properties);
      for (let i = 0; i < keys.length; i++) {
        eventProperties.set(keys[i], properties[keys[i]]);
      }
    }
    if (userProperties) {
      eventProperties.set('$set', userProperties);
    }
    if (userPropertiesSetOnce) {
      eventProperties.set('$set_once', userPropertiesSetOnce);
    }

    await this.enqueueEvent(eventName, eventProperties);
  }

  async screen(screenName: string, properties?: Record<string, Object>): Promise<void> {
    if (this.optedOut) return;

    const screenProperties: Map<string, Object> = new Map();
    screenProperties.set('$screen_name', screenName);
    if (properties) {
      const keys = Object.keys(properties);
      for (let i = 0; i < keys.length; i++) {
        screenProperties.set(keys[i], properties[keys[i]]);
      }
    }

    await this.enqueueEvent('$screen', screenProperties);
  }

  async alias(aliasValue: string): Promise<void> {
    if (this.optedOut) return;

    const properties: Map<string, Object> = new Map();
    properties.set('alias', aliasValue);

    await this.enqueueEvent('$create_alias', properties);
  }

  getDistinctId(): string {
    return this.currentDistinctId;
  }

  async reset(): Promise<void> {
    this.currentDistinctId = '';
    this.anonymousId = util.generateRandomUUID();
    this.currentDistinctId = this.anonymousId;
    this.superProperties.clear();
    this.featureFlags.clear();
    this.featureFlagPayloads.clear();
    await this.persistState();
  }

  optIn(): void {
    this.optedOut = false;
  }

  optOutFn(): void {
    this.optedOut = true;
  }

  isOptOut(): boolean {
    return this.optedOut;
  }

  setDebug(enabled: boolean): void {
    this.debugEnabled = enabled;
  }

  isFeatureEnabled(key: string): boolean {
    const flag = this.featureFlags.get(key);
    if (flag === undefined || flag === null) return false;
    if (typeof flag === 'boolean') return flag as boolean;
    return true;
  }

  getFeatureFlag(key: string): Object | null {
    const flag = this.featureFlags.get(key);
    if (flag === undefined) return null;
    return flag;
  }

  getFeatureFlagPayload(key: string): Object | null {
    const payload = this.featureFlagPayloads.get(key);
    if (payload === undefined) return null;
    return payload;
  }

  getFeatureFlagResult(key: string, sendEvent: boolean): FeatureFlagResult | null {
    const flag = this.featureFlags.get(key);
    if (flag === undefined || flag === null) return null;

    const enabled: boolean = typeof flag === 'boolean' ? (flag as boolean) : true;
    const variant: string | null = typeof flag === 'string' ? (flag as string) : null;
    const payloadVal = this.featureFlagPayloads.get(key);
    const payload: Object | null = payloadVal !== undefined ? payloadVal : null;

    if (sendEvent && this.sendFeatureFlagEvent) {
      const featureFlagProps: Map<string, Object> = new Map();
      featureFlagProps.set('$feature_flag', key);
      featureFlagProps.set('$feature_flag_response', flag);
      this.enqueueEvent('$feature_flag_called', featureFlagProps);
    }

    return new FeatureFlagResult(key, enabled, variant, payload);
  }

  async reloadFeatureFlags(): Promise<void> {
    try {
      const url = this.host + '/decide/?v=3';
      const body: Record<string, Object> = {
        'api_key': this.apiKey as Object,
        'distinct_id': this.currentDistinctId as Object,
      };

      const response = await this.httpPost(url, JSON.stringify(body));
      if (response) {
        const data = JSON.parse(response) as Record<string, Object>;

        const flags = data['featureFlags'] as Record<string, Object>;
        if (flags) {
          this.featureFlags.clear();
          const flagKeys = Object.keys(flags);
          for (let i = 0; i < flagKeys.length; i++) {
            this.featureFlags.set(flagKeys[i], flags[flagKeys[i]]);
          }
        }

        const payloads = data['featureFlagPayloads'] as Record<string, Object>;
        if (payloads) {
          this.featureFlagPayloads.clear();
          const payloadKeys = Object.keys(payloads);
          for (let i = 0; i < payloadKeys.length; i++) {
            this.featureFlagPayloads.set(payloadKeys[i], payloads[payloadKeys[i]]);
          }
        }

        this.logInfo('Feature flags reloaded successfully');

        if (this.onFeatureFlagsCallback) {
          this.onFeatureFlagsCallback();
        }
      }
    } catch (e) {
      this.logError('Failed to reload feature flags: ' + (e as Error).message);
    }
  }

  async group(groupType: string, groupKey: string,
    groupProperties?: Record<string, Object>): Promise<void> {
    if (this.optedOut) return;

    const properties: Map<string, Object> = new Map();
    properties.set('$group_type', groupType);
    properties.set('$group_key', groupKey);
    if (groupProperties) {
      properties.set('$group_set', groupProperties);
    }

    await this.enqueueEvent('$groupidentify', properties);
  }

  register(key: string, value: Object): void {
    this.superProperties.set(key, value);
  }

  unregister(key: string): void {
    this.superProperties.delete(key);
  }

  async flush(): Promise<void> {
    if (this.eventQueue.length === 0) return;

    const batchSize = Math.min(this.maxBatchSize, this.eventQueue.length);
    const eventsToSend: PostHogEvent[] = this.eventQueue.splice(0, batchSize);

    const batchArray: Record<string, Object>[] = [];
    for (let i = 0; i < eventsToSend.length; i++) {
      batchArray.push(eventsToSend[i].toRecord());
    }

    const url = this.host + '/batch/';
    const bodyRecord: Record<string, Object> = {
      'api_key': this.apiKey as Object,
      'batch': batchArray as Object,
    };

    try {
      await this.httpPost(url, JSON.stringify(bodyRecord));
      this.logInfo('Flushed ' + eventsToSend.length + ' events');
    } catch (e) {
      // Put events back on failure
      for (let i = eventsToSend.length - 1; i >= 0; i--) {
        this.eventQueue.unshift(eventsToSend[i]);
      }
      this.logError('Failed to flush events: ' + (e as Error).message);
    }
  }

  async captureException(properties?: Record<string, Object>,
    timestamp?: number): Promise<void> {
    if (this.optedOut) return;

    const eventProperties: Map<string, Object> = new Map();
    if (properties) {
      const keys = Object.keys(properties);
      for (let i = 0; i < keys.length; i++) {
        eventProperties.set(keys[i], properties[keys[i]]);
      }
    }

    await this.enqueueEvent('$exception', eventProperties, timestamp);
  }

  async close(): Promise<void> {
    this.stopFlushTimer();
    await this.flush();
    PostHogClient.instance = null;
  }

  getSessionId(): string | null {
    return null;
  }

  isSessionReplayActive(): boolean {
    return false;
  }

  startSessionReplay(_resumeCurrent: boolean): void {
  }

  stopSessionReplay(): void {
  }

  // Private methods

  private async enqueueEvent(eventName: string, properties: Map<string, Object>,
    timestamp?: number): Promise<void> {
    const allProperties: Map<string, Object> = new Map();

    // Add super properties
    this.superProperties.forEach((value: Object, key: string) => {
      allProperties.set(key, value);
    });

    // Merge with event properties (event properties take precedence)
    properties.forEach((value: Object, key: string) => {
      allProperties.set(key, value);
    });

    // Add common properties
    allProperties.set('$lib', this.sdkName);
    allProperties.set('$lib_version', this.sdkVersion);
    allProperties.set('distinct_id', this.currentDistinctId);

    const tsString: string = timestamp
      ? new Date(timestamp).toISOString()
      : new Date().toISOString();

    const event = new PostHogEvent(eventName, allProperties, tsString);

    if (this.eventQueue.length >= this.maxQueueSize) {
      this.eventQueue.shift();
    }
    this.eventQueue.push(event);

    if (this.eventQueue.length >= this.flushAt) {
      await this.flush();
    }
  }

  private async httpPost(url: string, body: string): Promise<string | null> {
    try {
      const httpRequest = http.createHttp();
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'User-Agent': this.sdkName + '/' + this.sdkVersion,
        },
        extraData: body,
        connectTimeout: 10000,
        readTimeout: 10000,
      });
      httpRequest.destroy();

      if (response.responseCode >= 200 && response.responseCode < 300) {
        return response.result as string;
      } else {
        this.logError('HTTP error: ' + response.responseCode);
        return null;
      }
    } catch (e) {
      this.logError('HTTP request failed: ' + (e as Error).message);
      return null;
    }
  }

  private startFlushTimer(): void {
    this.stopFlushTimer();
    this.flushTimer = setInterval(() => {
      this.flush();
    }, this.flushIntervalSeconds * 1000);
  }

  private stopFlushTimer(): void {
    if (this.flushTimer !== null) {
      clearInterval(this.flushTimer);
      this.flushTimer = null;
    }
  }

  private async loadPersistedState(): Promise<void> {
    if (!this.appContext) return;

    try {
      const store = await preferences.getPreferences(this.appContext, PREFS_STORE_NAME);
      this.currentDistinctId = (await store.get('distinctId', '')) as string;
      this.anonymousId = (await store.get('anonymousId', '')) as string;
    } catch (e) {
      this.logError('Failed to load persisted state: ' + (e as Error).message);
    }
  }

  private async persistState(): Promise<void> {
    if (!this.appContext) return;

    try {
      const store = await preferences.getPreferences(this.appContext, PREFS_STORE_NAME);
      await store.put('distinctId', this.currentDistinctId);
      await store.put('anonymousId', this.anonymousId);
      await store.flush();
    } catch (e) {
      this.logError('Failed to persist state: ' + (e as Error).message);
    }
  }

  private logInfo(message: string): void {
    if (this.debugEnabled) {
      hilog.info(DOMAIN, TAG, message);
    }
  }

  private logError(message: string): void {
    hilog.error(DOMAIN, TAG, message);
  }
}
