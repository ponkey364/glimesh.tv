defmodule Glimesh.Api.ChatResolver do
  @moduledoc false

  alias Glimesh.Accounts
  alias Glimesh.ChannelLookups
  alias Glimesh.Chat

  def create_chat_message(
        _parent,
        %{channel_id: channel_id, message: message_obj},
        %{context: %{access: access}}
      ) do
    with :ok <- Bodyguard.permit(Glimesh.Api.Scopes, :chat, access) do
      channel = ChannelLookups.get_channel!(channel_id)
      # Force a refresh of the user just in case they are platform banned
      user = Accounts.get_user!(access.user.id)

      case Chat.create_chat_message(user, channel, message_obj) do
        {:ok, message} ->
          {:ok, message}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, Glimesh.Api.parse_ecto_changeset_errors(changeset)}

        {:error, message} when is_binary(message) ->
          {:error, message}

        _ ->
          {:error, "Unknown error."}
      end
    end
  end

  def create_tenor_message(
        _parent,
        %{channel_id: channel_id, message: message_obj},
        %{context: %{access: access}}
      ) do
    with :ok <- Bodyguard.permit(Glimesh.Api.Scopes, :chat, access) do
      channel = ChannelLookups.get_channel!(channel_id)
      # Force a refresh of the user just in case they are platform banned
      user = Accounts.get_user!(access.user.id)

      case Chat.create_tenor_message(user, channel, message_obj) do
        {:ok, message} ->
          {:ok, message}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, Glimesh.Api.parse_ecto_changeset_errors(changeset)}

        {:error, message} when is_binary(message) ->
          {:error, message}

        _ ->
          {:error, "Unknown error."}
      end
    end
  end

  def short_timeout_user(parent, params, context) do
    perform_channel_action(parent, params, context, :short_timeout)
  end

  def long_timeout_user(parent, params, context) do
    perform_channel_action(parent, params, context, :long_timeout)
  end

  def ban_user(parent, params, context) do
    perform_channel_action(parent, params, context, :ban)
  end

  def unban_user(parent, params, context) do
    perform_channel_action(parent, params, context, :unban)
  end

  @doc """
  Sends a delete chat message call, but make sure the api access is allowed
  """
  def delete_chat_message(_parent, %{channel_id: channel_id, message_id: message_id}, %{
        context: %{access: access}
      }) do
    # Send an action to the Chat context to figure out permissions on, but first make sure
    # the api access is allowed access to the chat.
    with :ok <- Bodyguard.permit(Glimesh.Api.Scopes, :chat, access) do
      channel = ChannelLookups.get_channel!(channel_id)
      moderator = Accounts.get_user!(access.user.id)
      chat_message = Chat.get_chat_message!(message_id)
      user = Accounts.get_user!(chat_message.user_id)

      Chat.delete_message(moderator, channel, user, chat_message)
    end
  end

  def autocomplete_recent_chat_users(
        _parent,
        %{channel_id: channel_id, partial_usernames: partial_usernames},
        %{context: %{access: access}}
      ) do
    with :ok <- Bodyguard.permit(Glimesh.Api.Scopes, :chat, access) do
      channel = ChannelLookups.get_channel!(channel_id)
      suggestions = Chat.get_recent_chatters_username_autocomplete(channel, partial_usernames)

      suggested_usernames =
        Enum.into(suggestions, [], fn item ->
          item[:suggestion]
        end)

      {:ok, suggested_usernames}
    end
  end

  defp perform_channel_action(
         _parent,
         %{channel_id: channel_id, user_id: user_id},
         %{context: %{access: access}},
         action
       ) do
    with :ok <- Bodyguard.permit(Glimesh.Api.Scopes, :chat, access) do
      channel = ChannelLookups.get_channel!(channel_id)
      moderator = Accounts.get_user!(access.user.id)
      user = Accounts.get_user!(user_id)

      case action do
        :short_timeout -> Chat.short_timeout_user(moderator, channel, user)
        :long_timeout -> Chat.long_timeout_user(moderator, channel, user)
        :ban -> Chat.ban_user(moderator, channel, user)
        :unban -> Chat.unban_user(moderator, channel, user)
      end
    end
  end
end
