function env = Environment()

env.gravity      = 9.81;
env.body.mass    = 30;
env.body.inertia = 0.3;
env.foot.mass    = 0.4;

env.length.stiffness      = 1e4;
env.length.damping        = 1e2;
env.length.motor.inertia  = 1e-3;
env.length.motor.damping  = 1e-1;
env.length.motor.ratio    = 48;
env.length.motor.torque   = 12;
env.length.hardstop.min   = 0.3;
env.length.hardstop.max   = 1;
env.length.hardstop.kp    = 4e3;
env.length.hardstop.kd    = 4e1;
env.length.hardstop.dfade = 1e-2;
env.length.hardstop.fmax  = 1e5;

env.angle.stiffness      = 1e4;
env.angle.damping        = 1e2;
env.angle.motor.inertia  = 1e-3;
env.angle.motor.damping  = 1e-1;
env.angle.motor.ratio    = 16;
env.angle.motor.torque   = 12;
env.angle.hardstop.min   = -1.5;
env.angle.hardstop.max   = 1.5;
env.angle.hardstop.kp    = 1e3;
env.angle.hardstop.kd    = 1e1;
env.angle.hardstop.dfade = 1e-2;
env.angle.hardstop.fmax  = 1e3;

env.ground.damping_depth = 1e-3;
env.ground.slip_ramp     = 1e-4;