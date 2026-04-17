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
      
      # 运行验证（会自动 restore_execution_state 恢复 @data_version）
      # cleanup: false 表示不删除测试数据（用于手动测试）
      result = validator.execute_verify(cleanup: false)
      
      # execute_verify 已经更新了 ValidatorExecution 记录
      # 但我们需要补充设置 is_active = false
      execution.update!(is_active: false)
      
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
      
      # 更新 execution 记录为失败
      if execution
        execution.update(
          status: 'failed',
          score: 0.0,
          verify_result: { error: e.message },
          is_active: false
        )
      end
      
      render json: { 
        error: "Validation failed: #{e.message}",
        score: 0,
        passed: false,
        assertions: []
      }, status: :internal_server_error
    end
    
    # DELETE /api/sessions/:session_id
    # 移除指定会话
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
        
        # 推导类名
        relative_path = file.gsub(Rails.root.join('app/validators/').to_s, '')
        class_path = relative_path.gsub('.rb', '').split('/')
        class_name = class_path.map(&:camelize).join('::')
        
        begin
          klass = class_name.constantize
          next unless klass < BaseValidator
          
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
  end
end
