function list = camConfigList()

list = struct;
i = 1;
list(i).Tag = 'bellyCam';
list(i).DeviceSerialNumber = '19462577';
list(i).FrameRate = 30;
list(i).LocalPort = 1001;

i = i+1;
list(i).Tag = 'bodyCam';
list(i).DeviceSerialNumber = '19462583';
list(i).FrameRate = 30;
list(i).LocalPort = 1002;