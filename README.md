# vBox
Video acquisition package, initially written for FLIR machine vision cameras.

## Installation
- Uninstall any FLIR related drivers/software from the system (e.g. FlyCapture and Spinnaker software). Matlab will only work with very specific (older) versions of them.
- Pointgrey camera support package for Matlab, **clean** install only the Matlab compatible version from the Add-On manager or from here: https://uk.mathworks.com/hardware-support/point-grey-camera.html
- Spinnaker camera support package for Matlab, follow the the instructions here: https://uk.mathworks.com/matlabcentral/fileexchange/69202-flir-spinnaker-support-by-image-acquisition-toolbox
. Note that you will need to both install it as a toolbox, and also download the zip file, which will contain the necessary .dll for registering the adaptor.
 - Open FlyCapture software (it will be installed together with the Pointgrey camera support package). 
 Check the cameras' Serial Numbers (you will need these for the `camConfig.m` file), in the Advanced settings select to embed Timestamp and Frame Counter information into the frames.
  When previewing the camera images you should see that the first 8 pixels in the first row of the image are now 'flickering' with the metadata.
 - Create a local, outside of this git repository (e.g. in you MATLAB folder) copy and edit the `camConfig.m` and the `vBoxStart.m` (this one can have a different name) files according to your needs.
 - Create a bash script (see `vBoxStartExamle.m` for an example) if you don't want to manually start all your cameras in separate Matlab sessions.
 - You should be good to go
 
 Note: FlyCapture installation might not be necessary (we do not use that adaptor in Matlab), but I could not find a way to switch the meta-data embedding on from the Spinnaker software. The option is there, but it doesn't seem to work. 
