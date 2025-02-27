defmodule Glimesh.StreamsTest do
  use Glimesh.DataCase
  use Bamboo.Test

  import Glimesh.AccountsFixtures
  import Glimesh.RaidingFixtures
  alias Glimesh.Raids
  alias Glimesh.AccountFollows
  alias Glimesh.AccountFollows.Follower
  alias Glimesh.ChannelLookups
  alias Glimesh.Streams
  alias Glimesh.Repo

  describe "followers" do
    def followers_fixture do
      streamer = streamer_fixture()
      user = user_fixture()

      {:ok, followers} = AccountFollows.follow(streamer, user)

      followers
    end

    test "follow/2 successfully follows streamer" do
      streamer = streamer_fixture()
      user = user_fixture()
      AccountFollows.follow(streamer, user)

      followed = ChannelLookups.list_all_followed_channels(user)

      assert Enum.map(followed, fn x -> x.user.username end) == [streamer.username]
    end

    test "unfollow/2 successfully unfollows streamer" do
      streamer = streamer_fixture()
      user = user_fixture()
      AccountFollows.follow(streamer, user)
      followed = ChannelLookups.list_all_followed_channels(user)

      assert Enum.map(followed, fn x -> x.user.username end) == [streamer.username]

      AccountFollows.unfollow(streamer, user)
      assert ChannelLookups.list_all_followed_channels(user) == []
    end

    test "is_following?/1 detects active follow" do
      streamer = streamer_fixture()
      user = user_fixture()
      AccountFollows.follow(streamer, user)
      assert AccountFollows.is_following?(streamer, user) == true
    end

    test "follow/2 twice successfully updates follow" do
      streamer = streamer_fixture()
      user = user_fixture()
      AccountFollows.follow(streamer, user)

      assert {:ok, %Follower{}} = AccountFollows.follow(streamer, user)

      followed = ChannelLookups.list_all_followed_channels(user)
      assert Enum.map(followed, fn x -> x.user.username end) == [streamer.username]
    end

    test "list_all_follows/0 successfully returns data" do
      streamer = streamer_fixture()
      user = user_fixture()
      AccountFollows.follow(streamer, user)

      follows = AccountFollows.list_all_follows()

      assert Enum.map(follows, fn x -> x.user_id end) == [user.id]
      assert Enum.map(follows, fn x -> x.streamer_id end) == [streamer.id]
    end

    test "list_followers/1 successfully returns data" do
      streamer = streamer_fixture()
      user = user_fixture()
      AccountFollows.follow(streamer, user)

      follows = AccountFollows.list_followers(streamer)

      assert Enum.map(follows, fn x -> x.user.username end) == [user.username]
    end

    test "list_following/1 successfully returns data" do
      streamer = streamer_fixture()
      user = user_fixture()
      AccountFollows.follow(streamer, user)

      follows = AccountFollows.list_following(user)

      assert Enum.map(follows, fn x -> x.streamer.username end) == [streamer.username]
    end
  end

  describe "channels" do
    setup do
      streamer = streamer_fixture()
      {:ok, channel: streamer.channel, streamer: streamer}
    end

    test "create_channel/1 creates a channel" do
      {:ok, channel} = Streams.create_channel(user_fixture())

      assert channel.title == "Live Stream!"
    end

    test "delete_channel/1 inactivates a channel", %{channel: channel, streamer: streamer} do
      {:ok, channel} = Streams.delete_channel(streamer, channel)
      assert channel.inaccessible
      assert is_nil(Glimesh.ChannelLookups.get_channel_for_user(streamer))

      assert Glimesh.ChannelLookups.get_any_channel_for_user(streamer).inaccessible
    end

    test "create_channel/1 will recreate a channel", %{channel: channel, streamer: streamer} do
      {:ok, channel} = Streams.delete_channel(streamer, channel)

      {:ok, new_channel} = Streams.create_channel(streamer)

      assert channel.id == new_channel.id
    end

    test "rotate_stream_key/1 changes a hmac key", %{channel: channel, streamer: streamer} do
      {:ok, new_channel} = Streams.rotate_stream_key(streamer, channel)
      assert new_channel.hmac_key != channel.hmac_key
    end

    test "prompt_mature_content/2 flags content correctly", %{
      streamer: streamer,
      channel: channel
    } do
      user = user_fixture()
      assert Streams.prompt_mature_content(channel, user) == false

      {:ok, channel} =
        Streams.update_channel(streamer, channel, %{
          mature_content: true
        })

      assert Streams.prompt_mature_content(channel, user) == true
      assert Streams.prompt_mature_content(channel, nil) == true

      user_pref = Glimesh.Accounts.get_user_preference!(user)

      {:ok, _} =
        Glimesh.Accounts.update_user_preference(user_pref, %{
          show_mature_content: true
        })

      user = Glimesh.Accounts.get_user!(user.id)

      assert Streams.prompt_mature_content(channel, user) == false
    end
  end

  describe "ingest stream api" do
    setup do
      %{channel: channel} = streamer_fixture()

      {:ok, channel: channel}
    end

    test "start_stream/1 successfully starts a stream", %{channel: channel} do
      {:ok, stream} = Streams.start_stream(channel)
      new_channel = ChannelLookups.get_channel!(channel.id)

      assert stream.started_at != nil
      assert stream.ended_at == nil
      assert stream.id == new_channel.stream_id
      assert stream.category_id == new_channel.category_id
      assert new_channel.status == "live"
    end

    test "start_stream/1 stores subcategory", %{channel: channel} do
      subcategory = subcategory_fixture()

      {:ok, channel} =
        channel
        |> Glimesh.Repo.preload(:subcategory)
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:subcategory, subcategory)
        |> Glimesh.Repo.update()

      {:ok, stream} = Streams.start_stream(channel)

      assert stream.subcategory_id == subcategory.id
    end

    test "start_stream/1 stores historical tags", %{channel: channel} do
      tag = tag_fixture()

      {:ok, channel} =
        channel
        |> Glimesh.Repo.preload(:tags)
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:tags, [tag])
        |> Glimesh.Repo.update()

      {:ok, stream} = Streams.start_stream(channel)

      assert stream.category_tags == [tag.id]
    end

    test "start_stream/1 stops any other streams that still are lingering", %{channel: channel} do
      %Glimesh.Streams.Stream{channel: channel}
      |> Glimesh.Streams.Stream.changeset(%{})
      |> Glimesh.Repo.insert()

      %Glimesh.Streams.Stream{channel: channel}
      |> Glimesh.Streams.Stream.changeset(%{})
      |> Glimesh.Repo.insert()

      {:ok, _} = Streams.start_stream(channel)

      assert Repo.one(
               from(s in Glimesh.Streams.Stream,
                 where: s.channel_id == ^channel.id and is_nil(s.ended_at),
                 select: count(s.id)
               )
             ) == 1
    end

    test "end_stream/1 successfully stops a stream", %{channel: channel} do
      {:ok, _} = Streams.start_stream(channel)
      fresh_channel = ChannelLookups.get_channel!(channel.id)
      {:ok, stream} = Streams.end_stream(fresh_channel)
      new_channel = ChannelLookups.get_channel!(channel.id)

      assert stream.started_at != nil
      assert stream.ended_at != nil
      assert new_channel.status == "offline"
      assert new_channel.stream_id == nil
    end

    test "end_stream/1 successfully stops a stream with stream", %{channel: channel} do
      {:ok, stream} = Streams.start_stream(channel)
      {:ok, stream} = Streams.end_stream(stream)
      new_channel = ChannelLookups.get_channel!(channel.id)

      assert stream.started_at != nil
      assert stream.ended_at != nil
      assert new_channel.status == "offline"
      assert new_channel.stream_id == nil
    end

    test "log_stream_metadata/1 successfully logs some metadata", %{channel: channel} do
      {:ok, stream} = Streams.start_stream(channel)

      incoming_attrs = %{
        audio_codec: "mp3",
        ingest_server: "test",
        ingest_viewers: 32,
        stream_time_seconds: 1024,
        lost_packets: 0,
        nack_packets: 0,
        recv_packets: 100,
        source_bitrate: 5000,
        source_ping: 100,
        vendor_name: "OBS",
        vendor_version: "1.0.0",
        video_codec: "mp4",
        video_height: 1024,
        video_width: 768
      }

      assert {:ok, %{}} = Streams.log_stream_metadata(stream, incoming_attrs)
    end
  end

  describe "Raiding" do
    setup do
      target_channel = streamer_fixture(%{}, %{allow_raiding: true})
      Glimesh.Streams.update_channel(target_channel, target_channel.channel, %{status: "live"})
      viewer_one = user_fixture()
      viewer_two = user_fixture()
      raiding_channel = streamer_fixture()
      Glimesh.Streams.update_channel(raiding_channel, raiding_channel.channel, %{status: "live"})

      Glimesh.Presence.track_presence(
        self(),
        Streams.get_subscribe_topic(:raid, raiding_channel.channel.id),
        viewer_one.id,
        %{
          logged_in_user_id: viewer_one.id
        }
      )

      Glimesh.Presence.track_presence(
        self(),
        Streams.get_subscribe_topic(:raid, raiding_channel.channel.id),
        viewer_two.id,
        %{
          logged_in_user_id: viewer_two.id
        }
      )

      {:ok, topic} = Streams.subscribe_to(:raid, raiding_channel.channel.id)
      present_users = Glimesh.Presence.list_presences(topic)

      %{
        target: target_channel,
        viewer_one: viewer_one,
        viewer_two: viewer_two,
        raider: raiding_channel,
        present_users: present_users
      }
    end

    test "streamer can raid another channel", %{
      target: target,
      viewer_one: viewer_one,
      viewer_two: viewer_two,
      raider: raider,
      present_users: present_users
    } do
      payload = Streams.start_raid_channel(raider, raider.channel, target.channel, present_users)
      assert payload[:target] == target.channel
      assert not is_nil(payload[:group_id])
      assert not is_nil(payload[:time])
      assert payload[:action] === "pending"

      raid_definition = Glimesh.Raids.get_raid_definition(payload[:group_id])
      raid_users = Glimesh.Raids.get_raid_users(payload[:group_id])

      assert not is_nil(raid_definition) and raid_definition.status == :pending
      assert Enum.count(raid_users) == 2
      assert Enum.any?(raid_users, fn raider -> viewer_one.id == raider.user.id end)
      assert Enum.any?(raid_users, fn raider -> viewer_two.id == raider.user.id end)
    end

    test "streamer can NOT raid a channel with raiding disabled", %{
      raider: raider,
      present_users: present_users
    } do
      target = streamer_fixture(%{}, %{allow_raiding: false})
      Glimesh.Streams.update_channel(target, target.channel, %{status: "live"})

      assert match?(
               :error,
               Streams.start_raid_channel(raider, raider.channel, target.channel, present_users)
             )
    end

    test "streamer can NOT raid a channel with raiding restricted to followers only if they aren't following",
         %{raider: raider, present_users: present_users} do
      target = streamer_fixture(%{}, %{allow_raiding: true, only_followed_can_raid: true})
      Glimesh.Streams.update_channel(target, target.channel, %{status: "live"})

      assert match?(
               :error,
               Streams.start_raid_channel(raider, raider.channel, target.channel, present_users)
             )
    end

    test "streamer can raid a channel with raiding restricted to followers only if they are following",
         %{
           viewer_one: viewer_one,
           viewer_two: viewer_two,
           raider: raider,
           present_users: present_users
         } do
      target = streamer_fixture(%{}, %{allow_raiding: true, only_followed_can_raid: true})
      Glimesh.Streams.update_channel(target, target.channel, %{status: "live"})
      AccountFollows.follow(raider, target)

      payload = Streams.start_raid_channel(raider, raider.channel, target.channel, present_users)
      assert payload[:target] == target.channel
      assert not is_nil(payload[:group_id])
      assert not is_nil(payload[:time])
      assert payload[:action] === "pending"

      raid_definition = Glimesh.Raids.get_raid_definition(payload[:group_id])
      raid_users = Glimesh.Raids.get_raid_users(payload[:group_id])

      assert not is_nil(raid_definition) and raid_definition.status == :pending
      assert Enum.count(raid_users) == 2
      assert Enum.any?(raid_users, fn raider -> viewer_one.id == raider.user.id end)
      assert Enum.any?(raid_users, fn raider -> viewer_two.id == raider.user.id end)
    end

    test "user can NOT raid a channel if they do not own the raiding channel", %{
      raider: raider,
      present_users: present_users
    } do
      target = streamer_fixture(%{}, %{allow_raiding: true})
      Glimesh.Streams.update_channel(target, target.channel, %{status: "live"})
      some_user = streamer_fixture()
      Glimesh.Streams.update_channel(some_user, some_user.channel, %{status: "live"})

      assert match?(
               :error,
               Streams.start_raid_channel(
                 some_user,
                 raider.channel,
                 target.channel,
                 present_users
               )
             )
    end

    test "streamer can cancel a raid they started", %{
      target: target,
      viewer_one: viewer_one,
      viewer_two: viewer_two,
      raider: raider
    } do
      {:ok, raid_definition} = create_raid_definition(raider, target.channel)
      {:ok, raid_user_one} = create_raid_user(viewer_one, raid_definition)
      {:ok, raid_user_two} = create_raid_user(viewer_two, raid_definition)

      assert match?(
               {:ok, _},
               Streams.cancel_raid_channel(raider, raider.channel, raid_definition.group_id)
             )

      updated_raid_definition = Glimesh.Repo.get(Glimesh.Streams.ChannelRaids, raid_definition.id)
      updated_raid_user_one = Glimesh.Repo.get(Glimesh.Streams.RaidUser, raid_user_one.id)
      updated_raid_user_two = Glimesh.Repo.get(Glimesh.Streams.RaidUser, raid_user_two.id)
      assert updated_raid_definition.status == :cancelled
      assert updated_raid_user_one.status == :cancelled
      assert updated_raid_user_two.status == :cancelled
    end

    test "streamer can't cancel a raid that completed", %{
      target: target,
      viewer_one: viewer_one,
      viewer_two: viewer_two,
      raider: raider
    } do
      {:ok, raid_definition} = create_raid_definition(raider, target.channel)
      {:ok, raid_user_one} = create_raid_user(viewer_one, raid_definition)
      {:ok, raid_user_two} = create_raid_user(viewer_two, raid_definition)
      Raids.update_raid_status(raid_definition.group_id, :complete)

      assert match?(
               :error,
               Streams.cancel_raid_channel(raider, raider.channel, raid_definition.group_id)
             )

      updated_raid_definition = Glimesh.Repo.get(Glimesh.Streams.ChannelRaids, raid_definition.id)
      updated_raid_user_one = Glimesh.Repo.get(Glimesh.Streams.RaidUser, raid_user_one.id)
      updated_raid_user_two = Glimesh.Repo.get(Glimesh.Streams.RaidUser, raid_user_two.id)
      assert updated_raid_definition.status == :complete
      assert updated_raid_user_one.status == :complete
      assert updated_raid_user_two.status == :complete
    end

    test "user can't cancel a raid started by another channel", %{
      target: target,
      viewer_one: viewer_one,
      viewer_two: viewer_two,
      raider: raider
    } do
      {:ok, raid_definition} = create_raid_definition(raider, target.channel)
      {:ok, raid_user_one} = create_raid_user(viewer_one, raid_definition)
      {:ok, raid_user_two} = create_raid_user(viewer_two, raid_definition)
      some_user = streamer_fixture()

      assert match?(
               :error,
               Streams.cancel_raid_channel(some_user, raider.channel, raid_definition.group_id)
             )

      updated_raid_definition = Glimesh.Repo.get(Glimesh.Streams.ChannelRaids, raid_definition.id)
      updated_raid_user_one = Glimesh.Repo.get(Glimesh.Streams.RaidUser, raid_user_one.id)
      updated_raid_user_two = Glimesh.Repo.get(Glimesh.Streams.RaidUser, raid_user_two.id)
      assert updated_raid_definition.status == :pending
      assert updated_raid_user_one.status == :pending
      assert updated_raid_user_two.status == :pending
    end

    test "can't cancel a raid that doesn't exist", %{raider: raider} do
      random_uuid = Ecto.UUID.generate()
      assert match?(:error, Streams.cancel_raid_channel(raider, raider.channel, random_uuid))
    end
  end
end
