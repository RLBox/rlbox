# frozen_string_literal: true

module Api
  class TasksController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :restore_validator_context  # API 不需要恢复验证器上下文
    before_action :authenticate_admin!
    
    # POST /api/tasks/:task_id/start
    # 启动新的验证会话
    def start
      task_id = params[:task_id]
      
      # 查找验证器
      validator_class = find_validator_class(task_id)
      
      unless validator_class
        render json: { error: "Validator not found: #{task_id}" }, status: :not_found
        return
      end
      
      # 生成新的 session_id（execution_id）
      session_id = SecureRandom.uuid
      
      # 创建验证器实例
      validator = validator_class.new(session_id)
      
      # 执行 prepare 阶段（会自动设置 data_version 并保存 execution 记录）
      prepare_result = validator.execute_prepare
      
      # execute_prepare 已经通过 save_execution_state 创建了 ValidatorExecution 记录
      # 现在我们只需要找到它并更新额外的字段
      execution = ValidatorExecution.find_by!(execution_id: session_id)
      
      # 更新额外的元数据字段
      execution.update!(
        validator_id: task_id,
        user_id: current_admin.id,
        status: 'running',
        is_active: true
      )
      
      # 返回响应（模拟 fliggy 的响应格式）
      render json: {
        verification: {
          config: {
            params: {
              session_id: session_id
            }
          }
        },
        execution_id: session_id,
        validator_id: task_id,
        status: 'running',
        message: 'Session created successfully'
      }
    rescue StandardError => e
      Rails.logger.error "Failed to start validation session: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: { error: "Failed to start session: #{e.message}" }, status: :internal_server_error
    end
    
    # POST /api/verify/run
    # 运行验证
    def verify
      task_id = params[:task_id]
      session_id = params[:session_id]
      
      unless session_id.present?
        render json: { error: 'Missing session_id' }, status: :bad_request
        return
      end
      
      # 查找验证器类
      validator_class = find_validator_class(task_id)
      
      unless validator_class
        render json: { error: "Validator not found: #{task_id}" }, status: :not_found
        return
      end
      
      # 查找 execution 记录
      execution = ValidatorExecution.find_by(execution_id: session_id)
      
      unless execution
        render json: { error: "Session not found: #{session_id}" }, status: :not_found
        return
      end
      
      # 创建验证器实例
      validator = validator_class.new(session_id)
      
      # 🔍 只读验证（ADR-010: CQRS 读写分离）
      # cleanup: false — verify 是纯读操作，必须可重复调用（幂等）。
      # 数据清理请走独立端点：POST /api/sessions/:session_id/cleanup
      result = validator.execute_verify(cleanup: false)
      
      # 注意：不再在 verify 时设置 is_active=false，
      # session 的生命周期归 cleanup / remove_session 管。
      
      # 写入 JSON 状态文件（主权威，面板直接读 JSON）
      persist_validator_status!(task_id, result[:status], result[:score])
      
      # 返回验证结果
      render json: {
        score: result[:score],
        passed: result[:status] == 'passed',
        assertions: result[:assertions],
        errors: result[:errors],
        execution_id: session_id
      }
    rescue StandardError => e
      Rails.logger.error "Failed to run validation: #{e.message}\n#{e.backtrace.join("\n")}"
      
      # 写入失败状态到 JSON
      persist_validator_status!(task_id, 'failed', 0.0) if task_id.present?
      
      render json: { 
        error: "Validation failed: #{e.message}",
        score: 0,
        passed: false,
        assertions: []
      }, status: :internal_server_error
    end
    
    # DELETE /api/sessions/:session_id
    # 移除指定会话（软删除：仅标记 is_active=false，不清数据）
    # 需要同时清数据请用 POST /api/sessions/:session_id/cleanup
    def remove_session
      session_id = params[:session_id]
      
      execution = ValidatorExecution.find_by(execution_id: session_id)
      
      unless execution
        render json: { error: "Session not found: #{session_id}" }, status: :not_found
        return
      end
      
      # 软删除：标记为非活跃
      execution.update!(is_active: false)
      
      render json: { message: 'Session removed successfully' }
    rescue StandardError => e
      Rails.logger.error "Failed to remove session: #{e.message}"
      render json: { error: "Failed to remove session: #{e.message}" }, status: :internal_server_error
    end
    
    # POST /api/sessions/:session_id/cleanup
    # 🗑️ 清理会话数据（ADR-010: CQRS 读写分离）
    #
    # 独立于 verify 的清理端点。调用语义：
    #   - 告知系统 "这个 session 的任务已结束，可以清理了"
    #   - 同时清三样东西：
    #     1) 业务数据（data_version 对应的所有 DataVersionable 记录）
    #     2) validator_executions 的 state 记录
    #     3) session 软删除标记（is_active=false）
    #
    # 幂等性：**宽松幂等**。约定"调 cleanup = 任务结束"，第二次调用：
    #   - 即使 state 已清 / 数据已空 / session 已失活，都返回 200
    #   - 不 raise、不 500，调用方无需防御
    def cleanup_session
      session_id = params[:session_id]
      
      unless session_id.present?
        render json: { error: 'Missing session_id' }, status: :bad_request
        return
      end
      
      execution = ValidatorExecution.find_by(execution_id: session_id)
      
      # 幂等：session 找不到也返回成功（可能是二次调用）
      unless execution
        render json: {
          message: 'Already cleaned (session not found)',
          session_id: session_id,
          cleaned_up: true
        }
        return
      end
      
      # 找 validator 类，走 execute_cleanup 抽象接口
      validator_class = find_validator_class(execution.validator_id)
      
      if validator_class
        validator = validator_class.new(session_id)
        result = validator.execute_cleanup
      else
        # validator 类查不到（被改名/删除），降级只清 session 不清业务数据
        result = { cleaned_up: true, reason: "validator class not found: #{execution.validator_id}" }
      end
      
      # 软删除 session
      execution.update!(is_active: false)
      
      render json: {
        message: 'Cleaned up successfully',
        session_id: session_id,
        cleaned_up: result[:cleaned_up],
        data_version: result[:data_version],
        reason: result[:reason]
      }.compact
    rescue StandardError => e
      # 宽松幂等：捕获所有错误，Rails 层记日志但对外返回成功
      Rails.logger.warn "cleanup_session swallowed error (idempotent): #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render json: {
        message: 'Cleaned up with warnings',
        session_id: session_id,
        cleaned_up: true,
        warning: e.message
      }
    end
    
    # DELETE /api/sessions
    # 清除所有会话
    def clear_all_sessions
      task_id = params[:task_id]
      
      if task_id.present?
        # 清除指定任务的所有会话
        ValidatorExecution.where(validator_id: task_id, user_id: current_admin.id).update_all(is_active: false)
      else
        # 清除当前用户的所有会话
        ValidatorExecution.where(user_id: current_admin.id).update_all(is_active: false)
      end
      
      render json: { message: 'All sessions cleared successfully' }
    rescue StandardError => e
      Rails.logger.error "Failed to clear sessions: #{e.message}"
      render json: { error: "Failed to clear sessions: #{e.message}" }, status: :internal_server_error
    end
    
    private
    
    def authenticate_admin!
      unless current_admin
        render json: { error: 'Unauthorized' }, status: :unauthorized
      end
    end
    
    def current_admin
      @current_admin ||= Administrator.find_by(id: session[:current_admin_id])
    end
    
    # 根据 validator_id 查找验证器类
    def find_validator_class(validator_id)
      # 自动加载所有 validator 文件
      validator_files = Dir[Rails.root.join('app/validators/**/*_validator.rb')]
      
      validator_files.each do |file|
        next if file.end_with?('base_validator.rb') || file.end_with?('multi_turn_base_validator.rb')
        
        # 推导类名（含 Validators:: 命名空间前缀）
        relative_path = file.gsub(Rails.root.join('app/validators/').to_s, '')
        class_path = relative_path.gsub('.rb', '').split('/')
        class_name = "Validators::" + class_path.map(&:camelize).join('::')
        
        begin
          klass = class_name.constantize
          next unless klass < Validators::BaseValidator
          
          # 匹配 validator_id
          if klass.validator_id == validator_id
            return klass
          end
        rescue StandardError => e
          Rails.logger.warn "Failed to load validator #{class_name}: #{e.message}"
        end
      end
      
      nil
    end

    # 将 validator 的执行结果持久化到 db/validator_statuses.json（主权威）。
    #
    # 并发安全：用 File::LOCK_EX 独占锁，保证多 session 并发跑不互相覆盖。
    # 锁粒度是整个 JSON 文件，写入时间极短（< 1ms），对吞吐量无影响。
    def persist_validator_status!(validator_id, status, score)
      path = Rails.root.join('db/validator_statuses.json')

      File.open(path, File::RDWR | File::CREAT) do |f|
        f.flock(File::LOCK_EX)

        # 读现有内容（文件可能刚创建为空）
        content = f.read
        statuses = content.present? ? JSON.parse(content) : {}

        # 更新目标 validator 条目
        statuses[validator_id] = {
          'status'     => status,
          'score'      => score,
          'updated_at' => Time.current.iso8601
        }

        # 回写
        f.rewind
        f.write(JSON.pretty_generate(statuses))
        f.truncate(f.pos)
      end
    rescue StandardError => e
      # 写 JSON 失败只记日志，不影响 verify 主流程返回
      Rails.logger.warn "persist_validator_status! failed for #{validator_id}: #{e.message}"
    end
  end
end
