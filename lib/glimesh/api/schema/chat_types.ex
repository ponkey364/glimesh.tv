defmodule Glimesh.Api.ChatTypes do
  @moduledoc false
  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  import Absinthe.Resolution.Helpers

  alias Glimesh.Api.ChatResolver
  alias Glimesh.Repo
  alias Glimesh.Streams

  input_object :chat_message_input do
    field :message, :string
  end

  object :chat_mutations do
    @desc "Create a chat message"
    field :create_chat_message, type: :chat_message do
      arg(:channel_id, non_null(:id))
      arg(:message, non_null(:chat_message_input))

      resolve(&ChatResolver.create_chat_message/3)
    end

    @desc "Create a tenor reaction gif chat message"
    field :create_tenor_message, type: :chat_message do
      arg(:channel_id, non_null(:id))
      arg(:message, non_null(:chat_message_input))

      resolve(&ChatResolver.create_tenor_message/3)
    end

    @desc "Short timeout (5 minutes) a user from a chat channel."
    field :short_timeout_user, type: :channel_moderation_log do
      arg(:channel_id, non_null(:id))
      arg(:user_id, non_null(:id))

      resolve(&ChatResolver.short_timeout_user/3)
    end

    @desc "Long timeout (15 minutes) a user from a chat channel."
    field :long_timeout_user, type: :channel_moderation_log do
      arg(:channel_id, non_null(:id))
      arg(:user_id, non_null(:id))

      resolve(&ChatResolver.long_timeout_user/3)
    end

    @desc "Ban a user from a chat channel."
    field :ban_user, type: :channel_moderation_log do
      arg(:channel_id, non_null(:id))
      arg(:user_id, non_null(:id))

      resolve(&ChatResolver.ban_user/3)
    end

    @desc "Deletes a specific chat message from channel."
    field :delete_chat_message, type: :channel_moderation_log do
      arg(:channel_id, non_null(:id))
      arg(:message_id, non_null(:id))

      resolve(&ChatResolver.delete_chat_message/3)
    end

    @desc "Unban a user from a chat channel."
    field :unban_user, type: :channel_moderation_log do
      arg(:channel_id, non_null(:id))
      arg(:user_id, non_null(:id))

      resolve(&ChatResolver.unban_user/3)
    end
  end

  object :chat_subscriptions do
    field :chat_message, :chat_message do
      arg(:channel_id, :id)

      config(fn args, _ ->
        case Map.get(args, :channel_id) do
          nil -> {:ok, topic: [Streams.get_subscribe_topic(:chat)]}
          channel_id -> {:ok, topic: [Streams.get_subscribe_topic(:chat, channel_id)]}
        end
      end)
    end
  end

  @desc "Chat Message Token Interface"
  interface :chat_message_token do
    field :type, :string, description: "Token type"
    field :text, :string, description: "Token text"

    resolve_type(fn
      %{type: "text"}, _ -> :text_token
      %{type: "url"}, _ -> :url_token
      %{type: "emote"}, _ -> :emote_token
      %{type: "tenor"}, _ -> :tenor_token
      _, _ -> nil
    end)
  end

  @desc "Chat Message Text Token"
  object :text_token do
    field :type, :string, description: "Token type"
    field :text, :string, description: "Token text"

    interface(:chat_message_token)
  end

  @desc "Chat Message URL Token"
  object :url_token do
    field :type, :string, description: "Token type"
    field :text, :string, description: "Token text"
    field :url, :string, description: "Token URL"

    interface(:chat_message_token)
  end

  @desc "Chat Message Emote Token"
  object :emote_token do
    field :type, :string, description: "Token type"
    field :text, :string, description: "Token text"

    # URL is no longer necessary, src will return the full URL.
    # field :url, :string
    field :src, :string, description: "Token src URL"

    interface(:chat_message_token)
  end

  @desc "Tenor Reaction Gif Chat Message Token"
  object :tenor_token do
    field :type, :string, description: "Token type"
    field :text, :string, description: "Token text"
    field :src, :string, description: "Gif src URL"
    field :tenor_id, :string, description: "Tenor Gif ID"
    field :small_src, :string, description: "Tenor small Gif URL"

    interface(:chat_message_token)
  end

  @desc "A chat message sent to a channel by a user."
  object :chat_message do
    field :id, non_null(:id), description: "Unique chat message identifier"

    field :message, :string,
      description:
        "The chat message contents, be careful to sanitize because any user input is allowed"

    field :tokens, list_of(:chat_message_token), description: "List of chat message tokens used"

    field :metadata, :chat_message_metadata,
      description: "A collection of metadata attributed to the chat message"

    field :is_followed_message, :boolean,
      description: "Was this message generated by our system for a follow",
      deprecate: "We're going to replace this shortly after launch"

    field :is_subscription_message, :boolean,
      description: "Was this message generated by our system for a subscription",
      deprecate: "We're going to replace this shortly after launch"

    field :is_raid_message, :boolean,
      description: "Was this message generated by our system for an incoming raid"

    # Disabling isMod until we can figure out a performant way of storing the data
    # Re: https://github.com/Glimesh/glimesh.tv/issues/640
    # field :is_mod, :boolean, description: "Is this user that posted this message a moderator" do
    #   resolve(fn message, _, _ ->
    #     message =
    #       message
    #       |> Repo.preload([:channel, :user])

    #     if message.user_id == message.channel.user_id do
    #       {:ok, true}
    #     else
    #       {:ok, Glimesh.Chat.is_moderator?(message.channel, message.user)}
    #     end
    #   end)
    # end

    field :channel, non_null(:channel),
      resolve: dataloader(Repo),
      description: "Channel where the chat message occurs"

    field :user, non_null(:user),
      resolve: dataloader(Repo),
      description: "User who sent the chat message"

    field :inserted_at, non_null(:naive_datetime), description: "Chat message creation date"
    field :updated_at, non_null(:naive_datetime), description: "Chat message updated date"
  end

  @desc "Metadata attributed to the chat message"
  object :chat_message_metadata do
    field :admin, :boolean, description: "Was the user a admin at the time of this message"
    field :streamer, :boolean, description: "Was the user a streamer at the time of this message"

    field :moderator, :boolean,
      description: "Was the user a moderator at the time of this message"

    field :subscriber, :boolean,
      description: "Was the user a subscriber at the time of this message"

    field :platform_founder_subscriber, :boolean,
      description: "Was the user a platform_founder_subscriber at the time of this message"

    field :platform_supporter_subscriber, :boolean,
      description: "Was the user a platform_supporter_subscriber at the time of this message"
  end

  connection node_type: :chat_message do
    field :count, :integer do
      resolve(fn
        _, %{source: conn} ->
          {:ok, length(conn.edges)}
      end)
    end

    edge do
      field :node, :chat_message do
        resolve(fn %{node: message}, _args, _info ->
          {:ok, message}
        end)
      end
    end
  end

  @desc "A channel timeout or ban"
  object :channel_ban do
    field :id, non_null(:id), description: "Unique channel ban identifier"

    field :channel, non_null(:channel),
      resolve: dataloader(Repo),
      description: "Channel the ban affects"

    field :user, non_null(:user), resolve: dataloader(Repo), description: "User the ban affects"

    field :expires_at, :naive_datetime, description: "When the ban expires"
    field :reason, :string, description: "Reason for channel ban"

    field :inserted_at, non_null(:naive_datetime), description: "Channel ban creation date"
    field :updated_at, non_null(:naive_datetime), description: "Channel ban updated date"
  end

  connection node_type: :channel_ban do
    field :count, :integer do
      resolve(fn
        _, %{source: conn} ->
          {:ok, length(conn.edges)}
      end)
    end

    edge do
      field :node, :channel_ban do
        resolve(fn %{node: message}, _args, _info ->
          {:ok, message}
        end)
      end
    end
  end

  @desc "A channel moderator"
  object :channel_moderator do
    field :id, non_null(:id), description: "Unique channel moderator identifier"

    field :channel, non_null(:channel),
      resolve: dataloader(Repo),
      description: "Channel the moderator can moderate in"

    field :user, non_null(:user), resolve: dataloader(Repo), description: "Moderating User"

    field :can_short_timeout, :boolean, description: "Can perform a short timeout action"
    field :can_long_timeout, :boolean, description: "Can perform a long timeout action"
    field :can_un_timeout, :boolean, description: "Can untimeout a user"
    field :can_ban, :boolean, description: "Can ban a user"
    field :can_unban, :boolean, description: "Can unban a user"
    field :can_delete, :boolean, description: "Can delete a message"

    field :inserted_at, non_null(:naive_datetime), description: "Moderator creation date"
    field :updated_at, non_null(:naive_datetime), description: "Moderator updated date"
  end

  connection node_type: :channel_moderator do
    field :count, :integer do
      resolve(fn
        _, %{source: conn} ->
          {:ok, length(conn.edges)}
      end)
    end

    edge do
      field :node, :channel_moderator do
        resolve(fn %{node: message}, _args, _info ->
          {:ok, message}
        end)
      end
    end
  end

  @desc "A moderation event that happened"
  object :channel_moderation_log do
    field :id, non_null(:id), description: "Unique moderation event identifier"

    field :channel, non_null(:channel),
      resolve: dataloader(Repo),
      description: "Channel the event occurred in"

    field :moderator, non_null(:user),
      resolve: dataloader(Repo),
      description: "Moderator that performed the event"

    field :user, non_null(:user),
      resolve: dataloader(Repo),
      description: "Receiving user of the event"

    field :action, :string, description: "Action performed"

    field :inserted_at, non_null(:naive_datetime), description: "Event creation date"
    field :updated_at, non_null(:naive_datetime), description: "Event updated date"
  end

  connection node_type: :channel_moderation_log do
    field :count, :integer do
      resolve(fn
        _, %{source: conn} ->
          {:ok, length(conn.edges)}
      end)
    end

    edge do
      field :node, :channel_moderation_log do
        resolve(fn %{node: message}, _args, _info ->
          {:ok, message}
        end)
      end
    end
  end

  object :chat_autocomplete do
    @desc "Autocomplete a partial user name"
    field :autocomplete_recent_chat_users, list_of(:string) do
      arg(:channel_id, non_null(:id))
      arg(:partial_usernames, non_null(list_of(:string)))

      resolve(&ChatResolver.autocomplete_recent_chat_users/3)
    end
  end
end
