classdef ImagingSource < handle
    
    properties
        vid
        src
        hPreview
        VW
        hMeta
        hTimes
    end
    
    properties(Access = private)
        defaultFrameRate = '30.00';
        defaultExposure = 0.0333;
        defaultFormat = 'Y800 (640x480)';
        defaultAdaptorName = 'tisimaq_r2013_64';
        defaultCR = 10;
        memOnStart = []; % amount of memory this Matlab session was using at the beginning of current acquisition
        ramOnStart = []; % amount of RAM available at the beginning of current acquisition
    end
    
    methods
        function obj = ImagingSource(SerialNumber)
            hw = imaqhwinfo(obj.defaultAdaptorName);
            nCams = length(hw.DeviceIDs);
            if nargin > 0
                for iCam = 1:nCams
                    obj.vid = videoinput(obj.defaultAdaptorName, hw.DeviceIDs{iCam}, obj.defaultFormat);
                    obj.src = getselectedsource(obj.vid);
                    if isequal(obj.src.SerialNo, SerialNumber)
                        break; % correct camera found - break from the loop
                    end
                end
                if ~isequal(obj.src.SerialNo, SerialNumber)
                    delete(obj);
                    warning('Requested camera with SN ''%s'' not found', SerialNumber);
                    warning('No camera was initialized')
                    return;
                end
            else
                obj.vid = videoinput(obj.defaultAdaptorName, hw.DeviceIDs{1}, obj.defaultFormat);
                obj.src = getselectedsource(obj.vid);
            end

            obj.src.Brightness = 0;
            obj.src.ExposureAuto = 'Off';
            obj.src.Exposure = obj.defaultExposure;
            obj.src.FrameRate = obj.defaultFrameRate;
            obj.src.GainAuto = 'off';
            obj.src.Gain = 1023;
            obj.src.Gamma = 100;
            obj.src.Strobe = 'Disable';
            obj.src.Trigger = 'Disable';
            
            obj.vid.FramesPerTrigger = Inf;
            obj.vid.TriggerRepeat = 0;
%             triggerconfig(obj.vid, 'immediate');
            
            fprintf('%s (SN %d) camera had been initialized\n', ...
                'TheImagingSource', obj.src.SerialNo);
            
        end
        
        function fps = setFrameRate(obj, frameRate)
            warning('off', 'spinnaker:propertySet');
            frInfo = propinfo(obj.src, 'FrameRate');
            frOptions = frInfo.ConstraintValue;
            frNums = cellfun(@str2num, frOptions);
            [~, ind] = min((frNums - frameRate).^2);
            obj.src.FrameRate = frInfo.ConstraintValue{ind};

            fps = str2double(obj.src.FrameRate);
            % setting max possible exposure for the current frameRate
            obj.src.Exposure = floor(1/fps*1e4)/1e4;
        end
        
        function fps = getFrameRate(obj)
            fps = str2double(obj.src.FrameRate);
        end
        
        function setExposure(obj, expDur)
            fps = str2double(obj.src.FrameRate);
            % setting max possible exposure for the current frameRate
            maxExposure = floor(1/fps*1e4)/1e4;

            if ~isempty(expDur)
                expInfo = propinfo(obj.src, 'Exposure');
                expLimits = expInfo.ConstraintValue;
%                 warning('off', 'spinnaker:propertySet');
                if expDur > min(maxExposure, expLimits(2)) 
                    fprintf('Requested exposure of %g s is too long, setting it to %g s\n', ...
                        expDur, min(maxExposure, expLimits(2)));
                    obj.src.Exposure = min(maxExposure, expLimits(2));
                elseif expDur < expLimits(1)
                    fprintf('Requested exposure of %g s is too short, setting it to %g s\n', ...
                        expDur, expLimits(1));
                    obj.src.Exposure = expLimits(1);
                else
                    obj.src.Exposure = expDur;
                end
%                 warning('on', 'spinnaker:propertySet');
            end
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
        
        function allGood = startAcquisition(obj, fileBase, CR)
            % define acquisition parameters
            allGood = false;
            if nargin < 3 || isempty(CR)
                CR = obj.defaultCR;
            end
            vw = VideoWriter(fileBase, 'Motion JPEG 2000');
            vw.FrameRate = str2double(obj.src.FrameRate);
            vw.MJ2BitDepth = 8;
            vw2 = VideoWriter([fileBase, '_lastFrames'], 'Motion JPEG 2000');
            vw2.FrameRate = str2double(obj.src.FrameRate);
            vw2.MJ2BitDepth = 8;
            if CR == 0
                vw.LosslessCompression = true;
                vw2.LosslessCompression = true;
            else
                vw.LosslessCompression = false;
                vw.CompressionRatio = CR;
                vw2.LosslessCompression = false;
                vw2.CompressionRatio = CR;
            end
            obj.VW = vw2;
            obj.vid.LoggingMode = 'memory';
            obj.vid.DiskLogger = vw;
            obj.vid.FramesAcquiredFcnCount = 100;
            obj.vid.FramesAcquiredFcn = @obj.grabFrames;
            obj.vid.StopFcn = @obj.grabFrames;
            obj.vid.TimerFcn = @obj.printStats;
            obj.vid.TimerPeriod = 30;
            
            obj.hTimes = fopen([fileBase, '_times.txt'], 'wt+');
            if (obj.hTimes == -1)
                warning('Failed to open %s file for logging timing metadata\n', ...
                    [fileBase, '_times.txt']);
                warning('System message: %s\n', errorMsg);
                warning('Will not start acquisition (will cause TimeOut)');
                return;
            end
            fprintf(obj.hTimes, ...
                'AbsTime\t\t\t\tFrameNumber\tRelativeFrame\tTriggerIndex\tTime\r\n');
            
            % actually start acquisition
            open(obj.vid.DiskLogger);
            fprintf('Starting acquisition...\n');
            fprintf('The following warning about DiskLogger ... ''memory'' ... ''disk'' ... ''disk&memory'' is OK\n');
            warning off
            start(obj.vid);
            warning on
            % Immediately print stats to get inital memory values
            obj.printStats;
            
            % TODO Make sure it is running? How?
            allGood = true;
        end
        
        function stopAcquisition(obj)
            % stop acquisition
            stop(obj.vid);
            if (obj.vid.FramesAvailable > 0)
                % should never get here
                tic;
                nChar = 1;
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
            
            % postprocessing of metadata
            % this will save the  *_frameTime.mat file
            obj.processMetadata;
            
            % clean up
            fclose(obj.hTimes);
            delete(obj.vid.DiskLogger);
            obj.vid.DiskLogger = [];
            delete(obj.VW);
            obj.VW = [];
            obj.memOnStart = [];
            obj.ramOnStart = [];
        end
        
        function grabFrames(obj, src, eventData)
            % this function will run every FramesAcquiredFcnCount frames
            nFrames = src.FramesAvailable;
            [data, t, meta] = getdata(src, nFrames);
            if isequal(src.Logging, 'on')
                writeVideo(src.DiskLogger, data);
            else
                open(obj.VW);
                writeVideo(obj.VW, data)
                close(obj.VW);
            end

            % Logging the timing metadata, as received from getdata();
            % This is in computer time - less precise
            for iFrame = 1:nFrames
                s = meta(iFrame);
                fprintf(obj.hTimes, '[%d,%d,%d,%d,%d,%.5f]\t%d\t\t%d\t\t%d\t\t%.5f\r', ...
                    s.AbsTime, s.FrameNumber, s.RelativeFrame, s.TriggerIndex, t(iFrame));
            end
            
        end
        
        function printStats(obj, src, eventData)
            try
                fprintf('[%s] FramesAcquired = %g, FramesLogged = %g, FramesAvailable = %g\n', ...
                    src.Tag, src.FramesAcquired, get(src.DiskLogger, 'FrameCount'), src.FramesAvailable);
            catch
                fprintf('[%s] FramesAcquired = %g, FramesLogged = %g, FramesAvailable = %g\n', ...
                    obj.vid.Tag, obj.vid.FramesAcquired, get(obj.vid.DiskLogger, 'FrameCount'), obj.vid.FramesAvailable);
            end
            [usr, sys] = memory;
            if isempty(obj.memOnStart)
                % initialize persistent variables on the first run
                obj.memOnStart = usr.MemUsedMATLAB;
                obj.ramOnStart = sys.PhysicalMemory.Available;
            end
            fprintf('\tMemory: Matlab uses %4.2fGB (%3.1f%%), Available RAM %4.2fGB (%3.1f%%)\n',...
                usr.MemUsedMATLAB/1024^3, usr.MemUsedMATLAB/obj.memOnStart*100, ...
                sys.PhysicalMemory.Available/1024^3, ...
                sys.PhysicalMemory.Available/obj.ramOnStart*100);
        end
        
        function processMetadata(obj)
            
            % extract the software timing information from txt log files
            % expected number of Frames
            nFrames = obj.vid.FramesAcquired;
            absTime = nan(nFrames, 1);
            frameNumber = nan(nFrames, 1);
            frameTime = nan(nFrames, 1);
            frewind(obj.hTimes);
            textLine = fgetl(obj.hTimes); % this is title line
            iFrame = 0;
            while ~feof(obj.hTimes)
                textLine = fgetl(obj.hTimes);
                if ~isempty(textLine) && ~isequal(textLine, -1)
                    iFrame = iFrame +1;
                    tmp = str2num(textLine);
                    absTime(iFrame) = datenum(tmp(1:6));
                    frameNumber(iFrame) = tmp(7);
                    frameTime(iFrame) = tmp(10);
                end
            end
            
            softData = struct('absTime', absTime, ...
                'frameNumber', frameNumber, ...
                'frameTime', frameTime);
            
            % A hacky way to figure out what is the filename
            [~, fn, ~] = fileparts(get(obj.vid.DiskLogger, 'FileName'));
            fp = get(obj.vid.DiskLogger, 'Path');
            
            save(fullfile(fp, [fn, '_frameTimes']), 'softData');
            
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
