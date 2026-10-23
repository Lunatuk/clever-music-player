#include "cmp_media.h"
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/channel_layout.h>
#include <libavutil/error.h>
#include <libavutil/imgutils.h>
#include <libavutil/log.h>
#include <libavutil/mem.h>
#include <libavutil/sha.h>
#include <libswresample/swresample.h>

#ifdef _WIN32
#include <windows.h>
#include <io.h>
typedef struct _stat64 FileStamp;
#define file_stat _fstat64
#define file_read _read
#define file_write _write
#define file_seek _lseeki64
#define file_close _close
#define file_sync _commit
static volatile LONG busy, cancelled;
static int take_job(void) { return InterlockedCompareExchange(&busy,1,0)==0; }
static void release_job(void) { InterlockedExchange(&busy,0); }
static void set_cancel(int v) { InterlockedExchange(&cancelled,v); }
static int is_cancelled(void) { return InterlockedCompareExchange(&cancelled,0,0)!=0; }
static int64_t milliseconds(void) { return (int64_t)GetTickCount64(); }
/* Windows is a qualification harness only, not the app's Windows backend. */
static int open_file(const char *name, int write_mode) {
    wchar_t wide[16384];
    if (!name || !MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,name,-1,wide,16384)) return -1;
    return _wopen(wide,(write_mode ? _O_WRONLY : _O_RDONLY)|_O_BINARY|_O_NOINHERIT);
}
static int regular(FileStamp *s) { return (s->st_mode & _S_IFMT)==_S_IFREG; }
static int same_file(int first,int second) {
    BY_HANDLE_FILE_INFORMATION a,b;
    if (!GetFileInformationByHandle((HANDLE)_get_osfhandle(first),&a) ||
        !GetFileInformationByHandle((HANDLE)_get_osfhandle(second),&b)) return 1;
    return a.dwVolumeSerialNumber==b.dwVolumeSerialNumber && a.nFileIndexHigh==b.nFileIndexHigh && a.nFileIndexLow==b.nFileIndexLow;
}
#else
#include <stdatomic.h>
#include <time.h>
#include <unistd.h>
typedef struct stat FileStamp;
#define file_stat fstat
#define file_read read
#define file_write write
#define file_seek lseek
#define file_close close
#define file_sync fsync
static atomic_int busy, cancelled;
static int take_job(void) { int v=0; return atomic_compare_exchange_strong(&busy,&v,1); }
static void release_job(void) { atomic_store(&busy,0); }
static void set_cancel(int v) { atomic_store(&cancelled,v); }
static int is_cancelled(void) { return atomic_load(&cancelled); }
static int64_t milliseconds(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec*1000LL+t.tv_nsec/1000000; }
static int open_file(const char *name, int write_mode) {
    if (!name) return -1;
    return open(name,(write_mode ? O_WRONLY : O_RDONLY)|O_NOFOLLOW|O_CLOEXEC);
}
static int regular(FileStamp *s) { return S_ISREG(s->st_mode); }
static int same_file(int first,int second) {
    FileStamp a,b;
    return file_stat(first,&a)!=0 || file_stat(second,&b)!=0 || (a.st_dev==b.st_dev && a.st_ino==b.st_ino);
}
#endif

#define AUDIO_LIMIT (8LL*1024*1024*1024)
#define COVER_LIMIT (8*1024*1024)
#define JSON_LIMIT (128*1024)
#define MAX_SECONDS (12*3600)
static int64_t deadline;
static int logged_error;
static char response[JSON_LIMIT];
static const char *tag_keys[8] = {"title","artist","album","album_artist","genre","track","disc","date"};
static int interrupted(void *unused) { (void)unused; return is_cancelled() || milliseconds()>deadline; }
static void log_callback(void *avcl,int level,const char *fmt,va_list args) {
    (void)avcl; (void)fmt; (void)args;
    if (level<=AV_LOG_ERROR) logged_error=1; /* Never export paths/tags/log text. */
}
int cmp_media_begin(void) {
    if (!take_job()) return 0;
    set_cancel(0); deadline=milliseconds()+30*60*1000;
    av_max_alloc(64*1024*1024);
    av_log_set_callback(log_callback);
    return 1;
}
void cmp_media_cancel(void) { set_cancel(1); }
void cmp_media_end(void) { release_job(); }

typedef struct { int fd, writing, quota_hit; int64_t size, limit, offset; } FileIO;
typedef struct { AVFormatContext *format; AVIOContext *io; FileIO file; int audio, picture, container; FileStamp stamp; } Input;
typedef struct { char *text; size_t used; int failed; } Json;
static void append(Json *j,const char *fmt,...) {
    if (j->failed) return;
    va_list a; va_start(a,fmt);
    int n=vsnprintf(j->text+j->used,JSON_LIMIT-j->used,fmt,a); va_end(a);
    if (n<0 || (size_t)n>=JSON_LIMIT-j->used) { j->failed=1; return; }
    j->used+=(size_t)n;
}
static void quote(Json *j,const char *s) {
    append(j,"\"");
    if (s) for (const unsigned char *p=(const unsigned char *)s; *p; p++) {
        if (*p=='"' || *p=='\\') append(j,"\\%c",*p);
        else if (*p<32) append(j,"\\u%04x",*p);
        else append(j,"%c",*p);
    }
    append(j,"\"");
}
static const char *failure(const char *status) {
    if (is_cancelled()) status="cancelled";
    else if (milliseconds()>deadline) status="timedOut";
    snprintf(response,sizeof(response),"{\"status\":\"%s\"}",status);
    return response;
}
static int input_read(void *opaque,uint8_t *buffer,int length) {
    FileIO *f=opaque;
    if (interrupted(NULL)) return AVERROR_EXIT;
    if (f->offset>=f->size) return AVERROR_EOF;
    if ((int64_t)length>f->size-f->offset) length=(int)(f->size-f->offset);
    int n;
    do { n=(int)file_read(f->fd,buffer,length); } while(n<0 && errno==EINTR && !interrupted(NULL));
    if (n>0) f->offset+=n;
    return n>0 ? n : n==0 ? AVERROR_EOF : AVERROR(errno);
}
static int output_write(void *opaque,const uint8_t *buffer,int length) {
    FileIO *f=opaque;
    if (length<0 || f->offset>f->limit-length) { f->quota_hit=1; return AVERROR(ENOSPC); }
    int total=0;
    while (total<length) {
        if (interrupted(NULL)) return AVERROR_EXIT;
        int n=(int)file_write(f->fd,buffer+total,length-total);
        if (n<0 && errno==EINTR) continue;
        if (n<=0) return AVERROR(errno ? errno : EIO);
        total+=n; f->offset+=n;
    }
    if (f->offset>f->size) f->size=f->offset;
    return total;
}
static int64_t seek_file(void *opaque,int64_t offset,int whence) {
    FileIO *f=opaque;
    if (interrupted(NULL)) return AVERROR_EXIT;
    if (whence==AVSEEK_SIZE) return f->size;
    whence &= ~AVSEEK_FORCE;
    int64_t base=whence==SEEK_SET ? 0 : whence==SEEK_CUR ? f->offset : whence==SEEK_END ? f->size : -1;
    int64_t bound=f->writing ? f->limit : f->size;
    if (base<0 || offset < -base || offset > bound-base) return AVERROR(EINVAL);
    int64_t position=file_seek(f->fd,base+offset,SEEK_SET);
    if (position<0) return AVERROR(errno);
    f->offset=position; return position;
}
static AVIOContext *make_io(FileIO *file) {
    uint8_t *buffer=av_malloc(65536);
    if (!buffer) return NULL;
    AVIOContext *io=avio_alloc_context(buffer,65536,file->writing,file,
        file->writing ? NULL : input_read,file->writing ? output_write : NULL,seek_file);
    if (!io) av_free(buffer);
    return io;
}
static void free_io(AVIOContext **io) {
    if (*io) { av_freep(&(*io)->buffer); avio_context_free(io); }
}
static int close_input(Input *in) {
    avformat_close_input(&in->format); free_io(&in->io);
    int r=in->file.fd<0 ? 0 : file_close(in->file.fd); in->file.fd=-1; return r;
}
static int open_input(Input *in,const char *path) {
    memset(in,0,sizeof(*in)); in->file.fd=-1; in->audio=in->picture=-1;
    in->file.fd=open_file(path,0);
    if (in->file.fd<0 || file_stat(in->file.fd,&in->stamp)!=0 || !regular(&in->stamp) ||
        in->stamp.st_size<=0 || in->stamp.st_size>AUDIO_LIMIT) return -1;
    in->file.size=in->file.limit=in->stamp.st_size;
    in->io=make_io(&in->file); in->format=avformat_alloc_context();
    if (!in->io || !in->format) return -1;
    in->format->pb=in->io; in->format->flags |= AVFMT_FLAG_CUSTOM_IO;
    in->format->interrupt_callback.callback=interrupted;
    in->format->max_streams=2;
    AVDictionary *options=NULL;
    av_dict_set(&options,"format_whitelist","mp3,mov,flac",0);
    av_dict_set(&options,"protocol_whitelist","",0);
    av_dict_set(&options,"probesize","2097152",0);
    av_dict_set(&options,"analyzeduration","10000000",0);
    av_dict_set(&options,"enable_drefs","0",0);
    av_dict_set(&options,"use_absolute_path","0",0);
    int r=avformat_open_input(&in->format,NULL,NULL,&options); av_dict_free(&options);
    if (r<0 || avformat_find_stream_info(in->format,NULL)<0 || logged_error ||
        in->format->nb_streams<1 || in->format->nb_streams>2) return -1;
    const char *name=in->format->iformat->name;
    in->container=!strcmp(name,"mp3") ? 0 : strstr(name,"mov") ? 1 : !strcmp(name,"flac") ? 2 : -1;
    for (unsigned i=0;i<in->format->nb_streams;i++) {
        AVStream *s=in->format->streams[i]; AVCodecParameters *p=s->codecpar;
        if (p->codec_type==AVMEDIA_TYPE_AUDIO) { if (in->audio!=-1) return -1; in->audio=(int)i; }
        else if (p->codec_type==AVMEDIA_TYPE_VIDEO && (s->disposition & AV_DISPOSITION_ATTACHED_PIC) &&
            (p->codec_id==AV_CODEC_ID_PNG || p->codec_id==AV_CODEC_ID_MJPEG)) {
            if (in->picture!=-1 || s->attached_pic.size<=0 || s->attached_pic.size>COVER_LIMIT) return -1;
            in->picture=(int)i;
        } else return -1;
    }
    if (in->container<0 || in->audio<0) return -1;
    AVCodecParameters *p=in->format->streams[in->audio]->codecpar;
    enum AVCodecID expected=in->container==0 ? AV_CODEC_ID_MP3 : in->container==1 ? AV_CODEC_ID_AAC : AV_CODEC_ID_FLAC;
    return p->codec_id==expected && p->sample_rate>=8000 && p->sample_rate<=192000 &&
        p->ch_layout.nb_channels>=1 && p->ch_layout.nb_channels<=8 ? 0 : -1;
}
static int64_t duration_us(Input *in) {
    AVStream *s=in->format->streams[in->audio];
    return s->duration>0 && s->duration!=AV_NOPTS_VALUE ? av_rescale_q(s->duration,s->time_base,AV_TIME_BASE_Q) : in->format->duration;
}
static int inspect(Input *in,Json *j) {
    AVCodecParameters *p=in->format->streams[in->audio]->codecpar;
    int64_t duration=duration_us(in);
    if (duration<=0 || duration>MAX_SECONDS*1000000LL) return -1;
    append(j,"{\"status\":\"ok\",\"inspection\":{\"container\":\"%s\",\"codec\":\"%s\",\"durationUs\":%" PRId64 ",\"sizeBytes\":%" PRId64 ",\"audioStreamIndex\":%d,\"sampleRate\":%d,\"channels\":%d,\"bitRate\":",
        in->container==0 ? "mp3" : in->container==1 ? "m4a" : "flac",
        in->container==0 ? "mp3" : in->container==1 ? "aac" : "flac",duration,in->file.size,in->audio,p->sample_rate,p->ch_layout.nb_channels);
    if (p->bit_rate>0) append(j,"%" PRId64,p->bit_rate); else append(j,"null");
    append(j,",\"bitDepth\":");
    if (p->bits_per_raw_sample>0) append(j,"%d",p->bits_per_raw_sample); else append(j,"null");
    append(j,",\"coverStreamIndex\":");
    if (in->picture>=0) append(j,"%d",in->picture); else append(j,"null");
    append(j,",\"tags\":{"); int count=0;
    for (int k=0;k<8;k++) {
        AVDictionaryEntry *e=av_dict_get(in->format->metadata,tag_keys[k],NULL,0);
        if (!e) e=av_dict_get(in->format->streams[in->audio]->metadata,tag_keys[k],NULL,0);
        if (!e && k==3) e=av_dict_get(in->format->metadata,"albumartist",NULL,0);
        if (!e) continue;
        if (strlen(e->value)>16384) return -1;
        if (count++) append(j,","); quote(j,tag_keys[k]); append(j,":"); quote(j,e->value);
    }
    append(j,"}}}"); return j->failed ? -1 : 0;
}
static void digest_text(struct AVSHA *sha,char hex[65]) {
    uint8_t bytes[32]; static const char digits[]="0123456789abcdef";
    av_sha_final(sha,bytes);
    for (int i=0;i<32;i++) { hex[2*i]=digits[bytes[i]>>4]; hex[2*i+1]=digits[bytes[i]&15]; }
    hex[64]=0;
}
static int packet_digest(Input *in,char hex[65]) {
    struct AVSHA *sha=av_sha_alloc(); AVPacket *packet=av_packet_alloc(); int r=-1; int64_t bytes=0;
    if (!sha || !packet || av_sha_init(sha,256)<0) goto done;
    while (!interrupted(NULL) && (r=av_read_frame(in->format,packet))>=0) {
        if (packet->stream_index==in->audio) {
            if (packet->flags & AV_PKT_FLAG_CORRUPT) { r=-1; goto done; }
            av_sha_update(sha,packet->data,packet->size); bytes+=packet->size;
        }
        av_packet_unref(packet);
    }
    if (r==AVERROR_EOF && bytes>0 && !interrupted(NULL)) { digest_text(sha,hex); r=0; } else r=-1;
done: av_packet_free(&packet); av_free(sha); return r;
}
typedef struct { struct AVSHA *sha; SwrContext *swr; int rate, channels, format; int64_t samples; AVChannelLayout layout; } Pcm;
static int consume(Pcm *pcm,AVFrame *frame) {
    if (interrupted(NULL) || frame->nb_samples<=0 || frame->nb_samples>131072 ||
        frame->sample_rate!=pcm->rate || frame->ch_layout.nb_channels!=pcm->channels ||
        (frame->flags & AV_FRAME_FLAG_CORRUPT)) return -1;
    if (!pcm->swr) {
        if (av_channel_layout_copy(&pcm->layout,&frame->ch_layout)<0) return -1;
        pcm->format=frame->format;
        if (swr_alloc_set_opts2(&pcm->swr,&pcm->layout,AV_SAMPLE_FMT_S32,pcm->rate,
                &frame->ch_layout,(enum AVSampleFormat)frame->format,pcm->rate,0,NULL)<0 || swr_init(pcm->swr)<0) return -1;
    } else if (pcm->format!=frame->format || av_channel_layout_compare(&pcm->layout,&frame->ch_layout)!=0) return -1;
    uint8_t *buffer=NULL; int line=0;
    if (av_samples_alloc(&buffer,&line,pcm->channels,frame->nb_samples,AV_SAMPLE_FMT_S32,1)<0) return -1;
    int n=swr_convert(pcm->swr,&buffer,frame->nb_samples,(const uint8_t **)frame->extended_data,frame->nb_samples);
    if (n!=frame->nb_samples) { av_free(buffer); return -1; }
    av_sha_update(pcm->sha,buffer,n*pcm->channels*4); av_free(buffer); pcm->samples+=n;
    return pcm->samples<=MAX_SECONDS*(int64_t)pcm->rate ? 0 : -1;
}
static int drain(AVCodecContext *decoder,AVFrame *frame,Pcm *pcm) {
    int r;
    while ((r=avcodec_receive_frame(decoder,frame))>=0) {
        int valid=consume(pcm,frame); av_frame_unref(frame); if (valid<0) return -1;
    }
    return r==AVERROR(EAGAIN) || r==AVERROR_EOF ? 0 : -1;
}
static int decode_audio(Input *in,char hex[65],int64_t *duration) {
    AVCodecParameters *p=in->format->streams[in->audio]->codecpar;
    AVCodecContext *decoder=avcodec_alloc_context3(avcodec_find_decoder(p->codec_id));
    AVFrame *frame=av_frame_alloc(); AVPacket *packet=av_packet_alloc();
    Pcm pcm={0}; pcm.sha=av_sha_alloc(); pcm.rate=p->sample_rate; pcm.channels=p->ch_layout.nb_channels;
    int r=-1;
    if (!decoder || !frame || !packet || !pcm.sha || av_sha_init(pcm.sha,256)<0 || avcodec_parameters_to_context(decoder,p)<0) goto done;
    decoder->thread_count=1; decoder->err_recognition=AV_EF_CRCCHECK|AV_EF_BITSTREAM|AV_EF_BUFFER|AV_EF_EXPLODE;
    if (avcodec_open2(decoder,avcodec_find_decoder(p->codec_id),NULL)<0) goto done;
    while (!interrupted(NULL) && (r=av_read_frame(in->format,packet))>=0) {
        if (packet->stream_index==in->audio && ((packet->flags & AV_PKT_FLAG_CORRUPT) ||
            avcodec_send_packet(decoder,packet)<0 || drain(decoder,frame,&pcm)<0)) { r=-1; goto done; }
        av_packet_unref(packet);
    }
    if (r!=AVERROR_EOF || interrupted(NULL) || avcodec_send_packet(decoder,NULL)<0 || drain(decoder,frame,&pcm)<0 || pcm.samples<=0) { r=-1; goto done; }
    digest_text(pcm.sha,hex); *duration=av_rescale(pcm.samples,1000000,pcm.rate); r=0;
done:
    avcodec_free_context(&decoder); av_frame_free(&frame); av_packet_free(&packet);
    swr_free(&pcm.swr); av_channel_layout_uninit(&pcm.layout); av_free(pcm.sha); return r;
}
static int decode_picture(AVPacket *packet,enum AVCodecID codec,int *width,int *height) {
    const AVCodec *implementation=avcodec_find_decoder(codec);
    AVCodecContext *decoder=avcodec_alloc_context3(implementation); AVFrame *frame=av_frame_alloc(); int r=-1;
    if (!decoder || !frame || packet->size<=0 || packet->size>COVER_LIMIT) goto done;
    decoder->thread_count=1; decoder->max_pixels=4096*4096;
    decoder->err_recognition=AV_EF_CRCCHECK|AV_EF_BITSTREAM|AV_EF_BUFFER|AV_EF_EXPLODE;
    if (avcodec_open2(decoder,implementation,NULL)<0 || avcodec_send_packet(decoder,packet)<0 ||
        avcodec_receive_frame(decoder,frame)<0 || frame->width<=0 || frame->height<=0 ||
        frame->width>4096 || frame->height>4096 || (frame->flags & AV_FRAME_FLAG_CORRUPT)) goto done;
    *width=frame->width; *height=frame->height; av_frame_unref(frame);
    if (avcodec_send_packet(decoder,NULL)<0 || avcodec_receive_frame(decoder,frame)!=AVERROR_EOF) goto done;
    r=0;
done: avcodec_free_context(&decoder); av_frame_free(&frame); return r;
}
static int load_cover(const char *path,int format,AVPacket *packet) {
    int fd=open_file(path,0); FileStamp stamp; int r=-1;
    if (fd<0) return -1;
    if (file_stat(fd,&stamp)!=0 || !regular(&stamp) || stamp.st_size<=0 || stamp.st_size>COVER_LIMIT || av_new_packet(packet,(int)stamp.st_size)<0) goto done;
    int total=0;
    while (total<packet->size && !interrupted(NULL)) {
        int n=(int)file_read(fd,packet->data+total,packet->size-total);
        if (n<0 && errno==EINTR) continue;
        if (n<=0) goto done;
        total+=n;
    }
    if (total!=packet->size || (format!=1 && format!=2)) goto done;
    if (format==1 && (packet->size<8 || memcmp(packet->data,"\x89PNG\r\n\x1a\n",8))) goto done;
    if (format==2 && (packet->size<3 || memcmp(packet->data,"\xff\xd8\xff",3))) goto done;
    r=0;
done: if (file_close(fd)!=0) r=-1; return r;
}
static int remux(Input *in,const char *path,const char *cover_path,int cover_format,int64_t limit,const char *const tags[8],int *quota) {
    AVFormatContext *out=NULL; AVIOContext *io=NULL; FileIO file={0}; file.fd=-1; file.writing=1; file.limit=limit;
    AVPacket *cover=av_packet_alloc(),*packet=av_packet_alloc(); int r=-1, width=0,height=0; AVDictionary *options=NULL;
    enum AVCodecID picture_codec=AV_CODEC_ID_NONE;
    if (!cover || !packet) goto done;
    if (cover_path) {
        if (load_cover(cover_path,cover_format,cover)<0) goto done;
        picture_codec=cover_format==1 ? AV_CODEC_ID_PNG : AV_CODEC_ID_MJPEG;
    } else if (in->picture>=0) {
        if (av_packet_ref(cover,&in->format->streams[in->picture]->attached_pic)<0) goto done;
        picture_codec=in->format->streams[in->picture]->codecpar->codec_id;
    }
    if (picture_codec!=AV_CODEC_ID_NONE && decode_picture(cover,picture_codec,&width,&height)<0) goto done;
    if (avformat_alloc_output_context2(&out,NULL,in->container==0 ? "mp3" : in->container==1 ? "ipod" : "flac",NULL)<0 || !out) goto done;
    AVStream *audio=avformat_new_stream(out,NULL);
    if (!audio || avcodec_parameters_copy(audio->codecpar,in->format->streams[in->audio]->codecpar)<0) goto done;
    audio->codecpar->codec_tag=0; audio->time_base=in->format->streams[in->audio]->time_base;
    if (picture_codec!=AV_CODEC_ID_NONE) {
        AVStream *picture=avformat_new_stream(out,NULL); if (!picture) goto done;
        picture->codecpar->codec_type=AVMEDIA_TYPE_VIDEO; picture->codecpar->codec_id=picture_codec;
        picture->codecpar->width=width; picture->codecpar->height=height; picture->disposition=AV_DISPOSITION_ATTACHED_PIC;
        picture->time_base=(AVRational){1,90000};
        av_dict_set(&picture->metadata,"title","Album cover",0); av_dict_set(&picture->metadata,"comment","Cover (front)",0);
    }
    for (int k=0;k<8;k++) if (tags && tags[k]) {
        if (!tags[k][0] || strlen(tags[k])>16384 || av_dict_set(&out->metadata,tag_keys[k],tags[k],0)<0) goto done;
    }
    file.fd=open_file(path,1); FileStamp stamp;
    if (file.fd<0 || file_stat(file.fd,&stamp)!=0 || !regular(&stamp) || stamp.st_size!=0 ||
        same_file(file.fd,in->file.fd)) goto done;
    io=make_io(&file); if (!io) goto done;
    out->pb=io; out->flags |= AVFMT_FLAG_CUSTOM_IO; out->interrupt_callback.callback=interrupted;
    if (in->container==0) av_dict_set(&options,"id3v2_version","4",0);
    if (avformat_write_header(out,&options)<0) goto done;
    if (picture_codec!=AV_CODEC_ID_NONE) {
        cover->stream_index=1; cover->pts=cover->dts=0; cover->duration=0; cover->pos=-1; cover->flags |= AV_PKT_FLAG_KEY;
        if (av_interleaved_write_frame(out,cover)<0) goto done;
    }
    while (!interrupted(NULL) && (r=av_read_frame(in->format,packet))>=0) {
        if (packet->stream_index==in->audio) {
            if (packet->flags & AV_PKT_FLAG_CORRUPT) { r=-1; goto done; }
            av_packet_rescale_ts(packet,in->format->streams[in->audio]->time_base,audio->time_base);
            packet->stream_index=0; packet->pos=-1;
            if (av_interleaved_write_frame(out,packet)<0) { r=-1; goto done; }
        }
        av_packet_unref(packet);
    }
    if (r!=AVERROR_EOF || interrupted(NULL) || av_write_trailer(out)<0) { r=-1; goto done; }
    avio_flush(io); r=io->error<0 || file_sync(file.fd)!=0 ? -1 : 0;
done:
    if (out) out->pb=NULL;
    avformat_free_context(out); free_io(&io); av_packet_free(&cover); av_packet_free(&packet); av_dict_free(&options);
    if (file.fd>=0 && file_close(file.fd)!=0) r=-1;
    *quota=file.quota_hit; return r;
}
const char *cmp_media_run(int op,const char *source,const char *output,const char *cover,int cover_format,int mode,int64_t max_output,const char *const tags[8]) {
    logged_error=0; response[0]=0;
    if (interrupted(NULL)) return failure("cancelled");
    if (op==0) {
        snprintf(response,sizeof(response),"{\"status\":\"ok\",\"profile\":\"cmp-android-audio-1\",\"version\":\"%s\",\"license\":\"%s\"}",av_version_info(),avutil_license());
        return response;
    }
    if (op<1 || op>5 || !source || strlen(source)>16384 || (op==5 && (!output || max_output<=0 || max_output>AUDIO_LIMIT))) return failure("unreadable");
    Input in; int r=open_input(&in,source); char hash[65]; int64_t duration=0; int quota=0;
    Json json={response,0,0}; const char *error="invalidAudio";
    if (r<0) goto done;
    if (op==1) r=inspect(&in,&json);
    else if (op==2 || (op==4 && mode==1)) {
        r=decode_audio(&in,hash,&duration);
        if (r==0) append(&json,"{\"status\":\"ok\",\"digest\":\"%s\",\"durationUs\":%" PRId64 "}",hash,duration);
    } else if (op==3 || (op==4 && mode==2)) {
        error="invalidCover"; int width,height;
        if (in.picture<0) { r=-1; error="coverMissing"; goto done; }
        AVStream *s=in.format->streams[in.picture];
        r=decode_picture(&s->attached_pic,s->codecpar->codec_id,&width,&height);
        if (r==0) {
            struct AVSHA *sha=av_sha_alloc(); if (!sha || av_sha_init(sha,256)<0) { av_free(sha); r=-1; goto done; }
            av_sha_update(sha,s->attached_pic.data,s->attached_pic.size); digest_text(sha,hash); av_free(sha);
            append(&json,"{\"status\":\"ok\",\"digest\":\"%s\"}",hash);
        }
    } else if (op==4 && mode==0) {
        r=packet_digest(&in,hash); if (r==0) append(&json,"{\"status\":\"ok\",\"digest\":\"%s\"}",hash);
    } else if (op==5) {
        r=remux(&in,output,cover,cover_format,max_output,tags,&quota);
        if (r==0) append(&json,"{\"status\":\"ok\"}");
        if (quota) error="quotaExceeded";
    } else r=-1;
done:
    if (close_input(&in)!=0) r=-1;
    if (r<0 || logged_error || json.failed || interrupted(NULL)) return failure(error);
    return response;
}
