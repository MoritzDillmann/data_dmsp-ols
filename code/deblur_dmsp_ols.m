% Based on https://raw.githubusercontent.com/alexeiabrahams/nighttime-lights/master/deblur_roving_window_call_script

clear
clc

% Set the working directory to the one where this script is located
this_script_full_path = mfilename('fullpath') % https://www.mathworks.com/help/matlab/ref/mfilename.html
[filepath,name,ext] = fileparts(this_script_full_path) %  https://www.mathworks.com/help/matlab/ref/fileparts.html
cd(filepath)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%PARAMETERS:
num_cpus = 1; %set number of CPUs for parallel processing
whole_image=1; %deblur whole image on one CPU with whole_image=1. deblur image using multiple CPUs in parallel with whole_image=0; note that the borders of the image may not be blurred depending on window size
freq_filter = 1;%default value: 1. this variable decides if frequency filtering should occur. set to zero if undesired.
threshold=20.0;%minimum percentage of cloud-free nights permissible; all pixels with lower frequency are set to zero
use_default_noise_sig_ratio = 1; %set to 1 to use default noise-to-signal ratio for deconvolution (see block_deblur.m); set to zero to calculate ratio locally (not recommended for parallelized roving window deblurring)

avg_vis_folder = strcat('../data');
pct_folder = strcat('../temp');
output_folder = strcat('../data'); %change to appropriate working directory

% The rest of the script will be looped over all satellite years (NOTE: F182011 is removed from the array below.)
%satellite_years = {'F101992','F101993','F101994','F121994','F121995','F121996','F121997','F121998','F121999','F141997','F141998','F141999','F142000','F142001','F142002','F142003','F152000','F152001','F152002','F152003','F152004','F152005','F152006','F152007','F162004','F162005','F162006','F162007','F162008','F162009','F182010','F182012','F182013'};
satellite_years = {'F101994','F121994','F121995','F121996','F121997','F121998','F121999','F141997','F141998','F141999','F142000','F142001','F142002','F142003','F152000','F152001','F152002','F152003','F152004','F152005','F152006','F152007','F162004','F162005','F162006','F162007','F162008','F162009','F182010','F182012','F182013'};

for j=1:length(satellite_years);

% INPUT FILES
blurred_image_pathname = strcat(avg_vis_folder, '/', satellite_years{1,j}, '_stable_lights_aze.tif') %avg_vis image
blurred_image_perc_pathname = strcat(pct_folder, '/', satellite_years{1,j}, '_pct_lights_aze.tif') %pct image

% OUTPUT
deblurred_image_pathname = strcat(output_folder, '/', satellite_years{1,j}, '_deblurred_aze.tif');%name of the deblurred image to be produced by this script

%%NOTHING BELOW THIS LINE NEEDS TO BE CHANGED BY THE USER :-)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
[blurred_image, input_georeference] = geotiffread(blurred_image_pathname);
rescale_factor = 1.0;

if max(max(blurred_image))>255 %then this is a rad-cal image, so to avoid 8-bit topcoding we must re-scale:
rescale_factor = 255.0/max(max(blurred_image));
blurred_image = rescale_factor*blurred_image;
end

blurred_image = uint16(blurred_image);

[blurred_image_perc, input_georeference] = geotiffread(blurred_image_perc_pathname);
imagesc(blurred_image)
colorbar

%average latitude in image:
avg_latitude=sum(input_georeference.LatitudeLimits/2.0);
NS_in_degrees = 0.008333333333;%pixel length in degrees (Lambertian coordinates)
EW_in_degrees = 0.008333333333;%pixel width in degrees (Lambertian coordinates)
%convert from Lambertian coordinates to kilometers:
pixel_length = NS_in_degrees*111.13209;

if whole_image==0
    disp('deblurring image by roving window...')
    parpool(num_cpus)
    %CHOP UP IMAGE INTO BLOCKS, AND DEBLUR EACH BLOCK; THEN RE-ASSEMBLE:
    num_rows = size(blurred_image,1);
    num_cols = size(blurred_image',1);
    deblurred_image = blurred_image;
    init_col_offset = 1;
    init_row_offset = 1;
    window_size = 60;
    step_size = 10;

    top_row = init_row_offset;
    left_col = init_col_offset;
    num_cells_per_row = 1 + floor((num_cols - window_size)/step_size);
    num_cells_per_col = 1 + floor((num_rows - window_size)/step_size);
    total_cells = num_cells_per_row * num_cells_per_col

    %this matrix will store the dimensions of each cell block:
    cell_dimensions = zeros(total_cells, 4);

    for cell_num = 1:total_cells
        top_row = 1+step_size*floor((cell_num-1)/num_cells_per_row);
        left_col = 1 + (cell_num-floor((cell_num-1)/num_cells_per_row)*num_cells_per_row-1)*step_size;
        bottom_row = top_row + window_size - 1;
        right_col = left_col + window_size - 1;
        cell_dimensions(cell_num, :) = [top_row, bottom_row, left_col, right_col];
    end

    deblurred_images = zeros(total_cells, step_size, step_size);
    parfor cell_num = 1:total_cells
    %for cell_num = 1:total_cells
        cell_num
        top_row = cell_dimensions(cell_num, 1);
        bottom_row = cell_dimensions(cell_num, 2);
        left_col = cell_dimensions(cell_num, 3);
        right_col = cell_dimensions(cell_num, 4);

        avg_latitude = (left_col/num_cols)*input_georeference.LatitudeLimits(1) + ((num_cols-left_col)/num_cols)*input_georeference.LatitudeLimits(2);
        pixel_width = EW_in_degrees*111.41513*cos(avg_latitude*pi/180.0);

        block = blurred_image(top_row:bottom_row, left_col:right_col);
        perc_block = blurred_image_perc(top_row:bottom_row, left_col:right_col);
        deblurred_block = block_deblur(block, perc_block, pixel_length, pixel_width, use_default_noise_sig_ratio); %deblur the block
        trust_deblurred_block = deblurred_block(window_size/2 - step_size/2 + 1:window_size/2 + step_size/2, window_size/2 - step_size/2 + 1:window_size/2 + step_size/2);
        deblurred_images(cell_num, :, :) = trust_deblurred_block;
    end

    for cell_num = 1:total_cells
        top_row = cell_dimensions(cell_num, 1);
        bottom_row = cell_dimensions(cell_num, 2);
        left_col = cell_dimensions(cell_num, 3);
        right_col = cell_dimensions(cell_num, 4);
        deblurred_image(top_row + window_size/2 - step_size/2 : bottom_row - window_size/2 + step_size/2, left_col + window_size/2 - step_size/2 :right_col - window_size/2 + step_size/2) = (1.0/rescale_factor)*deblurred_images(cell_num, :, :);
    end
    poolobj = gcp('nocreate');
    delete(poolobj);
else
    disp('deblurring whole image...')
    %user wants whole image to be processed as one item
    avg_latitude = (input_georeference.LatitudeLimits(1) + input_georeference.LatitudeLimits(2))/2.0;
    pixel_width = EW_in_degrees*111.41513*cos(avg_latitude*pi/180.0);
    block = blurred_image;
    perc_block = blurred_image_perc;
    deblurred_block = block_deblur(block, perc_block, pixel_length, pixel_width, use_default_noise_sig_ratio); %deblur the block
    deblurred_image = (1.0/rescale_factor)*deblurred_block;
end
geotiffwrite(deblurred_image_pathname,deblurred_image,input_georeference);
imagesc(deblurred_image)
colorbar
min(min(deblurred_image))
max(max(deblurred_image))

end;
