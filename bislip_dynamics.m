function [dX, body, leg_a, leg_b] = bislip_dynamics(X, u, params, ground_data)
% X: [body_x;    body_xdot;    body_y;  body_ydot;  body_th;  body_thdot;
%     leg_a_leq; leg_a_leqdot; leg_a_l; leg_a_ldot; leg_a_th; leg_a_thdot;
%     leg_b_leq; leg_b_leqdot; leg_b_l; leg_b_ldot; leg_b_th; leg_b_thdot]
% u: [length_motor_a_torque; angle_motor_a_torque;
%     length_motor_b_torque; angle_motor_b_torque]
% params: [body_mass; body_inertia; foot_mass; leg_stiffness; leg_damping; 
%         length_motor_inertia; length_motor_ratio; length_motor_damping; 
%         angle_motor_inertia;  angle_motor_ratio;  angle_motor_damping; 
%         gravity]
% ground_data: [ground_x, ground_y, ground_stiffness, 
%               ground_damping, ground_friction]

% Kinematics
% body: [x; xdot; y; ydot; th; thdot]
% leg: [leq; leqdot; l; ldot; th; thdot; x; xdot; y; ydot; xdir; ydir]
% Leg agles are relative to body angle
% Leg x, y, xdot, ydot are absolute
body = X(1:6);
leg_a = leg_kinematics(X(7:12), body);
leg_b = leg_kinematics(X(13:18), body);

% Calculate world frame acceleration for each leg
[foot_a_accel_abs, leg_a_leqddot, reaction_force_a, reaction_torque_a] ...
    = leg_acceleration(leg_a, params, u(1:2), body, ground_data);
[foot_b_accel_abs, leg_b_leqddot, reaction_force_b, reaction_torque_b] ...
    = leg_acceleration(leg_b, params, u(3:4), body, ground_data);

% Calculate forces on body
body_gravity_force = params(12)*params(1)*[0; -1];
body_ground_force = ground_contact_model(body([1 3]) + [0; -0.1], body([2 4]), body([1 3]), ground_data);
body_force = reaction_force_a + reaction_force_b + body_gravity_force + body_ground_force;
body_torque = reaction_torque_a + reaction_torque_b;

% Calculate body acceleration
body_xddot = body_force(1)/params(1);
body_yddot = body_force(2)/params(1);
body_thddot = body_torque/params(2);

% Convert foot acceleration to relative radial acceleration
[leg_a_lddot, leg_a_thddot] ...
    = leg_radial_acceleration(leg_a, foot_a_accel_abs, body, ...
                              [body_xddot; body_yddot], body_thddot);
[leg_b_lddot, leg_b_thddot] ...
    = leg_radial_acceleration(leg_b, foot_b_accel_abs, body, ...
                              [body_xddot; body_yddot], body_thddot);

% Compose state derivative vector
dX = [X(2);  body_xddot;    X(4);  body_yddot;  X(6);  body_thddot; 
      X(8);  leg_a_leqddot; X(10); leg_a_lddot; X(12); leg_a_thddot;
      X(14); leg_b_leqddot; X(16); leg_b_lddot; X(18); leg_b_thddot];
0;


function leg = leg_kinematics(X_leg, body)
% Calculate lengths, derivatives, etc
leg = zeros(12, 1);
leg(1:6) = X_leg(1:6); % th, leg, l, and derivatives of each
leg(11:12) = [sin(leg(5) + body(5)); -cos(leg(5) + body(5))]; % leg direction unit vector, absolute
leg([7 9]) = body([1 3]) + leg(3)*leg(11:12); % x and y
leg([8 10]) = leg(4)*leg(11:12) + leg(3)*leg(6)*[-leg(12); leg(11)]; % xdot and ydot


function [foot_accel_abs, leqddot, body_reaction_force, body_reaction_torque] ...
    = leg_acceleration(leg, params, u_leg, body, ground)
% Get foot acceleration in absolute cartesian coordinates and body reactions
% Friendlier names for variables
foot_mass = params(3);
leg_stiffness = params(4);
leg_damping = params(5);
length_motor_inertia = params(6);
length_motor_ratio = params(7);
length_damping = params(8);
angle_motor_inertia = params(9);
angle_motor_ratio = params(10);
angle_motor_damping = params(11);
gravity = params(12);
leq = leg(1);
leqdot = leg(2);
l = leg(3);
ldot = leg(4);
thdot = leg(6);
ldir = leg(11:12);
thdir = [-ldir(2); ldir(1)];
length_torque = u_leg(1);
angle_torque = u_leg(2);
foot_inertia = foot_mass*leg(3)^2;
leg_angle_inertia = foot_inertia + angle_motor_ratio^2*angle_motor_inertia;
eq_length_inertia = length_motor_ratio^2*length_motor_inertia;

% Forces on foot in absolute x,y coordinates
spring_force_mag = leg_stiffness*(leq - l) + leg_damping*(leqdot - ldot);
spring_force = spring_force_mag*ldir;
total_angle_torque = (angle_torque - angle_motor_damping*angle_motor_ratio^2*thdot);
angle_motor_force = total_angle_torque*foot_inertia/leg_angle_inertia/l*thdir;
gravity_force = gravity*foot_mass*[0; -1];
ground_force = ground_contact_model(leg([7 9]), leg([8 10]), body([1 3]), ground);
foot_force_abs = spring_force + angle_motor_force + gravity_force + ground_force;
foot_accel_abs = foot_force_abs/foot_mass;

% Leg equilibrium length acceleration
length_force = length_motor_ratio*length_torque;
length_damping = length_damping*length_motor_ratio^2*leqdot;
leqddot = (length_force - length_damping - spring_force_mag)/eq_length_inertia;

% Reaction force and torque from leg on body
body_reaction_force  = -spring_force - length_force*ldir - angle_motor_force;
body_reaction_torque = -total_angle_torque;


function [lddot, thddot] ...
    = leg_radial_acceleration(leg, foot_accel_abs, body, body_accel, body_thddot)
% Convert absolute cartesian foot acceleration to relative polar coordinates
% Friendlier names for variables
l = leg(3);
ldot = leg(4);
thdot = leg(6);
ldir = leg(11:12);
thdir = [-ldir(2); ldir(1)];

foot_accel_rel = foot_accel_abs - body_accel - body_thddot*l*thdir;
foot_accel_l = dot(foot_accel_rel, ldir);
foot_accel_th = dot(foot_accel_rel, thdir);

lddot = foot_accel_l + l*(thdot + body(6))^2;
thddot = (foot_accel_th - 2*ldot*(thdot + body(6)))/l;


function ground_force = ground_contact_model(pos, vel, ref, ground_data)
% Ground contact force model
% Takes position and velocity of point that forces act on, a reference
% position used to find the correct ground intersection location, external
% forces on the point, and the ground data structure
% Returns the ground forces and a structure containing intermediate values

% Get unit direction vector from reference to point
refdir = pos - ref;
refdir = refdir/norm(refdir);

% Find location on ground that point is contacting
[xi, yi, ii] = linexpoly([ref(1); pos(1)], [ref(2); pos(2)], ground_data(:, 1), ground_data(:, 2));
if length(xi) < 1
    % No ground contact
    ground_tangent = [1; 0];
    ground_normal = [0; 1];
    depth = 0;
    ddepth = 0;
    ground_stiffness = 0;
    ground_damping = 0;
    ground_friction = 0;
else
    % Find depth into ground, speed, and ground properties at contact
    % Ground intersection geometry calculations
    depths2 = (xi - pos(1)).^2 + (yi - pos(2)).^2;
    [~, imax] = max(depths2);
    igs = ii(imax(1));
    ground_segment = [diff(ground_data(igs:igs+1, 1)); diff(ground_data(igs:igs+1, 2))];
    intersection_vector = [xi(imax) - ground_data(igs, 1); yi(imax) - ground_data(igs, 2)];
    p = (intersection_vector(1)*ground_segment(1) + intersection_vector(2)*ground_segment(2))...
        /(ground_segment(1)^2 + ground_segment(2)^2);
    
    % Ground contact properties
    ground_tangent = ground_segment/norm(ground_segment);
    ground_normal = [-ground_tangent(2); ground_tangent(1)];
    depth = sqrt(depths2(imax))*(-refdir(1)*ground_normal(1) - refdir(2)*ground_normal(2));
    ddepth = -vel(1)*ground_normal(1) - vel(2)*ground_normal(2);
    ground_stiffness = interpolate(ground_data(:, 3), igs, p);
    ground_damping = interpolate(ground_data(:, 4), igs, p);
    ground_friction = interpolate(ground_data(:, 5), igs, p);
    
    % Make sure ground normal points towards reference position
    if -refdir(1)*ground_normal(1) - refdir(2)*ground_normal(2) < 0
        ground_tangent = -ground_tangent;
        ground_normal = -ground_normal;
    end
    
    % Ramp up damping with depth
    damping_threshold = 1e-5;
    ground_damping = ground_damping*depth/(depth + damping_threshold);
end

% Ground reaction force from spring-damper system
% Acts nomral to the ground
spring_force = ground_normal*max(depth*ground_stiffness + ddepth*ground_damping, 0);

% Friction magnitude is proportional to component of ground spring force
% normal to ground
friction_mag = ground_friction*(spring_force(1)*ground_normal(1) + spring_force(2)*ground_normal(2));

% Calculate friction, replacing the jump discontinuity due to the sign
% function with a continuous ramp
ground_slip = vel(1)*ground_tangent(1) + vel(2)*ground_tangent(2);
slip_ramp_width = friction_mag*1e-8;
p = min(max(abs(ground_slip)/slip_ramp_width, 0), 1);
friction_force = -sign(ground_slip)*p*friction_mag*ground_tangent;

% Total ground force
ground_force = spring_force + friction_force;


function out = interpolate(v, i, p)
% Interpolation function for ground properties
out = v(i) + p*(v(2) - v(i));


function [xi, yi, ii] = linexpoly(x1, y1, x2, y2)
% Customized implementation of polyxpoly for codegen
dx1 = x1(2) - x1(1);
dy1 = y1(2) - y1(1);
dx2 = x2(2:end) - x2(1:end-1);
dy2 = y2(2:end) - y2(1:end-1);
dx12 = x1(1) - x2(1:end-1);
dy12 = y1(1) - y2(1:end-1);

num = dx2.*dy12 - dy2.*dx12;
den = dy2.*dx1 - dx2.*dy1;

sa = num./den;
sb = (dx12 + sa.*dx1)./dx2;

ii = find(den ~= 0 & sa >= 0 & sa < 1 & sb >= 0 & sb < 1);
xi = x1(1) + sa(ii).*dx1;
yi = y1(1) + sa(ii).*dy1;
