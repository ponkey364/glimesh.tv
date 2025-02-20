defmodule GlimeshWeb.UserRegistrationController do
  use GlimeshWeb, :controller

  alias Glimesh.Accounts
  alias Glimesh.Accounts.User
  alias GlimeshWeb.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%User{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"user" => user_params, "h-captcha-response" => captcha_response}) do
    safe_params =
      Map.take(user_params, [
        "username",
        "password",
        "email",
        "allow_glimesh_newsletter_emails"
      ])

    existing_preferences = %Glimesh.Accounts.UserPreference{
      locale: GlimeshWeb.LayoutView.site_locale(conn),
      site_theme: GlimeshWeb.LayoutView.site_theme(conn)
    }

    user_ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    user_params = Map.put(safe_params, "raw_user_ip", user_ip)

    case Hcaptcha.verify(captcha_response) do
      {:ok, _} ->
        case Accounts.register_user(user_params, existing_preferences) do
          {:ok, user} ->
            # credo:disable-for-lines:4
            {:ok, _} =
              Accounts.deliver_user_confirmation_instructions(
                user,
                fn confirmation -> ~p"/users/confirm/#{confirmation}" end
              )

            conn
            |> put_flash(:info, gettext("User created successfully."))
            |> UserAuth.log_in_user(user)

          {:error, %Ecto.Changeset{} = changeset} ->
            render(conn, "new.html", changeset: changeset)
        end

      {:error, _} ->
        conn
        |> put_flash(
          :error,
          gettext("Captcha validation failed, please try again.")
        )
        |> redirect(to: ~p"/users/register")
    end
  end

  def create(conn, %{"user" => _}) do
    conn
    |> put_flash(
      :error,
      gettext("Captcha validation failed, please make sure you have JavaScript enabled.")
    )
    |> redirect(to: ~p"/users/register")
  end
end
