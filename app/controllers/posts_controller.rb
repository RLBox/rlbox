# frozen_string_literal: true

class PostsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_post, only: %i[show edit update destroy]

  def index
    @posts = Current.user.posts.order(created_at: :desc)
  end

  def show; end

  def new
    @post = Post.new
  end

  def create
    @post = Current.user.posts.build(post_params)
    if @post.save
      redirect_to @post, notice: 'Post was created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @post.update(post_params)
      redirect_to @post, notice: 'Post was updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @post.destroy
    redirect_to posts_path, notice: 'Post was deleted.'
  end

  private

  def set_post
    @post = Current.user.posts.find(params[:id])
  end

  def post_params
    params.require(:post).permit(:title, :body, :status)
  end
end
