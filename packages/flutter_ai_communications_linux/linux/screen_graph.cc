#include "screen_graph.h"

#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <gio/gio.h>
#include <gio/gunixfdlist.h>
#include <unistd.h>
#include <mutex>
#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <thread>

#ifdef FAC_HAS_PIPEWIRE
#include <pipewire/pipewire.h>
#include <spa/param/video/format-utils.h>
#include <spa/param/video/raw.h>
#include <spa/pod/builder.h>
#endif

struct ScreenGraph::PwCapture {
#ifdef FAC_HAS_PIPEWIRE
  pw_thread_loop* loop = nullptr;
  pw_context* context = nullptr;
  pw_core* core = nullptr;
  pw_stream* stream = nullptr;
  spa_hook listener{};
  uint32_t spa_format = 0;
  int src_w = 0;
  int src_h = 0;
#endif
};

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

ScreenGraph::ScreenGraph(FlTextureRegistrar* textures) : textures_(textures) {
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
      CaptureX11(snapshot, send_width_, send_height_, &front_);
    }
    if (textures_ != nullptr && texture_ != nullptr) {
      fl_texture_registrar_mark_texture_frame_available(textures_,
                                                        FL_TEXTURE(texture_));
    }
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
    if (pw_->stream != nullptr) {
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
  self->front_.assign(static_cast<size_t>(out_w) * out_h * 4, 0);
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
  if (datas[0].data == nullptr) {
    pw_stream_queue_buffer(self->pw_->stream, buffer);
    return;
  }
  const uint8_t* src =
      static_cast<const uint8_t*>(datas[0].data) + datas[0].chunk->offset;
  const int stride = datas[0].chunk->stride;
  const uint8_t* uv = nullptr;
  int uv_stride = 0;
  if (self->pw_->spa_format == SPA_VIDEO_FORMAT_NV12) {
    if (buffer->buffer->n_datas >= 2 && datas[1].data != nullptr) {
      uv = static_cast<const uint8_t*>(datas[1].data) + datas[1].chunk->offset;
      uv_stride = datas[1].chunk->stride;
    } else {
      uv = src + stride * self->pw_->src_h;
      uv_stride = stride;
    }
  }
  self->CopyPipeWireFrame(src, self->pw_->src_w, self->pw_->src_h, stride,
                          self->pw_->spa_format, uv, uv_stride);
  if (self->textures_ != nullptr && self->texture_ != nullptr) {
    fl_texture_registrar_mark_texture_frame_available(self->textures_,
                                                      FL_TEXTURE(self->texture_));
  }
  pw_stream_queue_buffer(self->pw_->stream, buffer);
#else
  (void)data;
#endif
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
  front_.assign(static_cast<size_t>(out_w) * out_h * 4, 255);
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
    uint8_t* out = front_.data() + static_cast<size_t>(y) * out_w * 4;
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
      PW_KEY_MEDIA_ROLE, "Screen", PW_KEY_TARGET_OBJECT, node, nullptr);
  pw_->stream = pw_stream_new(pw_->core, "fac-screencast", props);
  if (pw_->stream == nullptr) {
    pw_thread_loop_unlock(pw_->loop);
    StopPipeWire();
    return false;
  }
  pw_stream_events events{};
  events.version = PW_VERSION_STREAM_EVENTS;
  events.param_changed = [](void* data, uint32_t id, const spa_pod* param) {
    ScreenGraph::OnPwParamChanged(data, id, param);
  };
  events.process = [](void* data) { ScreenGraph::OnPwProcess(data); };
  pw_stream_add_listener(pw_->stream, &pw_->listener, &events, this);
  uint8_t buffer[1024];
  spa_pod_builder builder = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
  spa_rectangle def_size = SPA_RECTANGLE(
      static_cast<uint32_t>(width > 0 ? width : 1920),
      static_cast<uint32_t>(height > 0 ? height : 1080));
  spa_rectangle min_size = SPA_RECTANGLE(1, 1);
  spa_rectangle max_size = SPA_RECTANGLE(4096, 4096);
  spa_fraction def_fps =
      SPA_FRACTION(static_cast<uint32_t>(motion_ ? 30 : 5), 1);
  spa_fraction min_fps = SPA_FRACTION(0, 1);
  spa_fraction max_fps = SPA_FRACTION(60, 1);
  const spa_pod* params[] = {
      static_cast<spa_pod*>(spa_pod_builder_add_object(
          &builder, SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
          SPA_FORMAT_mediaType, SPA_POD_Id(SPA_MEDIA_TYPE_video),
          SPA_FORMAT_mediaSubtype, SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw),
          SPA_FORMAT_VIDEO_format,
          SPA_POD_CHOICE_ENUM_Id(5, SPA_VIDEO_FORMAT_BGRx, SPA_VIDEO_FORMAT_RGBx,
                                 SPA_VIDEO_FORMAT_BGRA, SPA_VIDEO_FORMAT_RGBA,
                                 SPA_VIDEO_FORMAT_NV12),
          SPA_FORMAT_VIDEO_size,
          SPA_POD_CHOICE_RANGE_Rectangle(&def_size, &min_size, &max_size),
          SPA_FORMAT_VIDEO_framerate,
          SPA_POD_CHOICE_RANGE_Fraction(&def_fps, &min_fps, &max_fps))),
  };
  const int connected = pw_stream_connect(
      pw_->stream, PW_DIRECTION_INPUT, PW_ID_ANY,
      static_cast<pw_stream_flags>(PW_STREAM_FLAG_AUTOCONNECT |
                                   PW_STREAM_FLAG_MAP_BUFFERS),
      params, 1);
  pw_thread_loop_unlock(pw_->loop);
  if (connected < 0) {
    StopPipeWire();
    return false;
  }
  if (pw_thread_loop_start(pw_->loop) < 0) {
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
  *buffer = front_.data();
  *width = static_cast<uint32_t>(send_width_);
  *height = static_cast<uint32_t>(send_height_);
  return TRUE;
}

struct ScreenGraph::PortalState {
  std::mutex mutex;
  std::atomic<bool> cancel{false};
  GMainLoop* loop = nullptr;
  ScreenGraph* graph = nullptr;
  FlMethodCall* pending = nullptr;
};

namespace {

struct PortalWait {
  GMainLoop* loop = nullptr;
  guint code = 2;
  GVariant* results = nullptr;
};

void OnPortalResponse(GDBusConnection*, const gchar*, const gchar*,
                      const gchar*, const gchar*, GVariant* parameters,
                      gpointer user_data) {
  auto* wait = static_cast<PortalWait*>(user_data);
  g_variant_get(parameters, "(u@a{sv})", &wait->code, &wait->results);
  g_main_loop_quit(wait->loop);
}

void UnrefResults(GVariant* results) {
  if (results != nullptr) {
    g_variant_unref(results);
  }
}

bool PortalCall(GDBusProxy* proxy, const char* method, GVariant* args,
                GVariant** results, guint* code,
                const std::shared_ptr<ScreenGraph::PortalState>& state) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) ret = g_dbus_proxy_call_sync(
      proxy, method, args, G_DBUS_CALL_FLAGS_NONE, 180000, nullptr, &error);
  if (ret == nullptr || state->cancel) {
    return false;
  }
  const gchar* request_path = nullptr;
  g_variant_get(ret, "(&o)", &request_path);
  PortalWait wait;
  wait.loop = g_main_loop_new(nullptr, FALSE);
  state->loop = wait.loop;
  GDBusConnection* bus = g_dbus_proxy_get_connection(proxy);
  const guint sub = g_dbus_connection_signal_subscribe(
      bus, "org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request",
      "Response", request_path, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      OnPortalResponse, &wait, nullptr);
  g_main_loop_run(wait.loop);
  g_dbus_connection_signal_unsubscribe(bus, sub);
  state->loop = nullptr;
  g_main_loop_unref(wait.loop);
  if (state->cancel) {
    UnrefResults(wait.results);
    return false;
  }
  *code = wait.code;
  *results = wait.results;
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

bool ScreenGraph::StartPortal(FlMethodCall* pending, bool cursor, bool motion) {
  if (pending == nullptr) {
    return false;
  }
  CancelPortal();
  auto state = std::make_shared<PortalState>();
  state->graph = this;
  state->pending = pending;
  g_object_ref(pending);
  portal_state_ = state;
  portal_thread_ = std::thread([this, state, cursor, motion]() {
    auto finish = [state](const char* status, const char* reason) {
      FlMethodCall* pending_call = nullptr;
      ScreenGraph* graph = nullptr;
      {
        std::lock_guard<std::mutex> lock(state->mutex);
        if (state->cancel) {
          return;
        }
        pending_call = state->pending;
        state->pending = nullptr;
        graph = state->graph;
      }
      if (pending_call == nullptr) {
        return;
      }
      struct Done {
        ScreenGraph* graph;
        FlMethodCall* pending;
        std::string status;
        std::string reason;
      };
      auto* done = new Done{graph, pending_call, status,
                            reason == nullptr ? "" : reason};
      g_idle_add(
          [](gpointer data) -> gboolean {
            auto* done = static_cast<Done*>(data);
            g_autoptr(FlValue) map = fl_value_new_map();
            fl_value_set_string_take(map, "status",
                                     fl_value_new_string(done->status.c_str()));
            if (done->status == "started" && done->graph != nullptr) {
              g_autoptr(FlValue) started = done->graph->PortalStartedMap();
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
            } else if (!done->reason.empty()) {
              fl_value_set_string_take(
                  map, "reason", fl_value_new_string(done->reason.c_str()));
            }
            g_autoptr(FlMethodResponse) response =
                FL_METHOD_RESPONSE(fl_method_success_response_new(map));
            fl_method_call_respond(done->pending, response, nullptr);
            g_object_unref(done->pending);
            delete done;
            return G_SOURCE_REMOVE;
          },
          done);
    };

    g_autoptr(GError) error = nullptr;
    g_autoptr(GDBusProxy) proxy = g_dbus_proxy_new_for_bus_sync(
        G_BUS_TYPE_SESSION, G_DBUS_PROXY_FLAGS_NONE, nullptr,
        "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.ScreenCast", nullptr, &error);
    if (proxy == nullptr || state->cancel) {
      finish("unavailable", "none");
      return;
    }

    gchar token[32];
    g_snprintf(token, sizeof(token), "fac%d", g_random_int_range(1, 1 << 20));
    GVariantBuilder opts;
    g_variant_builder_init(&opts, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_add(&opts, "{sv}", "handle_token",
                          g_variant_new_string(token));
    g_variant_builder_add(&opts, "{sv}", "session_handle_token",
                          g_variant_new_string(token));
    GVariant* results = nullptr;
    guint code = 2;
    if (!PortalCall(proxy, "CreateSession", g_variant_new("(a{sv})", &opts),
                    &results, &code, state) ||
        code != 0 || results == nullptr) {
      UnrefResults(results);
      finish("unavailable", code == 1 ? "denied" : "none");
      return;
    }
    const gchar* session_path = nullptr;
    g_variant_lookup(results, "session_handle", "&o", &session_path);
    if (session_path == nullptr) {
      UnrefResults(results);
      finish("unavailable", "none");
      return;
    }
    const std::string session = session_path;
    UnrefResults(results);

    g_variant_builder_init(&opts, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_add(&opts, "{sv}", "handle_token",
                          g_variant_new_string(token));
    g_variant_builder_add(&opts, "{sv}", "types",
                          g_variant_new_uint32(1 | 2));
    g_variant_builder_add(&opts, "{sv}", "multiple",
                          g_variant_new_boolean(FALSE));
    g_variant_builder_add(&opts, "{sv}", "cursor_mode",
                          g_variant_new_uint32(cursor ? 4 : 2));
    results = nullptr;
    if (!PortalCall(proxy, "SelectSources",
                    g_variant_new("(oa{sv})", session.c_str(), &opts), &results,
                    &code, state) ||
        code != 0) {
      UnrefResults(results);
      finish("unavailable", code == 1 ? "denied" : "none");
      return;
    }
    UnrefResults(results);

    g_variant_builder_init(&opts, G_VARIANT_TYPE_VARDICT);
    g_variant_builder_add(&opts, "{sv}", "handle_token",
                          g_variant_new_string(token));
    results = nullptr;
    if (!PortalCall(proxy, "Start",
                    g_variant_new("(osa{sv})", session.c_str(), "", &opts),
                    &results, &code, state) ||
        code != 0 || results == nullptr) {
      UnrefResults(results);
      finish("unavailable", code == 1 ? "denied" : "none");
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
          g_variant_lookup(props, "size", "(ii)", &stream_w, &stream_h);
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
    g_autoptr(GVariant) fd_ret = g_dbus_proxy_call_with_unix_fd_list_sync(
        proxy, "OpenPipeWireRemote",
        g_variant_new("(oa{sv})", session.c_str(), &fd_opts),
        G_DBUS_CALL_FLAGS_NONE, 5000, nullptr, &fd_list, nullptr, &fd_error);
    int pw_fd = -1;
    if (fd_ret != nullptr && fd_list != nullptr) {
      gint32 handle = -1;
      g_variant_get(fd_ret, "(h)", &handle);
      pw_fd = g_unix_fd_list_get(fd_list, handle, &fd_error);
    }
    UnrefResults(results);
    if (state->cancel || !have_stream || pw_fd < 0) {
      if (pw_fd >= 0) {
        close(pw_fd);
      }
      finish("unavailable", "none");
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
      front_.assign(static_cast<size_t>(send_width_) * send_height_ * 4, 0);
    }
    if (!ConnectPipeWire(pw_fd, node_id, stream_w, stream_h)) {
      g_autoptr(GError) close_error = nullptr;
      g_autoptr(GDBusConnection) bus =
          g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
      if (bus != nullptr) {
        g_dbus_connection_call_sync(
            bus, "org.freedesktop.portal.Desktop", session.c_str(),
            "org.freedesktop.portal.Session", "Close", nullptr, nullptr,
            G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, &close_error);
      }
      finish("unavailable", "none");
      return;
    }
    portal_session_ = session;
    finish("started", nullptr);
  });
  return true;
}
