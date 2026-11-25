// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include "include/media_kit_video/texture_sw.h"

#include <string.h>

struct _TextureSW {
  FlPixelBufferTexture parent_instance;
  guint32 current_width;
  guint32 current_height;
  VideoOutput* video_output;
  // WTV patch: Flutter uploads this copy after copy_pixels returns, while mpv may already be
  // writing the next frame into its own buffer; uploading that buffer tore fast motion.
  guint8* front;
  gsize front_size;
};

G_DEFINE_TYPE(TextureSW, texture_sw, fl_pixel_buffer_texture_get_type())

static void texture_sw_init(TextureSW* self) {
  self->current_width = 1;
  self->current_height = 1;
  self->video_output = NULL;
  self->front = NULL;
  self->front_size = 0;
}

static void texture_sw_dispose(GObject* object) {
  TextureSW* self = TEXTURE_SW(object);
  g_clear_pointer(&self->front, g_free);
  self->front_size = 0;
  G_OBJECT_CLASS(texture_sw_parent_class)->dispose(object);
}

static void texture_sw_class_init(TextureSWClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = texture_sw_copy_pixels;
  G_OBJECT_CLASS(klass)->dispose = texture_sw_dispose;
}

TextureSW* texture_sw_new(VideoOutput* video_output) {
  TextureSW* self = TEXTURE_SW(g_object_new(texture_sw_get_type(), NULL));
  self->video_output = video_output;
  return self;
}

gboolean texture_sw_copy_pixels(FlPixelBufferTexture* texture,
                                const guint8** buffer,
                                guint32* width,
                                guint32* height,
                                GError** error) {
  TextureSW* self = TEXTURE_SW(texture);
  VideoOutput* video_output = self->video_output;
  gint32 required_width = (guint32)video_output_get_width(video_output);
  gint32 required_height = (guint32)video_output_get_height(video_output);
  if (required_width > 0 && required_height > 0) {
    gsize size = (gsize)required_width * (gsize)required_height * 4;
    if (self->front_size != size) {
      g_free(self->front);
      self->front = g_new0(guint8, size);
      self->front_size = size;
    }
    video_output_lock(video_output);
    memcpy(self->front, video_output_get_pixel_buffer(video_output), size);
    video_output_unlock(video_output);
    if (self->current_width != required_width ||
        self->current_height != required_height) {
      self->current_width = required_width;
      self->current_height = required_height;
      // Notify Flutter about the change in texture's dimensions.
      video_output_notify_texture_update(video_output);
    }
    *buffer = self->front;
    *width = required_width;
    *height = required_height;
  }
  return TRUE;
}
