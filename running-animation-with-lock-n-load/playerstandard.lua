-- New members in PlayerStandard:
-- _stop_running_anim_expire_t: number | nil
-- _ready_to_shoot_expire_t: number | nil
-- _anim_state: userdata (Idstring representing an animation state) | nil

local start_running_state = Idstring("fps/start_running")
local running_state = Idstring("fps/running")
local stop_running_state = Idstring("fps/stop_running")

local function try_play_start_running(self)
	local is_playing = false

	if self._running
		and not self._end_running_expire_t
		and not self._shooting
		and not self._ready_to_shoot_expire_t
		and not self._anim_state
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
	local is_playing = false
	local state = self._ext_camera:anim_state_machine():segment_state(self:get_animation("base"))

	if (state == start_running_state) or (state == running_state) then
		local speed_multiplier = self._equipped_unit:base():exit_run_speed_multiplier()
		self._ext_camera:play_redirect(self:get_animation("stop_running"), speed_multiplier)
		self._stop_running_anim_expire_t = t + (0.4 / speed_multiplier)
		is_playing = true
	elseif self._end_running_expire_t and (state == stop_running_state) then
		self._stop_running_anim_expire_t = self._end_running_expire_t
		is_playing = true
	end

	return is_playing
end

local _check_action_primary_attack = PlayerStandard._check_action_primary_attack
function PlayerStandard:_check_action_primary_attack(t, input, params)
	if self._equipped_unit:base():run_and_shoot_allowed() then
		if input.btn_primary_attack_press then
			-- Exit the ready-to-shoot state.
			-- The player may have released the attack button before pressing it again.
			self._ready_to_shoot_expire_t = nil
			try_play_stop_running(self, t)
		end

		if input.btn_primary_attack_release then
			-- Enter the ready-to-shoot state, it will last for 3 seconds.
			self._ready_to_shoot_expire_t = t + 3
		end

		if self._stop_running_anim_expire_t and self._stop_running_anim_expire_t > t then
			return false
		end
	end
	
	return _check_action_primary_attack(self, t, input, params)
end

local _check_action_deploy_underbarrel = PlayerStandard._check_action_deploy_underbarrel
function PlayerStandard:_check_action_deploy_underbarrel(t, input)
	if self._equipped_unit:base():run_and_shoot_allowed() then
		if input.btn_deploy_bipod and self._running then
			local is_playing = try_play_stop_running(self, t)

			if is_playing then
				self._toggle_underbarrel_wanted = true
			end
		end

		if self._stop_running_anim_expire_t and self._stop_running_anim_expire_t > t then
			return false
		end
	end

	local new_action = _check_action_deploy_underbarrel(self, t, input)

	if new_action and self._equipped_unit:base():run_and_shoot_allowed() then
		-- Assume that the underbarrel toggle animation is playing.
		self._anim_state = self._ext_camera:anim_state_machine():segment_state(self:get_animation("base"))
	end

	return new_action
end

Hooks:PostHook(PlayerStandard, "_start_action_reload", "RunningAnimationWithLockNLoad", function (self, t)
	if self:_is_reloading() and self._equipped_unit:base():run_and_shoot_allowed() then
		-- Assume that the reload animation is playing.
		self._anim_state = self._ext_camera:anim_state_machine():segment_state(self:get_animation("base"))
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

	if self._ready_to_shoot_expire_t and self._ready_to_shoot_expire_t <= t then
		self._ready_to_shoot_expire_t = nil
		try_play_start_running(self)
	end

	if self._anim_state and not self._ext_camera:anim_state_machine():is_playing(self._anim_state) then
		self._anim_state = nil
		try_play_start_running(self)
	end
end)
