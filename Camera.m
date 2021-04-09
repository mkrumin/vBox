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
            fprintf('%s camera had been initialized, running at %5.3f fps\n', ...
                obj.src.DeviceModelName, obj.src.AcquisitionFrameRate); 
            
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
        
        function startAcquisition(obj, fileName)
            
        end
        
        function stopAcquisition(obj)
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
