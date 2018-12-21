clear all

%% SETUP
HOSTNAME = 'hpc06.tudelft.net';
USERNAME = '<yourNetID>'; % Please fill in your netID
disp('Please fill in your NetID password in the dlg box...')
PASSWORD = passwordUI(); % NEVER HARD-CODE YOUR PASSWORD. USE THE UI!
research_group = 'pme'; % group: 'dcsc', 'pme', 'mse'


%% Login and retrieve data from cluster
addpath('SSH_bin/ssh2_v2_m1_r6')
cmd_all_nodes = ssh2_simple_command(HOSTNAME,USERNAME,PASSWORD,['pbsnodes | grep -B 3 ' research_group]);
cmd_all_jobs  = [ssh2_simple_command(HOSTNAME,USERNAME,PASSWORD,['qstat ' research_group ' -n -1']); ...
                 ssh2_simple_command(HOSTNAME,USERNAME,PASSWORD,['qstat guest -n -1']) ];
clear PASSWORD

%% Process information
% Find all nodes for research_group queue
nodes  = struct();
nodeId = 0;
for i = 1:length(cmd_all_nodes)
    str_read = cmd_all_nodes{i};
    if strncmpi(str_read,'n06-',3)
        nodeId = nodeId + 1;
        nodes(nodeId).name  = str_read;
        tmp_id = regexp(str_read,'n06-(?<id>\d+)','names');
        nodes(nodeId).id = str2double(tmp_id.id);
    end
    if strncmpi(str_read,'     state',9)
        nodes(nodeId).state = extractAfter(cmd_all_nodes{i},"state = ");
    end
    if strncmpi(str_read,'     np =',7)
        nodes(nodeId).np = str2double(extractAfter(cmd_all_nodes{i},"np = "));
        nodes(nodeId).availability = ones(1,nodes(nodeId).np); % Initialize as available (1=available, 0=taken)
    end    
    if strncmpi(str_read,'     properties',10)
        nodes(nodeId).properties = extractAfter(cmd_all_nodes{i},"properties = ");
    end      
end
% disp(['Number of nodes: ' num2str(length(nodes))])
clear nodeId i tmp_id


% Determine jobs currently in research_group queue
clear jobs
jobId = 0;
for i = 1:length(cmd_all_jobs)
    li = cmd_all_jobs{i};
    result = regexp(li,['(?<jobID>\d+).hpc06.hpc\s+(?<usr>\w+)\s+' research_group '\s+(?<name>\w+)'],'names');
    if ~isempty(result)
        tmpJobQueue = research_group;
    else
        result = regexp(li,['(?<jobID>\d+).hpc06.hpc\s+(?<usr>\w+)\s+guest\s+(?<name>\w+)'],'names');
        tmpJobQueue = 'guest';
    end
        
    if ~isempty(result)
        % Also add number of cores for this job to the result
        result.cores = regexp(li,'n06-(?<no>[\d]{1,3})/(?<proc>\d+)','names');
        
        if ~isempty(result.cores)
            % Determine if nodes are part of the specified queue
            clear coresOut
            for uuu = 1:length(result.cores)
                if any([nodes.id]==str2num(result.cores(uuu).no))
                    if exist('coresOut') == 0
                        coresOut = result.cores(uuu);
                    else
                        coresOut(end+1) = result.cores(uuu);
                    end
                end
            end
            if exist('coresOut')
                result.cores = coresOut;
                jobId = jobId + 1;
                result.queue = tmpJobQueue;
                jobs(jobId) = result; % Add to struct
            end
        end
    end
end
% disp(['Number of active jobs: ' num2str(length(jobs))])


% Determine the node availability
for i = 1:length(jobs)
    jobi = jobs(i);
    [xPlot,yPlot] = deal([]);
    for j = 1:length(jobi.cores)
        nodeId = find(str2double(jobi.cores(j).no)==[nodes.id]); % Find node corresponding to core j of job i
        coreId = str2double(jobi.cores(j).proc);
        nodes(nodeId).availability(coreId+1) = 0;
        xPlot = [xPlot nodeId];
        yPlot = [yPlot coreId+1];
    end
    jobs(i).xPlot = xPlot;
    jobs(i).yPlot = yPlot;
end


%% Draw figure
figure;
x = 0;
colorPalet = colormap(lines(length(jobs)));
for i = 1:length(jobs)
    hold on
    if strcmp(jobs(i).queue,'guest')
        h=scatter(jobs(i).xPlot,jobs(i).yPlot,'diamond','filled');
    else
        h=scatter(jobs(i).xPlot,jobs(i).yPlot,'filled');
    end
    h.MarkerFaceColor = colorPalet(i,:);
end    
for i = 1:length(nodes)
    x = x + 1;
    % Plot free nodes
    for y = 1:nodes(i).np
        if nodes(i).availability(y)
            hold on
            h=scatter(x,y,'filled');
            h.MarkerFaceColor = 'k';
            h.MarkerFaceAlpha = 0.15;
        end
    end
end
hold off

% Determine legend names
for i = 1:length(jobs)
    lgdName{i} = ['[' upper(jobs(i).queue) '] ' jobs(i).jobID ' (' jobs(i).usr ')'];
end
legend([lgdName {'free nodes'}],'Location','eastoutside')
legend('boxoff')
xlim([0 length(nodes)+1]);
ylim([0 max([nodes.np])+1]);
ylabel('# processor');
xlabel('# node');
grid on;
title(['Queue: ' research_group ', Jobs: ' num2str(length(jobs)) ', Used: ' num2str(sum([nodes.np])-sum([nodes.availability])) ', Available: ' num2str(sum([nodes.availability]))])
set(gca,'XTick',1:length(nodes))