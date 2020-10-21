#include <ruby.h>
#include "webrtc/common_audio/vad/include/webrtc_vad.h"

struct vad_instance{
  VadInst* inst;  
  int rage;
};

void vad_free(struct vad_instance* ptr) {
  WebRtcVad_Free(ptr->inst);
}

static VALUE rb_vad_create(VALUE klass, VALUE rb_rage) {
  struct vad_instance* vad;
  VALUE obj = Data_Make_Struct(klass, struct vad_instance, NULL, vad_free, vad);
  VALUE argv[1];
  argv[0] = rb_rage;
  rb_obj_call_init(obj, 1, argv);
  return obj;
}

static int __attribute__ ((unused)) get_aggressiveness(VALUE rb_rage) {
  int rage = NUM2INT(rb_rage);
  if (rage < 0 || rage > 3) {
    rb_raise(rb_const_get(rb_cObject, rb_intern("ArgumentError")), "Invalid VAD aggressiveness value");
  }
  return rage;
}

static VALUE rb_vad_init(VALUE self, VALUE rb_rage) {
  struct vad_instance* vad;
  Data_Get_Struct(self, struct vad_instance, vad);
  
  vad->inst = WebRtcVad_Create();
  vad->rage = get_aggressiveness(rb_rage);
  
  if (WebRtcVad_Init(vad->inst)) {
    rb_raise(rb_eRuntimeError, "Cannot init VAD");
  }
  if (WebRtcVad_set_mode(vad->inst, vad->rage)) {
    rb_raise(rb_eRuntimeError, "Cannot set VAD aggressiveness");
  }
  return self;
}

static VALUE rb_vad_set_aggressiveness(VALUE self, VALUE rb_rage) {
  struct vad_instance* vad;
  Data_Get_Struct(self, struct vad_instance, vad);
  
  int rage = get_aggressiveness(rb_rage);
  if (WebRtcVad_set_mode(vad->inst, rage)) {
    rb_raise(rb_eRuntimeError, "Cannot set VAD aggressiveness");
  }
  vad->rage = rage;
  return rb_rage;
}

static VALUE rb_vad_get_aggressiveness(VALUE self) {
  struct vad_instance* vad;
  Data_Get_Struct(self, struct vad_instance, vad);
  
  return INT2NUM(vad->rage);
}

static VALUE rb_valid_rate_and_frame_length(VALUE self, VALUE rb_rate, VALUE rb_frame_len) {
  int rate, frame_length;
  rate = NUM2INT(rb_rate);
  frame_length = NUM2INT(rb_frame_len);

  if (WebRtcVad_ValidRateAndFrameLength(rate, frame_length)) {
    return Qfalse;
  } else {
    return Qtrue;
  }
}

static VALUE rb_vad_process(VALUE self, VALUE rb_sample_rate, VALUE rb_audio_frame, VALUE rb_offset, VALUE rb_frame_len) {
  int sr = NUM2INT(rb_sample_rate);
  int offset = NUM2INT(rb_offset);
  int frame_length = NUM2INT(rb_frame_len);
  int result;
  int16_t *buf = (int16_t*)(StringValuePtr(rb_audio_frame) + offset);
  
  struct vad_instance* ptr;
  Data_Get_Struct(self, struct vad_instance, ptr);
  
  result = WebRtcVad_Process(ptr->inst, sr, buf, frame_length);
  switch (result) {
  case 1:
    return INT2NUM(1);
  case 0:
    return INT2NUM(0);
  case -1:
    break;
  default:
    rb_raise(rb_eRuntimeError, "Error while processing frame");
  }
  return Qnil;
}

void Init_webrtcvad(void) {
  VALUE mod = rb_define_module("WebRTC");
  VALUE cVad = rb_define_class_under(mod, "Vad", rb_cObject);

  rb_define_singleton_method(cVad, "new", rb_vad_create, 1);
  rb_define_method(cVad, "initialize", rb_vad_init, 1);
  rb_define_method(cVad, "aggressiveness=", rb_vad_set_aggressiveness, 1);
  rb_define_method(cVad, "aggressiveness", rb_vad_get_aggressiveness, 0);
  rb_define_method(cVad, "process", rb_vad_process, 4);
  rb_define_singleton_method(cVad, "valid_rate_and_frame_length?", rb_valid_rate_and_frame_length, 2);
  rb_define_method(cVad, "valid_frame?", rb_valid_rate_and_frame_length, 2);
}
