rootdir = '/Volumes/Backstaff/field/gb_proc/';
mooring = '1076';
dep = 'a';
% mooring = '1076';
% dep = 'b';
% mooring = '1078';
% dep = 'a';
% mooring = '1078';
% dep = 'b';
% mooring = '1079';
% dep = 'b';

height = '1';

infile = [rootdir mooring dep '/' mooring height upper(dep) 'aqd/' mooring height upper(dep) 'aqdwvsb-cal.nc'];

initial_instrument_height = ncreadatt(infile, '/', 'initial_instrument_height');
fs = ncreadatt(infile, '/', 'WaveSampleRate');
fs = str2num(fs(1:strfind(fs, ' ')-1));
pres = ncread(infile, 'P_1ac'); % this assumes atmospherically corrected pressure
vel1= ncread(infile, 'vel1_1277'); % this assumes atmospherically corrected pressure
vel2 = ncread(infile, 'vel2_1278'); % this assumes atmospherically corrected pressure
vel3 = ncread(infile, 'vel3_1279'); % this assumes atmospherically corrected pressure
cellpos = ncread(infile, 'cellpos'); % this assumes atmospherically corrected pressure
adcpheight = ncreadatt(infile, '/', 'initial_instrument_height');
heading = ncread(infile, 'Hdg_1215');
pitch = ncread(infile, 'Ptch_1216');
roll = ncread(infile, 'Roll_1217'); 

%% Process AQD wave data with DIWASP
for burst = 1:size(pres,2)
    
    ID.data = [pres(:,burst) vel1(:,burst)/1000 vel2(:,burst)/1000 vel3(:,burst)/1000];
    ID.layout = make_xyzpos(0, heading(burst), pitch(burst), roll(burst), cellpos(burst), adcpheight); % magvar has already been applied
    ID.datatypes={'pres' 'radial' 'radial' 'radial'};
%     ID.layout = [0    0    0
%         0    0    0
%         adcpheight  cellpos(burst)+adcpheight  cellpos(burst)+adcpheight];
%     ID.datatypes = {'pres', 'velx', 'vely'};
    
    % ID.data = aqd.waveburst(burst).pres;
    % ID.layout = [0
    %              0
    %               .15  ];
    % ID.datatypes = {'pres'};
    
    ID.depth = mean(pres(:,burst)) + adcpheight;
    ID.fs = 2;
    
    SM.freqs = 1/256:1/128:ID.fs/2-1/256;
    SM.dirs = 5:10:360-5;
    SM.xaxisdir = 90;
    SM.funit = 'Hz';
    SM.dunit = 'naut';
    
    EP.method = 'IMLM';
    % 'DFTM' Direct Fourier transform method
    % 'EMLM' Extended maximum likelihood method
    % 'IMLM' Iterated maximum likelihood method
    % 'EMEP' Extended maximum entropy principle
    % 'BDM' Bayesian direct method
    %EP.nfft = 8;
    %EP.dres = 10;
    %EP.smooth = 'off';
    
    [diwasp.S(burst), diwasp.E(burst)] = dirspec(ID, SM, EP, {'MESSAGE', 0, 'PLOTTYPE', 0});
    [diwasp.Hs(burst), diwasp.Tp(burst), diwasp.Dtp(burst), diwasp.Dp(burst)] = infospec(diwasp.S(burst));
    disp(num2str(burst))
end

%%
dw.wh_4061 = diwasp.Hs;
dw.wp_peak = diwasp.Tp;
dw.frequency = diwasp.S(1).freqs;
for n = 1:length(diwasp.S)
    dw.pspec(:,n) = sum(diwasp.S(n).S, 2) * diff(diwasp.S(1).dirs(1:2));
    m0 = sum(sum(diwasp.S(n).S)) * diff(diwasp.S(1).dirs(1:2)) * diff(diwasp.S(1).freqs(1:2));
    m1 = sum(sum(repmat(diwasp.S(1).freqs', 1, 8) .* diwasp.S(n).S)) * diff(diwasp.S(1).dirs(1:2)) * diff(diwasp.S(1).freqs(1:2));
    dw.wp_4060(n) = m0/m1;
end
%%

outfile = [rootdir mooring dep '/' mooring height upper(dep) 'aqd/' mooring height upper(dep) 'aqdwvs-diwasp-pres.nc'];

nccreate(outfile, 'wh_4061', 'dimensions', {'time', size(dw.wh_4061, 2)});
ncwrite(outfile, 'wh_4061', dw.wh_4061);

nccreate(outfile, 'wp_peak', 'dimensions', {'time', size(dw.wp_peak, 2)});
ncwrite(outfile, 'wp_peak', dw.wp_peak);

nccreate(outfile, 'wp_4060', 'dimensions', {'time', size(dw.wp_4060, 2)});
ncwrite(outfile, 'wp_4060', dw.wp_4060);

nccreate(outfile, 'frequency', 'dimensions', {'frequency', size(dw.frequency, 2)});
ncwrite(outfile, 'frequency', dw.frequency);

nccreate(outfile, 'pspec', 'dimensions', {'frequency', size(dw.pspec, 1), 'time', size(dw.pspec, 2)});
ncwrite(outfile, 'pspec', dw.pspec);



%% 
function xyzpositions = make_xyzpos(magvar, heading, pitch, roll, height, adcpheight)

xyzpos=ones(3,3);
pos=height*tand(25);

% as x,  y , z
% meas 1
% meas 2
% meas 3
xyzpos(:,1)=[0,pos,height];
xyzpos(:,2)=[pos*cosd(30),-pos*.5,height];
xyzpos(:,3)=[-pos*cosd(30),-pos*.5,height];

% set up the new coordinate transformation matrix
CH = cosd(heading+magvar);
SH = sind(heading+magvar);
CP = cosd(pitch);
SP = sind(pitch);
CR = cosd(-roll);
SR = sind(-roll);

%  let the matrix elements be ( a b c; d e f; g h j);
a = CH.*CR - SH.*SP.*SR;  b = SH.*CP; c = -CH.*SR - SH.*SP.*CR;
d = -SH.*CR - CH.*SP.*SR; e = CH.*CP; f = SH.*SR - CH.*SP.*CR;
g = CP.*SR;              h = SP;     j = CP.*CR;

%transform the original x,y,z positions to the new positions accounting for
%heading, pitch and roll... we also add adcpheight back in

new_xyzpos(1,:)=xyzpos(1,:)*a+xyzpos(2,:)*b+xyzpos(3,:)*c;
new_xyzpos(2,:)=xyzpos(1,:)*d+xyzpos(2,:)*e+xyzpos(3,:)*f;
new_xyzpos(3,:)=xyzpos(1,:)*g+xyzpos(2,:)*h+xyzpos(3,:)*j+adcpheight;
new_xyzpos(4,:)=[0,0,adcpheight];

xyzpositions=new_xyzpos;
xyzpositions = xyzpositions([4, 1:3], :);

end