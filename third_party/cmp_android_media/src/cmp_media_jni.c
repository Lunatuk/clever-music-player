#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include "cmp_media.h"

JNIEXPORT jboolean JNICALL Java_dev_lunatuk_clever_1music_1player_AndroidMediaNative_begin(JNIEnv *env,jobject self) {
    (void)env; (void)self; return cmp_media_begin() ? JNI_TRUE : JNI_FALSE;
}
JNIEXPORT void JNICALL Java_dev_lunatuk_clever_1music_1player_AndroidMediaNative_cancel(JNIEnv *env,jobject self) {
    (void)env; (void)self; cmp_media_cancel();
}
JNIEXPORT void JNICALL Java_dev_lunatuk_clever_1music_1player_AndroidMediaNative_end(JNIEnv *env,jobject self) {
    (void)env; (void)self; cmp_media_end();
}
/* JNI modified UTF-8 cannot represent ordinary UTF-8 emoji faithfully. Kotlin
 * passes explicit UTF-8 byte arrays for paths/tags and receives the same here. */
static char *utf8(JNIEnv *env,jbyteArray bytes,int *valid) {
    if (!bytes) return NULL;
    jsize size=(*env)->GetArrayLength(env,bytes);
    if (size<=0 || size>16384) { *valid=0; return NULL; }
    char *text=malloc((size_t)size+1);
    if (!text) { *valid=0; return NULL; }
    (*env)->GetByteArrayRegion(env,bytes,0,size,(jbyte *)text);
    if ((*env)->ExceptionCheck(env) || memchr(text,0,size)) { free(text); *valid=0; return NULL; }
    text[size]=0; return text;
}
JNIEXPORT jbyteArray JNICALL Java_dev_lunatuk_clever_1music_1player_AndroidMediaNative_run(
    JNIEnv *env,jobject self,jint op,jbyteArray source,jbyteArray output,jbyteArray cover,
    jint cover_format,jint mode,jlong limit,jobjectArray tag_values) {
    (void)self; int valid=1; char *src=utf8(env,source,&valid),*out=utf8(env,output,&valid),*image=utf8(env,cover,&valid);
    char *tags[8]={0};
    if (!tag_values || (*env)->GetArrayLength(env,tag_values)!=8) valid=0;
    else for (int i=0;i<8;i++) {
        jbyteArray value=(jbyteArray)(*env)->GetObjectArrayElement(env,tag_values,i);
        tags[i]=utf8(env,value,&valid); if (value) (*env)->DeleteLocalRef(env,value);
    }
    const char *text=valid ? cmp_media_run(op,src,out,image,cover_format,mode,limit,(const char *const *)tags) : "{\"status\":\"unreadable\"}";
    jsize length=(jsize)strlen(text); jbyteArray result=NULL;
    if (!(*env)->ExceptionCheck(env)) {
        result=(*env)->NewByteArray(env,length);
        if (result) (*env)->SetByteArrayRegion(env,result,0,length,(const jbyte *)text);
    }
    free(src); free(out); free(image); for (int i=0;i<8;i++) free(tags[i]);
    return result;
}
