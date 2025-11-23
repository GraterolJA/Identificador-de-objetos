%% deteccion de imagenes
clc 
clear all
close all

%%leer imagen
I = imread ("Desodorante.jpg");
figure
imshow (I)

%%convertir a escala de grises

I= rgb2gray(I);

%buscando bordes por metodo Canny y Prewitt

BW1 = edge(I, "canny");
BW2 = edge(I, "prewitt");

%comparando resultados
figure
imshowpair (BW1, BW2,'montage')

%% deteccion de imagenes
clc 
clear all
close all

%%leer imagen
I = imread ("Objetos.jpg");
figure
imshow (I)
I= rgb2gray(I);

%%suvianzado ruido

I = wiener2(I,[50 50]);
figure
imshow (I)

%Binarizando la imagen
I = im2bw(I, 0.50)
figure 
imshow (I)

%eliminando ruido
I = bwareaopen (I,130)
figure
imshow (I)

%rellando espacios

se = strel('disk',6);
I = imclose (I,se);
figure
imshow (I)

%%identificando y delimitando regiones

[B,L] = bwboundaries (I, 'noholes');
imshow (label2rgb(L,@jet, [.5 .5 .5]))
hold on

for k = 1:length(B)  boundary = B{k};
    plot(boundary(:,2),boundary(:,1),'w','LineWidth',2)
end

%extrayendo y recopilando informacion

stats = regionprops(L, 'Area','Centroid');
threshold = 0.94;
for k = 1:length(B)
    boundary = B{k};
    delta_sq = diff(boundary).^2;
    perimeter = sum(sqrt(sum(delta_sq,2)));
    area = stats(k).Area;
    metric = 4*pi*area/perimeter^2;
    metric_string = sprintf('%2.2f',metric);
    if metric_string > threshold
        centroid = stats(k).Centroid;
        plot(centroid(1),centroid(2),'ko');
    end
 
text (boundary (1,2)-35,boundary(1,1)+13,metric_string, 'Color', 'k', 'FontSize',20, 'FontWeight','bold')
end