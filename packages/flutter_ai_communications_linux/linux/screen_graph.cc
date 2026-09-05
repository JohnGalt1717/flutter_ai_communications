#include "screen_graph.h"

#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <gio/gio.h>
#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <thread>

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
  g_autoptr(FlValue) map = fl_value_new_map();
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

ScreenGraph::ScreenGraph(FlTextureRegistrar* textures) : textures_(textures) {}

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
  g_autoptr(FlValue) list = fl_value_new_list();
  for (const auto& source : sources_) {
    fl_value_append_take(
        list,
        SourceValue(source.id, source.name, source.kind, source.x, source.y,
                    source.width, source.height,
                    source.kind != "systemPicker", source.applicationName));
  }
  return fl_value_clone(list);
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
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "previews", fl_value_new_map());
    return fl_value_clone(map);
  }
  EnsureDisplay();
  g_autoptr(FlValue) previews = fl_value_new_map();
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
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "previews", fl_value_ref(previews));
  return fl_value_clone(map);
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
  g_autoptr(FlValue) result = fl_value_new_map();
  if (found != nullptr && found->kind == "systemPicker") {
    cursor_ = cursor;
    motion_ = motion;
    if (StartPortal(pending, cursor, motion)) {
      return nullptr;
    }
    fl_value_set_string_take(result, "status",
                             fl_value_new_string("unavailable"));
    fl_value_set_string_take(result, "reason", fl_value_new_string("none"));
    return fl_value_clone(result);
  }
  if (found == nullptr) {
    fl_value_set_string_take(result, "status",
                             fl_value_new_string("unavailable"));
    fl_value_set_string_take(result, "reason", fl_value_new_string("none"));
    return fl_value_clone(result);
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
  return fl_value_clone(result);
}

void ScreenGraph::Stop() {
  running_ = false;
  CancelPortal();
  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }
  HideFrame();
  send_id_.clear();
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
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "status", fl_value_new_string("started"));
  fl_value_set_string_take(map, "textureId", fl_value_new_int(texture_id_));
  fl_value_set_string_take(map, "width", fl_value_new_int(send_width_));
  fl_value_set_string_take(map, "height", fl_value_new_int(send_height_));
  fl_value_set_string_take(map, "frameRate",
                           fl_value_new_int(motion_ ? 30 : 5));
  return fl_value_clone(map);
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
    UnrefResults(results);
    if (state->cancel) {
      finish("unavailable", "none");
      return;
    }
    send_width_ = 1920;
    send_height_ = 1080;
    motion_ = motion;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      send_id_ = "system-picker";
      running_ = true;
      front_.assign(static_cast<size_t>(send_width_) * send_height_ * 4, 0);
    }
    finish("started", nullptr);
  });
  return true;
}
