# wraptool-cpp2nim
Macros allowing generating compact and readable wrappers to C++ classes fior Nim programming language

Macros allow you create C++ code wrapper in style:
```Nimrod
namespace("<opencv2/core.hpp>", "cv"):
  annotate_class(Size[T], "Size_"):
    proc Size(w, h: T)
    proc area*(): T
    
  annotate_class(Rect[T], "Rect_"):
    proc Rect(x, y, w, h: T)
    proc area*(): T
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
  
  template<typename _Tp> class Size_
  {
  public:
    Size_();
    Size_(_Tp _width, _Tp _height);
    _Tp area() const;
}
```

Documentation generated automaticaly if following command executed:
```Bash
$ nim doc wraptool.nim
```
