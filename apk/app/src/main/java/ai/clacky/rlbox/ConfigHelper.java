package RLBOX_PACKAGE_ID;

import android.content.Context;
import android.provider.Settings;
import android.util.Log;

/**
 * 配置帮助类
 * 用于读取通过 adb shell settings put global 设置的配置
 */
public class ConfigHelper {
    private static final String TAG = "ConfigHelper";

    // 配置键名（与 adb 命令中的 key 对应）
    public static final String KEY_API_ENDPOINT = "app_api_endpoint";
    public static final String KEY_SESSION_ID = "app_session_id";
    public static final String KEY_TASK_ID = "app_task_id";

    /**
     * 读取全局配置
     * @param context 上下文
     * @param key 配置键名
     * @param defaultValue 默认值
     * @return 配置值
     */
    public static String getGlobalSetting(Context context, String key, String defaultValue) {
        try {
            String value = Settings.Global.getString(context.getContentResolver(), key);
            if (value != null && !value.isEmpty()) {
                Log.d(TAG, "Read global setting: " + key + " = " + value);
                return value;
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to read global setting: " + key, e);
        }
        Log.d(TAG, "Using default value for " + key + ": " + defaultValue);
        return defaultValue;
    }

    /**
     * 获取 API 端点
     * 支持动态配置（云手机场景）
     */
    public static String getApiEndpoint(Context context) {
        // 从全局设置读取（通过 adb 设置）
        String endpoint = getGlobalSetting(context, KEY_API_ENDPOINT, null);

        if (endpoint != null) {
            Log.d(TAG, "Using dynamic API endpoint: " + endpoint);
            return endpoint;
        }

        // 使用编译时配置的默认值
        String defaultEndpoint = context.getString(R.string.launchUrl);
        Log.d(TAG, "Using default API endpoint: " + defaultEndpoint);
        return defaultEndpoint;
    }

    /**
     * 获取 Session ID
     */
    public static String getSessionId(Context context) {
        return getGlobalSetting(context, KEY_SESSION_ID, null);
    }

    /**
     * 获取 Task ID
     */
    public static String getTaskId(Context context) {
        return getGlobalSetting(context, KEY_TASK_ID, null);
    }
}
