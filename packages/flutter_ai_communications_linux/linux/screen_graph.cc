#include "screen_graph.h"

#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <algorithm>
#include <cstdlib>
#include <cstring>

namespace {

FlValue* SourceValue(const std::string& id, const std::string& name,
                     const std::string& kind, int x, int y, int w, int h,
                     bool preview) {
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "id", fl_value_new_string(id.c_str()));
  fl_value_set_string_take(map, "name", fl_value_new_string(name.c_str()));
  fl_value_set_string_take(map, "kind", fl_value_new_string(kind.c_str()));
  fl_value_set_string_take(map, "x", fl_value_new_int(x));
  fl_value_set_string_take(map, "y", fl_value_new_int(y));
  fl_value_set_string_take(map, "width", fl_value_new_int(w));
  fl_value_set_string_take(map, "height", fl_value_new_int(h));
  fl_value_set_string_take(map, "canPreview", fl_value_new_bool(preview));
  return fl_value_clone(map);
}

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

ScreenGraph::ScreenGraph(FlTextureRegistrar* textures) : textures_(textures) {}

ScreenGraph::~ScreenGraph() {
  Stop();
  if (textures_ != nullptr && texture_ != nullptr) {
    fl_texture_registrar_unregister_texture(textures_, FL_TEXTURE(texture_));
  }
  if (texture_ != nullptr) {
    g_object_unref(texture_);
    texture_ = nullptr;
  }
}

bool ScreenGraph::IsWaylandOnly() const {
  const char* session = std::getenv("XDG_SESSION_TYPE");
  const char* display = std::getenv("DISPLAY");
  return session != nullptr && std::strcmp(session, "wayland") == 0 &&
         (display == nullptr || display[0] == '\0');
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
  if (XQueryTree(display, root_window, &root_ret, &parent, &children, &count)) {
    for (unsigned int i = 0; i < count; i++) {
      XWindowAttributes attrs{};
      if (!XGetWindowAttributes(display, children[i], &attrs) ||
          attrs.map_state != IsViewable || attrs.width < 64 ||
          attrs.height < 64) {
        continue;
      }
      char* name = nullptr;
      if (!XFetchName(display, children[i], &name) || name == nullptr) {
        continue;
      }
      Source source;
      source.id = "window-" + std::to_string(children[i]);
      source.name = name;
      source.kind = "window";
      source.x = attrs.x;
      source.y = attrs.y;
      source.width = attrs.width;
      source.height = attrs.height;
      source.window = children[i];
      sources_.push_back(source);
      XFree(name);
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
  g_autoptr(FlValue) list = fl_value_new_list();
  for (const auto& source : sources_) {
    fl_value_append_take(
        list, SourceValue(source.id, source.name, source.kind, source.x,
                          source.y, source.width, source.height, false));
  }
  return fl_value_clone(list);
}

std::string ScreenGraph::RequestPermission() { return "granted"; }

FlValue* ScreenGraph::BeginPick() {
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "previews", fl_value_new_map());
  return fl_value_clone(map);
}

void ScreenGraph::EndPick() {}

void ScreenGraph::Indicate(const std::string&) {}

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

FlValue* ScreenGraph::Start(const std::string& source_id, bool, bool, bool motion) {
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
  g_autoptr(FlValue) result = fl_value_new_map();
  if (found == nullptr || found->kind == "systemPicker") {
    fl_value_set_string_take(result, "status",
                             fl_value_new_string("unavailable"));
    fl_value_set_string_take(result, "reason", fl_value_new_string("none"));
    return fl_value_clone(result);
  }
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
  running_ = true;
  capture_thread_ = std::thread([this] { CaptureLoop(); });
  fl_value_set_string_take(result, "status", fl_value_new_string("started"));
  fl_value_set_string_take(result, "textureId", fl_value_new_int(texture_id_));
  fl_value_set_string_take(result, "width", fl_value_new_int(send_width_));
  fl_value_set_string_take(result, "height", fl_value_new_int(send_height_));
  fl_value_set_string_take(result, "frameRate",
                           fl_value_new_int(motion ? 30 : 5));
  return fl_value_clone(result);
}

void ScreenGraph::Stop() {
  running_ = false;
  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }
  send_id_.clear();
}

bool ScreenGraph::SetIncludeSystemAudio(bool) { return false; }

void ScreenGraph::SetMotion(bool motion) { motion_ = motion; }

void ScreenGraph::SetCursor(bool) {}

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
      CaptureX11(snapshot, send_width_, send_height_);
    }
    if (textures_ != nullptr && texture_ != nullptr) {
      fl_texture_registrar_mark_texture_frame_available(textures_,
                                                        FL_TEXTURE(texture_));
    }
    const int fps = motion_ ? 30 : 5;
    g_usleep(static_cast<guint>(1000000 / std::max(1, fps)));
  }
}

bool ScreenGraph::CaptureX11(const Source& source, int out_w, int out_h) {
  Display* display = XOpenDisplay(nullptr);
  if (display == nullptr || source.window == 0) {
    return false;
  }
  XImage* image =
      XGetImage(display, source.window, 0, 0, static_cast<unsigned>(source.width),
                static_cast<unsigned>(source.height), AllPlanes, ZPixmap);
  if (image == nullptr) {
    XCloseDisplay(display);
    return false;
  }
  front_.assign(static_cast<size_t>(out_w) * out_h * 4, 0);
  for (int y = 0; y < out_h; y++) {
    const int src_y = y * source.height / out_h;
    for (int x = 0; x < out_w; x++) {
      const int src_x = x * source.width / out_w;
      const unsigned long pixel = XGetPixel(image, src_x, src_y);
      const size_t i = static_cast<size_t>(y * out_w + x) * 4;
      front_[i] = static_cast<uint8_t>((pixel >> 16) & 0xff);
      front_[i + 1] = static_cast<uint8_t>((pixel >> 8) & 0xff);
      front_[i + 2] = static_cast<uint8_t>(pixel & 0xff);
      front_[i + 3] = 255;
    }
  }
  XDestroyImage(image);
  XCloseDisplay(display);
  return true;
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
