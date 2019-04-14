#include <stdio.h>
#include <stdlib.h>
#include <omp.h>
#include <unistd.h>
#include <string.h>
#include "ppmFile.h"


typedef struct pix{
    int r,g,b;

}pix;


pix blurFilter(Image* pic,int w,int h,int r,int x, int y);

int main(int argc, char *argv[]){

    //--------------Handle Input Arguments
    int r = atoi(argv[1]);
    char const * inFile = argv[2];
    char const * outFile = argv[3];

    //--------------Create
    Image* oldPic;
    Image* newPic;
    
    oldPic = ImageRead(inFile);                  //read old

    int WIDTH = ImageWidth(oldPic);
    int HEIGHT = ImageHeight(oldPic);


    newPic = ImageCreate(WIDTH,HEIGHT);        //make new same size as old

    printf("Processing...\n");

    int i;
    int j;

    #pragma omp parallel
    { 
        pix avg;
        #pragma omp for collapse(2)
        for(i = 0;i<HEIGHT;i++){
            for(j = 0;j<WIDTH; j++){    //j is x, i is y, for cache efficiency
                
                avg = blurFilter(oldPic,WIDTH,HEIGHT,r,j,i);

                ImageSetPixel(newPic,j,i,0,avg.r);
                ImageSetPixel(newPic,j,i,1,avg.g);
                ImageSetPixel(newPic,j,i,2,avg.b);

            }
        }
    }

    ImageWrite(newPic,outFile);
    
    //printf("old: [%d,%d,%d]\n",ImageGetPixel(oldPic,2500,900,0),ImageGetPixel(oldPic,2500,900,1),ImageGetPixel(oldPic,2500,900,2));
    //printf("new: [%d,%d,%d]\n",ImageGetPixel(newPic,2500,900,0),ImageGetPixel(newPic,2500,900,1),ImageGetPixel(newPic,2500,900,2));
    printf("New picture written to: %s\n",outFile);

    return 0;
}    

pix blurFilter(Image* pic,int w,int h,int r,int x, int y){
    pix avg = {0};
    
    int xMin, xMax, yMin, yMax;

    if((xMin = x-r) < 0) xMin = 0;
    if((yMin = y-r) < 0) yMin = 0;
    if((xMax = x+r) > w-1) xMax = w;
    if((yMax = y+r) > h-1) yMax = h;

    int i;
    int j;
    for(i=yMin; i < yMax; i++){        //i is y, j is x for row first iteration
        for(j=xMin; j < xMax; j++){    //efficient for cache
        
        avg.r += ImageGetPixel(pic,j,i,0); 
        avg.g += ImageGetPixel(pic,j,i,1); 
        avg.b += ImageGetPixel(pic,j,i,2); 

        }
    }

    int num = (yMax-yMin)*(xMax-xMin);
    

    avg.r = avg.r/num;
    avg.g = avg.g/num;
    avg.b = avg.b/num;

    return avg;    
    
}