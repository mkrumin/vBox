function list = camConfig()

% This is a sample function. Do not use it as is.
% Create a copy in your path outside of this repository, rename it to
% camConfig.m and edit according to the cameras you have and to the desired
% acquisition parameters.

% list = camConfigList() will create a list of camera configurations
% list - structure array with the following fields
%   Name : camera nickname, a string that will be used for file naming
%   DeviceSerialNumber : Unique ID of the camera. It is a string for FLIR
%       pointgrey cameras. Might be of a different type of other cameras
%   FrameRate : Desired framerate in fps. Default - 30 fps. 
%       In reality might be slightly off, depending on camera.
%   Exposure : Exposure in microseconds. Default will be the maximum 
%       possible for the current FrameRate.
%   LocalPort : Local port number for UDP communication with master (master
%       should send communication to this port number). Default - 1001.
%   CompressionRatio : Control the filesize vs. quality. Set to 0 for 
%       lossless compression. Default - 10. Also has an effect on CPU load,
%       so test this value for fast frame rates.
%   liveViewOn : {true, false} Default - true. Controls whether the video
%       live preview will be running during the acquisition. For some fast 
%       framerate acquisitions it might be beneficial to set it to 'false'. 
%       Based on experience with sepcific setup
%   copyToServer : {true, false} Default - false. Set to true, if you want 
%       to immediately copy all the files to the remote data repository at 
%       the end of each acquisition. Consider network speed. Camera will 
%       only echo UDPs after copying is finished, on slow connectins (or 
%       large files) the master host might time out waiting for the response.
%   cameraClass : (Not implemented yet) - will be used to use cameras other
%       than FLIR pointgrey cameras. Will require writing a separate class 
%       for these cameras. Currently @Camera is the only class available.

list = struct;

i = 1;
list(i).Name = 'bellyCam'; 
list(i).DeviceSerialNumber = '19462577';
list(i).FrameRate = 60;
list(i).LocalPort = 1001;
list(i).CompressionRatio = 5;

i = i+1;
list(i).Name = 'bodyCam';
list(i).DeviceSerialNumber = '19462583';
list(i).FrameRate = 150;
list(i).LocalPort = 1002;
list(i).CompressionRatio = 5;
