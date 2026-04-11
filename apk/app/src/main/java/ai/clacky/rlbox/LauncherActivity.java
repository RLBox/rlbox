/*
 * Copyright 2020 Google Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package RLBOX_PACKAGE_ID;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;

/**
 * LauncherActivity - 启动器
 * 简单的跳转器，直接启动 CustomWebViewFallbackActivity
 */
public class LauncherActivity extends Activity {

    private static final String TAG = "LauncherActivity";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Log.d(TAG, "onCreate: Starting LauncherActivity");

        // 直接启动全屏 WebView Activity
        Intent intent = new Intent(this, CustomWebViewFallbackActivity.class);

        // 传递 Intent Data（支持 Deeplink 参数）
        if (getIntent().getData() != null) {
            intent.setData(getIntent().getData());
            Log.d(TAG, "Passing deeplink data: " + getIntent().getData());
        }

        startActivity(intent);
        finish();
    }
}
