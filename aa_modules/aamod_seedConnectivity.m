function [aap, resp] = aamod_seedConnectivity(aap, task, subj)

resp = '';


switch task
    case 'report'
        
    case 'doit'
        
        if ~(marsbar('is_started'))
            marsbar on;
        end

        
        % Subject name and directory
        subjName = aap.acq_details.subjects(subj).mriname;
        subjDir = aas_getsubjpath(aap, subj);
        
        % Load the SPM model
        SPM = load(aas_getfiles_bystream(aap, subj, 'firstlevel_spm'));
        SPM = SPM.SPM;
        
        % path to the mask.nii generated by SPM model
        brainMaskDir = SPM.swd;
        
        % Misc image information... (using first image as a template)
        imgDim = SPM.xY.VY(1).dim;         % Dimensions of the images
        imgMat = SPM.xY.VY(1).mat;         % Orientation, scaling, etc.
        
        % aap.directory_conventions.stats_singlesubj
        % can have module specific value, but kept for backwards
        % compatability
        if (isfield(aap.tasklist.currenttask.extraparameters,'stats_suffix'))
            stats_suffix=aap.tasklist.currenttask.extraparameters.stats_suffix;
        else
            stats_suffix=[];
        end
        
        anaDir = fullfile(subjDir, [aap.directory_conventions.stats_singlesubj stats_suffix]);
        if ~exist(anaDir,'dir')
            mkdir(subjDir, [aap.directory_conventions.stats_singlesubj stats_suffix]);
        end
        cd(anaDir);
        
        % ROI description
        roiDesc = aap.tasklist.currenttask.settings.ROIdesc;
        roiRadius = aap.tasklist.currenttask.settings.radius;
        
        % ROIs can be mask files, NYI
        if ischar(roiDesc)
            
            fcDesc = roiDesc;
            
            % Extract the ROI name, for use in writing new images
            [x fcName ext] = fileparts(roi1Name);
            
            % TO UPDATE, EVENTUALLY
            
            %     % If the ROI is a marsbar _roi.mat file, convert it to an image first
            %     if strcmp(ext, '.mat')
            %         fprintf('Creating ROIs in NIfTI format\n');
            %         roi1Name = [fcName '.nii'];
            % %             dataSpace = mars_space(SPM.xY.VY(1));
            % %
            % %             roi1File = fullfile(MYV.root, MYV.subjects{i}.name, MYV.subDir, MYV.roiDir, fcName);
            % %             roimat = maroi('load', [roi1File '.mat']);
            % %             save_as_image(roimat, [roi1File '.nii'], dataSpace);
            %         end
            %     end
            
            %             roi1F = fullfile(MYV.root, thisSubject.name, MYV.subDir, 'ROIs', roi1Name);
            %             fprintf('ROI1 file: %s\n', roi1F);
            %             roi1 = maroi_image(spm_vol(roi1F));
            %             roi1XYZ = voxpts(roi1, struct('mat', imgMat, 'dim', imgDim));
            %             roi1XYZ = [roi1XYZ; ones(1, size(roi1XYZ,2))];
            
            % OR they are coordinates
        else
            % TODO: verify coordinates (3 numbers, within the volume, etc).
            fcDesc = sprintf('%d_%d_%d_r=%d', roiDesc(1), roiDesc(2), roiDesc(3), roiRadius);
            seed = maroi_sphere(struct('centre', roiDesc, 'radius', roiRadius));
            
            %             % Save an image of the ROI, used for masking the analysis
            %             if vargs.mask
            %                 roi1F = sprintf('Sphere_$d_%d_%D.img', roi1Name(i,1), roi1Name(i,2), roi1Name(i,3));
            %                 roi1F = fullfile(rDir, roi1F);
            %                 save_as_image(roi1, fullfile(roi1, 'RL.img'));
            %             end
            
%             fprintf('ROI1 is a sphere at [%d %d %d], r=%d\n', roiDesc(i,1), roiDesc(i,2), roiDesc(i,3), vargs.radius);
            roi1XYZ = voxpts(seed, struct('mat', imgMat, 'dim', imgDim));
            roi1XYZ = [roi1XYZ; ones(1, size(roi1XYZ,2))];
            
        end
        
        
        fprintf('\n--- Time to make some correlation maps!! ---\n');
        
        % Extract the seed data
        y = spm_get_data(SPM.xY.VY, roi1XYZ);
        y = spm_filter(SPM.xX.K, SPM.xX.W*y);
        
        % Correct seed time series for confounds? NOT YET TESTED
        if ~isempty(aap.tasklist.currenttask.settings.IC)
            fprintf('Correcting Y0 with ''%s''\n', SPM.xCon(vargs.IC).name);
            B = spm_get_data(SPM.Vbeta, roi1XYZ);
            y = y - spm_FcUtil('Y0', SPM.xCon(vargs.IC), SPM.xX.xKXs, B);
        end
        y = y(:,~any(isnan(y)));
        
        % Summarize the seed voxels' time series into a single timecourse
        switch aap.tasklist.currenttask.settings.summaryFun
            
            case 'mean'
                Y = mean(y, 2);
                
            case 'median'
                Y = median(y, 2);
                
            case 'eigen1'
                [m n]   = size(y);
                if m > n
                    [v s v] = svd(spm_atranspa(y));
                    s       = diag(s);
                    v       = v(:,1);
                    u       = y*v/sqrt(s(1));
                else
                    [u s u] = svd(spm_atranspa(y'));
                    s       = diag(s);
                    u       = u(:,1);
                    v       = y'*u/sqrt(s(1));
                end
                d       = sign(sum(v));
                u       = u*d;
                v       = v*d;
                Y       = u*sqrt(s(1)/n);
                
            case 'default'
                aas_log(aap, 1, 'Invalid summary function option');
        end
        
        % Matrix of confound data (global, csf, wm)
        Xc = []; confoundNames = {};
        
        % gAH JUST READ ALL THE DATA IN
        Ytot = spm_read_vols(SPM.xY.VY);
        
        % Extract signal in the CSf
        if ~isempty(aap.tasklist.currenttask.settings.CSFSeed)
            csfROIXYZ = round(imgMat \ [aap.tasklist.currenttask.settings.CSFSeed';1]);
            Ycsf = squeeze(Ytot(csfROIXYZ(1), csfROIXYZ(2), csfROIXYZ(3), :));
            Ycsf = Ycsf - mean(Ycsf); % xero-mean
            Xc = [Xc Ycsf];
            confoundNames = [confoundNames 'CSF'];
        end
        
        % Extract signal in the WM
        if ~isempty(aap.tasklist.currenttask.settings.WMSeed)
            wmROIXYZ = round(imgMat \ [aap.tasklist.currenttask.settings.WMSeed';1]);
            Ywm = squeeze(Ytot(wmROIXYZ(1), wmROIXYZ(2), wmROIXYZ(3), :));
            Ywm = Ywm - mean(Ywm); % xero-mean
            Xc = [Xc Ywm];
            confoundNames = [confoundNames 'WM'];
        end
        
        % Extract global signal, UPDATE THIS TO NOT USE MARSBAR (we already
        % have the data loaded in
        if aap.tasklist.currenttask.settings.globalRegress
            
            % Load the generated brain mask and to extract global signal
            brainMaskV = spm_vol(fullfile(brainMaskDir, 'mask.img'));
            brainROI = maroi_image(struct('vol', brainMaskV, 'binarize', 1, 'func', ''));          
            Gg = get_marsy(brainROI, SPM.xY.VY, 'mean');   
            [Yg Vg Gg] = summary_data(Gg);
            Yg = Yg - mean(Yg); % zero the mean
            Xc =[Xc Yg];
            confoundNames = [confoundNames 'Global'];
        end
        
        % Regress the confounds out of the seed time series
        if ~isempty(Xc)           
            B = pinv(Xc) * Y;
            Y = Y - Xc * B;
        end
        
        % Copy settings from the original SPM model
        fcSPM.xY.P = SPM.xY.P;
        fcSPM.xBF = SPM.xBF;
        fcSPM.xY.RT = SPM.xY.RT;
        fcSPM.nscan = SPM.nscan;
        fcSPM.xGX.iGXcalc = SPM.xGX.iGXcalc ;
        fcSPM.xVi.form = SPM.xVi.form;
        fcSPM.xX.K.HParam = SPM.xX.K.HParam;
        
        % Copy Session Info
        nScans = [0 fcSPM.nscan];
        iC = []; iG = [];
        
        nPrevCols = 0;
        for sess = 1 : length(SPM.Sess)
            
            % Indices of scans in this session
            vI = nScans(sess)+1 : nScans(sess+1);
            
            % Add in the seed time series and the global
            fcSPM.Sess(sess).C.C = [Y(vI) Xc(vI, :) SPM.Sess(sess).C.C];
            fcSPM.Sess(sess).C.name = ['seed' confoundNames SPM.Sess(sess).C.name];
            
            % No events...
            fcSPM.Sess(sess).U = {};
            
            % Only the seed time series is a column of interest
            iC = [iC nPrevCols+1];
            iG = [iG nPrevCols+2:size(fcSPM.Sess(sess).C.C, 2)];
            nPrevCols = nPrevCols + size(fcSPM.Sess(sess).C.C, 2);   
        end
        
        % Configure design matrix
        fcSPM = spm_fmri_spm_ui(fcSPM);
        
        fcSPM.xX.iC = iC;
        fcSPM.xX.iG = iG;
        
        % Mask the analysis with the ROI file, nice!
        mask = ones(imgDim);
        mask(roi1XYZ(1,:), roi1XYZ(2,:), roi1XYZ(3,:)) = 0;
        maskV = SPM.xY.VY(1);
        maskV.fname = fullfile(anaDir, 'NOT_roi.nii');
        spm_write_vol(maskV, mask);
        fcSPM.xM.VM = spm_vol(maskV.fname);
        fcSPM.xM.xs.Masking = 'analysis threshold+explicit mask';
        
        % Estimate parameters
        spm_unlink(fullfile('.', 'mask.img')); % avoid overwrite dialog
        fcSPM = spm_spm(fcSPM);
        
        % Create a t-contrast for the seed time series
        seedContrast = zeros(1, size(fcSPM.xX.X, 2));
        seedContrast(iC) = 1;
        fcSPM.xCon =  spm_FcUtil('Set', fcDesc, 'T', 'c', seedContrast', fcSPM.xX.xKXs);
        spm_contrasts(fcSPM);
        

end

end
