function list = camConfigList()

list = struct;
i = 1;
list(i).Name = 'bellyCam';
list(i).DeviceSerialNumber = '19462577';
list(i).FrameRate = 150;
list(i).LocalPort = 1001;

i = i+1;
list(i).Name = 'bodyCam';
list(i).DeviceSerialNumber = '19462583';
list(i).FrameRate = 150;
list(i).LocalPort = 1002;