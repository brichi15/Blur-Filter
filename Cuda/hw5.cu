#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <ctype.h>
#include <sys/types.h>

//----------------------------------------------------------------------------//
//----------------------------------ppmFile.c----------------------------------//
//----------------------------------------------------------------------------//

typedef struct Image
{
	  int width;
	  int height;
	  unsigned char *data;
} Image;

/************************ private functions ****************************/

/* die gracelessly */

static void
die(char const *message)
{
    fprintf(stderr, "ppm: %s\n", message);
    exit(1);
}


/* check a dimension (width or height) from the image file for reasonability */

static void
checkDimension(int dim)
{
    if (dim < 1 || dim > 6000) 
    die("file contained unreasonable width or height");
}


	/* read a header: verify format and get width and height */

static void
readPPMHeader(FILE *fp, int *width, int *height)
{
    char ch;
    int  maxval;

    if (fscanf(fp, "P%c\n", &ch) != 1 || ch != '6') 
    die("file is not in ppm raw format; cannot read");

    /* skip comments */
    ch = getc(fp);
    while (ch == '#')
    {
        do {
    ch = getc(fp);
        } while (ch != '\n');	/* read to the end of the line */
        ch = getc(fp);            
    }

    if (!isdigit(ch)) die("cannot read header information from ppm file");

    ungetc(ch, fp);		/* put that digit back */

    /* read the width, height, and maximum value for a pixel */
    fscanf(fp, "%d%d%d\n", width, height, &maxval);

    if (maxval != 255) die("image is not true-color (24 bit); read failed");
    
    checkDimension(*width);
    checkDimension(*height);
}

	/************************ exported functions ****************************/
__host__
Image *
ImageCreate(int width, int height)
{
    Image *image = (Image *) malloc(sizeof(Image));

    if (!image) die("cannot allocate memory for new image");

    image->width  = width;
    image->height = height;
    image->data   = (unsigned char *) malloc(width * height * 3);

    if (!image->data) die("cannot allocate memory for new image");

    return image;
}
	  
__host__
Image *
ImageRead(char const *filename)
{
    int width, height, num, size;
    //unsigned  *p;

    Image *image = (Image *) malloc(sizeof(Image));
    FILE  *fp    = fopen(filename, "rb");

    if (!image) die("cannot allocate memory for new image");
    if (!fp)    die("cannot open file for reading");

    readPPMHeader(fp, &width, &height);

    size          = width * height * 3;
    image->data   = (unsigned  char*) malloc(size);
    image->width  = width;
    image->height = height;

    if (!image->data) die("cannot allocate memory for new image");

    num = fread((void *) image->data, 1, (size_t) size, fp);

    if (num != size) die("cannot read image data from file");

    fclose(fp);

    return image;
}

__host__
void ImageWrite(Image *image, char const *filename)
{
    int num;
    int size = image->width * image->height * 3;

    FILE *fp = fopen(filename, "wb");

    if (!fp) die("cannot open file for writing");

    fprintf(fp, "P6\n%d %d\n%d\n", image->width, image->height, 255);

    num = fwrite((void *) image->data, 1, (size_t) size, fp);

    if (num != size) die("cannot write image data to file");

    fclose(fp);
}  

__host__
int
ImageWidth(Image *image)
{
    return image->width;
}

__host__
int
ImageHeight(Image *image)
{
    return image->height;
}

__host__
void   
ImageClear(Image *image, unsigned char red, unsigned char green, unsigned char blue)
{
    int i;
    int pix = image->width * image->height;

    unsigned char *data = image->data;

    for (i = 0; i < pix; i++)
    {
        *data++ = red;
        *data++ = green;
        *data++ = blue;
    }
}

__device__
void ImageSetPixel(unsigned char* data, int x, int y, int chan, unsigned char val,int width)    // changed for data use
{
    int offset = (y * width + x) * 3 + chan;

    data[offset] = val;
}


__device__
unsigned  char ImageGetPixel(unsigned char* data, int x, int y, int chan, int width)    //changed for data use
{
    int offset = (y * width + x) * 3 + chan;

    return data[offset];
}    


//========================================================================================//
//==============================          MY CODE          ===============================//
//========================================================================================//

typedef struct pix{
    int r,g,b;

}pix;


//--------------------------------KERNEL FUNCTION---------------------//   

__device__
pix getAvg(unsigned char* data,int w,int h,int r,int x, int y){
    pix avg = {0};

    
    int xMin, xMax, yMin, yMax;

    if((xMin = x-r) < 0) xMin = 0;
    if((yMin = y-r) < 0) yMin = 0;              //define bounds
    if((xMax = x+r) > w-1) xMax = w;
    if((yMax = y+r) > h-1) yMax = h;

    int i;
    int j;
        
    for(i=yMin; i < yMax; i++){        //i is y, j is x for row first iteration
        for(j=xMin; j < xMax; j++){    //efficient for cache
        
        avg.r += ImageGetPixel(data,j,i,0,w); 
        avg.g += ImageGetPixel(data,j,i,1,w); 
        avg.b += ImageGetPixel(data,j,i,2,w); 

        }
    }


    int num = (yMax-yMin)*(xMax-xMin);
    

    avg.r = avg.r/num;
    avg.g = avg.g/num;
    avg.b = avg.b/num;

    return avg;    
    
}

//--------------------------KERNEL---------------------------//

__global__
void myKernel(unsigned char* oldData, unsigned char* newData,int WIDTH, int HEIGHT, int r){


    int indx = blockIdx.x * blockDim.x + threadIdx.x;
    int indy = blockIdx.y * blockDim.y + threadIdx.y;

    pix avg;

    int stride_x = gridDim.x*blockDim.x;
    int stride_y = gridDim.y*blockDim.y;

    int i;
    int j;
    for(i=indy; i<HEIGHT; i+= stride_y){
        for(j=indx; j<WIDTH; j+= stride_x){

            avg = getAvg(oldData,WIDTH,HEIGHT,r,j,i);


            ImageSetPixel(newData,j,i,0,avg.r,WIDTH);
            ImageSetPixel(newData,j,i,1,avg.g,WIDTH);
            ImageSetPixel(newData,j,i,2,avg.b,WIDTH);
        }
    }
}


//------------------------------------MAIN----------------------------------//

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

    //------------------cuda init----------------//

    dim3 blockDim(32,32);   //1024
    dim3 gridDim(20,20);

    int dsize = WIDTH*HEIGHT*3;         //size of data

    unsigned char* oldDataDevice;             //device data 
    unsigned char* newDataDevice;

    cudaMalloc(&oldDataDevice,dsize);
    cudaMalloc(&newDataDevice,dsize);

    cudaMemcpy(oldDataDevice,oldPic->data,dsize,cudaMemcpyHostToDevice);    //copy to device data

    //----------------------KERNEL--------------------//
    
    myKernel<<<gridDim,blockDim>>>(oldDataDevice,newDataDevice,WIDTH,HEIGHT,r);
    cudaDeviceSynchronize();

    //----------------------post proccess------------------------//

    cudaMemcpy(newPic->data,newDataDevice,dsize, cudaMemcpyDeviceToHost);           //copy back
    ImageWrite(newPic,outFile);

    cudaFree(oldDataDevice);
    cudaFree(newDataDevice);
    printf("New picture written to: %s\n",outFile);

    return 0;
}    

