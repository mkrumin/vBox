function forceStartAllCameras(ExpRef)

% will start recording for all cameras defined in camConfig.m
% useful whent the ExpStart UDP was missed for whatever reason or when
% debugging cameras whitout the need to run full experiment

[subject, date, seq] = dat.expRefToMpep(ExpRef);
msg = sprintf('ExpStart %s %d %d', subject, date, seq);
camList = camConfig;

u = udp(myIP);
fopen(u);
for iCam = 1:numel(camList)
    u.RemotePort = camList(iCam).LocalPort;
    fwrite(u, msg);
end
fclose(u);
delete(u);
