--!strict
-- Minimal synchronous signal.

export type Connection = { Disconnect: (self: Connection) -> () }

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local handlers: { (T...) -> () } = {}
	local self = {}

	function self.Connect(_: any, fn: (T...) -> ()): Connection
		table.insert(handlers, fn)
		local conn = {}
		function conn.Disconnect(_: any)
			local i = table.find(handlers, fn)
			if i then
				table.remove(handlers, i)
			end
		end
		return conn :: any
	end

	function self.Fire(_: any, ...: T...)
		for _, fn in table.clone(handlers) do
			task.spawn(fn, ...)
		end
	end

	return self :: any
end

return Signal
