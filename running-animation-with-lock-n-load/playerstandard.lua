-- New members in PlayerStandard:
-- _stop_running_anim_expire_t: number | nil
-- _block_running_anim: boolean | nil
-- _block_running_anim_expire_t: number | nil
-- _anim_state: userdata (Idstring representing an animation state) | nil
-- _anim_state_callback: function | nil

local start_running_state = Idstring("fps/start_running")
local running_state = Idstring("fps/running")
local stop_running_state = Idstring("fps/stop_running")

local function try_play_start_running(self)
	local is_playing = false

	if self._running
		and not self._end_running_expire_t
		and not self._block_running_anim
	then
		local state = self._ext_camera:anim_state_machine():segment_state(self:get_animation("base"))

		if (state ~= start_running_state) and (state ~= running_state) then
			self._ext_camera:play_redirect(self:get_animation("start_running"))
		end

		is_playing = true
	end

	return is_playing
end

local function try_play_stop_running(self, t)
	local state = self._ext_camera:anim_state_machine():segment_state(self:get_animation("base"))

	if (state == start_running_state) or (state == running_state) then
		local speed_multiplier = self._equipped_unit:base():exit_run_speed_multiplier()
		self._ext_camera:play_redirect(self:get_animation("stop_running"), speed_multiplier)
		self._stop_running_anim_expire_t = t + (0.4 / speed_multiplier)
	end

	local is_playing = self._stop_running_anim_expire_t and true or false
	return is_playing
end

local _check_action_primary_attack = Hooks:GetFunction(PlayerStandard, "_check_action_primary_attack")
Hooks:OverrideFunction(PlayerStandard, "_check_action_primary_attack", function (self, t, input, params)
	if self._equipped_unit:base():run_and_shoot_allowed() then
		if input.btn_primary_attack_press then
			self._block_running_anim = true
			self._block_running_anim_expire_t = nil
			try_play_stop_running(self, t)
		end

		if input.btn_primary_attack_release then
			-- Unblock the running anim after 3 seconds.
			self._block_running_anim_expire_t = t + 3
		end

		if self._stop_running_anim_expire_t and self._stop_running_anim_expire_t > t then
			return false
		end
	end
	
	return _check_action_primary_attack(self, t, input, params)
end)

local _check_action_deploy_underbarrel = Hooks:GetFunction(PlayerStandard, "_check_action_deploy_underbarrel")
Hooks:OverrideFunction(PlayerStandard, "_check_action_deploy_underbarrel", function (self, t, input)
	local run_and_shoot_allowed = self._equipped_unit:base():run_and_shoot_allowed()

	if run_and_shoot_allowed then
		if input.btn_deploy_bipod and self._equipped_unit:base():underbarrel_name_id() then
			self._block_running_anim = true
			self._block_running_anim_expire_t = nil
			local is_playing = try_play_stop_running(self, t)

			if is_playing then
				self._toggle_underbarrel_wanted = true
			end
		end

		if self._stop_running_anim_expire_t and self._stop_running_anim_expire_t > t then
			return false
		end
	end

	local toggle_underbarrel_wanted = self._toggle_underbarrel_wanted
	local new_action = _check_action_deploy_underbarrel(self, t, input)

	if run_and_shoot_allowed then
		if new_action then
			-- Assume that the toggle underbarrel animation is playing,
			self._anim_state = self._ext_camera:anim_state_machine():segment_state(self:get_animation("base"))
			self._anim_state_callback = function (self, t)
				self._block_running_anim_expire_t = t + 3
			end
		elseif input.btn_deploy_bipod or toggle_underbarrel_wanted then
			-- Failed to toggle the underbarrel. Unblock the running animation.
			self._block_running_anim = nil
			try_play_start_running(self)
		end
	end

	return new_action
end)

Hooks:PostHook(PlayerStandard, "_start_action_reload", "RunningAnimationWithLockNLoad", function (self, t)
	if self._equipped_unit:base():run_and_shoot_allowed() and self:_is_reloading() then
		self._block_running_anim = true
		self._block_running_anim_expire_t = nil
		-- Assume that the reload animation is playing.
		self._anim_state = self._ext_camera:anim_state_machine():segment_state(self:get_animation("base"))
		self._anim_state_callback = function (self, t)
			self._block_running_anim_expire_t = t + 3
		end
	end
end)

Hooks:PostHook(PlayerStandard, "_start_action_running", "RunningAnimationWithLockNLoad", function (self, t)
	if self._equipped_unit:base():run_and_shoot_allowed() then
		try_play_start_running(self)
	end
end)

Hooks:PostHook(PlayerStandard, "_end_action_running", "RunningAnimationWithLockNLoad", function (self, t)
	if self._equipped_unit:base():run_and_shoot_allowed() then
		try_play_stop_running(self, t)
	end
end)

Hooks:PreHook(PlayerStandard, "update", "RunningAnimationWithLockNLoad", function (self, t, dt)
	if self._stop_running_anim_expire_t and self._stop_running_anim_expire_t <= t then
		self._stop_running_anim_expire_t = nil
	end

	if self._block_running_anim_expire_t and self._block_running_anim_expire_t <= t then
		self._block_running_anim_expire_t = nil
		self._block_running_anim = nil
		try_play_start_running(self)
	end

	if self._anim_state and not self._ext_camera:anim_state_machine():is_playing(self._anim_state) then
		self._anim_state = nil

		if self._anim_state_callback then
			local callback = self._anim_state_callback
			self._anim_state_callback = nil
			callback(self, t)
		end
	end	
end)
