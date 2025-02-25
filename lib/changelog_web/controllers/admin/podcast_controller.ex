defmodule ChangelogWeb.Admin.PodcastController do
  use ChangelogWeb, :controller

  alias Changelog.{Cache, Fastly, Podcast}

  plug :assign_podcast when action in [:show, :edit, :update]
  plug Authorize, [Policies.Admin.Podcast, :podcast]
  plug :scrub_params, "podcast" when action in [:create, :update]

  def index(conn = %{assigns: %{current_user: user}}, _params) do
    draft =
      Podcast.draft()
      |> Podcast.preload_active_hosts()
      |> Repo.all()
      |> Enum.filter(fn p -> Policies.Admin.Podcast.show(user, p) end)

    active =
      Podcast.active()
      |> Podcast.not_retired()
      |> Podcast.by_position()
      |> Podcast.preload_active_hosts()
      |> Repo.all()
      |> Enum.filter(fn p -> Policies.Admin.Podcast.show(user, p) end)

    retired =
      Podcast.retired()
      |> Podcast.oldest_first()
      |> Podcast.preload_active_hosts()
      |> Repo.all()
      |> Enum.filter(fn p -> Policies.Admin.Podcast.show(user, p) end)

    conn
    |> assign(:active, active)
    |> assign(:draft, draft)
    |> assign(:retired, retired)
    |> assign(:downloads, ChangelogWeb.Admin.PageController.downloads())
    |> render(:index)
  end

  def new(conn, _params) do
    changeset = Podcast.insert_changeset(%Podcast{podcast_hosts: []})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, params = %{"podcast" => podcast_params}) do
    changeset = Podcast.insert_changeset(%Podcast{}, podcast_params)

    case Repo.insert(changeset) do
      {:ok, podcast} ->
        Repo.update(Podcast.file_changeset(podcast, podcast_params))
        Cache.delete(podcast)

        conn
        |> put_flash(:result, "success")
        |> redirect_next(params, Routes.admin_podcast_path(conn, :edit, podcast.slug))

      {:error, changeset} ->
        conn
        |> put_flash(:result, "failure")
        |> render(:new, changeset: changeset)
    end
  end

  def show(conn = %{assigns: %{podcast: podcast}}, _params) do
    redirect(conn, to: Routes.admin_podcast_episode_path(conn, :index, podcast.slug))
  end

  def edit(conn = %{assigns: %{podcast: podcast}}, _params) do
    podcast =
      podcast
      |> Podcast.preload_hosts()
      |> Podcast.preload_topics()

    changeset = Podcast.update_changeset(podcast)

    render(conn, :edit, podcast: podcast, changeset: changeset)
  end

  def update(conn = %{assigns: %{podcast: podcast}}, params = %{"podcast" => podcast_params}) do
    podcast =
      podcast
      |> Repo.preload(:podcast_topics)
      |> Repo.preload(:podcast_hosts)

    changeset = Podcast.update_changeset(podcast, podcast_params)

    case Repo.update(changeset) do
      {:ok, podcast} ->
        Fastly.purge(podcast)
        Cache.delete(podcast)

        params =
          replace_next_edit_path(params, Routes.admin_podcast_path(conn, :edit, podcast.slug))

        conn
        |> put_flash(:result, "success")
        |> redirect_next(params, Routes.admin_podcast_path(conn, :index))

      {:error, changeset} ->
        render(conn, :edit, podcast: podcast, changeset: changeset)
    end
  end

  defp assign_podcast(conn = %{params: %{"id" => id}}, _) do
    podcast = Repo.get_by!(Podcast, slug: id) |> Podcast.preload_hosts()
    assign(conn, :podcast, podcast)
  end
end
