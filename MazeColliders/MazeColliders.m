clear all
path = pwd;
addpath(genpath([path,'\Toolboxes\']));
addpath(genpath([path,'\map\']));
 
%run startMobileRoboticsSimulationToolbox.m %% Comment out after first run to stop jumping to GettingStarted.mlx
port = serialportlist("available") %% List the available Serial ports
SerialPort = "COM4"; %% Change to the port connected to the Arduino
BaudRate = 9600;   %% Communication baud rate
task = "A3" ;       %% Task A3(randomized map with two goal) or A4(manually set map with three goals)
randomGoal = true;  %% Spawn random goals on map ? 
mapSetA4 = "map\map4.png" %% set the map manually,only work when task set to A4
randomPose = true;
%% Do not Modify
numberOfMaps = 5;
switch task
    case "A3"
        mapID=randi([1 numberOfMaps],1,1); % Randomize map ID
        f = dir('map\map*.png');
        mapLoad = imread(f(mapID).name); % Load map from .png pixel drawing (200x200 pixel)
    case "A4"
        mapLoad = imread(mapSetA4);
end
sensorAngle = 0*pi/180; %% Sensor scan angle in radian
scanDensity = 1; %% Amount of beam emited
sensorRange = 5; %% Max range of sensor
pose = [3; 4; 0]; %% Original robot position for A4
odometer = 0; %% Distance travelled
velocity = 0;
velocity_h=NaN;
%% Create map
grayimage = rgb2gray(mapLoad);
bwimage = grayimage < 0.5;
map = binaryOccupancyMap(bwimage,1);
%% GET A FREE POINT
resolution = 0.5;
numFree = 0;
spacing = 0.2; % distance away from the wall which goal and robot spawn
for x =0 : resolution : 20
    for  y=0 : resolution : 20
        if getOccupancy(map,[x y]) == 0 && getOccupancy(map,[x-spacing y]) == 0 && getOccupancy(map,[x-spacing y-spacing]) == 0&& getOccupancy(map,[x-spacing y+spacing]) == 0&& getOccupancy(map,[x y-spacing]) == 0&& getOccupancy(map,[x y+spacing]) == 0&& getOccupancy(map,[x+spacing y]) == 0&& getOccupancy(map,[x+spacing y+spacing]) == 0&& getOccupancy(map,[x+spacing y-spacing]) == 0
            numFree = numFree+1;
            freeLoc(numFree).x = x;
            freeLoc(numFree).y = y;
        end
    end
end
%% Pose generation
if randomPose == true
        PosSeed = randi([1,numFree],1,1);
        pose(1) = freeLoc(PosSeed).x;
        pose(2) = freeLoc(PosSeed).y;
        pose(3) = randi([0,3141],1,1)/1000;     
end

%% Innitialize Serial Communication
arduinoObj = serialport(SerialPort,BaudRate);
configureTerminator(arduinoObj,"CR/LF");
flush(arduinoObj);
arduinoObj.Timeout = 60; % Serial connection not reveive data within 60 second will stop automatically

%% Innitialize the Environment
viz = Visualizer2D;
viz.showTrajectory = false;          %% Show the robot Trajectory
viz.hasWaypoints = false;
viz.mapName = 'map';
lidar = LidarSensor;
lidar.scanAngles = linspace(sensorAngle-pi/180,sensorAngle+pi/180,scanDensity);
lidar.maxRange = sensorRange;
release(viz);
attachLidarSensor(viz,lidar);
ranges = lidar(pose);
viz(pose,ranges)

%% Generate random goals
gSwitch = 0; % to check if robot achieved Goal,0 is default, 1 when the robot reached goal 1 and 2 when robot reach goal 2.
seed = randi([1,numFree],2,1);
distance = sqrt( (freeLoc(seed(1)).x - freeLoc(seed(2)).x)^2 +  (freeLoc(seed(1)).y - freeLoc(seed(2)).y)^2);
while  distance < 5 distance && distance > 20
    seed = randi([1,numFree],2,1);
    distance = sqrt( (freeLoc(seed(1)).x - freeLoc(seed(2)).x)^2 +  (freeLoc(seed(1)).y - freeLoc(seed(2)).y)^2);
end
g(1) = freeLoc(seed(1));
g(2)= freeLoc(seed(2));
hold on
g1_h= NaN;
g2_h=NaN;
switch randomGoal
    case true
g1_h = plot(g(1).x,g(1).y,'Color','b','Marker','.','MarkerSize',30); %% <---Goal 1 coordinate here
g2_h = plot(g(2).x,g(2).y,'Color','r','Marker','*','MarkerSize',10); %% <---Goal 2 coordinate here
    case false
end
%% Start-end waypoint
if task == "A4"
   base =  plot(pose(1),pose(2),'Color','c','Marker','.','MarkerSize',30);
end
runFlag= false;
while runFlag == false
     disp("WAITING FOR START SIGNAL")
    buffer_s = arduinoObj.readline;
    if ~isempty(buffer_s)
        if buffer_s == "CMD_START"
        runFlag = true;
        disp("--------START--------")
        end
    end
end
tic

%% Loop
while runFlag == true
    buffer = arduinoObj.readline;
    if ~isempty(buffer)
        Status = DataLogger(buffer,'RX');
        switch buffer
            case "CMD_CLOSE"
                arduinoObj = [];
                runFlag = false;
                toc
                if randomGoal == true
                disp("Goal Achieved :")
                disp(gSwitch)
                end
                disp("Travelled Distance(metre):")
                disp(odometer)
                disp("-------SESSION END-------")
                clear
                break
            otherwise
                cmd = strsplit(buffer,'_'); % Splitting command into sectors
                if cmd(1) == 'CMD'
                    switch cmd(2)
                        case "ACT"          % Actuate Command
                            switch cmd(3)
                                case "LAT"                           % CMD_ACT_LAT_*Direction*_*DistanceValue* - Forward and backwards movement, Direction 1= forward, 0 =backward (m/s)
                                    direction = str2double(cmd(4));
                                    distance = str2double(cmd(5));
                                    [viz,pose,ranges,odometer,lidar,velocity_h,velocity,g,gSwitch]= moveStep(viz,pose,distance,direction,odometer,lidar,velocity_h,velocity,map,g,gSwitch,g1_h,g2_h);
                                case "ROT"                           % CMD_ACT_ROT_*Direction*_*Angle* - CW and CCW rotation,  Direction 1= CW, 0=CCW, Angle= rotation angle value
                                    noiseRot = 2;
                                    direction = str2double(cmd(4));
                                    angle = str2double(cmd(5))*pi/180;
                                    angle = angle + angle*randi([-noiseRot,noiseRot],1,1)/100;
                                    switch direction
                                        case 1
                                            pose = pose - [0; 0; angle];
                                            ranges = lidar(pose);
                                            viz(pose,ranges);
                                            pause(0.01)
                                        case 0
                                            pose = pose + [0; 0; angle];
                                            ranges = lidar(pose);
                                            viz(pose,ranges)
                                            pause(0.01)
                                        otherwise
                                            disp('WRONG DIRECTION INPUT')
                                    end
                                    if pose(3) >= 2*pi
                                        pose(3) = pose(3) - 2*pi;
                                    end
                                    if pose(3) < 0
                                        pose(3) = pose(3) + 2*pi;
                                    end
                                    ranges = lidar(pose);
                                    viz(pose,ranges)
                            end
                        case "SEN"          % Sensor Command
                            switch cmd(3)
                                case "IR"                            % CMD_SEN_IR - Function returns readings of the laser sensor
                                    noiseSEN = 5;                  % Percentage of noise created
                                    serialWrite(arduinoObj,ranges + ranges*randi([-noiseSEN,noiseSEN],1,1)/100);
                                case "ROT"                           % CMD_SEN_ROT_*Angle* - This will move the sensor to the specific position 0 is forward, 90 is right, 180 is back, 270 is left
                                    angle = str2double(cmd(4));
                                    while angle >= 360
                                        angle = angle - 360;
                                    end
                                    while angle <0
                                        angle = angle + 360;
                                    end
                                    release(viz)
                                    lidar.scanAngles = linspace((angle-1)*pi/180,(angle+1)*pi/180,scanDensity);
                                    sensorAngle = angle;
                                    attachLidarSensor(viz,lidar);
                                    ranges = lidar(pose);
                                    viz(pose,ranges);
                                case "CHECK"            % CMD_SEN_CHECK - This will return the current rotation on the sensor rotation 0-360
                                    serialWrite(arduinoObj,sensorAngle);
                                case "VEL"              % CMD_SEN_VEL - Return current Velocity of the robot
                                    serialWrite(arduinoObj,velocity);
                                case "DIST"             % CMD_SEN_DIST - Return current orientation of the robot
                                    serialWrite(arduinoObj,odometer);
                                case "PING"             % CMD_SEN_PING - Check if the goal point is nearby,return the distance to the goal if it within 5m range, return 0 if nothing in nearby
                                    d1 =  sqrt( (g(1).x - pose(1))^2 +  ( g(1).y - pose(2))^2);
                                    d2 =  sqrt( (g(2).x - pose(1))^2 +  ( g(2).y - pose(2))^2);
                                    
                                    if 0 < d1 && d1 <= 5
                                        serialWrite(arduinoObj,d1);
                                    else   
                                        if 0 < d2 && d2 <= 5
                                            serialWrite(arduinoObj,d2);
                                        else
                                            serialWrite(arduinoObj,0);
                                        end
                                    end
                                    
                                case "ID"         % CMD_SEN_ID - Identify the nearby goal within 2m, return 1 if near goal 1, return 2 if near goal 2, return 0 if no nearby goal
                                    d1 =  sqrt( (g(1).x - pose(1))^2 +  ( g(1).y - pose(2))^2);
                                    d2 =  sqrt( (g(2).x - pose(1))^2 +  ( g(2).y - pose(2))^2);
                                    if 0 < d1 && d1 < 2
                                        serialWrite(arduinoObj,1);
                                        return
                                    end
                                    if 0 < d2 && d2 < 2
                                        serialWrite(arduinoObj,2);
                                        return
                                    end
                                    serialWrite(arduinoObj,0);
                                case "GOAL"       % CMD_SEN_GOAL - Check the goal Switch, 0 is default, 1 when the robot reached goal 1 and 2 when robot reach goal 2.
                                    serialWrite(arduinoObj,gSwitch);
                            end
                            
                    end
                end
        end
    end
end
function serialWrite(arduinoObj,data)
if ~isempty(data)
    str = num2str(data);
    writeline(arduinoObj,str);
    %disp("Return from Arduino")
     Status = DataLogger(data,'TX');
  %  ReturnFromArduino = arduinoObj.readline
   %     actual = data
end
end
function [viz,pose,ranges,odometer,lidar,velocity_h,velocity,g,gSwitch]= moveStep(viz,pose,distance,direction,odometer,lidar,velocity_h,velocity,map,g,gSwitch,g1_h,g2_h)
try delete(velocity_h);end
vx=16;
vy=20.5;
maxDistance = 0.5; %% Maximum distance to goal required for the robot to be consider achieved goal
switch direction
    case 1
        velocity_h = text(vx,vy,sprintf('Velocity(m/s)=%f',1.5),'FontSize',7);
        velocity = 1.5;
        if distance < 2
            for i = 0:distance/25: distance
                nextPose = pose + [distance/25*cos(pose(3));distance/25*sin(pose(3));0];
                %% Check for wall
                if getOccupancy(map,[nextPose(1) nextPose(2)]) == 1
                    %disp('Wall Stop')
                    ranges = lidar(pose);
                    viz(pose,ranges)
                    return
                else
                    pose = nextPose;
                end
                %% Check for goal
                switch gSwitch
                    case 0
                        d1 =  sqrt( (g(1).x - pose(1))^2 +  ( g(1).y - pose(2))^2);
                        if d1 <= maxDistance
                            gSwitch = 1;
                            try delete(g1_h); end
                        end 
                    case 1
                        d2 =  sqrt( (g(2).x - pose(1))^2 +  ( g(2).y - pose(2))^2);
                        if d2 <= maxDistance
                            gSwitch = 2;
                            try delete(g2_h); end
                        end 
                end
                ranges = lidar(pose);
                viz(pose,ranges)
                pause(0.01)
            end
        else
            for i = 0:distance/50: distance
                nextPose = pose + [distance/50*cos(pose(3));distance/50*sin(pose(3));0];
                if getOccupancy(map,[nextPose(1) nextPose(2)]) == 1
                    %disp('Wall Stop')
                    ranges = lidar(pose);
                    viz(pose,ranges)
                    return
                else
                    pose = nextPose;
                end
                %% Check for goal
                switch gSwitch
                    case 0
                        d1 =  sqrt( (g(1).x - pose(1))^2 +  ( g(1).y - pose(2))^2);
                        if d1 <= maxDistance
                            gSwitch = 1;
                            try delete(g1_h); end
                        end 
                    case 1
                        d2 =  sqrt( (g(2).x - pose(1))^2 +  ( g(2).y - pose(2))^2);
                        if d2 <= maxDistance
                            gSwitch = 2;
                        end 
                end
                ranges = lidar(pose);
                velocity = 1.5;
                viz(pose,ranges)
                pause(0.01)
            end
        end
        delete(velocity_h);
        velocity_h = text(vx,vy,sprintf('Velocity(m/s)=%f',0),'FontSize',7);
        velocity=0;
    case 0
        velocity_h = text(vx,vy,sprintf('Velocity(m/s)=%f',-1.5),'FontSize',7);
        velocity = -1.5;
        if distance < 2
            for i = 0:distance/25: distance
                nextPose = pose - [distance/25*cos(pose(3));distance/25*sin(pose(3));0];
                if getOccupancy(map,[nextPose(1) nextPose(2)]) == 1
                    %disp('Wall Stop')
                    ranges = lidar(pose);
                    viz(pose,ranges)
                    return
                else
                    pose = nextPose;
                end
                                %% Check for goal
                switch gSwitch
                    case 0
                        d1 =  sqrt( (g(1).x - pose(1))^2 +  ( g(1).y - pose(2))^2);
                        if d1 <= maxDistance
                            gSwitch = 1;
                            try delete(g1_h); end
                        end 
                    case 1
                        d2 =  sqrt( (g(2).x - pose(1))^2 +  ( g(2).y - pose(2))^2);
                        if d2 <= maxDistance
                            gSwitch = 2;
                        end 
                end
                ranges = lidar(pose);
                velocity = -1.5;
                viz(pose,ranges)
                pause(0.02)
            end
        else
            for i = 0:distance/50: distance
                nextPose = pose - [distance/50*cos(pose(3));distance/50*sin(pose(3));0];
                if getOccupancy(map,[nextPose(1) nextPose(2)]) == 1
                    %disp('Wall Stop')
                    ranges = lidar(pose);
                    viz(pose,ranges)
                    return
                else
                    pose = nextPose;
                end
                                %% Check for goal
                switch gSwitch
                    case 0
                        d1 =  sqrt( (g(1).x - pose(1))^2 +  ( g(1).y - pose(2))^2);
                        if d1 <= maxDistance
                            gSwitch = 1;
                            try delete(g1_h); end
                        end 
                    case 1
                        d2 =  sqrt( (g(2).x - pose(1))^2 +  ( g(2).y - pose(2))^2);
                        if d2 <= maxDistance
                            gSwitch = 2;
                        end 
                end
                ranges = lidar(pose);
                velocity = -1.5;
                viz(pose,ranges)
                velocity_h = text(vx,vy,sprintf('Velocity=%f',velocity,'m/s'),'FontSize',7);
                
                pause(0.01)
            end
        end
        delete(velocity_h);
        velocity_h = text(vx,vy,sprintf('Velocity(m/s)=%f',0),'FontSize',7);
        velocity=0;
    otherwise
        disp('WRONG DIRECTION INPUT')
end
odometer = odometer + sqrt(distance*cos(pose(3))*distance*cos(pose(3))+distance*sin(pose(3))*distance*sin(pose(3)));
end
function [Status]=DataLogger(String,SendString)
   persistent Logger;
   if isempty(Logger)
       Logger={'TimeStamp','Recieved','Transmitted'};
   end
   DataVector{1,1}=datestr(datetime);
   if strcmp(SendString,'RX')
       DataVector{1,2}=String;
       DataVector{1,3}='';
   elseif strcmp(SendString,'TX')
       DataVector{1,2}='';
       DataVector{1,3}=String;
   end
   Logger=vertcat(Logger,DataVector);
   assignin('base','DataLog',Logger);
   Status=1;
end
