local TaskQueue = {}

function TaskQueue.create(onAllTasksComplete)
	local self = {
		tasks = {},
		onAllTasksComplete = onAllTasksComplete,
		canceled = false,
	}

	---@param taskFunction function
	function self.addTask(taskFunction)
		if not self.canceled then
			table.insert(self.tasks, taskFunction)
		end
	end

	---@return function | nil
	function self.getNextTask()
		if self.canceled then
			self.tasks = {}
		end
		return table.remove(self.tasks, 1)
	end

	function self.runNextTask()
		if self.canceled then
			return
		end

		local taskFunction = self.getNextTask()
		if taskFunction then
			taskFunction(self.runNextTask)
		elseif self.onAllTasksComplete then
			self.onAllTasksComplete()
		end
	end

	function self.cancel()
		self.tasks = {}
		self.canceled = true
	end

	return self
end

return TaskQueue
