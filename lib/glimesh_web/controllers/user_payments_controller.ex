defmodule GlimeshWeb.UserPaymentsController do
  use GlimeshWeb, :controller

  alias Glimesh.Accounts
  alias Glimesh.PaymentProviders.StripeProvider
  alias Glimesh.Payments

  plug(:put_layout, "user-sidebar.html")

  def index(conn, _params) do
    user = conn.assigns.current_user

    countries =
      ["Select Your Country": ""] ++
        StripeProvider.list_payout_countries()

    stripe_dashboard_url = Payments.get_stripe_dashboard_url(user)

    render(
      conn,
      "index.html",
      page_title: format_page_title(gettext("Your Payment Portal")),
      user: user,
      can_payments: Accounts.can_use_payments?(user),
      can_receive_payments: Accounts.can_receive_payments?(user),
      sum_incoming: Payments.sum_incoming(user),
      sum_outgoing: Payments.sum_outgoing(user),
      count_incoming: Payments.count_incoming(user),
      count_outgoing: Payments.count_outgoing(user),
      payable_history: Payments.list_payables_history(user),
      stripe_countries: countries,
      platform_subscription: Payments.get_platform_subscription(user),
      subscriptions: Payments.get_channel_subscriptions(user),
      default_payment_changeset: Accounts.change_stripe_default_payment(user),
      has_payment_method: !is_nil(user.stripe_payment_method),
      payment_history: Payments.list_payment_history(user),
      stripe_dashboard_url: stripe_dashboard_url
    )
  end

  def setup(conn, %{"country" => country}) do
    user = conn.assigns.current_user

    refresh_url = ~p"/users/payments"
    return_url = ~p"/users/payments/connect"

    stripe_url = StripeProvider.start_connect(user, country, return_url, refresh_url)

    case stripe_url do
      {:ok, stripe_oauth_url} ->
        render(conn, "setup.html",
          page_title: format_page_title(gettext("Setup Glimesh Payouts")),
          can_payments: Accounts.can_use_payments?(user),
          country: country,
          stripe_oauth_url: stripe_oauth_url
        )

      {:error, message} when is_bitstring(message) ->
        conn
        |> put_flash(:error, message)
        |> redirect(to: ~p"/users/payments")

      {:error, %Stripe.Error{}} ->
        conn
        |> put_flash(:error, "There was an error accessing the Stripe API.")
        |> redirect(to: ~p"/users/payments")
    end
  end

  def taxes(conn, _params) do
    user = conn.assigns.current_user

    if user.is_tax_verified do
      conn
      |> put_flash(:info, "Your tax information has already been collected.")
      |> redirect(to: ~p"/users/payments")
    else
      return_url = url(~p"/users/payments/taxes_pending")

      w8ben_url = Glimesh.PaymentProviders.TaxIDPro.request_w8ben(user, return_url)

      case w8ben_url do
        {:ok, url} ->
          render(conn, "taxes.html",
            page_title: format_page_title(gettext("Submit Tax Forms")),
            tax_form_url: url,
            can_payments: Accounts.can_use_payments?(user)
          )

        {:error, _} ->
          conn
          |> put_flash(
            :info,
            "There was a problem accessing our Tax Provider, please try again later."
          )
          |> redirect(to: ~p"/users/payments")
      end
    end
  end

  def taxes_pending(conn, _params) do
    conn
    |> put_flash(
      :info,
      "Your tax information has been collected and is currently being processed. Tax forms can take up to 14 days to process."
    )
    |> redirect(to: ~p"/users/payments")
  end

  def connect(conn, _params) do
    user = conn.assigns.current_user

    if user.stripe_user_id do
      case StripeProvider.check_account_capabilities_and_upgrade(user) do
        {:ok, _} ->
          conn
          |> put_flash(
            :info,
            "Your payments account is successfully linked. Your subscription button is now enabled."
          )
          |> redirect(to: ~p"/users/payments")

        {:pending_taxes, message} ->
          # Should redirect to a taxes page
          conn
          |> put_flash(:info, message)
          |> redirect(to: ~p"/users/payments/taxes")

        {:pending_stripe, message} ->
          conn
          |> put_flash(:info, message)
          |> redirect(to: ~p"/users/payments")
      end

      conn
    else
      conn
      |> put_flash(:error, "There was a problem connecting your payouts account.")
      |> redirect(to: ~p"/users/payments")
    end
  end

  def delete_default_payment(conn, %{}) do
    user = conn.assigns.current_user

    case Accounts.set_stripe_default_payment(user, nil) do
      {:ok, _} ->
        conn
        |> put_flash(:info, gettext("Payment method deleted!"))
        |> redirect(to: ~p"/users/payments")

      {:error, err} ->
        conn
        |> put_flash(:error, err)
        |> redirect(to: ~p"/users/payments")
    end
  end
end
