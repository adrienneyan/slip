function cparams = ControllerParams()

cparams.phase_rate = 1;
cparams.robot_weight = 30*9.8;
cparams.contact_threshold = 30*9.8/2/1e4;
cparams.l_max = 0.8;
cparams.step_height = 0.1;
cparams.ddx_filter = 0.1;
cparams.step_lock_phase = 0.7;
cparams.max_stride = 0.4;
cparams.target_dx = 0;
cparams.step_offset = 0;
cparams.energy_injection = 0;
cparams.phase_stretch = 0;
cparams.n = 0;

cparams.x_pd = struct(...
    'target', {0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0, 1.0, 1.0}, ...
    'kp',     {1e3, 1e3, 1e3, 1e3, 1e3, 1e3, 1e3, 1e3, 1e3, 1e3, 1e3}, ...
    'kd',     {1e2, 1e2, 1e2, 1e2, 1e2, 1e2, 1e2, 1e2, 1e2, 1e2, 1e2});
cparams.y_pd = struct(...
    'target', {0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0}, ...
    'kp',     {4e3, 4e3, 4e3, 4e3, 4e3, 4e3, 4e3, 4e3, 4e3, 4e3, 4e3}, ...
    'kd',     {1e2, 1e2, 1e2, 1e2, 1e2, 1e2, 1e2, 1e2, 1e2, 1e2, 1e2});
cparams.body_angle_pd = struct(...
    'target', {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}, ...
    'kp',     {2e3, 2e3, 2e3, 0.0, 0.0, 0.0, 0.0, 0.0, 2e3, 2e3, 2e3}, ...
    'kd',     {1e2, 1e2, 1e2, 0.0, 0.0, 0.0, 0.0, 0.0, 1e2, 1e2, 1e2});

cparams.weight_ff = [1.0, 1.0, 1.0, 0.5, 0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0];
cparams.energy_ff = [0.0, 0.5, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
