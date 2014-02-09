function [aap, resp]=aamod_dartel_normmni(aap, task, subj)
%AAMOD_DARTEL_NORMMNISEGMENTED_MODULATED Normalise grey/white segmentations using DARTEL.
%
% After DARTEL template has been created, write out normalized
% versions (MNI space) of each subject's segmentations.
%
% This function will also do smoothing, as specified in
% aap.tasksettings.aamod_dartel_normmnisegmented.fwhm. The default
% (specified in the .xml file) is 8 mm.
%
% input streams:    dartelimported_grey
%                   dartelimported_white
%                   dartel_flowfield
%                   dartel_template
%
% output streams:   dartelnormalised_grey
%                   dartelnormalised_white


resp='';

% possible tasks 'doit','report','checkrequirements'
switch task
    case 'report'
        resp='Write smoothed normalised segmented images in MNI space for DARTEL.';
    case 'doit'
        % template
        template = aas_getfiles_bystream(aap, 'dartel_template');

        % flow fields..
        job.data.subj.flowfield{1} = aas_getfiles_bystream(aap, subj, 'dartel_flowfield');
        
        % images
        imgs = '';
        streams=aap.tasklist.currenttask.outputstreams.stream;
        for streamind=1:length(streams)
            if isstruct(streams{streamind}), streams{streamind} = streams{streamind}.CONTENT; end
            imgs = strvcat(imgs, aas_getfiles_bystream(aap, subj, streams{streamind}));
        end
        job.data.subj.images = cellstr(imgs);

        % set up job, and run
        job.template{1} = template;
        job.bb = nan(2,3);
        job.vox = ones(1,3) * aap.tasklist.currenttask.settings.vox;    % voxel size
        job.fwhm = aap.tasklist.currenttask.settings.fwhm;              % smoothing
        job.preserve = aap.tasklist.currenttask.settings.preserve;      % modulation

        aas_log(aap, false, sprintf('Running with %s...', which('spm_dartel_norm_fun')));
        spm_dartel_norm_fun(job);

        % describe outputs (differ depending on modulation)
        if job.preserve==1
            prefix = 'smw';
        else
            prefix = 'sw';
        end
        
        for ind=1:length(job.data.subj.images)
            [pth, nm, ext] = fileparts(job.data.subj.images{ind});
            img = fullfile(pth, [prefix nm ext]);
            aap = aas_desc_outputs(aap, subj, streams{ind}, img);
        end
end