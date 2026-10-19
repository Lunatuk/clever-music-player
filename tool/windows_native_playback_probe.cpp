// Runs the production AudioPlayer and WinRT decoder without a Flutter UI.
// Test audio is muted. Success requires the real native position to advance.
#include <condition_variable>
#include <iostream>
#include <mutex>
#include <thread>

#include "player.hpp"

using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

class ProbeResult final : public flutter::MethodResult<Value> {
 public:
  std::function<void(const Value*)> success;
  std::function<void(const std::string&)> failure;

 protected:
  void SuccessInternal(const Value* value) override {
    if (success) success(value);
  }
  void ErrorInternal(const std::string& code, const std::string&,
                     const Value*) override {
    if (failure) failure(code);
  }
  void NotImplementedInternal() override {
    if (failure) failure("not_implemented");
  }
};

class ProbeMessenger final : public flutter::BinaryMessenger {
 public:
  void Send(const std::string& channel, const uint8_t* bytes, size_t length,
            flutter::BinaryReply reply = nullptr) const override {
    if (channel.find(".events.") != std::string::npos) {
      ProbeResult result;
      result.success = [&](const Value* value) {
        if (!value) return;
        if (const auto* map = std::get_if<Map>(value)) {
          std::lock_guard<std::mutex> lock(mutex_);
          frames_.push_back(*map);
          changed_.notify_all();
        }
      };
      result.failure = [&](const std::string&) {
        std::lock_guard<std::mutex> lock(mutex_);
        ++errorEnvelopes_;
        changed_.notify_all();
      };
      flutter::StandardMethodCodec::GetInstance()
          .DecodeAndProcessResponseEnvelope(bytes, length, &result);
    }
    if (reply) reply(nullptr, 0);
  }

  void SetMessageHandler(const std::string& channel,
                         flutter::BinaryMessageHandler handler) override {
    handlers_[channel] = handler;
  }

  void Listen(const std::string& channel) {
    const auto bytes = flutter::StandardMethodCodec::GetInstance()
        .EncodeMethodCall(flutter::MethodCall<Value>("listen", nullptr));
    handlers_.at(channel)(bytes->data(), bytes->size(),
                          [](const uint8_t*, size_t) {});
  }

  bool WaitForResult() const {
    std::unique_lock<std::mutex> lock(mutex_);
    return changed_.wait_for(lock, std::chrono::seconds(8), [&] {
      for (const auto& frame : frames_) {
        if (frame.find(Value("errorCode")) != frame.end()) return true;
        const auto state = frame.find(Value("processingState"));
        const auto duration = frame.find(Value("duration"));
        if (state != frame.end() && duration != frame.end() &&
            !duration->second.IsNull() && duration->second.LongValue() > 0 &&
            state->second.LongValue() == 3) return true;
      }
      return errorEnvelopes_ > 0;
    });
  }

  int64_t ErrorCode() const {
    std::lock_guard<std::mutex> lock(mutex_);
    for (const auto& frame : frames_) {
      const auto error = frame.find(Value("errorCode"));
      if (error != frame.end()) return error->second.LongValue();
    }
    return 0;
  }

  int ErrorEnvelopes() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return errorEnvelopes_;
  }

 private:
  std::map<std::string, flutter::BinaryMessageHandler> handlers_;
  mutable std::mutex mutex_;
  mutable std::condition_variable changed_;
  mutable std::vector<Map> frames_;
  mutable int errorEnvelopes_ = 0;
};

void Call(AudioPlayer& player, const std::string& name, const Map& arguments) {
  auto result = std::make_unique<ProbeResult>();
  result->failure = [](const std::string& code) {
    throw std::runtime_error("Native method failed: " + code);
  };
  player.HandleMethodCall(flutter::MethodCall<Value>(
      name, std::make_unique<Value>(arguments)), std::move(result));
}

int wmain(int argc, wchar_t** argv) {
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    if (argc != 3) return 2;
    const bool invalid = winrt::to_string(winrt::hstring(argv[1])) == "invalid";
    ProbeMessenger messenger;
    AudioPlayer player("native-probe", &messenger);
    messenger.Listen("com.ryanheise.just_audio.events.native-probe");
    messenger.Listen("com.ryanheise.just_audio.data.native-probe");
    player.mediaPlayer.Volume(0.0);
    const Map child{{Value("type"), Value("progressive")},
        {Value("uri"), Value(winrt::to_string(winrt::hstring(argv[2])))}};
    const Map source{{Value("type"), Value("concatenating")},
        {Value("children"), Value(flutter::EncodableList{Value(child)})}};
    Call(player, "load", {{Value("audioSource"), Value(source)},
        {Value("initialIndex"), Value(int32_t{0})},
        {Value("initialPosition"), Value(int32_t{0})}});
    const bool observed = messenger.WaitForResult();
    const int64_t error = messenger.ErrorCode();
    if (!observed || messenger.ErrorEnvelopes() != 0 ||
        (invalid ? error == 0 : error != 0)) {
      std::cout << "FAIL observed=" << observed << " HRESULT=" << error << "\n";
      return 3;
    }
    if (invalid) {
      std::cout << "PASS native_failure HRESULT=" << error << "\n";
    } else {
      Call(player, "play", {});
      std::this_thread::sleep_for(std::chrono::milliseconds(300));
      const auto snapshot = player.PlaybackSnapshot();
      const auto position = snapshot.at(Value("positionMs")).LongValue();
      const auto state = snapshot.at(Value("playbackState")).LongValue();
      std::cout << "NATIVE positionMs=" << position << " state=" << state << "\n";
      if (position <= 0 || state != 3 || messenger.ErrorCode() != 0) return 4;
      std::cout << "PASS native_open_and_play\n";
    }
    Call(player, "dispose", {});
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    return 0;
  } catch (const winrt::hresult_error& error) {
    std::cout << "FAIL WinRT=" << static_cast<int32_t>(error.code()) << "\n";
    return 5;
  } catch (const std::exception&) {
    std::cout << "FAIL native method/codec exception\n";
    return 6;
  }
}
