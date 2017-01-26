classdef Planner < matlab.System & matlab.system.mixin.Propagates
    
    properties (Nontunable)
        Ts = 1e-1;
        Ts_sim = 1e-3;
        Ts_tree = 0.25;
        robot = RobotParams();
        ground_data = zeros(2, 5);
        rollout_depth = 4;
        transition_samples = 4;
    end

    properties
        target_dx = 0;
    end
    
    properties (Access = private)
        tree
        rollout_node
        env
        state_evaluator
        t
        action_queue
        rngstate
    end
    
    
    methods (Access = protected)
        function setupImpl(obj)
            obj.rngstate = rng('shuffle');
            ss = SimulationState();
            ss.X = repmat(RobotState(), 1, obj.transition_samples);
            ss.cstate = repmat(ControllerState(), 1, obj.transition_samples);
            obj.tree = Tree(ss, 1024, 32);
            obj.env = Environment(obj.ground_data);
            obj.state_evaluator = StateEvaluator();
            obj.t = 0;
            obj.action_queue = Queue(ControllerParams(), obj.rollout_depth);
        end
        
        
        function cparams = stepImpl(obj, X, cstate)
            
            % Set rng state to value from previous step
            rng(obj.rngstate);

            goal = Goal();
            goal.dx = obj.target_dx;
            
            cparams = obj.tree.nodes(1).data.cparams;
            
            % Check whether next planner timestep will start a new tree timestep
            if obj.t - obj.Ts < 0
                % Project one planner timestep forward with current parameters
                % for delay compensation
                terrain = obj.env.getLocalTerrain(X.body.x);
                [Xp, cstatep] = biped_sim_mex(X, cstate, obj.robot, cparams, terrain, obj.Ts, obj.Ts_sim);
                
                % Store the highest value path in the action stack
                pathnodes = zeros(obj.rollout_depth + 1, 1);
                pathnodes(1) = 1;
                obj.action_queue.clear();
                n = 1;
                while any(obj.tree.nodes(n).children)
                    % Find child with highest rollout value
                    v_max = -inf;
                    n_new = 0;
                    for i = 1:numel(obj.tree.nodes(n).children)
                        c = obj.tree.nodes(n).children(i);
                        if c
                            v = obj.tree.nodes(c).data.path_value;
                            if v > v_max
                                cparams = obj.tree.nodes(c).data.cparams;
                                v_max = v;
                                n_new = c;
                            end
                        end
                    end
                    if ~n_new
                        break;
                    end
                    n = n_new;
                    pathnodes(find(~pathnodes, 1)) = n;
                    obj.action_queue.push(cparams);
                end
                
                if ~obj.action_queue.isempty()
                    % Head is the next action to take, remaining actions are
                    % first guesses for next planning cycle
                    cparams = obj.action_queue.pop();
                else
                    % If no full paths exist, choose the immediate child with
                    % the highest stability instead
                    stability_max = -inf;
                    for i = 1:numel(obj.tree.nodes(n).children)
                        c = obj.tree.nodes(1).children(i);
                        if c
                            stability = obj.tree.nodes(c).data.stability;
                            if stability > stability_max
                                cparams = obj.tree.nodes(c).data.cparams;
                                stability_max = stability;
                            end
                        end
                    end
                end
                
                % Simulate the upcoming tree timestep
                ss = obj.simulate_transition(Xp, cstatep, cparams, goal, obj.Ts_tree - obj.Ts);
                
                % Reset tree with predicted state as root
                obj.tree.reset(ss);
                obj.rollout_node = uint32(1);
            else
                % Otherwise, grow the tree
                
                % Check whether max depth on current rollout has been reached
                if obj.tree.nodes(obj.rollout_node).depth >= obj.rollout_depth
                    % Evaluate leaf node   
                    stability = obj.tree.nodes(obj.rollout_node).data.stability;
                    goal_value = obj.tree.nodes(obj.rollout_node).data.goal_value;
                    
                    path_value = (goal_value + 1) / 2;
                    if stability < 0.5
                        path_value = min(path_value, stability);
                    end
                    obj.tree.nodes(obj.rollout_node).data.path_value = path_value;
                    
                    % Propogate value to parents
                    i = obj.tree.nodes(obj.rollout_node).parent;
                    while (i > 0)
                        % Compute potential new path value
                        % path_value retained from child
                        stability = obj.tree.nodes(i).data.stability;
                        goal_value = obj.tree.nodes(i).data.goal_value;
                        
                        decay = 0.8;
                        new_path_value = (goal_value + 1) / 2;
                        new_path_value = path_value * decay + new_path_value * (1 - decay);
                        
                        % Set node value if greater than previous value
                        if obj.tree.nodes(i).data.path_value < new_path_value
                            path_value = new_path_value;
                            obj.tree.nodes(i).data.path_value = path_value;
                        else
                            % Otherwise, stop backprop
                            break;
                        end
                        
                        % Move to parent
                        i = obj.tree.nodes(i).parent;
                    end
                    
                    % Start new rollout
                    obj.rollout_node = obj.tree.randDepth(obj.rollout_depth - 1);
                end
                
                % Expand on current rollout node
                n = obj.rollout_node;
                
                % Sample a starting state from the parent node's distribution
                [Xn, cstaten] = obj.sample_node_state(n);
                
                % Generate a set of parameters to try
                gstate = obj.tree.nodes(n).data.gstate;
                terrain = obj.env.getLocalTerrain(Xn.body.x);
                [cparams_gen, gstate] = generate_params(Xn, goal, terrain, gstate, obj.action_queue);
                obj.tree.nodes(n).data.gstate = gstate;
                
                % Simulate the transition multiple times to estimate
                % stochasticity
                ss = obj.simulate_transition(Xn, cstaten, cparams_gen, goal, obj.Ts_tree);
                
                if ss.stability > 0.3
                    % If the stability is reasonably high, add it as a child and
                    % continue the rollout
                    c = obj.tree.addChild(n, ss);
                    
                    % If unable to add child node, delete the least stable child
                    if ~c
                        vs_min = inf;
                        c_min = uint32(0);
                        for i = 1:numel(obj.tree.nodes(n).children)
                            ci = obj.tree.nodes(n).children(i);
                            if ci
                                vsc = obj.tree.nodes(ci).data.stability;
                                if vsc <= vs_min
                                    vs_min = vsc;
                                    c_min = ci;
                                end
                            end
                        end
                        if c_min
                            obj.tree.deleteNode(c_min);
                            c = obj.tree.addChild(n, ss);
                        end
                    end
                    
                    % Child is next parent for the rollout
                    if c
                        obj.rollout_node = c;
                    else
                        % Adding child failed; tree is probably full
                        obj.rollout_node = obj.tree.randDepth(obj.rollout_depth - 1);
                    end
                else
                    % If the value is too low, start a new rollout
                    obj.rollout_node = obj.tree.randDepth(obj.rollout_depth - 1);
                end
            end
            
            % Increment tree timestep clock
            obj.t = mod(obj.t + obj.Ts, obj.Ts_tree);
            
            % Save rng state
            obj.rngstate = rng;
        end
        
        
        function resetImpl(obj)
            obj.rngstate = rng('shuffle');
            obj.tree.reset(SimulationState());
            obj.rollout_node = uint32(1);
            obj.env.ground_data = obj.ground_data;
            obj.t = 0;
            obj.action_queue.clear();
        end
        
        
        function s = saveObjectImpl(obj)
            s = saveObjectImpl@matlab.System(obj);
            s.tree = obj.tree;
            s.tree_nodes = obj.tree.nodes;
            s.rollout_node = obj.rollout_node;
            s.env = obj.env;
            s.state_evaluator = obj.state_evaluator;
            s.t = obj.t;
            s.action_queue = obj.action_queue;
            s.action_queue_queue = obj.action_queue.queue;
            s.action_queue_head = obj.action_queue.head;
            s.action_queue_size = obj.action_queue.size;
            s.rngstate = obj.rngstate;
        end
        
        
        function loadObjectImpl(obj, s, wasLocked)
            obj.tree = s.tree;
            obj.tree.nodes = s.tree_nodes;
            obj.rollout_node = s.rollout_node;
            obj.env = s.env;
            obj.state_evaluator = s.state_evaluator;
            obj.t = s.t;
            obj.action_queue = s.action_queue;
            obj.action_queue.queue = s.action_queue_queue;
            obj.action_queue.head = s.action_queue_head;
            obj.action_queue.size = s.action_queue_size;
            obj.rngstate = s.rngstate;
            loadObjectImpl@matlab.System(obj, s, wasLocked);
        end
        
        
        function [sz1] = getOutputSizeImpl(~)
            sz1 = [1 1];
        end
        function [dt1] = getOutputDataTypeImpl(~)
            dt1 = 'controller_params_bus';
        end
        function [cm1] = isOutputComplexImpl(~)
            cm1 = false;
        end
        function [fs1] = isOutputFixedSizeImpl(~)
            fs1 = true;
        end
        
    end
    
    
    methods (Access = private)
        
        function [Xn, cstaten] = sample_node_state(obj, n)
            isample = randi(obj.transition_samples);
            Xn = obj.tree.nodes(n).data.X(isample);
            cstaten = obj.tree.nodes(n).data.cstate(isample);
        end
        
        
        function ss = simulate_transition(obj, X, cstate, cparams, goal, tstop)
            
            % Get local terrain
            terrain = obj.env.getLocalTerrain(X.body.x);
            
            % Run several simulations
            for i = 1:obj.transition_samples
                % Simulate a step
                Xi = X;
                if i > 1
                    % Perturb initial conditions
                    Xi.body.x = Xi.body.x + 1e-3*randn();
                    Xi.body.y = Xi.body.y + 1e-3*randn();
                    Xi.body.dx = Xi.body.dx + 1e-2*randn();
                    Xi.body.dy = Xi.body.dy + 1e-2*randn();
                end
                
                [Xp(i), cstatep(i)] = biped_sim_mex(Xi, cstate, obj.robot, ...
                    cparams, terrain, tstop, obj.Ts_sim);
                
                % Evaluate the result
                terrainp = obj.env.getLocalTerrain(Xp(i).body.x);
                stability(i) = obj.state_evaluator.stability(Xp(i), terrainp);
                goal_value(i) = obj.state_evaluator.goal_value(Xp(i), goal);
            end
            
            % Average the goal value and take the minimum stability score
            goal_value = mean(goal_value);
            stability = min(stability);
            
            % Create simulation state structure
            gstate = GeneratorState();
            gstate.last_cparams = cparams;
            ss = SimulationState(Xp, cstatep, cparams, gstate, stability, goal_value, -inf);
        end
        
    end
    
end

