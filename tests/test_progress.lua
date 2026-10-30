local Test = require("tests.testlib")
local Progress = require("hypermax.progress")

Test.Run("Progress module exposes all public functions", function()
    for _, name in ipairs({ "Start", "Update", "Log", "Increment", "Finish", "Close" }) do
        Test.Type("function", Progress[name], "Missing Progress." .. name)
    end
end)

Test.Run("Progress updates and logging are safe before a window is started", function()
    -- Render intentionally does nothing when there is no progress buffer.
    Test.True(pcall(Progress.Update, "Testing", 1, 2))
    Test.True(pcall(Progress.Log, "test log entry"))
    Test.True(pcall(Progress.Increment, "increment test"))
    Test.True(pcall(Progress.Finish, true, "finished test"))
    Test.True(pcall(Progress.Close))
end)

Test.Run("Progress operations can be called repeatedly", function()
    Test.True(pcall(Progress.Close))
    Test.True(pcall(Progress.Close))
    Test.True(pcall(Progress.Update, "zero total", 0, 0))
    Test.True(pcall(Progress.Finish, false, "intentional test failure status"))
    Test.True(pcall(Progress.Close))
end)

Test.Run("Progress window can be closed with q and Escape", function()
    local Progress = require("hypermax.progress")
    local ok, err = pcall(Progress.Start, "Test progress", 1)
    Test.True(ok, tostring(err))
    local state = Progress.Get_State()
    Test.Not_Nil(state.buffer)
    local mappings = {}
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(state.buffer, "n")) do
        mappings[mapping.lhs] = mapping
    end
    Test.Not_Nil(mappings.q)
    Test.Not_Nil(mappings["<Esc>"])
    Test.Type("function", mappings.q.callback)
    Test.Type("function", mappings["<Esc>"].callback)
    Progress.Close()
    Test.Nil(Progress.Get_State().buffer)
    Test.Nil(Progress.Get_State().window)
end)
