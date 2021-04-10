classdef Connection < handle
    
    properties
        Name
        SerialNumber
        udpObj
        udpLogFile = [];
        ExpRef = '';
        cameraObj
    end
    
    properties(Access = private)
        defaultLocalPort = 1001;
    end
    
    methods
        function obj = Connection(name)
            camList = camConfigList;
            if nargin > 0 && ~isempty(name)
                camIndex = find(ismember({camList.Name}, name));
                if isempty(camIndex)
                    fprintf('Camera ''%s'' is not in the list of available cameras\n', name)
                    fprintf('Available cameras are: \n');
                    for iCam = 1:length(camList)
                        fprintf('''%s''\n', camList(iCam).Name);
                    end
                    fprintf('Will initialize camera ''%s'' (SN: %s)\n', ...
                        camList(1).Name, camList(1).DeviceSerialNumber)
                    camIndex = 1;
                end
            else
                fprintf('No camera name provided, will initialize camera ''%s'' (SN: %s)\n', ...
                    camList(1).Name, camList(1).DeviceSerialNumber)
                camIndex = 1;
            end
            camParams = camList(camIndex);
            obj.Name = camParams.Name;
            obj.SerialNumber = camParams.DeviceSerialNumber;
            
            fprintf('Setting up UDP communication..\n')
            [LocalIP, LocalHost] = myIP;
            
            obj.udpObj = udp('0.0.0.0', 1);
            if isfield(camParams, 'LocalPort')
                obj.udpObj.LocalPort = camParams.LocalPort;
            else
                obj.udpObj.LocalPort =  obj.defaultLocalPort;
            end
            fprintf('Camera ''%s'' (SN: %s) will be listening on IP %s (aka ''%s''), port %d\n', ...
                camParams.Name, camParams.DeviceSerialNumber, LocalIP, LocalHost, obj.udpObj.LocalPort);
            obj.udpObj.DatagramReceivedFcn = @obj.udpCallback;
            fopen(obj.udpObj);
            
            fprintf('Setting up ''%s'' camera...\n', obj.Name)
            obj.cameraObj = Camera(obj.SerialNumber);
            obj.cameraObj.vid.Tag = obj.Name;
            fps = obj.cameraObj.setFrameRate(camParams.FrameRate);
            fprintf('''%s'' camera is now running at %5.3f fps\n', obj.Name, fps);
            
            startPreview(obj.cameraObj);
        end
        
        function udpCallback(obj, src, eventData)
            
            timestamp = clock;
            timeStampStr = sprintf('[%s %s]', obj.Name, datestr(timestamp, 'HH:MM:SS.FFF'));
            
            RemoteIP=obj.udpObj.DatagramAddress;
            RemotePort=obj.udpObj.DatagramPort;
            % these are ne for proper echo
            obj.udpObj.RemoteHost=RemoteIP;
            obj.udpObj.RemotePort=RemotePort;
            receivedData=fread(obj.udpObj);
            str=char(receivedData');
            obj.logUDP(timestamp, str);
            fprintf('%s Received ''%s'' from %s:%d\n', timeStampStr, str, RemoteIP, RemotePort);
            %             fwrite(obj.udpObj, receivedData);
            
            info=dat.mpepMessageParse(str);
            
            switch info.instruction
                case 'hello'
                    fwrite(obj.udpObj, receivedData);
                case 'ExpStart'
                    obj.ExpRef = info.expRef;
                    localDataFolder = dat.expPath(obj.ExpRef, 'local', 'master');
                    fileBase = sprintf('%s_%s', obj.ExpRef, obj.Name);
                    if ~exist(localDataFolder, 'dir')
                        [success, errMsg] = mkdir(localDataFolder);
                        if success
                            fprintf('Folder %s successfully created\n', localDataFolder)
                        else
                            warning('There was a problem creating folder %s\n', localDataFolder)
                            warning('System message: %s\n', errMsg);
                            return; % this will crash the master host on timeout, 
                            % but will not disable DatagramReceivedFun of the udp
                        end
                    end
                    fileName = fullfile(localDataFolder, [fileBase, '_UDPLog.txt']);
                    [obj.udpLogFile, errMsg] = fopen(fileName, 'at');
                    if (obj.udpLogFile == -1)
                        fprintf('Failed to open %s, exiting...\n', fileName);
                        return;
                    else
                        fprintf('Opened %s for logging UDPs\n', fileName);
                    end
                    obj.logUDP(timestamp, char(receivedData'));
                    
                    % start camera acquisition
                    obj.cameraObj.startAcquisition(fullfile(localDataFolder, fileBase));
                    
                    fwrite(obj.udpObj, receivedData); % echo after completing required actions
                case {'ExpEnd', 'ExpInterrupt'}
                    fclose(obj.udpLogFile);
                    obj.udpLogFile = [];
                    % stop camera acquisition
                    try
                        obj.cameraObj.stopAcquisition();
                    catch
                    end
                    obj.ExpRef = '';
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
        
        function logUDP(obj, tStamp, msg)
            if ~isempty(obj.udpLogFile)
                fprintf(obj.udpLogFile, '[%s] ''%s'' from %s:%d\r\n', ...
                    datestr(tStamp, 'YYYY-mm-dd HH:MM:SS.FFF'), ...
                    msg, obj.udpObj.RemoteHost, obj.udpObj.RemotePort);
            end
            
        end
        
        function resetUDP(obj)
            fclose(obj.udpObj);
            fopen(obj.udpObj);
        end
        
        function delete(obj)
            fprintf('Destructor of Connection class called, will release the UDP port\n');
            if ~isempty(obj.udpObj)
                fclose(obj.udpObj);
                delete(obj.udpObj);
            end
            if ~isempty(obj.udpLogFile)
                fclose(obj.udpLogFile);
                obj.udpLogFile = [];
            end
        end
    end
end