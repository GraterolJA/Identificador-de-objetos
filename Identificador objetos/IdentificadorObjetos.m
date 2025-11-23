
classdef IdentificadorObjetos < handle
    properties
        fig
        ax
        btnCargar
        btnIdentificar
        btnAgregar
        lblTitulo
        lblResultado
        tblTop
        img                 % imagen original cargada
        templateDB          % base de plantillas (struct)
        alphaCorr = 0.55    % peso correlación
        alphaHu   = 0.45    % peso Hu moments
    end
    
    methods
        function app = IdentificadorObjetos
            % ===== UI =====
            app.fig = uifigure('Name','Sistema Identificador De Objetos', ...
                               'Position',[100 100 900 560], ...
                               'Color',[0.15 0.4 0.35]);
            app.lblTitulo = uilabel(app.fig,'Text','Sistema Identificador De Objetos', ...
                'FontWeight','bold','FontSize',18,'Position',[300 515 300 30], ...
                'HorizontalAlignment','center','BackgroundColor',[1 1 1]);
            
            app.ax = uiaxes(app.fig,'Position',[40 150 420 340]);
            app.ax.XTick = []; app.ax.YTick = [];
            title(app.ax,''); box(app.ax,'on');
            app.ax.BackgroundColor = [0.2 0.6 0.5];
            
            app.btnCargar = uibutton(app.fig,'push','Text','Cargar Imagen', ...
                'Position',[500 360 160 40], ...
                'ButtonPushedFcn',@(src,evt)app.onCargar());
            app.btnIdentificar = uibutton(app.fig,'push','Text','Identificar Objeto', ...
                'Position',[500 300 160 40], 'Enable','off', ...
                'ButtonPushedFcn',@(src,evt)app.onIdentificar());
            app.btnAgregar = uibutton(app.fig,'push','Text','Agregar a Plantillas', ...
                'Position',[500 240 160 40], 'Enable','off', ...
                'ButtonPushedFcn',@(src,evt)app.onAgregarPlantilla());
            
            app.lblResultado = uilabel(app.fig,'Text','El objeto es un(a): ', ...
                'Position',[40 90 820 40], 'BackgroundColor',[0.7 0.85 1], ...
                'FontSize',16, 'FontWeight','bold');
            
            % Tabla Top-3
            app.tblTop = uitable(app.fig,'Position',[500 150 370 80], ...
                'ColumnName',{'Clase','Score','Corr','DistHu'}, ...
                'ColumnFormat',{'char','numeric','numeric','numeric'}, ...
                'RowName',[]);
            
            % ===== Cargar base de plantillas =====
            try
                app.templateDB = app.buildTemplateDB(fullfile(pwd,'plantillas'));
                if isempty(app.templateDB)
                    uialert(app.fig,['No se encontraron plantillas. ' ...
                        'Cree carpetas por clase dentro de ./plantillas y agregue imágenes.'], ...
                        'Plantillas vacías');
                end
            catch ME
                uialert(app.fig,ME.message,'Error cargando plantillas');
                app.templateDB = struct([]);
            end
        end
        
        function onCargar(app)
            [file, path] = uigetfile({'*.jpg;*.png;*.jpeg;*.bmp','Imágenes'},'Seleccionar imagen');
            if isequal(file,0), return; end
            app.img = imread(fullfile(path,file));
            imshow(app.img,'Parent',app.ax);
            app.btnIdentificar.Enable = 'on';
            app.btnAgregar.Enable = 'on';
            app.lblResultado.Text = 'El objeto es un(a): ';
            app.tblTop.Data = cell(0,4);
        end
        
        function onIdentificar(app)
            if isempty(app.img)
                uialert(app.fig,'Primero cargue una imagen.','Aviso'); return;
            end
            if isempty(app.templateDB)
                uialert(app.fig,'No hay plantillas cargadas.','Aviso'); return;
            end
            
            % --- Pipeline (según tu código, ligeramente ajustado) ---
            Igray = app.ensureGray(app.img);
            Iden  = wiener2(Igray,[50 50]);
            BW    = imbinarize(Iden,0.50);     % im2bw obsoleto
            BW    = bwareaopen(BW,130);
            BW    = imclose(BW, strel('disk',6));
            BW    = imfill(BW,'holes');        % ayuda con huecos
            
            % Visualización de etiquetas
            imshow(BW,'Parent',app.ax); hold(app.ax,'on');
            [B,L] = bwboundaries(BW,'noholes');
            imshow(label2rgb(L,@jet,[.5 .5 .5]),'Parent',app.ax);
            for k = 1:length(B)
                boundary = B{k};
                plot(app.ax,boundary(:,2),boundary(:,1),'w','LineWidth',2);
            end
            hold(app.ax,'off');
            
            % ROI: mayor componente
            stats = regionprops(L,'Area','Centroid','Image');
            if isempty(stats)
                app.lblResultado.Text = 'El objeto es un(a): No detectado';
                return;
            end
            [~,idx] = max([stats.Area]);
            ROI = stats(idx).Image;         % máscara binaria del objeto
            ROI128 = imresize(ROI,[128 128]); % normalización para corr2
            
            % Hu moments del objeto
            objHu = app.huMoments(double(ROI));
            
            % --- Comparación contra base de plantillas ---
            n = numel(app.templateDB);
            scores = zeros(n,1);
            corrs  = zeros(n,1);
            dHus   = zeros(n,1);
            classes = strings(n,1);
            for i = 1:n
                t = app.templateDB(i);
                % correlación
                r = corr2(double(ROI128), double(t.bw128));
                % distancia de Hu (con log para estabilizar)
                d = norm(log(abs(objHu)) - log(abs(t.hu)));
                % normalización simple de distancia
                dNorm = d/(d+1); % en [0,1)
                % score combinado
                s = app.alphaCorr*r + app.alphaHu*(1 - dNorm);
                scores(i) = s; corrs(i) = r; dHus(i) = d; classes(i) = string(t.clase);
            end
            
            % Mejor clase + Top-3
            [scoresSorted, idxSorted] = sort(scores,'descend');
            best = idxSorted(1);
            claseBest = classes(best);
            conf = max(0, min(1, (scoresSorted(1)+1)/2)); % mapea score a [0,1]
            
            app.lblResultado.Text = sprintf('El objeto es un(a): %s  (confianza: %0.2f)', claseBest, conf);
            
            topN = min(3, numel(idxSorted));
            data = cell(topN,4);
            for k = 1:topN
                ii = idxSorted(k);
                data{k,1} = char(classes(ii));
                data{k,2} = scoresSorted(k);
                data{k,3} = corrs(ii);
                data{k,4} = dHus(ii);
            end
            app.tblTop.Data = data;
        end
        
        function onAgregarPlantilla(app)
            % Permite guardar la ROI actual como plantilla en una clase
            if isempty(app.img)
                uialert(app.fig,'Cargue una imagen antes de agregar.','Aviso'); return;
            end
            
            % Reusa el pipeline para extraer ROI del objeto cargado
            Igray = app.ensureGray(app.img);
            Iden  = wiener2(Igray,[50 50]);
            BW    = imbinarize(Iden,0.50);
            BW    = bwareaopen(BW,130);
            BW    = imclose(BW, strel('disk',6));
            BW    = imfill(BW,'holes');
            stats = regionprops(BW,'Area','Image');
            if isempty(stats)
                uialert(app.fig,'No se encontró objeto en la imagen.','Aviso'); return;
            end
            [~,idx] = max([stats.Area]);
            ROI = stats(idx).Image;
            ROI128 = imresize(ROI,[128 128]);
            
            % Pide nombre de clase
            answer = inputdlg({'Nombre de la clase (carpeta):'},'Agregar plantilla',1,{'nueva_clase'});
            if isempty(answer), return; end
            clase = strtrim(answer{1});
            if clase == "", return; end
            
            % Crea carpeta si no existe
            basePath = fullfile(pwd,'plantillas');
            folder   = fullfile(basePath,clase);
            if ~isfolder(folder), mkdir(folder); end
            
            % Guarda archivo PNG con timestamp
            fname = sprintf('%s_%s.png', clase, datestr(now,'yyyymmdd_HHMMSSFFF'));
            fullf = fullfile(folder, fname);
            imwrite(ROI128, fullf); % guardamos la máscara normalizada
            
            % Actualiza la base en caliente
            t.hu    = app.huMoments(double(ROI));
            t.bw128 = ROI128;
            t.clase = clase;
            t.filename = fullf;
            if isempty(app.templateDB)
                app.templateDB = t;
            else
                app.templateDB(end+1) = t;
            end
            
            uialert(app.fig, sprintf('Plantilla guardada en: %s', fullf), 'Éxito');
        end
        
        % ===== Utilidades =====
        function DB = buildTemplateDB(app, basePath)
            if ~isfolder(basePath)
                DB = struct([]);
                return;
            end
            classes = dir(basePath);
            DB = struct('hu',{},'bw128',{},'clase',{},'filename',{});
            for i = 1:numel(classes)
                if ~classes(i).isdir, continue; end
                cname = classes(i).name;
                if ismember(cname,{'.','..'}), continue; end
                files = [dir(fullfile(basePath,cname,'*.png')); ...
                         dir(fullfile(basePath,cname,'*.jpg')); ...
                         dir(fullfile(basePath,cname,'*.jpeg')); ...
                         dir(fullfile(basePath,cname,'*.bmp'))];
                for j = 1:numel(files)
                    f = fullfile(basePath,cname,files(j).name);
                    try
                        img = imread(f);
                        Igray = app.ensureGray(img);
                        bw = imbinarize(Igray);
                        bw = bwareaopen(bw,100);
                        bw = imfill(bw,'holes');
                        s = regionprops(bw,'Image','Area');
                        if isempty(s), continue; end
                        [~,kmax] = max([s.Area]);
                        ROI = s(kmax).Image;
                        ROI128 = imresize(ROI,[128 128]);
                        hu = app.huMoments(double(ROI));
                        item.hu = hu;
                        item.bw128 = ROI128;
                        item.clase = cname;
                        item.filename = f;
                        DB(end+1) = item; %#ok<AGROW>
                    catch
                        % Ignorar archivos problemáticos
                    end
                end
            end
        end
        
        function Igray = ensureGray(~, I)
            if size(I,3) > 1
                Igray = rgb2gray(I);
            else
                Igray = I;
            end
        end
        
        function hu = huMoments(~, I)
            % I: imagen binaria (double 0/1) de la ROI
            [rows, cols] = size(I);
            [X,Y] = meshgrid(1:cols,1:rows);
            m00 = sum(I(:));
            if m00 == 0
                hu = zeros(7,1); return;
            end
            xbar = sum(sum(X.*I))/m00; 
            ybar = sum(sum(Y.*I))/m00;
            mu11 = sum(sum( (X-xbar).*(Y-ybar).*I ));
            mu20 = sum(sum( (X-xbar).^2.*I ));
            mu02 = sum(sum( (Y-ybar).^2.*I ));
            mu30 = sum(sum( (X-xbar).^3.*I ));
            mu03 = sum(sum( (Y-ybar).^3.*I ));
            mu21 = sum(sum( (X-xbar).^2.*(Y-ybar).*I ));
            mu12 = sum(sum( (X-xbar).*(Y-ybar).^2.*I ));
            eta20 = mu20 / m00^(1+2/2); eta02 = mu02 / m00^(1+2/2); eta11 = mu11 / m00^(1+2/2);
            eta30 = mu30 / m00^(1+3/2); eta03 = mu03 / m00^(1+3/2);
            eta21 = mu21 / m00^(1+3/2); eta12 = mu12 / m00^(1+3/2);
            hu = zeros(7,1);
            hu(1) = eta20 + eta02;
            hu(2) = (eta20 - eta02)^2 + 4*eta11^2;
            hu(3) = (eta30 - 3*eta12)^2 + (3*eta21 - eta03)^2;
            hu(4) = (eta30 + eta12)^2 + (eta21 + eta03)^2;
            hu(5) = (eta30 - 3*eta12)*(eta30 + eta12)*((eta30 + eta12)^2 - 3*(eta21 + eta03)^2) + ...
                    (3*eta21 - eta03)*(eta21 + eta03)*(3*(eta30 + eta12)^2 - (eta21 + eta03)^2);
            hu(6) = (eta20 - eta02)*((eta30 + eta12)^2 - (eta21 + eta03)^2) + 4*eta11*(eta30 + eta12)*(eta21 + eta03);
            hu(7) = (3*eta21 - eta03)*(eta30 + eta12)*((eta30 + eta12)^2 - 3*(eta21 + eta03)^2) - ...
                    (eta30 - 3*eta12)*(eta21 + eta03)*(3*(eta30 + eta12)^2 - (eta21 + eta03)^2);
        end
    end
end

