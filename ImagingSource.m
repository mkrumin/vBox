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
        defaultFrameRate = '30.0000';
        defaultExposure = -5;
        defaultFormat = 'Y800_640x480';
        defaultAdaptorName = 'winvideo';
        defaultCR = 10;
        memOnStart = []; % amount of memory this Matlab session was using at the beginning of current acquisition
        ramOnStart = []; % amount of RAM available at the beginning of current acquisition
    end
    
    methods
        function obj = ImagingSource(DeviceID)
            obj.vid = videoinput(obj.defaultAdaptorName, DeviceID, obj.defaultFormat);
            obj.src = getselectedsource(obj.vid);
%             obj.src.Strobe = 'Disable';
%             obj.src.Trigger = 'Disable';
            obj.src.ExposureMode = 'manual';
            obj.src.Exposure = obj.defaultExposure;
            obj.src.FrameRate = obj.defaultFrameRate;
            obj.src.GainMode = 'manual';
            obj.src.Gain = 1023;
            obj.src.Gamma = 100;
            
            obj.vid.ReturnedColorspace = 'grayscale';
            obj.vid.FramesPerTrigger = Inf;
            obj.vid.TriggerRepeat = 0;
            triggerconfig(obj.vid, 'immediate');
            
            fprintf('%s (DeviceID %d) camera had been initialized\n', ...
                'TheImagingSource', obj.vid.DeviceID);
            
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
            obj.src.Exposure = round(log2(1/fps));
        end
        
        function fps = getFrameRate(obj)
            fps = str2double(obj.src.FrameRate);
        end
        
        function setExposure(obj, expDur)
            fps = str2double(obj.src.FrameRate);
            % setting max possible exposure for the current frameRate
            maxExposure = round(log2(1/fps));

            if ~isempty(expDur)
                expInfo = propinfo(obj.src, 'Exposure');
                expLimits = expInfo.ConstraintValue;
%                 warning('off', 'spinnaker:propertySet');
                if expDur > min(maxExposure, expLimits(2)) 
                    fprintf('Requested exposure of 2^(%g) s is too long, setting it to 2^(%g) s\n', ...
                        expDur, min(maxExposure, expLimits(2)));
                    obj.src.Exposure = min(maxExposure, expLimits(2));
                elseif expDur < expLimits(1)
                    fprintf('Requested exposure of 2^(%g) s is too short, setting it to 2^(%g) s\n', ...
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
            
            [obj.hMeta, errorMsg] = fopen([fileBase, '_meta.bin'], 'w+');
            if (obj.hMeta == -1)
                warning('Failed to open %s file for writing embedded metadata\n', ...
                    [fileBase, '_meta.bin']);
                warning('System message: %s\n', errorMsg);
                warning('Will not start acquisition (will cause TimeOut)')
                return;
            end
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
            fclose(obj.hMeta);
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
            % Writing metadata embedded in the frame (camera times - precise)
            % First 4 bytes is timestamp, next 4 bytes - frameCounter
            embeddedData = squeeze(data(1, 1:8, 1, :));
            fwrite(obj.hMeta, embeddedData, 'uint8');
            % Logging the timing metadata, as received from getdata();
            % This is in computer time - less precise
            for iFrame = 1:nFrames
                s = meta(iFrame);
                fprintf(obj.hTimes, '[%d,%d,%d,%d,%d,%.5f]\t%d\t\t%d\t\t%d\t\t%.5f\r\n', ...
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
            % extract and process metadata embedded in the frames
            frewind(obj.hMeta);
            embeddedData = fread(obj.hMeta, '*uint8');
            embeddedData = reshape(embeddedData, 8, [])';
            frameCounter = embeddedData(:, 5:8);
            frameCounter = bsxfun(@times, int64(frameCounter), int64(256.^[3 2 1 0]));
            frameCounter = sum(frameCounter, 2);
            dFrames = diff(frameCounter);
            dFrames(dFrames<0) = dFrames(dFrames<0) + 2^32;
            frameCounter = [1; cumsum(dFrames)+1];
            timeData = int16(embeddedData(:, 1:4));
            seconds = int8(floor(timeData(:,1))/2);
            cycles = mod(timeData(:, 1), 2) * 2^12 + timeData(:, 2) * 2^4 + floor(timeData(:,3)/2^4);
            
            dSeconds = int16(diff(seconds));
            dSeconds(dSeconds<0) = dSeconds(dSeconds<0) + 128;
            
            dCycles = diff(cycles);
            dCycles(dCycles<0) = dCycles(dCycles<0) + 8000;
            dCycles(dSeconds==1) = dCycles(dSeconds==1) - 8000;
            
            timeStamp = [0; double(cumsum(dSeconds)) + double(cumsum(dCycles))/8000];
            
            embeddedData  = struct('frameCounter', frameCounter, 'timeStamp', timeStamp);
            
            % extract the software timing information
            % expected number of Frames
            nFrames = length(embeddedData.frameCounter);
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
            
            save(fullfile(fp, [fn, '_frameTimes']), 'embeddedData', 'softData');
            
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
