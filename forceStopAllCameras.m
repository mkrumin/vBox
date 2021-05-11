function forceStopAllCameras()

% will stop recording for all cameras defined in camConfig.m
% useful whent the ExpEnd UDP was missed for whatever reason or when
% debugging cameras whitout the need to run full experiment

fakeExpRef = '1900-01-01_1_Forced';
[subject, date, seq] = dat.expRefToMpep(fakeExpRef);
msg = sprintf('ExpEnd %s %d %d', subject, date, seq);
camList = camConfig;

u = udp(myIP);
fopen(u);
for iCam = 1:numel(camList)
    u.RemotePort = camList(iCam).LocalPort;
    fwrite(u, msg);
end
fclose(u);
delete(u);
