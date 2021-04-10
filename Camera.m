classdef Camera < handle
    
    properties
        vid
        src
        hPreview
        VW
        hMeta
        hTimes
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
        
        function allGood = startAcquisition(obj, fileBase)
            % define acquisition parameters
            allGood = false;
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
            obj.vid.FramesAcquiredFcnCount = 100;
            obj.vid.FramesAcquiredFcn = @obj.grabFrames;
            obj.vid.StopFcn = @obj.grabFrames;
            obj.vid.TimerFcn = @obj.printStats;
            obj.vid.TimerPeriod = 10;
            
            [obj.hMeta, errorMsg] = fopen([fileBase, '_meta.bin'], 'w+');
            if (obj.hMeta == -1)
                warning('Failed to open %s file for writing embedded metadata\n', ...
                    [fileBase, '_meta.bin']);
                warning('System message: %s\n', errorMsg);
                warning('Will not start acquisition (will cause TimeOut)')
                return;
            end
            obj.hTimes = fopen([fileBase, '_times.txt'], 'at+');
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
            warning off
            start(obj.vid);
            warning on
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
            fprintf('\n[%s] FramesAcquired = %g, FramesLogged = %g, FramesAvailable = %g\n\n', ...
                src.Tag, src.FramesAcquired, get(src.DiskLogger, 'FrameCount'), src.FramesAvailable);
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
