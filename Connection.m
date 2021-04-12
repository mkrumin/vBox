classdef Connection < handle
    
    properties
        Name
        SerialNumber
        udpObj
        udpLogFile = [];
        ExpRef = '';
        cameraObj
        camPars
    end
    
    properties(Access = private)
        defaultVals = struct('FrameRate', 30, 'Exposure', [], ...
            'LocalPort', 1001, 'liveViewOn', true, 'copyToServer', false, ...
            'CompressionRatio', 10);
    end
    
    methods
        function obj = Connection(name)
            camList = camConfig;
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
            obj.camPars = camList(camIndex);
            % apply default values to non-existent fields 
            f = fieldnames(obj.defaultVals);
            for i = 1:length(f)
                if ~isfield(obj.camPars, f{i}) || isempty(obj.camPars.(f{i}))
                    obj.camPars.(f{i}) = obj.defaultVals.(f{i});
                end
            end
            obj.Name = obj.camPars.Name;
            obj.SerialNumber = obj.camPars.DeviceSerialNumber;
            
            fprintf('Setting up UDP communication..\n')
            [LocalIP, LocalHost] = myIP;
            
            obj.udpObj = udp('0.0.0.0', 1);
            obj.udpObj.LocalPort = obj.camPars.LocalPort;
            fprintf('Camera ''%s'' (SN: %s) will be listening on IP %s (aka ''%s''), port %d\n', ...
                obj.camPars.Name, obj.camPars.DeviceSerialNumber, LocalIP, LocalHost, obj.udpObj.LocalPort);
            obj.udpObj.DatagramReceivedFcn = @obj.udpCallback;
            fopen(obj.udpObj);
            
            fprintf('Setting up ''%s'' camera...\n', obj.Name)
            obj.cameraObj = Camera(obj.SerialNumber);
            obj.cameraObj.vid.Tag = obj.Name;
            fps = obj.cameraObj.setFrameRate(obj.camPars.FrameRate);
            if ~isempty(obj.camPars.Exposure)
                obj.cameraObj.setExposure(obj.camPars.Exposure);
            end
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
                        warning('Failed to open %s, exiting...\n', fileName);
                        warning('System message: %s\n', errMsg)
                        return;
                    else
                        fprintf('Opened %s for logging UDPs\n', fileName);
                    end
                    obj.logUDP(timestamp, char(receivedData'));
                    
                    % start camera acquisition
                    if ~obj.camPars.liveViewOn
                        stopPreview(obj.cameraObj);
                    end
                    success = obj.cameraObj.startAcquisition(fullfile(localDataFolder, fileBase), ...
                        obj.camPars.CompressionRatio);
                    
                    if success
                        fwrite(obj.udpObj, receivedData); % echo after completing required actions
                    end % otherwise mc/mpep will TimeOut
                case {'ExpEnd', 'ExpInterrupt'}
                    fclose(obj.udpLogFile);
                    obj.udpLogFile = [];
                    % stop camera acquisition
                    obj.cameraObj.stopAcquisition();
                    if ~obj.camPars.liveViewOn
                        startPreview(obj.cameraObj);
                    end
                    if obj.camPars.copyToServer
                        localFolder = dat.expPath(obj.ExpRef, 'local', 'master');
                        wildcard = sprintf('*%s*', obj.Name);
%                         files = dir(fullfile(localFolder, wildcard));
                        remoteFolder = dat.expPath(obj.ExpRef, 'main', 'master');
                        success = 1;
                        if ~exist(remoteFolder, 'dir')
                            [success, errMsg] = mkdir(remoteFolder);
                            if success
                                fprintf('Folder %s successfully created\n', remoteFolder)
                            else
                                warning('There was a problem creating folder %s\n', remoteFolder)
                                warning('System message: %s\n', errMsg);
                                warning('You will need to copy files manually\n')
                            end
                        end
                        if success
                            fprintf('[%s] Copying files to server..', obj.Name);
                            tic;
                            [success, errMsg] = ...
                                copyfile(fullfile(localFolder, wildcard), remoteFolder);
                            if success
                                fprintf('.done (%g seconds)\n', toc);
                            else
                                fprintf('.failed\n');
                                printf('System message: %s', errMsg)
                                warning('Check data integrity and copy files manually\n')
                            end
                        end

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
            delete(obj.cameraObj)
        end
    end
end