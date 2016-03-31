# wraptool-cpp2nim
Macros allowing generating compact and readable wrappers to C++ classes for Nim programming language

Work in progress.

Macros allow you create C++ code wrapper in following style:
```Nimrod
wrapheader "<opencv2/core.hpp>":
  namespace "cv":
    class "Rect_" as Rect[T]:
      proc Rect(x, y, w, h: T)
      proc area*(): T
      
    class Mat:
      proc Mat(rows, cols, t: cint)
      proc clone(): Mat
```
The code above will be expanded to:
```Nimrod
type
    Rect* {.importcpp: "cv::Rect_<\'0>", header: "<opencv2/core.hpp>".}[T] = object
    Mat* {.importcpp: "cv::Mat", header: "<opencv2/core.hpp>".} = object
proc newRect*[T](): Rect[T] {.importcpp: "cv::Rect(@)",
                           header: "<opencv2/core.hpp>", constructor.}
proc newRect*[T](x, y, w, h: T): Rect[T] {.importcpp: "cv::Rect(@)",
                                    header: "<opencv2/core.hpp>", constructor.}
proc area*[T](this: Rect[T]): T {.importcpp: "#.cv::Rect_<\'0>::area(@)",
                              header: "<opencv2/core.hpp>".}
proc newMat*(): Mat {.importcpp: "cv::Mat(@)", header: "<opencv2/core.hpp>",
                   constructor.}
proc newMat*(rows, cols, t: cint): Mat {.importcpp: "cv::Mat(@)",
                                   header: "<opencv2/core.hpp>", constructor.}
proc clone*(this: Mat): Mat {.importcpp: "#.cv::Mat::clone(@)",
                          header: "<opencv2/core.hpp>".} 
```
for header like following:
```C++
namespace cv {
  template<typename _Tp> class Rect_
  {
  public:
    Rect_();
    Rect_(_Tp _x, _Tp _y, _Tp _width, _Tp _height);
    _Tp area() const;
  }
  
  class Mat
  {
  public:
    Mat();
    Mat(int rows, int cols);
    Mat clone();
}
```
Documentation generated automaticaly if following command executed:
```Bash
$ nim doc wraptool.nim
```
