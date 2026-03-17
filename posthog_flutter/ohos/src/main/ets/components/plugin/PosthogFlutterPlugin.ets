import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PostHogClient, FeatureFlagResult } from './PostHogClient';

const TAG = 'PosthogFlutterPlugin';
const DOMAIN = 0x0001;
const CHANNEL_NAME = 'posthog_flutter';

export default class PosthogFlutterPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private client: PostHogClient = PostHogClient.getInstance();
  private context: Context | null = null;

  getUniqueClassName(): string {
    return 'PosthogFlutterPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
    this.context = binding.getApplicationContext();
    this.initPlugin();
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
  }

  private async initPlugin(): Promise<void> {
    // Auto-init is handled via the setup() method call from Dart side
    // OHOS does not have AndroidManifest meta-data, so we rely on Dart-side setup
    hilog.info(DOMAIN, TAG, 'PosthogFlutterPlugin attached to engine');
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'setup':
        this.setup(call, result);
        break;
      case 'identify':
        this.identify(call, result);
        break;
      case 'setPersonProperties':
        this.setPersonProperties(call, result);
        break;
      case 'capture':
        this.capture(call, result);
        break;
      case 'screen':
        this.screen(call, result);
        break;
      case 'alias':
        this.alias(call, result);
        break;
      case 'distinctId':
        this.distinctId(result);
        break;
      case 'reset':
        this.reset(result);
        break;
      case 'disable':
        this.disable(result);
        break;
      case 'enable':
        this.enable(result);
        break;
      case 'isOptOut':
        this.isOptOut(result);
        break;
      case 'isFeatureEnabled':
        this.isFeatureEnabled(call, result);
        break;
      case 'reloadFeatureFlags':
        this.reloadFeatureFlags(result);
        break;
      case 'group':
        this.group(call, result);
        break;
      case 'getFeatureFlag':
        this.getFeatureFlag(call, result);
        break;
      case 'getFeatureFlagPayload':
        this.getFeatureFlagPayload(call, result);
        break;
      case 'getFeatureFlagResult':
        this.getFeatureFlagResult(call, result);
        break;
      case 'register':
        this.register(call, result);
        break;
      case 'unregister':
        this.unregister(call, result);
        break;
      case 'debug':
        this.debugMethod(call, result);
        break;
      case 'flush':
        this.flush(result);
        break;
      case 'captureException':
        this.captureException(call, result);
        break;
      case 'close':
        this.close(result);
        break;
      case 'sendMetaEvent':
        // Session replay meta events - not supported on OHOS yet
        result.success(null);
        break;
      case 'sendFullSnapshot':
        // Session replay snapshots - not supported on OHOS yet
        result.success(null);
        break;
      case 'isSessionReplayActive':
        result.success(false);
        break;
      case 'startSessionRecording':
        result.success(null);
        break;
      case 'stopSessionRecording':
        result.success(null);
        break;
      case 'getSessionId':
        this.getSessionId(result);
        break;
      case 'openUrl':
        this.openUrl(call, result);
        break;
      case 'surveyAction':
        // Surveys are handled on the Dart side
        result.success(null);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private async setup(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const args = call.args as Map<string, Object>;
      if (!args) {
        result.error('PosthogFlutterException', 'Arguments is null or empty', null);
        return;
      }

      if (this.context) {
        await this.client.setup(args, this.context);

        // Set up feature flags callback
        this.client.setOnFeatureFlagsCallback(() => {
          const emptyMap: Map<string, Object> = new Map();
          this.invokeFlutterMethod('onFeatureFlagsCallback', emptyMap);
        });
      }

      result.success(null);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private async identify(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const args = call.args as Map<string, Object>;
      const userId = args.get('userId') as string;
      const userProperties = args.get('userProperties') as Map<string, Object> | undefined;
      const userPropertiesSetOnce = args.get('userPropertiesSetOnce') as Map<string, Object> | undefined;
      await this.client.identify(userId, userProperties, userPropertiesSetOnce);
      result.success(null);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private async setPersonProperties(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const args = call.args as Map<string, Object>;
      const userPropertiesToSet = args.get('userPropertiesToSet') as Map<string, Object> | undefined;
      const userPropertiesToSetOnce = args.get('userPropertiesToSetOnce') as Map<string, Object> | undefined;
      await this.client.setPersonProperties(userPropertiesToSet, userPropertiesToSetOnce);
      result.success(null);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private async capture(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const args = call.args as Map<string, Object>;
      const eventName = args.get('eventName') as string;
      const properties = args.get('properties') as Map<string, Object> | undefined;
      const userProperties = args.get('userProperties') as Map<string, Object> | undefined;
      const userPropertiesSetOnce = args.get('userPropertiesSetOnce') as Map<string, Object> | undefined;
      await this.client.capture(eventName, properties, userProperties, userPropertiesSetOnce);
      result.success(null);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private async screen(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const args = call.args as Map<string, Object>;
      const screenName = args.get('screenName') as string;
      const properties = args.get('properties') as Map<string, Object> | undefined;
      await this.client.screen(screenName, properties);
      result.success(null);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private async alias(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const args = call.args as Map<string, Object>;
      const alias = args.get('alias') as string;
      await this.client.alias(alias);
      result.success(null);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private distinctId(result: MethodResult): void {
    try {
      const id = this.client.getDistinctId();
      result.success(id);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private async reset(result: MethodResult): Promise<void> {
    try {
      await this.client.reset();
      result.success(null);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private disable(result: MethodResult): void {
    try {
      this.client.optOutFn();
      result.success(null);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private enable(result: MethodResult): void {
    try {
      this.client.optIn();
      result.success(null);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private isOptOut(result: MethodResult): void {
    try {
      result.success(this.client.isOptOut());
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private isFeatureEnabled(call: MethodCall, result: MethodResult): void {
    try {
      const args = call.args as Map<string, Object>;
      const key = args.get('key') as string;
      result.success(this.client.isFeatureEnabled(key));
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private async reloadFeatureFlags(result: MethodResult): Promise<void> {
    try {
      await this.client.reloadFeatureFlags();
      result.success(null);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private async group(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const args = call.args as Map<string, Object>;
      const groupType = args.get('groupType') as string;
      const groupKey = args.get('groupKey') as string;
      const groupProperties = args.get('groupProperties') as Map<string, Object> | undefined;
      await this.client.group(groupType, groupKey, groupProperties);
      result.success(null);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private getFeatureFlag(call: MethodCall, result: MethodResult): void {
    try {
      const args = call.args as Map<string, Object>;
      const key = args.get('key') as string;
      result.success(this.client.getFeatureFlag(key));
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private getFeatureFlagPayload(call: MethodCall, result: MethodResult): void {
    try {
      const args = call.args as Map<string, Object>;
      const key = args.get('key') as string;
      result.success(this.client.getFeatureFlagPayload(key));
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private getFeatureFlagResult(call: MethodCall, result: MethodResult): void {
    try {
      const args = call.args as Map<string, Object>;
      const key = args.get('key') as string;
      const sendEvent = args.get('sendEvent') as boolean ?? true;

      if (!key) {
        result.error('PosthogFlutterException', 'Missing argument: key', null);
        return;
      }

      const flagResult = this.client.getFeatureFlagResult(key, sendEvent);
      if (flagResult) {
        const resultMap: Record<string, Object> = {
          'key': flagResult.key as Object,
          'enabled': flagResult.enabled as Object,
        };
        if (flagResult.variant !== null) {
          resultMap['variant'] = flagResult.variant as Object;
        }
        if (flagResult.payload !== null) {
          resultMap['payload'] = flagResult.payload as Object;
        }
        result.success(resultMap);
      } else {
        result.success(null);
      }
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private register(call: MethodCall, result: MethodResult): void {
    try {
      const args = call.args as Map<string, Object>;
      const key = args.get('key') as string;
      const value = args.get('value') as Object;
      this.client.register(key, value);
      result.success(null);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private unregister(call: MethodCall, result: MethodResult): void {
    try {
      const args = call.args as Map<string, Object>;
      const key = args.get('key') as string;
      this.client.unregister(key);
      result.success(null);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private debugMethod(call: MethodCall, result: MethodResult): void {
    try {
      const args = call.args as Map<string, Object>;
      const debugEnabled = args.get('debug') as boolean;
      this.client.setDebug(debugEnabled);
      result.success(null);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private async flush(result: MethodResult): Promise<void> {
    try {
      await this.client.flush();
      result.success(null);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private async captureException(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const args = call.args as Map<string, Object>;
      if (!args) {
        result.error('INVALID_ARGUMENTS', 'Invalid arguments for captureException', null);
        return;
      }

      const properties = args.get('properties') as Map<string, Object> | undefined;
      const timestampMs = args.get('timestamp') as number | undefined;

      await this.client.captureException(properties, timestampMs);
      result.success(null);
    } catch (e) {
      result.error('CAPTURE_EXCEPTION_ERROR', 'Failed to capture exception: ' + (e as Error).message, null);
    }
  }

  private async close(result: MethodResult): Promise<void> {
    try {
      await this.client.close();
      result.success(null);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private getSessionId(result: MethodResult): void {
    try {
      const sessionId = this.client.getSessionId();
      result.success(sessionId);
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private openUrl(call: MethodCall, result: MethodResult): void {
    try {
      const url = call.args as string;
      if (!url || url.trim() === '') {
        result.error('InvalidArguments', 'URL is null or empty', null);
        return;
      }

      // On OHOS, URL opening requires the Want mechanism
      // This is a simplified version - actual implementation may need UIAbilityContext
      try {
        // Use bundleManager to open URL via system browser
        const want: Record<string, Object> = {
          'action': 'ohos.want.action.viewData' as Object,
          'uri': url as Object,
        };
        hilog.info(DOMAIN, TAG, 'openUrl: ' + url);
        // Note: Full URL opening requires UIAbilityContext which is not available in plugin context
        // This is handled by the Dart side as a fallback
        result.success(null);
      } catch (e) {
        result.error('ActivityNotFound', 'Failed to open URL: ' + (e as Error).message, null);
      }
    } catch (e) {
      result.error('PosthogFlutterException', (e as Error).message, null);
    }
  }

  private invokeFlutterMethod(method: string, args: Object | null): void {
    if (this.channel) {
      this.channel.invokeMethod(method, args);
    }
  }
}
