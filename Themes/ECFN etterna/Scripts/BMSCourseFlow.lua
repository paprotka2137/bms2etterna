-- 7k dan courses: after each song's result screen START goes to the next song
-- of the course, after the last one (or a failed one) to the COURSE RESULT
-- screen (ScreenBMSCourseResult), and from there on as usual.
do
	local afterEvaluation = Branch.AfterEvaluation
	Branch.AfterEvaluation = function()
		local next = BMSDan and BMSDan.afterEvaluation and BMSDan.afterEvaluation()
		if next == "next" then
			return ToGameplay()
		elseif next == "result" then
			return "ScreenBMSCourseResult"
		end
		return afterEvaluation()
	end
end
