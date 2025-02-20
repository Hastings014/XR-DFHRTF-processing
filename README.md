# XR-based HRTF Measurement Postprocessing
This set of MATLAB functions is a part of the [XR-based HRTF Measurement System](https://trsonic.github.io/XR-HRTFs/). It serves as a postprocessing workflow for binaural sine sweep signals recorded using the [HRTF Measurement Control App](https://github.com/trsonic/XR-HRTF-capture). Please see the wiki for additional info.  

## Getting Started
* Requirements
    * MATLAB (tested using R2024b)
    * [SOFA MATLAB Toolbox](https://github.com/sofacoustics/SOFAtoolbox) - optionally 
    * [Ambisonic Decoder Toolbox](https://bitbucket.org/ambidecodertoolbox/adt/src/master/) - optionally, comment out `saveAsAmbix` function call if you don't need Ambisonic decoders to be calculated.
* Usage
    * Once the binaural recordings have been captured, edit the path to the subject dir in `IRprocessing.m` script. Running the script should execute all necessary processing.

## Output data
* The blocked-canal Diffuse Field Head-Related Transfer Function of the measured ears in .csv format 
* A set of various plots (located in the subject folder under `/figures/`)
* Optionally - SOFA files:
    * RAW HRIRs at measured directions
    * Diffuse-field Equalized HRIRs at measured directions
    * RAW HRIRs at interpolated directions
    * Diffuse-field Equalized HRIRs at interpolated directions
* Measured HRIRs in Wave format
* Optionally - Ambix Ambisonic decoder config files
