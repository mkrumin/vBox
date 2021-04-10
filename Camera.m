classdef Camera < handle
    
    properties
        vid
        src
        hPreview
        VW
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
            CR = 5; % compression ratio
            vw = VideoWriter(fileBase, 'Motion JPEG 2000');
            vw.FrameRate = obj.src.AcquisitionFrameRate;
            vw.LosslessCompression = false;
            vw.CompressionRatio = CR;
            vw.MJ2BitDepth = 8;
            vw2 = VideoWriter([fileBase, '_lastFrames'], 'Motion JPEG 2000');
            vw2.FrameRate = obj.src.AcquisitionFrameRate;
            vw2.LosslessCompression = false;
            vw2.CompressionRatio = CR;
            vw2.MJ2BitDepth = 8;
            obj.VW = vw2;
            obj.vid.LoggingMode = 'memory';
            obj.vid.DiskLogger = vw;
            %             obj.VW = vw;
            obj.vid.FramesAcquiredFcnCount = 100;
            obj.vid.FramesAcquiredFcn = @obj.grabFrames;
            obj.vid.StopFcn = @obj.grabFrames;
            obj.vid.TimerFcn = @obj.printStats;
            obj.vid.TimerPeriod = 10;
            %             % actually start acquisition
            if obj.src.AcquisitionFrameRate > 151
                fprintf('Stopping preview for fast fps\n');
                obj.stopPreview;
            end
            %             open(obj.VW);
            open(obj.vid.DiskLogger);
            warning off
            start(obj.vid);
            warning on
            % make sure it is running?
            
        end
        
        function stopAcquisition(obj)
            % stop acquisition
            stop(obj.vid);
            % confirm if stopped
            %             waitStr = '-\|/';
            %             i = 1;
            tic;
            nChar = 1;
            %             while (obj.vid.FramesAcquired ~= obj.vid.DiskLoggerFrameCount)
            %                 fprintf(repmat('\b', 1, nChar));
            %                 nChar = fprintf('(%g)', obj.vid.FramesAcquired - obj.vid.DiskLoggerFrameCount);
            % %                 fprintf('\b%s', waitStr(mod(i, 4)+1));
            %                 pause(.1)
            %
            %                 i = i+1;
            %                 if (obj.vid.FramesAcquired - obj.vid.DiskLoggerFrameCount <= 1)
            %                     pause(0.1)
            %                     break;
            %                 end
            %             end
            
            if (obj.vid.FramesAvailable > 0)
                fprintf('[%s] Waiting for logging to finish...', obj.vid.Tag);
                
                while (obj.vid.FramesAvailable > 0)
                    fprintf(repmat('\b', 1, nChar));
                    nChar = fprintf('(%g)', obj.vid.FramesAvailable);
                    obj.grabFrames(obj.vid);
                end
                fprintf(repmat('\b', 1, nChar));
                fprintf('.done (%g seconds)\n', toc);
            end
            fprintf('[%s] Acquired %g frames, logged %g + %g frames\n', ...
                obj.vid.Tag, obj.vid.FramesAcquired, ...
                get(obj.vid.DiskLogger, 'FrameCount'), get(obj.VW, 'FrameCount'))
            
            % clean up
            %             pause(1);
            %             close(obj.VW);
            %             obj.VW = [];
            delete(obj.vid.DiskLogger);
            obj.vid.DiskLogger = [];
            if obj.src.AcquisitionFrameRate > 151
                fprintf('Resuming preview\n');
                obj.startPreview(obj.hPreview);
            end
        end
        
        function grabFrames(obj, src, eventData)
            % this function will run every FramesAcquiredFcnCount frames
%             fprintf('[%s] FramesAcquired = %g, FramesLogged = %g\n', ...
%                 src.Tag, src.FramesAcquired, get(src.DiskLogger, 'FrameCount'));
            tic
            nFrames = src.FramesAvailable;
            [data, t, meta] = getdata(src, nFrames);
%             fprintf('Pulled %d frames from memory in %5.3f seconds\n', nFrames, toc);
            tic;
            %             writeVideo(obj.VW, data);
            if isequal(src.Logging, 'on')
                writeVideo(src.DiskLogger, data);
%                 fprintf('Logged %d frames to disk in %5.3f seconds\n', nFrames, toc);
            else
%                 fprintf('Logging to the main file was off\n');
                open(obj.VW);
                writeVideo(obj.VW, data)
%                 fprintf('Logged %d frames to file %s in %5.3f seconds\n', ...
%                     nFrames, get(obj.VW, 'FileName'), toc);
                close(obj.VW);
            end
        end
        
        function printStats(obj, src, eventData)
            fprintf('\n[%s] FramesAcquired = %g, FramesLogged = %g, FramesAvailable = %g\n\n', ...
                src.Tag, src.FramesAcquired, get(src.DiskLogger, 'FrameCount'), src.FramesAvailable);
            
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
