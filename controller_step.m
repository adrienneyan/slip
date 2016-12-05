function [u, cstate] = controller_step(X, cstate, cparams, Ts)

% Get singleturn body angle to allow for flips
X.body.theta = mod(X.body.theta + pi, 2*pi) - pi;

% Above some speed, increase step rate instead of increasing stride length
if abs(X.body.dx / cparams.phase_rate) > cparams.max_stride * 2
     cparams.phase_rate = abs(X.body.dx / cparams.max_stride / 2);
end

dx_diff = clamp(X.body.dx - cparams.target_dx, -0.5, 0.5);
phase_rate_eq = cparams.phase_rate;
% cparams.phase_rate = cparams.phase_rate + 0.2 * dx_diff * sign(X.body.dx);

% Add speed-dependent term to energy injection
energy_injection = cparams.energy_injection + 500 * max(abs(X.body.dx) - 1, 0);

% Energy injection for speed control
energy_injection = energy_injection - dx_diff * 1000 * sign(X.body.dx);

% Increase leg phases with time
cstate.phase.right = cstate.phase.right + Ts * cparams.phase_rate;
cstate.phase.left  = cstate.phase.left  + Ts * cparams.phase_rate;

% Capture foot positions at phase rollover
if cstate.phase.right >= 1
    cstate.foot_x_last.right = X.body.x + X.right.l * sin(X.body.theta + X.right.theta);
end
if cstate.phase.left >= 1
    cstate.foot_x_last.left = X.body.x + X.left.l * sin(X.body.theta + X.left.theta);
end

% Limit phases to [0, 1)
cstate.phase.right = cstate.phase.right - floor(cstate.phase.right);
cstate.phase.left  = cstate.phase.left  - floor(cstate.phase.left);

% Modify timing and trajectory shapes by stretching the phase
phase.right = stretch_phase(cstate.phase.right, cparams.phase_stretch);
phase.left  = stretch_phase(cstate.phase.left,  cparams.phase_stretch);

% Estimate body acceleration
body_ddx_est = (X.body.dx - cstate.body_dx_last) / Ts;
cstate.body_ddx = cstate.body_ddx + cparams.ddx_filter * (body_ddx_est - cstate.body_ddx);
cstate.body_dx_last = X.body.dx;

% Detect ground contact
gc.right = clamp((X.right.l_eq - X.right.l) / cparams.contact_threshold, 0, 1);
gc.left = clamp((X.left.l_eq - X.left.l) / cparams.contact_threshold, 0, 1);

% Update leg targets
% foot_extension = exp(cparams.phase_stretch * 0.1) * (0.09 + phase_rate_eq * 0.24) * X.body.dx / phase_rate_eq + 0.1 * max(abs(X.body.dx) - 2, 0) + ...
%     0.1 * clamp(X.body.dx - cparams.target_dx, -0.5, 0.5) + ...
%     0.03 * cstate.body_ddx;
if phase.right < cparams.step_lock_phase
    foot_extension = (1 - phase.right) * X.body.dx / sqrt(phase_rate_eq) + ...
    0.15 * clamp(X.body.dx - cparams.target_dx, -0.5, 0.5) + ...
    0.03 * cstate.body_ddx;
    cstate.foot_x_target.right = X.body.x + foot_extension;
end
if phase.left < cparams.step_lock_phase
    foot_extension = (1 - phase.left) * X.body.dx / sqrt(phase_rate_eq) + ...
    0.15 * clamp(X.body.dx - cparams.target_dx, -0.5, 0.5) + ...
    0.03 * cstate.body_ddx;
    cstate.foot_x_target.left = X.body.x + foot_extension;
end

% Initialize torque struct
u = Control();

% Get PD controllers for x and y foot position (leg angle and length)
leg_pd.right.y = get_pd(cparams.y_pd, phase.right);
leg_pd.right.x = get_pd(cparams.x_pd, phase.right);
leg_pd.left.y  = get_pd(cparams.y_pd, phase.left);
leg_pd.left.x  = get_pd(cparams.x_pd, phase.left);

% Get transformed leg PD output
u.right = eval_leg_pd(leg_pd.right, X, X.right, cparams, cstate.foot_x_last.right, cstate.foot_x_target.right);
u.left  = eval_leg_pd(leg_pd.left,  X, X.left,  cparams, cstate.foot_x_last.left,  cstate.foot_x_target.left);

% Modulate angle target control with ground contact
u.right.theta_eq = (1 - gc.right) * u.right.theta_eq;
u.left.theta_eq = (1 - gc.left) * u.left.theta_eq;

% Add feedforward terms for weight compensation and energy injection
u.right.l_eq = u.right.l_eq + ...
    eval_ff(cparams.weight_ff, phase.right) * cparams.robot_weight + ...
    eval_ff(cparams.energy_ff, phase.right) * energy_injection;
u.left.l_eq = u.left.l_eq + ...
    eval_ff(cparams.weight_ff, phase.left) * cparams.robot_weight + ...
    eval_ff(cparams.energy_ff, phase.left) * energy_injection;

% Add body angle control, modulated with ground contact
u.right.theta_eq = u.right.theta_eq - ...
    gc.right * eval_pd(cparams.body_angle_pd, phase.right, X.body.theta, X.body.dtheta, 0, 0);
u.left.theta_eq = u.left.theta_eq - ...
    gc.left * eval_pd(cparams.body_angle_pd, phase.left, X.body.theta, X.body.dtheta, 0, 0);

end


function out = eval_ff(tpoints, phase)

i = 2 + floor(phase * 10);
p = phase * 10 - i + 2;

out = tpoints(i - 1) + p * (tpoints(i) - tpoints(i - 1));
end


function out = eval_pd(tpoints, phase, x, dx, zero_point, one_point)

i = 2 + floor(phase * 10);
phase_diff = 0.1;
p = phase * 10 - i + 2;

target = tpoints(i - 1).target + p * (tpoints(i).target - tpoints(i - 1).target);
dtarget = (tpoints(i).target - tpoints(i - 1).target) / phase_diff;
kp = tpoints(i - 1).kp + p * (tpoints(i).kp - tpoints(i - 1).kp);
kd = tpoints(i - 1).kd + p * (tpoints(i).kd - tpoints(i - 1).kd);

scale = one_point - zero_point;
offset = zero_point;

out = (kp * ((target * scale + offset) - x)) + (kd * (dtarget * scale - dx));
end


function pd = get_pd(tpoints, phase)

i = 2 + floor(phase * 10);
phase_diff = 0.1;
p = phase * 10 - i + 2;

pd.target = tpoints(i - 1).target + p * (tpoints(i).target - tpoints(i - 1).target);
pd.dtarget = (tpoints(i).target - tpoints(i - 1).target) / phase_diff;
pd.kp = tpoints(i - 1).kp + p * (tpoints(i).kp - tpoints(i - 1).kp);
pd.kd = tpoints(i - 1).kd + p * (tpoints(i).kd - tpoints(i - 1).kd);
end


function u = eval_leg_pd(pd, X, leg, p, x_last, x_target)
% Get scaled x and y targets
x = pd.x.target * (x_target - x_last) + x_last - X.body.x;
dx = pd.x.dtarget * (x_target - x_last) - X.body.dx;
y = p.l_max - pd.y.target * p.step_height;
dy = -pd.y.dtarget * p.step_height;

% Transform to polar
l = sqrt(x^2 + y^2);
dl = (x*dx + y*dy) / l;
theta = real(asin(complex(x / l))) - X.body.theta;
dtheta = (y*dx - x*dy) / l^2 - X.body.dtheta;

% Compute PD controllers
u.l_eq = pd.y.kp * (l - leg.l_eq) + pd.y.kd * (dl - leg.dl_eq);
u.theta_eq = pd.x.kp * (theta - leg.theta_eq) + pd.x.kd * (dtheta - leg.dtheta_eq);
end


function p = stretch_phase(p, stretch)
% Stretch the phase with a sigmoid to lengthen or shorten the middle relative
% to the ends

if abs(stretch) < 1e4*eps
    return
end

b = 1/(2*(exp(stretch/2) - 1));
if p < 0.5
    p = b*exp(stretch*p) - b;
else
    p = 1 - (b*exp(stretch*(1 - p)) - b);
end
end



function out = clamp(x, l, h)
out = min(max(x, l), h);
end
