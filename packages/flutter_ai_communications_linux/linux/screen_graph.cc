#include "screen_graph.h"

#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <gdk/gdk.h>
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#include <gio/gio.h>
#include <gio/gunixfdlist.h>
#include <gtk/gtk.h>
#include <linux/dma-buf.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <mutex>
#include <algorithm>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <stdio.h>
#include <cstring>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#ifdef FAC_HAS_PIPEWIRE
#include <pipewire/pipewire.h>
#include <spa/param/buffers.h>
#include <spa/param/video/format-utils.h>
#include <spa/param/video/raw.h>
#include <spa/pod/builder.h>
#ifdef FAC_HAS_EGL_DMABUF
#define EGL_EGLEXT_PROTOTYPES
#define GL_GLEXT_PROTOTYPES
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <drm/drm_fourcc.h>
#ifndef EGL_LINUX_DMA_BUF_EXT
#define EGL_LINUX_DMA_BUF_EXT 0x3270
#endif
#ifndef EGL_LINUX_DRM_FOURCC_EXT
#define EGL_LINUX_DRM_FOURCC_EXT 0x3271
#endif
#ifndef EGL_DMA_BUF_PLANE0_FD_EXT
#define EGL_DMA_BUF_PLANE0_FD_EXT 0x3272
#define EGL_DMA_BUF_PLANE0_OFFSET_EXT 0x3273
#define EGL_DMA_BUF_PLANE0_PITCH_EXT 0x3274
#endif
#ifndef EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT
#define EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT 0x3443
#define EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT 0x3444
#endif
#ifndef EGL_PLATFORM_GBM_KHR
#define EGL_PLATFORM_GBM_KHR 0x31D7
#endif
#ifndef GL_TEXTURE_EXTERNAL_OES
#define GL_TEXTURE_EXTERNAL_OES 0x8D65
#endif
#endif
#endif

namespace {

void FacScreenLog(const char* fmt, ...) G_GNUC_PRINTF(1, 2);
void FacScreenLog(const char* fmt, ...) {
  FILE* file = fopen("/tmp/fac-screen.log", "a");
  if (file == nullptr) {
    return;
  }
  va_list args;
  va_start(args, fmt);
  vfprintf(file, fmt, args);
  va_end(args);
  fputc('\n', file);
  fclose(file);
}

}  // namespace

struct ScreenGraph::PwCapture {
#ifdef FAC_HAS_PIPEWIRE
  pw_thread_loop* loop = nullptr;
  pw_context* context = nullptr;
  pw_core* core = nullptr;
  pw_stream* stream = nullptr;
  spa_hook listener{};
  pw_stream_events events{};
  uint32_t spa_format = 0;
  int src_w = 0;
  int src_h = 0;
  int process_logs = 0;
#ifdef FAC_HAS_EGL_DMABUF
  EGLDisplay egl_dpy = EGL_NO_DISPLAY;
  EGLContext egl_ctx = EGL_NO_CONTEXT;
  EGLSurface egl_surf = EGL_NO_SURFACE;
  EGLConfig egl_cfg{};
  GLuint gl_tex = 0;
  GLuint ext_tex = 0;
  GLuint color_tex = 0;
  GLuint gl_fbo = 0;
  GLuint blit_prog = 0;
  GLuint blit_vbo = 0;
  int color_w = 0;
  int color_h = 0;
  PFNEGLCREATEIMAGEKHRPROC create_image = nullptr;
  PFNEGLDESTROYIMAGEKHRPROC destroy_image = nullptr;
  PFNGLEGLIMAGETARGETTEXTURE2DOESPROC image_target = nullptr;
  bool egl_ok = false;
  bool egl_tried = false;
  uint64_t modifier = 0;
  bool has_modifier = false;
  int gbm_fd = -1;
  void* gbm_dev = nullptr;
  void* gbm_lib = nullptr;
#endif
#endif
};

#ifdef FAC_HAS_EGL_DMABUF
namespace {

GLuint FacCompileShader(GLenum type, const char* src) {
  const GLuint shader = glCreateShader(type);
  glShaderSource(shader, 1, &src, nullptr);
  glCompileShader(shader);
  GLint ok = 0;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
  if (ok != GL_TRUE) {
    char log[256];
    glGetShaderInfoLog(shader, sizeof(log), nullptr, log);
    FacScreenLog("shader compile failed %s", log);
    glDeleteShader(shader);
    return 0;
  }
  return shader;
}

}  // namespace

bool ScreenGraph::InitEglDmaBuf() {
  if (pw_ == nullptr) {
    return false;
  }
  if (pw_->egl_tried) {
    return pw_->egl_ok;
  }
  pw_->egl_tried = true;

  auto bind_display = [this](EGLDisplay dpy, const char* tag) -> bool {
    if (dpy == EGL_NO_DISPLAY) {
      FacScreenLog("egl display %s missing", tag);
      return false;
    }
    if (!eglInitialize(dpy, nullptr, nullptr)) {
      FacScreenLog("eglInitialize %s failed %d", tag, eglGetError());
      return false;
    }
    eglBindAPI(EGL_OPENGL_ES_API);
    const EGLint cfg_attrs[] = {EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
                                EGL_SURFACE_TYPE, EGL_PBUFFER_BIT | EGL_WINDOW_BIT,
                                EGL_NONE};
    EGLint ncfg = 0;
    if (!eglChooseConfig(dpy, cfg_attrs, &pw_->egl_cfg, 1, &ncfg) || ncfg < 1) {
      const EGLint fallback[] = {EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
                                 EGL_NONE};
      if (!eglChooseConfig(dpy, fallback, &pw_->egl_cfg, 1, &ncfg) ||
          ncfg < 1) {
        FacScreenLog("eglChooseConfig %s failed", tag);
        eglTerminate(dpy);
        return false;
      }
    }
    const EGLint ctx_attrs[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
    EGLContext ctx = eglCreateContext(dpy, pw_->egl_cfg, EGL_NO_CONTEXT,
                                      ctx_attrs);
    if (ctx == EGL_NO_CONTEXT) {
      FacScreenLog("eglCreateContext %s failed %d", tag, eglGetError());
      eglTerminate(dpy);
      return false;
    }
    EGLSurface surf = EGL_NO_SURFACE;
    if (!eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) {
      const EGLint pb[] = {EGL_WIDTH, 64, EGL_HEIGHT, 64, EGL_NONE};
      surf = eglCreatePbufferSurface(dpy, pw_->egl_cfg, pb);
      if (surf == EGL_NO_SURFACE ||
          !eglMakeCurrent(dpy, surf, surf, ctx)) {
        FacScreenLog("eglMakeCurrent %s failed %d", tag, eglGetError());
        if (surf != EGL_NO_SURFACE) {
          eglDestroySurface(dpy, surf);
        }
        eglDestroyContext(dpy, ctx);
        eglTerminate(dpy);
        return false;
      }
    }
    pw_->egl_dpy = dpy;
    pw_->egl_ctx = ctx;
    pw_->egl_surf = surf;
    pw_->create_image = reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(
        eglGetProcAddress("eglCreateImageKHR"));
    pw_->destroy_image = reinterpret_cast<PFNEGLDESTROYIMAGEKHRPROC>(
        eglGetProcAddress("eglDestroyImageKHR"));
    pw_->image_target = reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(
        eglGetProcAddress("glEGLImageTargetTexture2DOES"));
    if (pw_->create_image == nullptr || pw_->destroy_image == nullptr ||
        pw_->image_target == nullptr) {
      FacScreenLog("egl dma-buf procs missing (%s)", tag);
      return false;
    }
    const char* vendor =
        reinterpret_cast<const char*>(glGetString(GL_VENDOR));
    const char* renderer =
        reinterpret_cast<const char*>(glGetString(GL_RENDERER));
    const char* exts = eglQueryString(dpy, EGL_EXTENSIONS);
    FacScreenLog("egl %s vendor=%s renderer=%s exts=%s", tag,
                 vendor != nullptr ? vendor : "?",
                 renderer != nullptr ? renderer : "?",
                 exts != nullptr ? exts : "?");
    glGenTextures(1, &pw_->gl_tex);
    glGenTextures(1, &pw_->ext_tex);
    glGenTextures(1, &pw_->color_tex);
    glGenFramebuffers(1, &pw_->gl_fbo);
    glGenBuffers(1, &pw_->blit_vbo);
    const char* vs_src =
        "attribute vec2 a_pos;\n"
        "attribute vec2 a_uv;\n"
        "varying vec2 v_uv;\n"
        "void main() {\n"
        "  v_uv = a_uv;\n"
        "  gl_Position = vec4(a_pos, 0.0, 1.0);\n"
        "}\n";
    const char* fs_src =
        "#extension GL_OES_EGL_image_external : require\n"
        "precision mediump float;\n"
        "varying vec2 v_uv;\n"
        "uniform samplerExternalOES u_tex;\n"
        "void main() { gl_FragColor = texture2D(u_tex, v_uv); }\n";
    const GLuint vs = FacCompileShader(GL_VERTEX_SHADER, vs_src);
    const GLuint fs = FacCompileShader(GL_FRAGMENT_SHADER, fs_src);
    if (vs != 0 && fs != 0) {
      pw_->blit_prog = glCreateProgram();
      glAttachShader(pw_->blit_prog, vs);
      glAttachShader(pw_->blit_prog, fs);
      glBindAttribLocation(pw_->blit_prog, 0, "a_pos");
      glBindAttribLocation(pw_->blit_prog, 1, "a_uv");
      glLinkProgram(pw_->blit_prog);
      GLint linked = 0;
      glGetProgramiv(pw_->blit_prog, GL_LINK_STATUS, &linked);
      if (linked != GL_TRUE) {
        char log[256];
        glGetProgramInfoLog(pw_->blit_prog, sizeof(log), nullptr, log);
        FacScreenLog("blit link failed %s", log);
        glDeleteProgram(pw_->blit_prog);
        pw_->blit_prog = 0;
      }
    }
    if (vs != 0) {
      glDeleteShader(vs);
    }
    if (fs != 0) {
      glDeleteShader(fs);
    }
    const float quad[] = {
        -1.f, -1.f, 0.f, 0.f, 1.f, -1.f, 1.f, 0.f,
        -1.f,  1.f, 0.f, 1.f, 1.f,  1.f, 1.f, 1.f,
    };
    glBindBuffer(GL_ARRAY_BUFFER, pw_->blit_vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    pw_->egl_ok = true;
    FacScreenLog("egl dma-buf import ready (%s) blit=%d", tag,
                 pw_->blit_prog != 0 ? 1 : 0);
    return true;
  };

  if (bind_display(eglGetDisplay(EGL_DEFAULT_DISPLAY), "default")) {
    return true;
  }
  pw_->gbm_lib = dlopen("libgbm.so.1", RTLD_NOW);
  using GbmCreate = void* (*)(int);
  GbmCreate gbm_create = pw_->gbm_lib != nullptr
                             ? reinterpret_cast<GbmCreate>(
                                   dlsym(pw_->gbm_lib, "gbm_create_device"))
                             : nullptr;
  pw_->gbm_fd = open("/dev/dri/renderD128", O_RDWR | O_CLOEXEC);
  if (gbm_create != nullptr && pw_->gbm_fd >= 0) {
    pw_->gbm_dev = gbm_create(pw_->gbm_fd);
  }
  PFNEGLGETPLATFORMDISPLAYEXTPROC get_plat =
      reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(
          eglGetProcAddress("eglGetPlatformDisplayEXT"));
  if (get_plat == nullptr) {
    get_plat = reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(
        eglGetProcAddress("eglGetPlatformDisplay"));
  }
  if (get_plat != nullptr && pw_->gbm_dev != nullptr &&
      bind_display(get_plat(EGL_PLATFORM_GBM_KHR, pw_->gbm_dev, nullptr),
                   "gbm")) {
    return true;
  }
  FacScreenLog("egl dma-buf init failed gbm_fd=%d gbm_dev=%p", pw_->gbm_fd,
               pw_->gbm_dev);
  return false;
}

void ScreenGraph::DestroyEglDmaBuf() {
  if (pw_ == nullptr) {
    return;
  }
  if (pw_->egl_dpy != EGL_NO_DISPLAY && pw_->egl_ctx != EGL_NO_CONTEXT) {
    const EGLSurface surf =
        pw_->egl_surf == EGL_NO_SURFACE ? EGL_NO_SURFACE : pw_->egl_surf;
    eglMakeCurrent(pw_->egl_dpy, surf, surf, pw_->egl_ctx);
    if (pw_->gl_fbo != 0) {
      glDeleteFramebuffers(1, &pw_->gl_fbo);
      pw_->gl_fbo = 0;
    }
    if (pw_->gl_tex != 0) {
      glDeleteTextures(1, &pw_->gl_tex);
      pw_->gl_tex = 0;
    }
    if (pw_->ext_tex != 0) {
      glDeleteTextures(1, &pw_->ext_tex);
      pw_->ext_tex = 0;
    }
    if (pw_->color_tex != 0) {
      glDeleteTextures(1, &pw_->color_tex);
      pw_->color_tex = 0;
    }
    if (pw_->blit_vbo != 0) {
      glDeleteBuffers(1, &pw_->blit_vbo);
      pw_->blit_vbo = 0;
    }
    if (pw_->blit_prog != 0) {
      glDeleteProgram(pw_->blit_prog);
      pw_->blit_prog = 0;
    }
    eglMakeCurrent(pw_->egl_dpy, EGL_NO_SURFACE, EGL_NO_SURFACE,
                   EGL_NO_CONTEXT);
    if (pw_->egl_surf != EGL_NO_SURFACE) {
      eglDestroySurface(pw_->egl_dpy, pw_->egl_surf);
      pw_->egl_surf = EGL_NO_SURFACE;
    }
    eglDestroyContext(pw_->egl_dpy, pw_->egl_ctx);
    pw_->egl_ctx = EGL_NO_CONTEXT;
    eglTerminate(pw_->egl_dpy);
    pw_->egl_dpy = EGL_NO_DISPLAY;
  }
  if (pw_->gbm_dev != nullptr && pw_->gbm_lib != nullptr) {
    using GbmDestroy = void (*)(void*);
    auto destroy = reinterpret_cast<GbmDestroy>(
        dlsym(pw_->gbm_lib, "gbm_device_destroy"));
    if (destroy != nullptr) {
      destroy(pw_->gbm_dev);
    }
    pw_->gbm_dev = nullptr;
  }
  if (pw_->gbm_lib != nullptr) {
    dlclose(pw_->gbm_lib);
    pw_->gbm_lib = nullptr;
  }
  if (pw_->gbm_fd >= 0) {
    close(pw_->gbm_fd);
    pw_->gbm_fd = -1;
  }
  pw_->egl_ok = false;
}

bool ScreenGraph::CopyDmaBufEgl(int fd, int width, int height, int stride,
                                int offset, std::vector<uint8_t>* dest) {
  if (!InitEglDmaBuf() || pw_ == nullptr || dest == nullptr || fd < 0 ||
      width < 1 || height < 1 || stride < 1) {
    return false;
  }
  const EGLSurface surf =
      pw_->egl_surf == EGL_NO_SURFACE ? EGL_NO_SURFACE : pw_->egl_surf;
  if (!eglMakeCurrent(pw_->egl_dpy, surf, surf, pw_->egl_ctx)) {
    FacScreenLog("eglMakeCurrent frame failed %d", eglGetError());
    return false;
  }
  const EGLint fourccs[] = {DRM_FORMAT_XRGB8888, DRM_FORMAT_ARGB8888,
                            DRM_FORMAT_XBGR8888, DRM_FORMAT_ABGR8888};
  uint64_t mods[3];
  int nmods = 0;
  if (pw_->has_modifier) {
    mods[nmods++] = pw_->modifier;
  }
  mods[nmods++] = DRM_FORMAT_MOD_LINEAR;
  const bool try_bare = true;
  EGLImageKHR image = EGL_NO_IMAGE_KHR;
  EGLint used_fourcc = 0;
  for (EGLint fourcc : fourccs) {
    for (int m = 0; m < nmods + (try_bare ? 1 : 0); m++) {
      std::vector<EGLint> attribs = {
          EGL_WIDTH,
          width,
          EGL_HEIGHT,
          height,
          EGL_LINUX_DRM_FOURCC_EXT,
          fourcc,
          EGL_DMA_BUF_PLANE0_FD_EXT,
          fd,
          EGL_DMA_BUF_PLANE0_OFFSET_EXT,
          offset,
          EGL_DMA_BUF_PLANE0_PITCH_EXT,
          stride,
      };
      if (m < nmods) {
        attribs.push_back(EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT);
        attribs.push_back(static_cast<EGLint>(mods[m] & 0xffffffffu));
        attribs.push_back(EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT);
        attribs.push_back(static_cast<EGLint>(mods[m] >> 32));
      }
      attribs.push_back(EGL_NONE);
      eglGetError();
      image = pw_->create_image(pw_->egl_dpy, EGL_NO_CONTEXT,
                                EGL_LINUX_DMA_BUF_EXT, nullptr, attribs.data());
      if (image != EGL_NO_IMAGE_KHR) {
        used_fourcc = fourcc;
        break;
      }
    }
    if (image != EGL_NO_IMAGE_KHR) {
      break;
    }
  }
  if (image == EGL_NO_IMAGE_KHR) {
    FacScreenLog("eglCreateImageKHR failed %d fd=%d %dx%d stride=%d off=%d",
                 eglGetError(), fd, width, height, stride, offset);
    return false;
  }
  auto read_fbo = [&]() -> bool {
    dest->assign(static_cast<size_t>(width) * static_cast<size_t>(height) * 4,
                 0);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, dest->data());
    const GLenum err = glGetError();
    if (err != GL_NO_ERROR) {
      FacScreenLog("glReadPixels err=%x", err);
      return false;
    }
    const size_t row = static_cast<size_t>(width) * 4;
    for (int y = 0; y < height / 2; y++) {
      uint8_t* a = dest->data() + static_cast<size_t>(y) * row;
      uint8_t* b = dest->data() + static_cast<size_t>(height - 1 - y) * row;
      for (size_t i = 0; i < row; i++) {
        const uint8_t t = a[i];
        a[i] = b[i];
        b[i] = t;
      }
    }
    const size_t pixels = dest->size() / 4;
    const size_t step = std::max<size_t>(1, pixels / 32);
    for (size_t i = 0; i < pixels; i += step) {
      const uint8_t* px = dest->data() + i * 4;
      if (px[0] != 0 || px[1] != 0 || px[2] != 0) {
        return true;
      }
    }
    return false;
  };

  glBindTexture(GL_TEXTURE_2D, pw_->gl_tex);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  pw_->image_target(GL_TEXTURE_2D, image);
  glBindFramebuffer(GL_FRAMEBUFFER, pw_->gl_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                         pw_->gl_tex, 0);
  GLenum fbo = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  bool ok = false;
  if (fbo == GL_FRAMEBUFFER_COMPLETE && read_fbo()) {
    ok = true;
  } else if (pw_->blit_prog != 0) {
    if (pw_->color_w != width || pw_->color_h != height) {
      glBindTexture(GL_TEXTURE_2D, pw_->color_tex);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA,
                   GL_UNSIGNED_BYTE, nullptr);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
      pw_->color_w = width;
      pw_->color_h = height;
    }
    glBindTexture(GL_TEXTURE_EXTERNAL_OES, pw_->ext_tex);
    glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    pw_->image_target(GL_TEXTURE_EXTERNAL_OES, image);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                           pw_->color_tex, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE) {
      glViewport(0, 0, width, height);
      glUseProgram(pw_->blit_prog);
      glBindBuffer(GL_ARRAY_BUFFER, pw_->blit_vbo);
      glEnableVertexAttribArray(0);
      glEnableVertexAttribArray(1);
      glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 16, nullptr);
      glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 16,
                            reinterpret_cast<const void*>(8));
      const GLint loc = glGetUniformLocation(pw_->blit_prog, "u_tex");
      glActiveTexture(GL_TEXTURE0);
      glBindTexture(GL_TEXTURE_EXTERNAL_OES, pw_->ext_tex);
      if (loc >= 0) {
        glUniform1i(loc, 0);
      }
      glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
      glDisableVertexAttribArray(0);
      glDisableVertexAttribArray(1);
      glBindBuffer(GL_ARRAY_BUFFER, 0);
      glUseProgram(0);
      ok = read_fbo();
    } else {
      FacScreenLog("blit fbo incomplete %x (tex2d fbo=%x fourcc=%x)",
                   glCheckFramebufferStatus(GL_FRAMEBUFFER), fbo,
                   used_fourcc);
    }
  } else {
    FacScreenLog("fbo incomplete %x fourcc=%x no blit", fbo, used_fourcc);
  }
  pw_->destroy_image(pw_->egl_dpy, image);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  return ok;
}
#else
bool ScreenGraph::InitEglDmaBuf() { return false; }

void ScreenGraph::DestroyEglDmaBuf() {}

bool ScreenGraph::CopyDmaBufEgl(int fd, int width, int height, int stride,
                                int offset, std::vector<uint8_t>* dest) {
  (void)fd;
  (void)width;
  (void)height;
  (void)stride;
  (void)offset;
  (void)dest;
  return false;
}
#endif

namespace {

std::string WindowTitle(Display* display, Window window, Atom net_wm_name,
                        Atom utf8) {
  if (net_wm_name != None) {
    Atom actual = None;
    int format = 0;
    unsigned long nitems = 0;
    unsigned long bytes = 0;
    unsigned char* prop = nullptr;
    const Atom type = utf8 != None ? utf8 : AnyPropertyType;
    if (XGetWindowProperty(display, window, net_wm_name, 0, 1024, False, type,
                           &actual, &format, &nitems, &bytes, &prop) ==
            Success &&
        prop != nullptr && nitems > 0 && format == 8) {
      std::string name(reinterpret_cast<char*>(prop), nitems);
      XFree(prop);
      while (!name.empty() && name.back() == '\0') {
        name.pop_back();
      }
      if (!name.empty()) {
        return name;
      }
    } else if (prop != nullptr) {
      XFree(prop);
    }
  }
  char* name = nullptr;
  if (XFetchName(display, window, &name) && name != nullptr) {
    std::string out(name);
    XFree(name);
    return out;
  }
  return {};
}

std::string WindowApplicationName(Display* display, Window window) {
  XClassHint hint{};
  if (XGetClassHint(display, window, &hint) == 0) {
    return {};
  }
  std::string name;
  if (hint.res_class != nullptr && hint.res_class[0] != '\0') {
    name = hint.res_class;
  } else if (hint.res_name != nullptr && hint.res_name[0] != '\0') {
    name = hint.res_name;
  }
  if (hint.res_class != nullptr) {
    XFree(hint.res_class);
  }
  if (hint.res_name != nullptr) {
    XFree(hint.res_name);
  }
  return name;
}

FlValue* SourceValue(const std::string& id, const std::string& name,
                     const std::string& kind, int x, int y, int w, int h,
                     bool preview, const std::string& application_name) {
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "id", fl_value_new_string(id.c_str()));
  fl_value_set_string_take(map, "name", fl_value_new_string(name.c_str()));
  fl_value_set_string_take(map, "kind", fl_value_new_string(kind.c_str()));
  fl_value_set_string_take(map, "x", fl_value_new_int(x));
  fl_value_set_string_take(map, "y", fl_value_new_int(y));
  fl_value_set_string_take(map, "width", fl_value_new_int(w));
  fl_value_set_string_take(map, "height", fl_value_new_int(h));
  fl_value_set_string_take(map, "canPreview", fl_value_new_bool(preview));
  if (!application_name.empty()) {
    fl_value_set_string_take(map, "applicationName",
                             fl_value_new_string(application_name.c_str()));
  }
  return map;
}

int IgnoreXError(Display*, XErrorEvent*) { return 0; }

}  // namespace

G_DECLARE_FINAL_TYPE(FacScreenTexture, fac_screen_texture, FAC, SCREEN_TEXTURE,
                     FlPixelBufferTexture)

struct _FacScreenTexture {
  FlPixelBufferTexture parent_instance;
  ScreenGraph* graph;
};

G_DEFINE_TYPE(FacScreenTexture, fac_screen_texture,
              fl_pixel_buffer_texture_get_type())

static gboolean fac_screen_texture_copy_pixels(FlPixelBufferTexture* texture,
                                               const uint8_t** buffer,
                                               uint32_t* width, uint32_t* height,
                                               GError** error) {
  FacScreenTexture* self = FAC_SCREEN_TEXTURE(texture);
  if (self->graph == nullptr) {
    return FALSE;
  }
  return self->graph->CopyPixels(buffer, width, height, error);
}

static void fac_screen_texture_class_init(FacScreenTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
      fac_screen_texture_copy_pixels;
}

static void fac_screen_texture_init(FacScreenTexture* self) {
  self->graph = nullptr;
}

G_DECLARE_FINAL_TYPE(FacPreviewTexture, fac_preview_texture, FAC,
                     PREVIEW_TEXTURE, FlPixelBufferTexture)

struct _FacPreviewTexture {
  FlPixelBufferTexture parent_instance;
  ScreenGraph* graph;
  gchar* id;
};

G_DEFINE_TYPE(FacPreviewTexture, fac_preview_texture,
              fl_pixel_buffer_texture_get_type())

static gboolean fac_preview_texture_copy_pixels(FlPixelBufferTexture* texture,
                                                const uint8_t** buffer,
                                                uint32_t* width,
                                                uint32_t* height,
                                                GError** error) {
  FacPreviewTexture* self = FAC_PREVIEW_TEXTURE(texture);
  if (self->graph == nullptr || self->id == nullptr) {
    return FALSE;
  }
  return self->graph->CopyPreviewPixels(self->id, buffer, width, height, error);
}

static void fac_preview_texture_finalize(GObject* object) {
  FacPreviewTexture* self = FAC_PREVIEW_TEXTURE(object);
  g_free(self->id);
  self->id = nullptr;
  G_OBJECT_CLASS(fac_preview_texture_parent_class)->finalize(object);
}

static void fac_preview_texture_class_init(FacPreviewTextureClass* klass) {
  G_OBJECT_CLASS(klass)->finalize = fac_preview_texture_finalize;
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
      fac_preview_texture_copy_pixels;
}

static void fac_preview_texture_init(FacPreviewTexture* self) {
  self->graph = nullptr;
  self->id = nullptr;
}

ScreenGraph::ScreenGraph(FlTextureRegistrar* textures, GtkWidget* view)
    : textures_(textures), view_(view) {
  XInitThreads();
  XSetErrorHandler(IgnoreXError);
}

void ScreenGraph::EnsureDisplay() {
  if (display_ != nullptr) {
    return;
  }
  display_ = XOpenDisplay(nullptr);
}

void ScreenGraph::CloseDisplay() {
  if (display_ != nullptr) {
    if (frame_window_ != 0) {
      XDestroyWindow(display_, frame_window_);
      frame_window_ = 0;
    }
    XCloseDisplay(display_);
    display_ = nullptr;
  }
}

ScreenGraph::~ScreenGraph() {
  Stop();
  EndPick();
  HideFrame();
  CloseDisplay();
  if (textures_ != nullptr && texture_ != nullptr) {
    fl_texture_registrar_unregister_texture(textures_, FL_TEXTURE(texture_));
  }
  if (texture_ != nullptr) {
    g_object_unref(texture_);
    texture_ = nullptr;
  }
}

bool ScreenGraph::IsWaylandOnly() const {
  // Xwayland still sets DISPLAY; XGetImage of the compositor root is BadMatch.
  const char* session = std::getenv("XDG_SESSION_TYPE");
  return session != nullptr && std::strcmp(session, "wayland") == 0;
}

void ScreenGraph::RefreshSources() {
  sources_.clear();
  if (IsWaylandOnly()) {
    Source source;
    source.id = "system-picker";
    source.name = "System picker";
    source.kind = "systemPicker";
    sources_.push_back(source);
    return;
  }
  Display* display = XOpenDisplay(nullptr);
  if (display == nullptr) {
    Source source;
    source.id = "system-picker";
    source.name = "System picker";
    source.kind = "systemPicker";
    sources_.push_back(source);
    return;
  }
  Screen* screen = DefaultScreenOfDisplay(display);
  Source root;
  root.id = "display-0";
  root.name = "Display 1";
  root.kind = "display";
  root.width = WidthOfScreen(screen);
  root.height = HeightOfScreen(screen);
  root.window = RootWindowOfScreen(screen);
  sources_.push_back(root);
  Source all = root;
  all.id = "all-displays";
  all.name = "All displays";
  all.kind = "allDisplays";
  sources_.push_back(all);
  Window root_window = RootWindowOfScreen(screen);
  Window root_ret = 0;
  Window parent = 0;
  Window* children = nullptr;
  unsigned int count = 0;
  const Atom net_wm_name = XInternAtom(display, "_NET_WM_NAME", True);
  const Atom utf8 = XInternAtom(display, "UTF8_STRING", True);
  if (XQueryTree(display, root_window, &root_ret, &parent, &children, &count)) {
    for (unsigned int i = 0; i < count; i++) {
      XWindowAttributes attrs{};
      if (frame_window_ != 0 && children[i] == frame_window_) {
        continue;
      }
      if (!XGetWindowAttributes(display, children[i], &attrs) ||
          attrs.map_state != IsViewable || attrs.width < 64 ||
          attrs.height < 64) {
        continue;
      }
      const std::string title =
          WindowTitle(display, children[i], net_wm_name, utf8);
      const std::string app = WindowApplicationName(display, children[i]);
      if (title.empty() && app.empty()) {
        continue;
      }
      Source source;
      source.id = "window-" + std::to_string(children[i]);
      source.name = title;
      source.kind = "window";
      source.applicationName = app;
      source.x = attrs.x;
      source.y = attrs.y;
      source.width = attrs.width;
      source.height = attrs.height;
      source.window = children[i];
      sources_.push_back(source);
    }
    if (children != nullptr) {
      XFree(children);
    }
  }
  XCloseDisplay(display);
}

FlValue* ScreenGraph::Enumerate() {
  std::lock_guard<std::mutex> lock(mutex_);
  RefreshSources();
  FlValue* list = fl_value_new_list();
  for (const auto& source : sources_) {
    fl_value_append_take(
        list,
        SourceValue(source.id, source.name, source.kind, source.x, source.y,
                    source.width, source.height,
                    source.kind != "systemPicker", source.applicationName));
  }
  return list;
}

std::string ScreenGraph::RequestPermission() { return "granted"; }

void ScreenGraph::ClearPreviewsLocked() {
  for (auto& [id, preview] : previews_) {
    if (textures_ != nullptr && preview->texture != nullptr) {
      fl_texture_registrar_unregister_texture(textures_,
                                              FL_TEXTURE(preview->texture));
      g_object_unref(preview->texture);
      preview->texture = nullptr;
    }
  }
  previews_.clear();
}

FlValue* ScreenGraph::BeginPick() {
  std::lock_guard<std::mutex> lock(mutex_);
  ClearPreviewsLocked();
  RefreshSources();
  if (IsWaylandOnly()) {
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "previews", fl_value_new_map());
    return map;
  }
  EnsureDisplay();
  FlValue* previews = fl_value_new_map();
  for (const auto& source : sources_) {
    if (source.window == 0) {
      continue;
    }
    auto preview = std::make_unique<Preview>();
    auto* pixel = FAC_PREVIEW_TEXTURE(
        g_object_new(fac_preview_texture_get_type(), nullptr));
    pixel->graph = this;
    pixel->id = g_strdup(source.id.c_str());
    preview->texture = FL_PIXEL_BUFFER_TEXTURE(pixel);
    if (textures_ == nullptr ||
        !fl_texture_registrar_register_texture(textures_,
                                               FL_TEXTURE(preview->texture))) {
      g_object_unref(preview->texture);
      preview->texture = nullptr;
      continue;
    }
    CaptureX11(source, preview->width, preview->height, &preview->pixels);
    fl_texture_registrar_mark_texture_frame_available(
        textures_, FL_TEXTURE(preview->texture));
    fl_value_set_string_take(
        previews, source.id.c_str(),
        fl_value_new_int(fl_texture_get_id(FL_TEXTURE(preview->texture))));
    previews_[source.id] = std::move(preview);
  }
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "previews", previews);
  return map;
}

void ScreenGraph::EndPick() {
  std::lock_guard<std::mutex> lock(mutex_);
  ClearPreviewsLocked();
}

void ScreenGraph::Indicate(const std::string& source_id) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (source_id.empty() || IsWaylandOnly()) {
    HideFrame();
    return;
  }
  for (const auto& source : sources_) {
    if (source.id == source_id) {
      ShowFrame(source.x, source.y, source.width, source.height);
      return;
    }
  }
}

void ScreenGraph::ShowFrame(int x, int y, int w, int h) {
  EnsureDisplay();
  if (display_ == nullptr || w < 8 || h < 8) {
    return;
  }
  if (frame_window_ == 0) {
    XSetWindowAttributes attrs{};
    attrs.override_redirect = True;
    attrs.border_pixel = 0x00C42020;
    attrs.background_pixmap = None;
    frame_window_ = XCreateWindow(
        display_, DefaultRootWindow(display_), x, y, static_cast<unsigned>(w),
        static_cast<unsigned>(h), 4, CopyFromParent, InputOutput, CopyFromParent,
        CWOverrideRedirect | CWBorderPixel | CWBackPixmap, &attrs);
  } else {
    XMoveResizeWindow(display_, frame_window_, x, y, static_cast<unsigned>(w),
                      static_cast<unsigned>(h));
  }
  XMapRaised(display_, frame_window_);
  XFlush(display_);
}

void ScreenGraph::HideFrame() {
  if (display_ == nullptr || frame_window_ == 0) {
    return;
  }
  XUnmapWindow(display_, frame_window_);
  XFlush(display_);
}

void ScreenGraph::EnsureTexture() {
  if (texture_ != nullptr || textures_ == nullptr) {
    return;
  }
  auto* pixel =
      FAC_SCREEN_TEXTURE(g_object_new(fac_screen_texture_get_type(), nullptr));
  pixel->graph = this;
  texture_ = FL_PIXEL_BUFFER_TEXTURE(pixel);
  if (!fl_texture_registrar_register_texture(textures_, FL_TEXTURE(texture_))) {
    g_object_unref(texture_);
    texture_ = nullptr;
    return;
  }
  texture_id_ = fl_texture_get_id(FL_TEXTURE(texture_));
}

FlValue* ScreenGraph::Start(const std::string& source_id, bool, bool cursor,
                            bool motion, FlMethodCall* pending) {
  Stop();
  std::lock_guard<std::mutex> lock(mutex_);
  RefreshSources();
  const Source* found = nullptr;
  for (const auto& source : sources_) {
    if (source.id == source_id ||
        (source_id == "system-picker" && source.kind == "display")) {
      found = &source;
      break;
    }
  }
  FlValue* result = fl_value_new_map();
  if (found != nullptr && found->kind == "systemPicker") {
    cursor_ = cursor;
    motion_ = motion;
    if (StartPortal(pending, cursor, motion)) {
      fl_value_unref(result);
      return nullptr;
    }
    fl_value_set_string_take(result, "status",
                             fl_value_new_string("unavailable"));
    fl_value_set_string_take(result, "reason", fl_value_new_string("none"));
    return result;
  }
  if (found == nullptr) {
    fl_value_set_string_take(result, "status",
                             fl_value_new_string("unavailable"));
    fl_value_set_string_take(result, "reason", fl_value_new_string("none"));
    return result;
  }
  cursor_ = cursor;
  motion_ = motion;
  send_id_ = found->id;
  int src_w = std::max(1, found->width);
  int src_h = std::max(1, found->height);
  double scale = 1.0;
  if (src_w > 1920 || src_h > 1080) {
    scale = std::min(1920.0 / src_w, 1080.0 / src_h);
  }
  send_width_ = std::max(1, static_cast<int>(src_w * scale));
  send_height_ = std::max(1, static_cast<int>(src_h * scale));
  EnsureTexture();
  EnsureDisplay();
  ShowFrame(found->x, found->y, found->width, found->height);
  running_ = true;
  capture_thread_ = std::thread([this] { CaptureLoop(); });
  fl_value_set_string_take(result, "status", fl_value_new_string("started"));
  fl_value_set_string_take(result, "textureId", fl_value_new_int(texture_id_));
  fl_value_set_string_take(result, "width", fl_value_new_int(send_width_));
  fl_value_set_string_take(result, "height", fl_value_new_int(send_height_));
  fl_value_set_string_take(result, "frameRate",
                           fl_value_new_int(motion ? 30 : 5));
  return result;
}

void ScreenGraph::Stop() {
  running_ = false;
  CancelPortal();
  StopPipeWire();
  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }
  HideFrame();
  send_id_.clear();
  if (!portal_session_.empty()) {
    g_autoptr(GError) error = nullptr;
    g_autoptr(GDBusConnection) bus =
        g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
    if (bus != nullptr) {
      g_dbus_connection_call_sync(
          bus, "org.freedesktop.portal.Desktop", portal_session_.c_str(),
          "org.freedesktop.portal.Session", "Close", nullptr, nullptr,
          G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, &error);
    }
    portal_session_.clear();
  }
  CloseDisplay();
}

bool ScreenGraph::SetIncludeSystemAudio(bool) { return false; }

void ScreenGraph::SetMotion(bool motion) { motion_ = motion; }

void ScreenGraph::SetCursor(bool cursor) { cursor_ = cursor; }

void ScreenGraph::CaptureLoop() {
  while (running_) {
    Source snapshot;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      for (const auto& source : sources_) {
        if (source.id == send_id_) {
          snapshot = source;
          break;
        }
      }
      CaptureX11(snapshot, send_width_, send_height_, &back_);
      front_.swap(back_);
    }
    MarkTexture();
    const int fps = motion_ ? 30 : 5;
    g_usleep(static_cast<guint>(1000000 / std::max(1, fps)));
  }
}

bool ScreenGraph::CaptureX11(const Source& source, int out_w, int out_h,
                             std::vector<uint8_t>* dest) {
  if (dest == nullptr || display_ == nullptr || source.window == 0 ||
      source.width <= 0 || source.height <= 0 || out_w < 1 || out_h < 1) {
    return false;
  }
  XImage* image =
      XGetImage(display_, source.window, 0, 0,
                static_cast<unsigned>(source.width),
                static_cast<unsigned>(source.height), AllPlanes, ZPixmap);
  if (image == nullptr || image->data == nullptr) {
    return false;
  }
  const int bpp = image->bits_per_pixel / 8;
  if (bpp < 3) {
    XDestroyImage(image);
    return false;
  }
  dest->assign(static_cast<size_t>(out_w) * out_h * 4, 0);
  for (int y = 0; y < out_h; y++) {
    const int src_y = y * source.height / out_h;
    const char* row = image->data + static_cast<size_t>(src_y) * image->bytes_per_line;
    for (int x = 0; x < out_w; x++) {
      const int src_x = x * source.width / out_w;
      const auto* px =
          reinterpret_cast<const unsigned char*>(row + src_x * bpp);
      const size_t i = static_cast<size_t>(y * out_w + x) * 4;
      (*dest)[i] = px[2];
      (*dest)[i + 1] = px[1];
      (*dest)[i + 2] = px[0];
      (*dest)[i + 3] = 255;
    }
  }
  XDestroyImage(image);
  return true;
}

void ScreenGraph::StopPipeWire() {
#ifdef FAC_HAS_PIPEWIRE
  if (!pw_) {
    return;
  }
  if (pw_->loop != nullptr) {
    pw_thread_loop_lock(pw_->loop);
#ifdef FAC_HAS_EGL_DMABUF
    DestroyEglDmaBuf();
#endif
    if (pw_->stream != nullptr) {
      spa_hook_remove(&pw_->listener);
      pw_stream_disconnect(pw_->stream);
      pw_stream_destroy(pw_->stream);
      pw_->stream = nullptr;
    }
    if (pw_->core != nullptr) {
      pw_core_disconnect(pw_->core);
      pw_->core = nullptr;
    }
    if (pw_->context != nullptr) {
      pw_context_destroy(pw_->context);
      pw_->context = nullptr;
    }
    pw_thread_loop_unlock(pw_->loop);
    pw_thread_loop_stop(pw_->loop);
    pw_thread_loop_destroy(pw_->loop);
    pw_->loop = nullptr;
  }
  pw_.reset();
#endif
}

void ScreenGraph::OnPwParamChanged(void* data, uint32_t id, const void* param) {
#ifdef FAC_HAS_PIPEWIRE
  auto* self = static_cast<ScreenGraph*>(data);
  if (self == nullptr || self->pw_ == nullptr || param == nullptr ||
      id != SPA_PARAM_Format) {
    return;
  }
  spa_video_info_raw raw{};
  if (spa_format_video_raw_parse(static_cast<const spa_pod*>(param), &raw) <
      0) {
    return;
  }
  self->pw_->spa_format = raw.format;
  self->pw_->src_w = static_cast<int>(raw.size.width);
  self->pw_->src_h = static_cast<int>(raw.size.height);
#ifdef FAC_HAS_EGL_DMABUF
  self->pw_->modifier = raw.modifier;
  self->pw_->has_modifier = (raw.flags & SPA_VIDEO_FLAG_MODIFIER) != 0;
  FacScreenLog("pw format=%u size=%dx%d modifier=%llu flags=%u", raw.format,
               self->pw_->src_w, self->pw_->src_h,
               static_cast<unsigned long long>(raw.modifier), raw.flags);
#else
  FacScreenLog("pw format=%u size=%dx%d", raw.format, self->pw_->src_w,
               self->pw_->src_h);
#endif
  int out_w = self->pw_->src_w;
  int out_h = self->pw_->src_h;
  if (out_w > 1920 || out_h > 1080) {
    const double scale = std::min(1920.0 / out_w, 1080.0 / out_h);
    out_w = std::max(1, static_cast<int>(out_w * scale));
    out_h = std::max(1, static_cast<int>(out_h * scale));
  }
  std::lock_guard<std::mutex> lock(self->mutex_);
  self->send_width_ = out_w;
  self->send_height_ = out_h;
#else
  (void)data;
  (void)id;
  (void)param;
#endif
}

void ScreenGraph::OnPwProcess(void* data) {
#ifdef FAC_HAS_PIPEWIRE
  auto* self = static_cast<ScreenGraph*>(data);
  if (self == nullptr || self->pw_ == nullptr || self->pw_->stream == nullptr) {
    return;
  }
  pw_buffer* buffer = pw_stream_dequeue_buffer(self->pw_->stream);
  if (buffer == nullptr || buffer->buffer == nullptr ||
      buffer->buffer->n_datas < 1) {
    return;
  }
  spa_data* datas = buffer->buffer->datas;
  auto dma_sync = [](int fd, uint64_t flags) {
    if (fd < 0) {
      return;
    }
    struct dma_buf_sync sync {};
    sync.flags = flags;
    ioctl(fd, DMA_BUF_IOCTL_SYNC, &sync);
  };
  auto map_plane = [&](const spa_data& plane, void** map, size_t* map_size,
                       const uint8_t** ptr, int* stride) -> bool {
    if (plane.chunk == nullptr) {
      return false;
    }
    const uint8_t* base = nullptr;
    if (plane.data != nullptr) {
      base = static_cast<const uint8_t*>(plane.data);
    } else if (plane.fd >= 0 && plane.maxsize > 0) {
      const off_t off = static_cast<off_t>(plane.mapoffset);
      void* mapped =
          mmap(nullptr, plane.maxsize, PROT_READ, MAP_SHARED, plane.fd, off);
      if (mapped == MAP_FAILED) {
        mapped = mmap(nullptr, plane.maxsize, PROT_READ, MAP_PRIVATE, plane.fd,
                      off);
      }
      if (mapped == MAP_FAILED) {
        return false;
      }
      *map = mapped;
      *map_size = plane.maxsize;
      base = static_cast<const uint8_t*>(mapped);
      if (plane.type == SPA_DATA_DmaBuf) {
        dma_sync(static_cast<int>(plane.fd),
                 DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ);
      }
    }
    if (base == nullptr) {
      return false;
    }
    *ptr = base + plane.chunk->offset;
    *stride = plane.chunk->stride > 0
                  ? plane.chunk->stride
                  : static_cast<int>(plane.maxsize / std::max(1, self->pw_->src_h));
    return *stride != 0;
  };
  void* map0 = nullptr;
  size_t map0_size = 0;
  const uint8_t* src = nullptr;
  int stride = 0;
  const bool log_frame = self->pw_->process_logs < 8;
  if (log_frame) {
    FacScreenLog(
        "pw process n=%d type=%u fd=%ld data=%p max=%zu offset=%u chunk=%p",
        self->pw_->process_logs, datas[0].type, static_cast<long>(datas[0].fd),
        datas[0].data, static_cast<size_t>(datas[0].maxsize),
        static_cast<unsigned>(datas[0].mapoffset),
        static_cast<const void*>(datas[0].chunk));
    self->pw_->process_logs++;
  }
#ifdef FAC_HAS_EGL_DMABUF
  if (datas[0].type == SPA_DATA_DmaBuf && datas[0].chunk != nullptr) {
    const int stride_hint =
        datas[0].chunk->stride > 0
            ? datas[0].chunk->stride
            : self->pw_->src_w * 4;
    const int offset = static_cast<int>(datas[0].mapoffset) +
                       static_cast<int>(datas[0].chunk->offset);
    std::vector<uint8_t> rgba;
    if (self->CopyDmaBufEgl(static_cast<int>(datas[0].fd), self->pw_->src_w,
                            self->pw_->src_h, stride_hint, offset, &rgba) &&
        !rgba.empty()) {
      if (log_frame) {
        FacScreenLog("egl read px=%02x %02x %02x %02x", rgba[0], rgba[1],
                     rgba[2], rgba[3]);
      }
      {
        std::lock_guard<std::mutex> lock(self->mutex_);
        const int out_w = self->send_width_;
        const int out_h = self->send_height_;
        const int src_w = self->pw_->src_w;
        const int src_h = self->pw_->src_h;
        self->back_.assign(static_cast<size_t>(out_w) * out_h * 4, 255);
        for (int y = 0; y < out_h; y++) {
          const int src_y = y * src_h / std::max(1, out_h);
          const uint8_t* row =
              rgba.data() + static_cast<size_t>(src_y) * src_w * 4;
          uint8_t* out = self->back_.data() + static_cast<size_t>(y) * out_w * 4;
          for (int x = 0; x < out_w; x++) {
            const int src_x = x * src_w / std::max(1, out_w);
            std::memcpy(out + x * 4, row + src_x * 4, 4);
          }
        }
        self->front_.swap(self->back_);
      }
      self->MarkTexture();
      pw_stream_queue_buffer(self->pw_->stream, buffer);
      return;
    }
    if (log_frame) {
      FacScreenLog("egl dma-buf copy failed; skipping cpu mmap zeros");
    }
    pw_stream_queue_buffer(self->pw_->stream, buffer);
    return;
  }
#endif
  if (!map_plane(datas[0], &map0, &map0_size, &src, &stride)) {
    if (self->pw_->process_logs <= 5) {
      FacScreenLog("pw map_plane failed type=%u fd=%ld", datas[0].type,
                   static_cast<long>(datas[0].fd));
    }
    pw_stream_queue_buffer(self->pw_->stream, buffer);
    return;
  }
  if (self->pw_->process_logs <= 5) {
    FacScreenLog("pw mapped stride=%d src=%dx%d px=%02x %02x %02x %02x", stride,
                 self->pw_->src_w, self->pw_->src_h, src[0], src[1], src[2],
                 src[3]);
  }
  void* map1 = nullptr;
  size_t map1_size = 0;
  const uint8_t* uv = nullptr;
  int uv_stride = 0;
  if (self->pw_->spa_format == SPA_VIDEO_FORMAT_NV12) {
    if (buffer->buffer->n_datas >= 2) {
      map_plane(datas[1], &map1, &map1_size, &uv, &uv_stride);
    }
    if (uv == nullptr) {
      uv = src + stride * self->pw_->src_h;
      uv_stride = stride;
    }
  }
  self->CopyPipeWireFrame(src, self->pw_->src_w, self->pw_->src_h, stride,
                          self->pw_->spa_format, uv, uv_stride);
  self->MarkTexture();
  if (datas[0].type == SPA_DATA_DmaBuf) {
    dma_sync(static_cast<int>(datas[0].fd),
             DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ);
  }
  if (map1 != nullptr && buffer->buffer->n_datas >= 2 &&
      datas[1].type == SPA_DATA_DmaBuf) {
    dma_sync(static_cast<int>(datas[1].fd),
             DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ);
  }
  if (map1 != nullptr) {
    munmap(map1, map1_size);
  }
  if (map0 != nullptr) {
    munmap(map0, map0_size);
  }
  pw_stream_queue_buffer(self->pw_->stream, buffer);
#else
  (void)data;
#endif
}

void ScreenGraph::MarkTexture() {
  if (textures_ == nullptr || texture_ == nullptr) {
    return;
  }
  if (mark_pending_.exchange(true)) {
    return;
  }
  g_idle_add(
      [](gpointer data) -> gboolean {
        auto* graph = static_cast<ScreenGraph*>(data);
        graph->mark_pending_.store(false);
        if (graph->textures_ != nullptr && graph->texture_ != nullptr) {
          fl_texture_registrar_mark_texture_frame_available(
              graph->textures_, FL_TEXTURE(graph->texture_));
        }
        return G_SOURCE_REMOVE;
      },
      this);
}

void ScreenGraph::CopyPipeWireFrame(const uint8_t* src, int src_w, int src_h,
                                    int stride, uint32_t spa_format,
                                    const uint8_t* uv, int uv_stride) {
  if (src == nullptr || src_w < 1 || src_h < 1 || stride < 1) {
    return;
  }
  std::lock_guard<std::mutex> lock(mutex_);
  const int out_w = send_width_;
  const int out_h = send_height_;
  if (out_w < 1 || out_h < 1) {
    return;
  }
  back_.assign(static_cast<size_t>(out_w) * out_h * 4, 255);
#ifdef FAC_HAS_PIPEWIRE
  auto clamp = [](int value) -> uint8_t {
    if (value < 0) {
      return 0;
    }
    if (value > 255) {
      return 255;
    }
    return static_cast<uint8_t>(value);
  };
  for (int y = 0; y < out_h; y++) {
    const int src_y = y * src_h / out_h;
    uint8_t* out = back_.data() + static_cast<size_t>(y) * out_w * 4;
    if (spa_format == SPA_VIDEO_FORMAT_NV12 && uv != nullptr) {
      const uint8_t* y_row = src + static_cast<ptrdiff_t>(stride) * src_y;
      const uint8_t* uv_row =
          uv + static_cast<ptrdiff_t>(uv_stride) * (src_y / 2);
      for (int x = 0; x < out_w; x++) {
        const int src_x = x * src_w / out_w;
        const int c = y_row[src_x] - 16;
        const int d = uv_row[src_x & ~1] - 128;
        const int e = uv_row[(src_x & ~1) + 1] - 128;
        out[x * 4 + 0] = clamp((298 * c + 409 * e + 128) >> 8);
        out[x * 4 + 1] = clamp((298 * c - 100 * d - 208 * e + 128) >> 8);
        out[x * 4 + 2] = clamp((298 * c + 516 * d + 128) >> 8);
        out[x * 4 + 3] = 255;
      }
      continue;
    }
    const uint8_t* row = src + static_cast<ptrdiff_t>(stride) * src_y;
    const bool bgr = spa_format == SPA_VIDEO_FORMAT_BGRx ||
                     spa_format == SPA_VIDEO_FORMAT_BGRA;
    for (int x = 0; x < out_w; x++) {
      const int src_x = x * src_w / out_w;
      const uint8_t* px = row + src_x * 4;
      if (bgr) {
        out[x * 4 + 0] = px[2];
        out[x * 4 + 1] = px[1];
        out[x * 4 + 2] = px[0];
      } else {
        out[x * 4 + 0] = px[0];
        out[x * 4 + 1] = px[1];
        out[x * 4 + 2] = px[2];
      }
      out[x * 4 + 3] = 255;
    }
  }
  front_.swap(back_);
#else
  (void)spa_format;
  (void)uv;
  (void)uv_stride;
#endif
}

bool ScreenGraph::ConnectPipeWire(int fd, uint32_t node_id, int width,
                                  int height) {
#ifdef FAC_HAS_PIPEWIRE
  if (fd < 0) {
    return false;
  }
  StopPipeWire();
  static std::once_flag pw_once;
  std::call_once(pw_once, [] { pw_init(nullptr, nullptr); });
  pw_ = std::make_unique<PwCapture>();
  pw_->loop = pw_thread_loop_new("fac-screencast", nullptr);
  if (pw_->loop == nullptr) {
    close(fd);
    pw_.reset();
    return false;
  }
  if (pw_thread_loop_start(pw_->loop) < 0) {
    FacScreenLog("pw_thread_loop_start failed");
    close(fd);
    StopPipeWire();
    return false;
  }
  pw_thread_loop_lock(pw_->loop);
  pw_->context = pw_context_new(pw_thread_loop_get_loop(pw_->loop), nullptr, 0);
  if (pw_->context == nullptr) {
    pw_thread_loop_unlock(pw_->loop);
    StopPipeWire();
    close(fd);
    return false;
  }
  pw_->core = pw_context_connect_fd(pw_->context, fd, nullptr, 0);
  if (pw_->core == nullptr) {
    pw_thread_loop_unlock(pw_->loop);
    StopPipeWire();
    return false;
  }
  char node[16];
  g_snprintf(node, sizeof(node), "%u", node_id);
  pw_properties* props = pw_properties_new(
      PW_KEY_MEDIA_TYPE, "Video", PW_KEY_MEDIA_CATEGORY, "Capture",
      PW_KEY_MEDIA_ROLE, "Screen", nullptr);
  pw_->stream = pw_stream_new(pw_->core, "fac-screencast", props);
  if (pw_->stream == nullptr) {
    pw_thread_loop_unlock(pw_->loop);
    StopPipeWire();
    return false;
  }
  pw_->events.version = PW_VERSION_STREAM_EVENTS;
  pw_->events.param_changed = [](void* data, uint32_t id,
                                 const spa_pod* param) {
    FacScreenLog("pw param_changed id=%u param=%p", id,
                 static_cast<const void*>(param));
    ScreenGraph::OnPwParamChanged(data, id, param);
  };
  pw_->events.process = [](void* data) { ScreenGraph::OnPwProcess(data); };
  pw_->events.state_changed = [](void* data, pw_stream_state /*old*/,
                                 pw_stream_state next, const char* error) {
    auto* self = static_cast<ScreenGraph*>(data);
    FacScreenLog("pw stream state=%s error=%s", pw_stream_state_as_string(next),
                 error != nullptr ? error : "");
    if (next == PW_STREAM_STATE_PAUSED && self != nullptr &&
        self->pw_ != nullptr && self->pw_->stream != nullptr) {
      const int active = pw_stream_set_active(self->pw_->stream, true);
      FacScreenLog("pw_stream_set_active(paused) rc=%d", active);
    }
  };
  pw_stream_add_listener(pw_->stream, &pw_->listener, &pw_->events, this);
  pw_->src_w = width > 0 ? width : 1920;
  pw_->src_h = height > 0 ? height : 1080;
  const int connected = pw_stream_connect(
      pw_->stream, PW_DIRECTION_INPUT, node_id,
      static_cast<pw_stream_flags>(PW_STREAM_FLAG_AUTOCONNECT |
                                   PW_STREAM_FLAG_MAP_BUFFERS),
      nullptr, 0);
  int active = -1;
  if (connected >= 0) {
    active = pw_stream_set_active(pw_->stream, true);
  }
  pw_thread_loop_unlock(pw_->loop);
  FacScreenLog("pw_stream_connect rc=%d set_active=%d target=%s node=%u %dx%d",
               connected, active, node, node_id, width, height);
  if (connected < 0) {
    StopPipeWire();
    return false;
  }
  return true;
#else
  (void)fd;
  (void)node_id;
  (void)width;
  (void)height;
  return false;
#endif
}

gboolean ScreenGraph::CopyPreviewPixels(const std::string& id,
                                        const uint8_t** buffer, uint32_t* width,
                                        uint32_t* height, GError** error) {
  std::lock_guard<std::mutex> lock(mutex_);
  auto found = previews_.find(id);
  if (found == previews_.end() || found->second->pixels.empty()) {
    if (error != nullptr) {
      *error = g_error_new(G_IO_ERROR, G_IO_ERROR_FAILED, "no preview");
    }
    return FALSE;
  }
  *buffer = found->second->pixels.data();
  *width = static_cast<uint32_t>(found->second->width);
  *height = static_cast<uint32_t>(found->second->height);
  return TRUE;
}

gboolean ScreenGraph::CopyPixels(const uint8_t** buffer, uint32_t* width,
                                 uint32_t* height, GError** error) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (front_.empty()) {
    if (error != nullptr) {
      *error = g_error_new(G_IO_ERROR, G_IO_ERROR_FAILED, "no frame");
    }
    return FALSE;
  }
  upload_ = front_;
  *buffer = upload_.data();
  *width = static_cast<uint32_t>(send_width_);
  *height = static_cast<uint32_t>(send_height_);
  return TRUE;
}

struct ScreenGraph::PortalState {
  std::mutex mutex;
  std::atomic<bool> cancel{false};
  std::atomic<bool> response_done{false};
  GMainLoop* loop = nullptr;
  guint response_code = 2;
  GVariant* response_results = nullptr;
  ScreenGraph* graph = nullptr;
  FlMethodCall* pending = nullptr;
  GDBusProxy* proxy = nullptr;
  std::string session;
  bool motion = false;
  guint start_sub = 0;
  int pw_fd = -1;
  uint32_t node_id = 0;
  int stream_w = 0;
  int stream_h = 0;
};

namespace {

void UnrefResults(GVariant* results) {
  if (results != nullptr) {
    g_variant_unref(results);
  }
}

std::string NewPortalToken() {
  char token[32];
  g_snprintf(token, sizeof(token), "fac%d", g_random_int_range(1, G_MAXINT));
  return token;
}

std::string PortalRequestPath(GDBusConnection* bus, const char* token) {
  const gchar* unique =
      bus == nullptr ? nullptr : g_dbus_connection_get_unique_name(bus);
  if (unique == nullptr || unique[0] != ':' || token == nullptr ||
      token[0] == '\0') {
    return {};
  }
  std::string sender(unique + 1);
  for (char& c : sender) {
    if (c == '.') {
      c = '_';
    }
  }
  return std::string("/org/freedesktop/portal/desktop/request/") + sender +
         "/" + token;
}

void OnPortalResponse(GDBusConnection*, const gchar*, const gchar*,
                      const gchar*, const gchar*, GVariant* parameters,
                      gpointer user_data) {
  auto* state = static_cast<ScreenGraph::PortalState*>(user_data);
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    UnrefResults(state->response_results);
    state->response_results = nullptr;
    g_variant_get(parameters, "(u@a{sv})", &state->response_code,
                  &state->response_results);
    state->response_done = true;
  }
  if (state->loop != nullptr) {
    g_main_loop_quit(state->loop);
  }
}

void ClosePortalSession(GDBusProxy* proxy, const std::string& path) {
  if (proxy == nullptr || path.empty()) {
    return;
  }
  g_autoptr(GError) error = nullptr;
  g_dbus_connection_call_sync(
      g_dbus_proxy_get_connection(proxy), "org.freedesktop.portal.Desktop",
      path.c_str(), "org.freedesktop.portal.Session", "Close", nullptr, nullptr,
      G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, &error);
}

// Must run on the GTK thread. Subscribe before the method returns so
// GNOME's immediate SelectSources Response is not missed; Start is the
// picker and waits in a nested main loop until the user answers.
bool PortalCall(GDBusProxy* proxy, const char* method, GVariant* args,
                const char* handle_token, GVariant** results, guint* code,
                const std::shared_ptr<ScreenGraph::PortalState>& state) {
  GDBusConnection* bus = g_dbus_proxy_get_connection(proxy);
  const std::string request_path = PortalRequestPath(bus, handle_token);
  if (request_path.empty()) {
    return false;
  }

  {
    std::lock_guard<std::mutex> lock(state->mutex);
    state->response_done = false;
    UnrefResults(state->response_results);
    state->response_results = nullptr;
    state->response_code = 2;
  }

  const guint sub = g_dbus_connection_signal_subscribe(
      bus, "org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request",
      "Response", request_path.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      OnPortalResponse, state.get(), nullptr);

  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) ret = g_dbus_proxy_call_sync(
      proxy, method, args, G_DBUS_CALL_FLAGS_NONE, 180000, nullptr, &error);

  if (ret != nullptr && !state->response_done && !state->cancel) {
    GMainLoop* loop = g_main_loop_new(g_main_context_default(), FALSE);
    state->loop = loop;
    if (!state->response_done && !state->cancel) {
      g_main_loop_run(loop);
    }
    state->loop = nullptr;
    g_main_loop_unref(loop);
  }

  g_dbus_connection_signal_unsubscribe(bus, sub);

  if (state->cancel || !state->response_done) {
    std::lock_guard<std::mutex> lock(state->mutex);
    UnrefResults(state->response_results);
    state->response_results = nullptr;
    return false;
  }
  *code = state->response_code;
  *results = state->response_results;
  state->response_results = nullptr;
  return true;
}

}  // namespace

FlValue* ScreenGraph::PortalStartedMap() {
  EnsureTexture();
  if (textures_ != nullptr && texture_ != nullptr) {
    fl_texture_registrar_mark_texture_frame_available(textures_,
                                                      FL_TEXTURE(texture_));
  }
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "status", fl_value_new_string("started"));
  fl_value_set_string_take(map, "textureId", fl_value_new_int(texture_id_));
  fl_value_set_string_take(map, "width", fl_value_new_int(send_width_));
  fl_value_set_string_take(map, "height", fl_value_new_int(send_height_));
  fl_value_set_string_take(map, "frameRate",
                           fl_value_new_int(motion_ ? 30 : 5));
  return map;
}

void ScreenGraph::FinishPortal(const char* status, const char* reason) {
  const auto state = portal_state_;
  if (state == nullptr) {
    return;
  }
  FlMethodCall* pending_call = nullptr;
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (state->cancel) {
      return;
    }
    pending_call = state->pending;
    state->pending = nullptr;
  }
  if (pending_call == nullptr) {
    return;
  }
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "status", fl_value_new_string(status));
  if (std::strcmp(status, "started") == 0) {
    g_autoptr(FlValue) started = PortalStartedMap();
    FlValue* texture = fl_value_lookup_string(started, "textureId");
    FlValue* width = fl_value_lookup_string(started, "width");
    FlValue* height = fl_value_lookup_string(started, "height");
    FlValue* rate = fl_value_lookup_string(started, "frameRate");
    if (texture != nullptr) {
      fl_value_set_string(map, "textureId", texture);
    }
    if (width != nullptr) {
      fl_value_set_string(map, "width", width);
    }
    if (height != nullptr) {
      fl_value_set_string(map, "height", height);
    }
    if (rate != nullptr) {
      fl_value_set_string(map, "frameRate", rate);
    }
  } else if (reason != nullptr && reason[0] != '\0') {
    fl_value_set_string_take(map, "reason", fl_value_new_string(reason));
  }
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(map));
  fl_method_call_respond(pending_call, response, nullptr);
  g_object_unref(pending_call);
}

void ScreenGraph::OnPortalStartResponse(GDBusConnection*, const gchar*,
                                        const gchar*, const gchar*,
                                        const gchar*, GVariant* parameters,
                                        gpointer user_data) {
  auto* state = static_cast<ScreenGraph::PortalState*>(user_data);
  guint code = 2;
  GVariant* results = nullptr;
  g_variant_get(parameters, "(u@a{sv})", &code, &results);
  gchar* printed = results != nullptr ? g_variant_print(results, TRUE) : nullptr;
  FacScreenLog("Start Response code=%u results=%s", code,
               printed != nullptr ? printed : "(null)");
  g_free(printed);
  ScreenGraph* graph = nullptr;
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    graph = state->graph;
  }
  if (graph == nullptr) {
    UnrefResults(results);
    return;
  }
  graph->CompletePortalStart(results, code);
}

void ScreenGraph::CompletePortalStart(GVariant* results, guint code) {
  const auto state = portal_state_;
  if (state == nullptr) {
    UnrefResults(results);
    return;
  }
  GDBusProxy* proxy = state->proxy;
  const std::string session = state->session;
  const bool motion = state->motion;
  if (state->start_sub != 0 && proxy != nullptr) {
    g_dbus_connection_signal_unsubscribe(
        g_dbus_proxy_get_connection(proxy), state->start_sub);
    state->start_sub = 0;
  }
  if (state->cancel || code != 0 || results == nullptr) {
    UnrefResults(results);
    ClosePortalSession(proxy, session);
    FinishPortal("unavailable", code == 1 ? "denied" : "none");
    return;
  }
  uint32_t node_id = 0;
  int stream_w = 0;
  int stream_h = 0;
  bool have_stream = false;
  GVariant* streams = g_variant_lookup_value(results, "streams", nullptr);
  if (streams != nullptr) {
    GVariantIter iter;
    g_variant_iter_init(&iter, streams);
    GVariant* child = g_variant_iter_next_value(&iter);
    if (child != nullptr) {
      GVariant* props = nullptr;
      g_variant_get(child, "(u@a{sv})", &node_id, &props);
      if (props != nullptr) {
        if (!g_variant_lookup(props, "size", "(ii)", &stream_w, &stream_h)) {
          guint32 uw = 0;
          guint32 uh = 0;
          if (g_variant_lookup(props, "size", "(uu)", &uw, &uh)) {
            stream_w = static_cast<int>(uw);
            stream_h = static_cast<int>(uh);
          }
        }
        gchar* props_print = g_variant_print(props, TRUE);
        FacScreenLog("stream node=%u size=%dx%d props=%s", node_id, stream_w,
                     stream_h, props_print != nullptr ? props_print : "");
        g_free(props_print);
        g_variant_unref(props);
      }
      have_stream = true;
      g_variant_unref(child);
    }
    g_variant_unref(streams);
  }
  g_autoptr(GUnixFDList) fd_list = nullptr;
  g_autoptr(GError) fd_error = nullptr;
  GVariantBuilder fd_opts;
  g_variant_builder_init(&fd_opts, G_VARIANT_TYPE_VARDICT);
  g_autoptr(GVariant) fd_ret = nullptr;
  if (proxy != nullptr) {
    fd_ret = g_dbus_proxy_call_with_unix_fd_list_sync(
        proxy, "OpenPipeWireRemote",
        g_variant_new("(oa{sv})", session.c_str(), &fd_opts),
        G_DBUS_CALL_FLAGS_NONE, 5000, nullptr, &fd_list, nullptr, &fd_error);
  }
  int pw_fd = -1;
  if (fd_ret != nullptr && fd_list != nullptr) {
    gint32 handle = -1;
    g_variant_get(fd_ret, "(h)", &handle);
    pw_fd = g_unix_fd_list_get(fd_list, handle, &fd_error);
  }
  UnrefResults(results);
  FacScreenLog("OpenPipeWireRemote fd=%d have_stream=%d err=%s", pw_fd,
               have_stream ? 1 : 0,
               fd_error != nullptr ? fd_error->message : "none");
  if (state->cancel || !have_stream || pw_fd < 0) {
    if (pw_fd >= 0) {
      close(pw_fd);
    }
    ClosePortalSession(proxy, session);
    FinishPortal("unavailable", "none");
    return;
  }
  motion_ = motion;
  int out_w = stream_w > 0 ? stream_w : 1920;
  int out_h = stream_h > 0 ? stream_h : 1080;
  if (out_w > 1920 || out_h > 1080) {
    const double scale = std::min(1920.0 / out_w, 1080.0 / out_h);
    out_w = std::max(1, static_cast<int>(out_w * scale));
    out_h = std::max(1, static_cast<int>(out_h * scale));
  }
  {
    std::lock_guard<std::mutex> lock(mutex_);
    send_id_ = "system-picker";
    send_width_ = out_w;
    send_height_ = out_h;
    running_ = true;
    front_.assign(static_cast<size_t>(send_width_) * send_height_ * 4, 255);
    for (int i = 0; i < send_width_ * send_height_; i++) {
      front_[static_cast<size_t>(i) * 4 + 0] = 200;
      front_[static_cast<size_t>(i) * 4 + 1] = 40;
      front_[static_cast<size_t>(i) * 4 + 2] = 40;
      front_[static_cast<size_t>(i) * 4 + 3] = 255;
    }
  }
  state->pw_fd = pw_fd;
  state->node_id = node_id;
  state->stream_w = stream_w;
  state->stream_h = stream_h;
  portal_session_ = session;
  g_idle_add(
      [](gpointer data) -> gboolean {
        static_cast<ScreenGraph*>(data)->FinishPortalStartIdle();
        return G_SOURCE_REMOVE;
      },
      this);
}

void ScreenGraph::FinishPortalStartIdle() {
  const auto state = portal_state_;
  if (state == nullptr || state->cancel) {
    return;
  }
  EnsureTexture();
  FacScreenLog("idle start texture=%ld %dx%d", static_cast<long>(texture_id_),
               send_width_, send_height_);
  if (texture_id_ < 0) {
    if (state->pw_fd >= 0) {
      close(state->pw_fd);
      state->pw_fd = -1;
    }
    ClosePortalSession(state->proxy, state->session);
    FinishPortal("unavailable", "none");
    return;
  }
  FinishPortal("started", nullptr);
  FacScreenLog("FinishPortal started returned");
  const int pw_fd = state->pw_fd;
  const uint32_t node_id = state->node_id;
  const int stream_w = state->stream_w;
  const int stream_h = state->stream_h;
  state->pw_fd = -1;
  FacScreenLog("ConnectPipeWire node=%u %dx%d", node_id, stream_w, stream_h);
  if (!ConnectPipeWire(pw_fd, node_id, stream_w, stream_h)) {
    FacScreenLog("ConnectPipeWire failed");
    ClosePortalSession(state->proxy, state->session);
  }
}

void ScreenGraph::CancelPortal() {
  const auto state = portal_state_;
  if (state != nullptr) {
    state->cancel = true;
    {
      std::lock_guard<std::mutex> lock(state->mutex);
      state->graph = nullptr;
    }
    GMainLoop* loop = state->loop;
    if (loop != nullptr) {
      g_main_loop_quit(loop);
    }
    if (state->start_sub != 0 && state->proxy != nullptr) {
      g_dbus_connection_signal_unsubscribe(
          g_dbus_proxy_get_connection(state->proxy), state->start_sub);
      state->start_sub = 0;
    }
    ClosePortalSession(state->proxy, state->session);
    if (state->pw_fd >= 0) {
      close(state->pw_fd);
      state->pw_fd = -1;
    }
    if (state->proxy != nullptr) {
      g_object_unref(state->proxy);
      state->proxy = nullptr;
    }
  }
  if (portal_thread_.joinable()) {
    portal_thread_.join();
  }
  if (state != nullptr) {
    FlMethodCall* pending = nullptr;
    {
      std::lock_guard<std::mutex> lock(state->mutex);
      pending = state->pending;
      state->pending = nullptr;
    }
    if (pending != nullptr) {
      g_autoptr(FlValue) map = fl_value_new_map();
      fl_value_set_string_take(map, "status",
                               fl_value_new_string("unavailable"));
      fl_value_set_string_take(map, "reason", fl_value_new_string("none"));
      g_autoptr(FlMethodResponse) response =
          FL_METHOD_RESPONSE(fl_method_success_response_new(map));
      fl_method_call_respond(pending, response, nullptr);
      g_object_unref(pending);
    }
  }
  portal_state_.reset();
}

void ScreenGraph::EnsureParentWindow() {
  if (!parent_window_.empty() || view_ == nullptr) {
    return;
  }
  GtkWidget* top = gtk_widget_get_toplevel(view_);
  if (top == nullptr) {
    return;
  }
  if (!gtk_widget_get_realized(top)) {
    gtk_widget_realize(top);
  }
  GdkWindow* gdk_window = gtk_widget_get_window(top);
  if (gdk_window == nullptr) {
    return;
  }
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_WINDOW(gdk_window)) {
    char buf[32];
    g_snprintf(buf, sizeof(buf), "x11:%x",
               static_cast<unsigned>(gdk_x11_window_get_xid(gdk_window)));
    parent_window_ = buf;
    return;
  }
#endif
#ifdef GDK_WINDOWING_WAYLAND
  if (GDK_IS_WAYLAND_WINDOW(gdk_window)) {
    struct ExportWait {
      GMainLoop* loop = nullptr;
      std::string handle;
    } wait;
    wait.loop = g_main_loop_new(g_main_context_default(), FALSE);
    gdk_wayland_window_export_handle(
        gdk_window,
        [](GdkWindow*, const char* handle, gpointer data) {
          auto* wait = static_cast<ExportWait*>(data);
          if (handle != nullptr && handle[0] != '\0') {
            wait->handle = std::string("wayland:") + handle;
          }
          if (wait->loop != nullptr) {
            g_main_loop_quit(wait->loop);
          }
        },
        &wait, nullptr);
    const guint timeout_id = g_timeout_add(
        1000,
        [](gpointer data) -> gboolean {
          auto* wait = static_cast<ExportWait*>(data);
          if (wait->loop != nullptr) {
            g_main_loop_quit(wait->loop);
          }
          return G_SOURCE_REMOVE;
        },
        &wait);
    g_main_loop_run(wait.loop);
    g_source_remove(timeout_id);
    g_main_loop_unref(wait.loop);
    wait.loop = nullptr;
    parent_window_ = wait.handle;
  }
#endif
}

bool ScreenGraph::StartPortal(FlMethodCall* pending, bool cursor, bool motion) {
  if (pending == nullptr) {
    return false;
  }
  CancelPortal();
  EnsureTexture();
  if (texture_id_ < 0) {
    FacScreenLog("EnsureTexture failed before portal");
    return false;
  }
  FacScreenLog("EnsureTexture id=%ld", static_cast<long>(texture_id_));
  EnsureParentWindow();
  g_autoptr(GError) proxy_error = nullptr;
  g_autoptr(GDBusProxy) proxy = g_dbus_proxy_new_for_bus_sync(
      G_BUS_TYPE_SESSION, G_DBUS_PROXY_FLAGS_NONE, nullptr,
      "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
      "org.freedesktop.portal.ScreenCast", nullptr, &proxy_error);
  if (proxy == nullptr) {
    return false;
  }
  auto state = std::make_shared<PortalState>();
  state->graph = this;
  state->pending = pending;
  g_object_ref(pending);
  portal_state_ = state;
  state->proxy = G_DBUS_PROXY(g_object_ref(proxy));
  state->motion = motion;
  {
    if (state->cancel) {
      FinishPortal("unavailable", "none");
      return true;
    }

    const std::string session_token = NewPortalToken();
    std::string request_token = NewPortalToken();
    GVariantBuilder opts;
    g_variant_builder_init(&opts, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_add(&opts, "{sv}", "handle_token",
                          g_variant_new_string(request_token.c_str()));
    g_variant_builder_add(&opts, "{sv}", "session_handle_token",
                          g_variant_new_string(session_token.c_str()));
    GVariant* results = nullptr;
    guint code = 2;
    if (!PortalCall(proxy, "CreateSession", g_variant_new("(a{sv})", &opts),
                    request_token.c_str(), &results, &code, state) ||
        code != 0 || results == nullptr) {
      UnrefResults(results);
      FinishPortal("unavailable", code == 1 ? "denied" : "none");
      return true;
    }
    const gchar* session_path = nullptr;
    if (!g_variant_lookup(results, "session_handle", "&s", &session_path)) {
      g_variant_lookup(results, "session_handle", "&o", &session_path);
    }
    if (session_path == nullptr) {
      UnrefResults(results);
      FinishPortal("unavailable", "none");
      return true;
    }
    const std::string session = session_path;
    UnrefResults(results);

    request_token = NewPortalToken();
    g_variant_builder_init(&opts, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_add(&opts, "{sv}", "handle_token",
                          g_variant_new_string(request_token.c_str()));
    g_variant_builder_add(&opts, "{sv}", "types",
                          g_variant_new_uint32(1 | 2));
    g_variant_builder_add(&opts, "{sv}", "multiple",
                          g_variant_new_boolean(FALSE));
    g_variant_builder_add(&opts, "{sv}", "cursor_mode",
                          g_variant_new_uint32(cursor ? 4 : 2));
    results = nullptr;
    if (!PortalCall(proxy, "SelectSources",
                    g_variant_new("(oa{sv})", session.c_str(), &opts),
                    request_token.c_str(), &results, &code, state) ||
        code != 0) {
      UnrefResults(results);
      ClosePortalSession(proxy, session);
      FinishPortal("unavailable", code == 1 ? "denied" : "none");
      return true;
    }
    UnrefResults(results);

    // Start is the picker. Issue it asynchronously so GTK keeps processing
    // Wayland events; a nested loop here leaves the dialog unmapped.
    state->session = session;
    request_token = NewPortalToken();
    const std::string request_path =
        PortalRequestPath(g_dbus_proxy_get_connection(proxy),
                          request_token.c_str());
    state->start_sub = g_dbus_connection_signal_subscribe(
        g_dbus_proxy_get_connection(proxy), "org.freedesktop.portal.Desktop",
        "org.freedesktop.portal.Request", "Response", request_path.c_str(),
        nullptr, G_DBUS_SIGNAL_FLAGS_NONE, OnPortalStartResponse, state.get(),
        nullptr);
    g_variant_builder_init(&opts, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_add(&opts, "{sv}", "handle_token",
                          g_variant_new_string(request_token.c_str()));
    g_dbus_proxy_call(
        proxy, "Start",
        g_variant_new("(osa{sv})", session.c_str(), "", &opts),
        G_DBUS_CALL_FLAGS_NONE, 180000, nullptr, nullptr, nullptr);
  }
  return true;
}
