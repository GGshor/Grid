export type BaseHandler = {
	Name: string,
	Folder: Folder,

	Queue: {},
	IncomingQueue: {},
	IncomingQueueErrored: boolean,
}

export type EventHandler = BaseHandler & {
	Remote: RemoteEvent,

	Callbacks: { () -> () },
}

export type FunctionHandler = BaseHandler & {
	Remote: RemoteFunction,

	Callback: (...any) -> (),
}

export type Communications = {
	Functions: Folder,
	Events: Folder,
	Binds: Folder,
}

return {}
