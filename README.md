# wraptool-cpp2nim
Macros allowing generating compact and readable wrappers to C++ classes for Nim programming language

Work in progress.

Macros allow you create C++ code wrapper in style:
```Nimrod
wrapheader "<opencv2/core.hpp>":
  namespace "cv":
    class "Size_" as Size[T]:
      proc Size(w, h: T)
      proc area*(): T
      
    class Mat:
      proc Mat(rows, cols, t: cint)
      proc clone(): Mat
```
for code like following:
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
