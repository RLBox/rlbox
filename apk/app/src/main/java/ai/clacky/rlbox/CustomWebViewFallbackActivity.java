package RLBOX_PACKAGE_ID;

import android.graphics.Bitmap;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import androidx.appcompat.app.AppCompatActivity;

/**
 * 自定义 WebView Fallback Activity
 * 当 TWA 验证失败时，使用此 Activity 提供全屏 WebView 体验
 */
public class CustomWebViewFallbackActivity extends AppCompatActivity {
    private static final String TAG = "CustomWebViewFallback";
    private WebView webView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // 设置状态栏颜色和样式
        getWindow().setStatusBarColor(Color.parseColor("RLBOX_THEME_COLOR")); // 设置状态栏背景色

        // 设置浅色状态栏（状态栏图标为深色），不延伸到状态栏下方
        getWindow().getDecorView().setSystemUiVisibility(
            View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR  // 状态栏图标使用深色
        );

        // 创建 WebView
        webView = new WebView(this);
        webView.setBackgroundColor(Color.parseColor("RLBOX_THEME_COLOR"));

        // 配置 WebView
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);
        settings.setSupportZoom(true);
        settings.setBuiltInZoomControls(true);
        settings.setDisplayZoomControls(false);
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);

        // User Agent
        String userAgent = settings.getUserAgentString();
        settings.setUserAgentString(userAgent + " TWA-Fallback");

        // WebViewClient with error handling
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                Log.d(TAG, "shouldOverrideUrlLoading: " + url);
                return false; // 在 WebView 内导航
            }

            @Override
            public void onPageStarted(WebView view, String url, Bitmap favicon) {
                super.onPageStarted(view, url, favicon);
                Log.d(TAG, "onPageStarted: " + url);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                Log.d(TAG, "onPageFinished: " + url);
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                super.onReceivedError(view, request, error);
                Log.e(TAG, "onReceivedError: " + error.getDescription() +
                          " for URL: " + request.getUrl() +
                          " errorCode: " + error.getErrorCode());
            }
        });

        // WebChromeClient
        webView.setWebChromeClient(new WebChromeClient());

        setContentView(webView);

        // 构建最终 URL
        String finalUrl = buildLaunchUrl();
        Log.d(TAG, "Loading URL: " + finalUrl);
        webView.loadUrl(finalUrl);
    }

    /**
     * 构建启动 URL
     * 优先级: Deeplink 参数 > 全局配置参数 > 默认值
     */
    private String buildLaunchUrl() {
        // 1. 获取基础 API 端点（必须配置）
        String apiEndpoint = ConfigHelper.getApiEndpoint(this);

        if (apiEndpoint == null || apiEndpoint.isEmpty() || apiEndpoint.contains("localhost")) {
            // 未配置，返回错误页面
            return "data:text/html,<html><body style='margin:0;padding:40px;font-family:sans-serif;background:RLBOX_THEME_COLOR;color:#000;text-align:center;'>" +
                   "<h2>配置错误</h2>" +
                   "<p>请先配置 API 服务器地址：</p>" +
                   "<code style='background:#fff;padding:10px;display:block;margin:20px;border-radius:5px;'>" +
                   "adb shell settings put global app_api_endpoint http://YOUR_SERVER:PORT" +
                   "</code>" +
                   "</body></html>";
        }

        // 2. 构建 URL Builder
        Uri.Builder builder = Uri.parse(apiEndpoint).buildUpon();

        // 3. 从 Deeplink 获取参数
        Uri intentData = getIntent().getData();
        String taskIdFromDeeplink = null;
        String sessionIdFromDeeplink = null;

        if (intentData != null) {
            taskIdFromDeeplink = intentData.getQueryParameter("task_id");
            sessionIdFromDeeplink = intentData.getQueryParameter("session_id");
        }

        // 4. 添加 task_id（Deeplink > 全局配置）
        if (taskIdFromDeeplink != null) {
            builder.appendQueryParameter("task_id", taskIdFromDeeplink);
        } else {
            String taskId = ConfigHelper.getTaskId(this);
            if (taskId != null) {
                builder.appendQueryParameter("task_id", taskId);
            }
        }

        // 5. 添加 session_id（Deeplink > 全局配置）
        if (sessionIdFromDeeplink != null) {
            builder.appendQueryParameter("session_id", sessionIdFromDeeplink);
        } else {
            String sessionId = ConfigHelper.getSessionId(this);
            if (sessionId != null) {
                builder.appendQueryParameter("session_id", sessionId);
            }
        }

        return builder.build().toString();
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.destroy();
        }
        super.onDestroy();
    }
}
