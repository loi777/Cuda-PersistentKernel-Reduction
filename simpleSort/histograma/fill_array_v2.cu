#include <iostream>
#include <cuda.h>
#include <limits>

typedef unsigned int u_int;

#define BLOCKS 8                            // one block for one histogram
#define THREADS 5                           // n of threads

#define ARRAYSIZE 10                        // Size of the input array
#define HIST_SEGMENTATIONS 5                // BINS number

#define SEG_SIZE (ceil((float)ARRAYSIZE/(float)BLOCKS))   // Every block will solve this size, minimun of 1

#define HISTOGRAM (BLOCKS*HIST_SEGMENTATIONS)             // the full histogram, block:y | segmentation:x

// The input array  // only for testing
//const int h_input[ARRAYSIZE] = {2, 4, 33, 27, 8, 10, 42, 3, 12, 21, 10, 12, 15, 27, 38, 45, 18, 22};

#define BINSTART(min, binSize, i) ((u_int)((binWidth*i)+min))
#define BINEND(min, binSize, i) ((u_int)(BINSTART(min, binSize, (i+1))-1))
#define BINFIND(min, max, val, binSize, binQtd) (val >= max ? binQtd-1 : (val - min) / binSize)

//---------------------------------------------------------------



// Create and generate a random array of nElements
// returns as a pointer
u_int* genRandomArray(int nElem) {
  u_int* array = new u_int[nElem];

  for (int i = 0; i < nElem; ++i) {
    int a = std::rand() % 50;
    int b = std::rand();
    u_int v = a * 100 + b;
    array[i] = v;
  }

  return array;
}



//---------------------------------------------------------------



// returns the size of the number group of each bin
// needs some strange calculations due to precision error
u_int getBinSize(u_int min, u_int max, int segCount) {
  u_int binSize = max - min;
  if ((binSize % segCount) == 0) {
    // complete division
    binSize /= segCount;

  } else {
    // incomplete division
    binSize /= segCount;
    binSize++;

  }

  return binSize;
}


// returns the min value of an Array
u_int getMin(u_int* Array, int nElem) {
  u_int min = UINT_MAX;

  for (int i = 0; i < nElem; ++i) {
    if (Array[i] < min) {
        min = Array[i];
    }
  }

  return min;
}


// returns the max value of an Array
u_int getMax(u_int* Array, int nElem) {
  u_int max = 0;    // minimun value of an unsigned variable is 0

  for (int i = 0; i < nElem; ++i) {
    if (Array[i] > max) {
        max = Array[i];
    }
  }

  return max;
}



//---------------------------------------------------------------



// Debugg function to print an array
void printArray(u_int* a, int size) {
    // Print the generated array, do not allow this with arrays of billions
    for (int i = 0; i < size; i++) {
        std::cout << a[i] << " ";
    }
    std::cout << std::endl;
}


// Debugg function to print an array
void printSegmentations(u_int min, u_int max, u_int* a, int size, int segCount) {
    u_int binWidth = getBinSize(min, max, segCount);  

    //--

    std::cout << "min: " << min << " | max: " << max << std::endl;
    std::cout << "Bin Size: " << binWidth << std::endl;
    for (int i = 0; i < segCount; i++) {
        std::cout << "Seg|Bin [" << i << "]: " << BINSTART(min, binWidth, i) << " to " << BINEND(min, binWidth, i) << "\n";
    }
    std::cout << std::endl;
}



//---------------------------------------------------------------



// Kernel para calcular histogramas em particoes
// Cada bloco eh responsavel por um histograma (linha da matriz)
__global__ void calculateHistogram(const u_int *input, int *histograms, int arraySize, int segSize, int segCount, u_int minVal, u_int maxVal, u_int binWidth) {
    // Alloca shared memory para UM histograma
    extern __shared__ int sharedHist[];

    __syncthreads();  // threads will wait for the shared memory to be finished

    //---

    // Inicio da particao no vetor
    int blcStart = (blockIdx.x * segSize);    // bloco positionado na frente daquele que veio anterior a ele
    int thrPosi = threadIdx.x;              // 1 elemento por thread, starts as exactly the thread.x

    while(thrPosi < segSize && ((blcStart+thrPosi) < arraySize)) {
        // Loop enquanto a thread estiver resolvendo elementos validos dentro do bloco e do array

        u_int val = input[blcStart + thrPosi];    // get value
        atomicAdd(&sharedHist[BINFIND(minVal, maxVal, val, binWidth, segCount)], 1);  // add to its corresponding segment
        printf("DEBUGG: Blk(%d) Thr(%d): hist %d for number [%d] = %d\n", blockIdx.x, threadIdx.x, BINFIND(minVal, maxVal, val, binWidth, segCount), blcStart + thrPosi, val);

        thrPosi += blockDim.x; // thread pula para frente, garantindo que nao ira processar um valor ja processado
        // saira do bloco quando terminar todos os pixeis dos quais eh responsavel
    }

    __syncthreads();

    //--

    // Passa os resultados da shared memory para matriz
    // deixar isso a cargo da thread 0 eh mais modular que mandar uma pra uma
    if (threadIdx.x == 0) {
      for (int i = 0; i < segCount; i++) {
        atomicAdd(&histograms[(blockIdx.x * segCount) + i], sharedHist[i]); 
      }
    }
    // Y: (blockIdx.x * segCount)
    // X: threadIdx.x

    __syncthreads();
}



//---------------------------------------------------------------



int main() {
    ////======= ARRAY
    u_int *d_input;
    u_int* h_input = genRandomArray(ARRAYSIZE);

    // Allocate memory on the device
    cudaMalloc((void**)&d_input, ARRAYSIZE * sizeof(u_int));
    cudaMemcpy(d_input, h_input, ARRAYSIZE * sizeof(u_int), cudaMemcpyHostToDevice);

    u_int min = getMin(h_input, ARRAYSIZE);
    u_int max = getMax(h_input, ARRAYSIZE);
    u_int binWidth = getBinSize(min, max, HIST_SEGMENTATIONS);

    printArray(h_input, ARRAYSIZE);
    printSegmentations(min, max, h_input, ARRAYSIZE, HIST_SEGMENTATIONS);

    ////======= HISTOGRAM

    int *d_histograms;
    int h_histograms[BLOCKS][HIST_SEGMENTATIONS] = {0};

    // Allocate memory on the device
    cudaMalloc((void**)&d_histograms, HISTOGRAM * sizeof(int));
    cudaMemset(d_histograms, 0, HISTOGRAM * sizeof(int));  // Initialize histograms to 0

    ////======= KERNEL

    // Launch kernel
    calculateHistogram<<<BLOCKS, THREADS, SEG_SIZE>>>(d_input, d_histograms, ARRAYSIZE, SEG_SIZE, HIST_SEGMENTATIONS, min, max, binWidth);

    ////======= COPY BACK

    // Copy result back to host
    cudaMemcpy(h_histograms, d_histograms, HISTOGRAM * sizeof(int), cudaMemcpyDeviceToHost);

    ////======= PRINT RESULT

    // Print the histograms
    for (int i = 0; i < BLOCKS; i++) {
        std::cout << "Histogram " << i << ": ";
        for (int j = 0; j < HIST_SEGMENTATIONS; j++)
            std::cout << h_histograms[i][j] << " ";
        std::cout << std::endl;
    }

    ////======= FREE MEMORY

    // Free device memory
    cudaFree(d_input);
    cudaFree(d_histograms);

    return 0;
}

