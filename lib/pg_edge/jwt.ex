defmodule PgEdge.Jwt do
  @moduledoc """
  Parse JWT and verify claims
  """
  require Logger

  defmodule JwtAuthToken do
    @moduledoc false
    use Joken.Config

    @impl true
    def token_config do
      Application.fetch_env!(:pg_edge, :jwt_claim_validators)
      |> Enum.reduce(%{}, fn {claim_key, expected_val}, claims ->
        add_claim_validator(claims, claim_key, expected_val)
      end)
      |> add_claim_validator("exp")
    end

    defp add_claim_validator(claims, "exp") do
      add_claim(claims, "exp", nil, &(&1 > current_time()))
    end

    defp add_claim_validator(claims, claim_key, expected_val) do
      add_claim(claims, claim_key, nil, &(&1 == expected_val))
    end
  end

  @hs_algorithms ["HS256", "HS384", "HS512"]

  @spec authorize(String.t(), String.t()) :: {:ok, map()} | {:error, any()}
  def authorize(token, secret) when is_binary(token) do
    token
    |> clean_token()
    |> verify(secret)
  end

  def authorize(_token, _secret), do: {:error, :token_not_a_string}

  defp clean_token(token) do
    Regex.replace(~r/\s|\n/, URI.decode(token), "")
  end

  def authorize_conn(token, secret) do
    case authorize(token, secret) do
      {:ok, claims} ->
        required = MapSet.new(["role", "exp"])
        claims_keys = Map.keys(claims) |> MapSet.new()

        if MapSet.subset?(required, claims_keys) do
          {:ok, claims}
        else
          {:error, "Fields `role` and `exp` are required in JWT"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec verify(String.t(), String.t()) :: {:ok, map()} | {:error, any()}
  def verify(token, secret) when is_binary(token) do
    with {:ok, _claims} <- check_claims_format(token),
         {:ok, header} <- check_header_format(token),
         {:ok, signer} <- generate_signer(header, secret) do
      JwtAuthToken.verify_and_validate(token, signer)
    end
  end

  def verify(_token, _secret), do: {:error, :token_not_a_string}

  defp check_header_format(token) do
    case Joken.peek_header(token) do
      {:ok, header} when is_map(header) -> {:ok, header}
      _error -> {:error, :expected_header_map}
    end
  end

  defp check_claims_format(token) do
    case Joken.peek_claims(token) do
      {:ok, claims} when is_map(claims) -> {:ok, claims}
      _error -> {:error, :expected_claims_map}
    end
  end

  defp generate_signer(%{"typ" => "JWT", "alg" => alg}, jwt_secret) when alg in @hs_algorithms do
    {:ok, Joken.Signer.create(alg, jwt_secret)}
  end

  defp generate_signer(_header, _secret), do: {:error, :error_generating_signer}
end
