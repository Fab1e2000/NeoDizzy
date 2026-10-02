#import <Foundation/Foundation.h>
#include "AudioTagBridge.h"
#include <fileref.h>
#include <tfilestream.h>
#include <tpropertymap.h>
#include <tvariant.h>
#include <mpegfile.h>
#include <flacfile.h>
#include <mp4file.h>
#include <mp4properties.h>
#include <mp4tag.h>
#include <wavfile.h>
#include <aifffile.h>
#include <cstring>
using namespace TagLib;
static char *jsonResult(NSDictionary *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    return strdup([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
}
static char *errorResult(NSString *message) { return jsonResult(@{@"error":message}); }
static NSString *ns(const String &s) { return [NSString stringWithUTF8String:s.toCString(true)] ?: @""; }
static String tag(NSString *s) { return String(s.UTF8String, String::UTF8); }
static bool supported(FileRef &f) {
    if(f.isNull() || !f.file()->isValid() || !f.audioProperties()) return false;
    if(auto mp4 = dynamic_cast<MP4::File *>(f.file())) return mp4->audioProperties() && !mp4->audioProperties()->isEncrypted();
    return dynamic_cast<MPEG::File *>(f.file()) || dynamic_cast<FLAC::File *>(f.file()) ||
        dynamic_cast<RIFF::WAV::File *>(f.file()) || dynamic_cast<RIFF::AIFF::File *>(f.file());
}
static int mainPicture(const List<VariantMap> &pictures) {
    int i = 0;
    for(const auto &picture : pictures) {
        if(picture.contains("pictureType") && picture["pictureType"].toString() == "Front Cover") return i;
        ++i;
    }
    return pictures.isEmpty() ? -1 : 0;
}
static NSArray *fields() { return @[@"TITLE", @"ARTIST", @"ALBUM", @"ALBUMARTIST", @"TRACKNUMBER", @"DISCNUMBER", @"DATE", @"GENRE"]; }
extern "C" char *NDTagRead(const char *path) {
    @autoreleasepool { try {
        FileStream stream(path, true);
        FileRef f(&stream);
        if(!supported(f)) return errorResult(@"此文件的实际格式不支持标签编辑，或文件已损坏／受保护。");
        auto props = f.properties();
        NSMutableDictionary *values = [NSMutableDictionary dictionary];
        for(NSString *key in fields()) {
            NSMutableArray *list = [NSMutableArray array];
            for(const auto &s : props[tag(key)]) [list addObject:ns(s)];
            values[key] = list;
        }
        auto pictures = f.complexProperties("PICTURE");
        int main = mainPicture(pictures);
        NSString *cover = @"";
        if(main >= 0) {
            auto bytes = pictures[main]["data"].toByteVector();
            if(bytes.size() > 20 * 1024 * 1024) return errorResult(@"内嵌封面超过 20 MB，暂不支持编辑。");
            cover = [[NSData dataWithBytes:bytes.data() length:bytes.size()] base64EncodedStringWithOptions:0];
        }
        return jsonResult(@{@"values":values, @"cover":cover, @"isFLAC":@(dynamic_cast<FLAC::File *>(f.file()) != nullptr)});
    } catch(...) { return errorResult(@"无法读取文件标签。"); } }
}
extern "C" char *NDTagWrite(const char *path, const char *json) {
    @autoreleasepool { try {
        FileStream stream(path);
        FileRef f(&stream);
        if(!supported(f) || stream.readOnly()) return errorResult(@"此音频不可写或不支持标签编辑。");
        NSDictionary *input = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:json length:strlen(json)] options:0 error:nil];
        NSDictionary *values = input[@"values"];
        if(![values isKindOfClass:[NSDictionary class]]) return errorResult(@"标签数据无效。");
        auto props = f.properties();
        auto mp4 = dynamic_cast<MP4::File *>(f.file());
        const auto originalItems = mp4 ? mp4->tag()->itemMap() : MP4::ItemMap();
        // Only keys supplied by the editor are modified. Unsupported/unknown tags remain intact.
        for(NSString *key in fields()) {
            NSArray *array = values[key];
            if(!array) continue;
            props.erase(tag(key));
            StringList strings;
            for(NSString *s in array) strings.append(tag(s));
            if(!strings.isEmpty()) props.insert(tag(key), strings);
        }
        auto rejected = f.setProperties(props);
        for(NSString *key in fields()) if(values[key] && rejected.contains(tag(key))) return errorResult(@"此格式无法保存所填写的标签。");
        if(mp4) {
            // The generic property map uppercases free-form atom names. Restore
            // every untouched native atom to avoid rewriting/duplicating custom tags.
            NSDictionary *atoms = @{@"TITLE":@"©nam", @"ARTIST":@"©ART", @"ALBUM":@"©alb", @"ALBUMARTIST":@"aART",
                                    @"TRACKNUMBER":@"trkn", @"DISCNUMBER":@"disk", @"DATE":@"©day", @"GENRE":@"©gen"};
            StringList changedAtoms;
            for(NSString *key in values) if(atoms[key]) changedAtoms.append(tag(atoms[key]));
            const auto written = mp4->tag()->itemMap();
            for(const auto &[name, item] : written) if(!changedAtoms.contains(name)) mp4->tag()->removeItem(name);
            for(const auto &[name, item] : originalItems) if(!changedAtoms.contains(name)) mp4->tag()->setItem(name, item);
            if(values[@"GENRE"]) mp4->tag()->removeItem("gnre");
        }
        NSString *action = input[@"coverAction"] ?: @"keep";
        if(![action isEqualToString:@"keep"]) {
            auto pictures = f.complexProperties("PICTURE");
            int main = mainPicture(pictures);
            List<VariantMap> updated;
            int i = 0;
            for(const auto &picture : pictures) { if(i++ != main) updated.append(picture); }
            if([action isEqualToString:@"replace"]) {
                NSData *data = [[NSData alloc] initWithBase64EncodedString:input[@"cover"] options:0];
                if(!data || data.length > 20 * 1024 * 1024) return errorResult(@"封面数据无效。");
                VariantMap picture;
                picture.insert("data", ByteVector((const char *)data.bytes, (unsigned int)data.length));
                picture.insert("mimeType", tag(input[@"mime"] ?: @"image/jpeg"));
                picture.insert("pictureType", String("Front Cover"));
                picture.insert("description", String(""));
                // MP4 has no picture type; first image is its primary cover.
                List<VariantMap> ordered; ordered.append(picture);
                for(const auto &other : updated) ordered.append(other);
                updated = ordered;
            }
            if(!f.setComplexProperties("PICTURE", updated)) return errorResult(@"此格式无法保存封面。");
        }
        if(!f.save()) return errorResult(@"保存标签失败，请检查文件权限和剩余空间。");
        return jsonResult(@{@"ok":@YES});
    } catch(...) { return errorResult(@"写入标签失败，原文件未更改。"); } }
}
extern "C" void NDTagFree(char *value) { free(value); }
