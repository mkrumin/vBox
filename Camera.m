classdef Camera < handle
    
    properties 
        Tag = '';
        FrameRate
        vid
        src
    end
    
    properties(Access = private)
        defaultFrameRate = 30;
        defaultFormat = 'Mono8_Mode1';
    end
    
    methods
        function obj = Camera(adaptorName, deviceID, videoFormat)
            hw = imaqhwinfo(adaptorName, deviceID);
            if nargin > 2
                obj.vid = videoinput(adaptorName, deviceID, videoFormat);
            else
                obj.vid = videoinput(adaptorName, deviceID, obj.defaultFormat);
            end
            obj.src = getselectedsource(obj.vid);
            obj.Tag = 'bellyCam';
            obj.src.AcquisitionFrameRate = obj.defaultFrameRate;
            obj.FrameRate = obj.src.AcquisitionFrameRate;
        end
        
        function h = startPreview(obj, h)
            if nargin >= 2
                h = preview(obj.vid, h);
            else
               h = preview(obj.vid);
            end
        end
        
        function stopPreview(obj)
            stoppreview(obj.vid)
        end
        
        function closePreview(obj)
            closepreview(obj.vid)
        end
        
        function startAcquisition(obj)
        end
        
        function stopAcquisition(obj)
        end
        
        function delete(obj)
            delete(obj.vid);
        end
    end
    
    events
    end
    
%     enumeration
%     end
    
end
