classdef Camera < handle
    
    properties 
        vid
        src
        hPreview
    end
    
    properties(Access = private)
        defaultFrameRate = 30;
        defaultFormat = 'Mono8_Mode1';
        defaultAdaptorName = 'mwspinnakerimaq';
    end
    
    methods
        function obj = Camera(SerialNumber)
            hw = imaqhwinfo(obj.defaultAdaptorName);
            nCams = length(hw.DeviceIDs);
            if nargin > 0
                for iCam = 1:nCams
                    obj.vid = videoinput(obj.defaultAdaptorName, hw.DeviceIDs{iCam}, obj.defaultFormat);
                    obj.src = getselectedsource(obj.vid);
                    if isequal(obj.src.DeviceSerialNumber, SerialNumber)
                        break; % correct camera found - break from the loop
                    end
                end
                if ~isequal(obj.src.DeviceSerialNumber, SerialNumber)
                    delete(obj);
                    warning('Requested camera with SN ''%s'' not found', SerialNumber);
                    warning('No camera was initialized')
                    return;
                end
            else
                obj.vid = videoinput(obj.defaultAdaptorName, hw.DeviceIDs{1}, obj.defaultFormat);
                obj.src = getselectedsource(obj.vid);
            end
            warning('off', 'spinnaker:propertySet');
            obj.src.AcquisitionFrameRateEnabled = 'True';
            obj.src.AcquisitionFrameRateAuto = 'Off';
            obj.src.AcquisitionFrameRate = obj.defaultFrameRate;
            obj.src.ExposureAuto = 'Off';
            obj.src.ExposureMode = 'Timed';
            % setting max possible exposure
            exposureInfo = propinfo(obj.src, 'ExposureTime');
            obj.src.ExposureTime = exposureInfo.ConstraintValue(2);
            obj.src.BlackLevel = 0;
            obj.src.SharpnessEnabled = 'True';
            obj.src.SharpnessAuto = 'Off';
            obj.src.Sharpness = 1024;
            obj.src.GainAuto = 'Off';
            obj.src.Gain = 0;
            warning('on', 'spinnaker:propertySet');
            
            obj.vid.FramesPerTrigger = Inf;
            obj.vid.TriggerRepeat = 0;
            
            fprintf('%s (DeviceID %d) camera had been initialized\n', ...
                obj.src.DeviceModelName, obj.vid.DeviceID); 
            
        end
        
        function fps = setFrameRate(obj, frameRate)
            warning('off', 'spinnaker:propertySet');
            obj.src.AcquisitionFrameRate = frameRate;
            exposureInfo = propinfo(obj.src, 'ExposureTime');
            % setting max possible exposure for the current frameRate
            obj.src.ExposureTime = exposureInfo.ConstraintValue(2);
            warning('on', 'spinnaker:propertySet');
            fps = obj.src.AcquisitionFrameRate;
        end
        
        function startPreview(obj, h)
            if nargin >= 2
                obj.hPreview = preview(obj.vid, h);
            else
               obj.hPreview = preview(obj.vid);
            end
        end
        
        function stopPreview(obj)
            stoppreview(obj.vid)
        end
        
        function closePreview(obj)
            closepreview(obj.vid)
        end
        
        function startAcquisition(obj, fileBase)
            % define acquisition parameters
            vw = VideoWriter(fileBase, 'Motion JPEG 2000');
            vw.FrameRate = obj.src.AcquisitionFrameRate;
            vw.LosslessCompression = false;
            vw.CompressionRatio = 10;
            vw.MJ2BitDepth = 8;
            obj.vid.DiskLogger = vw;
            obj.vid.LoggingMode = 'disk';
            obj.vid.FramesAcquiredFcnCount = 1000;
            obj.vid.FramesAcquiredFcn = @obj.grabFrames;
%             % actually start acquisition
%             fprintf('Stopping preview for fast fps\n');
%             obj.stopPreview;
            start(obj.vid);
            % make sure it is running?
            
        end
        
        function stopAcquisition(obj)
            % stop acquisition
            stop(obj.vid);
            % confirm if stopped
            fprintf('[%s] Waiting for logging to finish...', obj.vid.Tag);
            waitStr = '-\|/';
            i = 1;
            tic;
            nChar = 1;
            while (obj.vid.FramesAcquired ~= obj.vid.DiskLoggerFrameCount)
                fprintf(repmat('\b', 1, nChar));
                nChar = fprintf('(%g)', obj.vid.FramesAcquired - obj.vid.DiskLoggerFrameCount);
%                 fprintf('\b%s', waitStr(mod(i, 4)+1));
                pause(.1)
                
                i = i+1;
                if (obj.vid.FramesAcquired - obj.vid.DiskLoggerFrameCount <= 1)
                    pause(0.1)
                    break;
                end
            end
            fprintf(repmat('\b', 1, nChar));
            fprintf('.done (%g seconds)\n', toc);
            fprintf('[%s] Acquired %g frame, logged %g frames\n', ...
                obj.vid.Tag, obj.vid.FramesAcquired, obj.vid.DiskLoggerFrameCount)

            % clean up
            delete(obj.vid.DiskLogger);
            obj.vid.DiskLogger = [];
%             fprintf('Resuming preview\n');
%             obj.startPreview(obj.hPreview);
        end
        
        function grabFrames(obj, src, eventData)
            % this function will run every FramesAcquiredFcnCount frames
            fprintf('[%s] FramesAcquired = %g, FramesLogged = %g\n', ...
                obj.vid.Tag, obj.vid.FramesAcquired, obj.vid.DiskLoggerFrameCount);
        end
        
        function delete(obj)
            fprintf('Camera destuructor called, will close the preview and delete the object now\n');
            closepreview(obj.vid)
            delete(obj.vid);
        end
    end
    
    events
    end
    
%     enumeration
%     end
    
end
