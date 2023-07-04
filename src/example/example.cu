#include <gputt.h>
#include <gputt_runtime.h>

#include <iostream>
#include <vector>

//
// Error checking wrapper for gpuTT and vendor API.
//

#define GPUTT_ERR_CHECK(stmt)                                                  \
  do {                                                                         \
    gputtResult err = stmt;                                                    \
    if (err != GPUTT_SUCCESS) {                                                \
      fprintf(stderr, "Error \"%d\" at %s :%d\n", err, __FILE__, __LINE__);    \
      exit(-1);                                                                \
    }                                                                          \
  } while (0)

#define GPU_ERR_CHECK(x)                                                       \
  do {                                                                         \
    gpuError_t err = x;                                                        \
    if (err != gpuSuccess) {                                                   \
      fprintf(stderr, "Error \"%s\" at %s :%d \n", gpuGetErrorString(err),     \
              __FILE__, __LINE__);                                             \
      exit(-1);                                                                \
    }                                                                          \
  } while (0)

template <typename D, typename T>
static void check(D &dim, T &idata, T &odata) {
  // Perform the same permutation on the CPU.
  T odata2(odata.size());
  for (int d0 = 0; d0 < dim[0]; d0++)
    for (int d1 = 0; d1 < dim[1]; d1++)
      for (int d2 = 0; d2 < dim[2]; d2++)
        for (int d3 = 0; d3 < dim[3]; d3++) {
          auto in = idata[d3 * dim[2] * dim[1] * dim[0] + d2 * dim[1] * dim[0] +
                          d1 * dim[0] + d0];

          // int permutation[4] = {3, 0, 2, 1};
          auto &out2 = odata2[d1 * dim[2] * dim[0] * dim[3] +
                              d2 * dim[0] * dim[3] + d0 * dim[3] + d3];

          out2 = in;

          // Compare with gpuTT's output element.
          auto out = odata[d1 * dim[2] * dim[0] * dim[3] +
                           d2 * dim[0] * dim[3] + d0 * dim[3] + d3];
#if 1
          if (out != out2) {
            std::cout << "Output elements mismatch at [" << d0 << "][" << d1
                      << "][" << d2 << "][" << d3 << "]: " << out
                      << " != " << out2 << std::endl;
            exit(-1);
          }
#endif
        }

  if (memcmp(odata.data(), odata2.data(), odata.size() * sizeof(odata[0]))) {
    fprintf(stderr, "Output tensors mismatch\n");
#if 1
    exit(-1);
#endif
  }
}

template <typename T> static void test() {
  std::cout << "Testing for type size = " << sizeof(T) << std::endl;
  
  // Four dimensional tensor
  // Transpose (31, 549, 2, 3) -> (3, 31, 2, 549)
  int dim[4] = {31, 549, 2, 3};
  int permutation[4] = {3, 0, 2, 1};

  std::vector<T> idata(dim[0] * dim[1] * dim[2] * dim[3]);
  for (int i = 0; i < idata.size(); i++)
    idata[i] = i;
  std::vector<T> odata(idata.size());

  gputtHandle plan;
  std::vector<gputtHandle> plans;

  // Option 1: Create plan on NULL stream and choose the method manually.
  for (int i = 0; i < NumTransposeMethods; i++) {
    auto method = static_cast<gputtTransposeMethod>(i);

    // Only use the methods that are supported for the given parameters.
    if (GPUTT_SUCCESS ==
        gputtPlan(&plan, 4, dim, permutation, sizeof(idata[0]), 0, method))
      plans.push_back(plan);
  }

  // Option 2: Create plan on NULL stream and choose the method based on
  // heuristics GPUTT_ERR_CHECK(gputtPlan(&plan, 4, dim, permutation,
  // sizeof(idata[0]), 0)); plans.push_back(plan);

  // Option 3: Create plan on NULL stream and choose the method based on
  // performance measurements GPUTT_ERR_CHECK(gputtPlanMeasure(&plan, 4, dim,
  // permutation, sizeof(idata[0]), 0, idata, odata)); plans.push_back(plan);

  for (auto plan : plans) {
    T *idataGPU;
    GPU_ERR_CHECK(gpuMalloc(&idataGPU, idata.size() * sizeof(idata[0])));
    GPU_ERR_CHECK(gpuMemcpy(idataGPU, idata.data(),
                            idata.size() * sizeof(idata[0]),
                            gpuMemcpyHostToDevice));

    T *odataGPU;
    GPU_ERR_CHECK(gpuMalloc(&odataGPU, odata.size() * sizeof(odata[0])));

    gputtTransposeMethod method;
    GPUTT_ERR_CHECK(gputtPlanMethod(plan, &method));
    std::cout << "Testing method " << method << std::endl;

    // Execute plan
    GPUTT_ERR_CHECK(gputtExecute(plan, idataGPU, odataGPU));

    GPU_ERR_CHECK(gpuDeviceSynchronize());

    GPU_ERR_CHECK(gpuMemcpy(odata.data(), odataGPU,
                            odata.size() * sizeof(odata[0]),
                            gpuMemcpyDeviceToHost));

    // Destroy plan
    GPUTT_ERR_CHECK(gputtDestroy(plan));

    GPU_ERR_CHECK(gpuFree(idataGPU));
    GPU_ERR_CHECK(gpuFree(odataGPU));

    check(dim, idata, odata);
  }
}

int main(int argc, char *argv[]) {
  // Using integer element type to ease elements comparison.
#if 0
  test<uint16_t>();
#endif
  test<uint32_t>();
  test<uint64_t>();

  return 0;
}
