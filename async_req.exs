Mix.install([
  {:finch, path: "./", override: true},
  :req
])

Supervisor.start_link([{Finch, name: Finch}], strategy: :one_for_one)

defmodule Example do
  def stream do
    Finch.build(:get, "https://httpbin.org/stream/10")
    |> Finch.async_request(Finch)
    |> Stream.unfold(fn request_ref ->
      receive do
        {^request_ref, :done} -> nil
        {^request_ref, message} -> {message, request_ref}
      end
    end)
  end
end

for message <- Example.stream() do
  IO.inspect(message)
end
