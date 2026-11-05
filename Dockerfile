FROM elixir:1.16.3-slim

ENV MIX_BUILD_PATH=/opt/searchie/_build \
    MIX_DEPS_PATH=/opt/searchie/deps

WORKDIR /app

# There are currently no external dependencies or required system packages.
COPY mix.exs ./
RUN mix deps.get

COPY . .
RUN mix compile

# Keep a development container available for compose exec shell/console commands.
CMD ["elixir", "--no-halt"]
