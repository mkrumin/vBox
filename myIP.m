function [ipString, hostName] = myIP()

[~, str] = system('ipconfig');
spl = splitlines(str);

lineIndex = find(~cellfun(@isempty, strfind(spl, 'IPv4 Address')));

myString = spl{lineIndex};
[stIndex, endIndex] = regexp(myString, '(\d{1,3}\.){3}\d{1,3}');
ipString = myString(stIndex:endIndex);

if nargout > 1
    [~, hostName] = system('hostname');
    hostName = hostName(1:end-1);
end