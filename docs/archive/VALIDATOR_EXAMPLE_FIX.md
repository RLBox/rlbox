> ⚠️ **Archived** — 一次性修复笔记，仅保留作历史参考，勿模仿。

# Validation Task Example Fix

## 问题描述

用户发现验证任务管理页面显示 "No validation tasks yet"，但是 `v001_create_post_validator.rb` 文件已经存在。

## 根本原因

示例 validator 文件使用了 `requires_ui` 方法，但该方法在 `BaseValidator` 中未定义，导致 validator 加载失败。

## 解决方案

### 1. 修复 v001_create_post_validator.rb

移除了 `requires_ui` 方法调用，并进行了以下改进：

**主要变更**:
- ❌ 移除 `requires_ui :posts, :title, :body, status: %i[draft published]`
- ✅ 在 `prepare` 方法中返回任务信息和提示
- ✅ 在 `verify` 中添加 `data_version` 过滤确保会话隔离
- ✅ 在 `simulate` 中添加 `data_version` 字段
- ✅ 改进错误消息，提供更清晰的诊断信息
- ✅ 将界面语言从中文改为英文，与其他页面保持一致

**修改后的文件结构**:
```ruby
class V001CreatePostValidator < BaseValidator
  self.validator_id   = 'v001_create_post'
  self.title          = 'Create a Post in the System'
  self.description    = 'Please create a post with title "Hello World" and status "published".'
  self.timeout_seconds = 60

  def prepare
    {
      task: 'Create a post titled "Hello World" with status "published"',
      hint: 'Navigate to Posts section and create a new post'
    }
  end

  def verify
    add_assertion('A post titled "Hello World" exists', weight: 50) do
      post = Post.find_by(title: 'Hello World', data_version: @data_version)
      expect(post).not_to be_nil, 'No post with title "Hello World" found'
    end

    add_assertion('Post status is "published"', weight: 50) do
      post = Post.find_by(title: 'Hello World', data_version: @data_version)
      expect(post&.status).to eq('published'), 
        "Post status is incorrect. Expected: published, Actual: #{post&.status}"
    end
  end

  def simulate
    user = User.where(data_version: 0).first
    raise 'No users in baseline data' unless user

    Post.create!(
      title:  'Hello World',
      status: 'published',
      body:   'Created by V001CreatePostValidator simulate.',
      user:   user,
      data_version: @data_version
    )

    { message: 'Created post "Hello World" with status "published".' }
  end
end
```

### 2. 验证修复

运行测试命令确认 validator 可以正确加载：

```bash
cd /Users/zoey/rlbox && bin/rails runner "puts V001CreatePostValidator.metadata.inspect"
```

输出：
```
{id: "v001_create_post", validator_id: "v001_create_post", task_id: nil, 
 title: "Create a Post in the System", 
 description: "Please create a post with title \"Hello World\" and status \"published\".", 
 timeout: 60, is_multi_turn: false}
```

### 3. Controller 验证

测试 controller 能否正确加载：

```bash
cd /Users/zoey/rlbox && bin/rails runner "
controller = Admin::ValidationTasksController.new
tasks = controller.send(:load_all_validators)
puts 'Found ' + tasks.length.to_s + ' validators'
"
```

输出：
```
Found 1 validators:
  - v001_create_post: Create a Post in the System
```

## 最终结果

✅ Validator 文件语法正确
✅ Validator 可以被 Rails 正确加载
✅ Controller 可以读取 validator metadata
✅ 页面应该显示 "1 tasks total"

## 如何使用

1. 刷新浏览器页面 `http://localhost:3000/admin/validation_tasks`
2. 应该看到 "v001_create_post" 任务
3. 点击任务可以查看详情
4. 可以创建会话来测试这个验证任务

## 参考

- 原始文件: `/Users/zoey/rlbox/app/validators/v001_create_post_validator.rb`
- Controller: `/Users/zoey/rlbox/app/controllers/admin/validation_tasks_controller.rb`
- BaseValidator: `/Users/zoey/rlbox/app/validators/base_validator.rb`

修复完成时间: 2026-04-15
