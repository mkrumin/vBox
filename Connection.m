classdef Connection < handle
    
    properties
        LocalPort
        Tag
        udpObj
        ExpRef
        cameraObj
    end
    
    properties(Access = private)
        defaultLocalPort = 1001;
    end
    
    methods
        function obj = Connection(tag)
            camList = camConfigList;
            if nargin > 0 && ~isempty(tag)
                camIndex = find(ismember({camList.Tag}, tag));
                if isempty(camIndex)
                    fprintf('Camera ''%s'' is not in the list of available cameras\n', tag)
                    fprintf('Available cameras are: \n');
                    for iCam = 1:length(camList)
                        fprintf('''%s''\n', camList(iCam).Tag);
                    end
                    fprintf('Will initialize camera ''%s'' (Serial Number %s)\n', ...
                        camList(1).Tag, camList(1).DeviceSerialNumber)
                    camIndex = 1;
                end
            else
                fprintf('No camera name provided, will initialize camera ''%s'' (Serial Number %s)\n', ...
                    camList(1).Tag, camList(1).DeviceSerialNumber)
                camIndex = 1;
            end
            camParams = camList(camIndex);
            fprintf('Setting up UDP communication..\n')
            [LocalIP, LocalHost] = myIP;
            
            if isfield(camParams, 'LocalPort')
                obj.udpObj = udp('0.0.0.0', 1, 'LocalPort', camParams.LocalPort);
            else
                obj.udpObj = udp('0.0.0.0', 1, 'LocalPort', obj.defaultLocalPort);
            end
            fprintf('Camera ''%s'' will listen on IP %s (aka ''%s''), port %d\n', ...
                camParams.Tag, LocalIP, LocalHost, obj.udpObj.LocalPort);
            obj.udpObj.DatagramReceivedFcn = @obj.udpCallback;
            fopen(obj.udpObj);
        end
        
        function udpCallback(obj, src, eventData)
            
            timestamp = clock;
            timeStampStr = sprintf('[%s %s]', obj.Tag, datestr(timestamp, 'HH:MM:SS.FFF'));
            
            RemoteIP=obj.udpObj.DatagramAddress;
            RemotePort=obj.udpObj.DatagramPort;
            % these are ne for proper echo
            obj.udpObj.RemoteHost=RemoteIP;
            obj.udpObj.RemotePort=RemotePort;
            receivedData=fread(obj.udpObj);
            str=char(receivedData');
            fprintf('%s Received ''%s'' from %s:%d\n', timeStampStr, str, RemoteIP, RemotePort);
            %             fwrite(obj.udpObj, receivedData);
            
            info=dat.mpepMessageParse(str);
            
            switch info.instruction
                case 'hello'
                    fwrite(obj.udpObj, receivedData);
                case 'ExpStart'
                    fwrite(obj.udpObj, receivedData); % echo after completing required actions
                case {'ExpEnd', 'ExpInterrupt'}
                    fwrite(obj.udpObj, receivedData); % echo after completing required actions
                case 'alyx' % recieved Alyx instance
                    fwrite(obj.udpObj, receivedData);
                case 'BlockStart'
                    fwrite(obj.udpObj, receivedData);
                case 'BlockEnd'
                    fwrite(obj.udpObj, receivedData);
                case 'StimStart'
                    fwrite(obj.udpObj, receivedData);
                case 'StimEnd'
                    fwrite(obj.udpObj, receivedData);
                otherwise
                    fprintf('Unknown instruction : %s', info.instruction);
                    fwrite(obj.udpObj, receivedData);
            end
        end
        
        function delete(obj)
            fclose(obj.udpObj);
            delete(obj.udpObj);
        end
    end
end