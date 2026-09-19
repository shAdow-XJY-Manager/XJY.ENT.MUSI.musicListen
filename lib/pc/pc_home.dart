import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_common/flutter_common.dart';

import '../view_model/music_model.dart';
import '../view_model/set_up_data.dart';

class PCHomePage extends StatefulWidget {
  const PCHomePage({super.key});
  @override
  State<PCHomePage> createState() => _PCHomePageState();
}

class _PCHomePageState extends State<PCHomePage> {

  // 通过单例获取
  final musicList = MusicManager.instance.musicList;

  //audio
  bool isPlaying = false;
  final AssetsAudioPlayer assetsAudioPlayer = AssetsAudioPlayer();

  void musicPlayerInit() {
    List<Audio> audios = [];
    for (MusicModel model in musicList) {
      audios.add(Audio(model.songUrl));
    }
    assetsAudioPlayer.open(
        Playlist(
            audios: audios
        ),
        loopMode: LoopMode.playlist //loop the full playlist
    );
  }

  void songOperator(int num){
    //0 :pause or play
    //1 :pre song
    //2 :next song
    if(assetsAudioPlayer.playlist == null){
      musicPlayerInit();
      debugPrint("init");
    }else{
      switch (num){
        case 0:{assetsAudioPlayer.playOrPause();}
        break;
        case 1:{assetsAudioPlayer.previous();}
        break;
        case 2:{assetsAudioPlayer.next();}
        break;
        default : break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: siteBackground,
      appBar: AppBar(
        title: const Text("Music Directory"),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            crossAxisSpacing: 20,
            mainAxisSpacing: 20,
            childAspectRatio: 0.75,
          ),
          itemCount: musicList.length,
          itemBuilder: (context, index) {
            final music = musicList[index];
            return MediaCard(
              assetImage: "assets/images/music_default.png",
              title: music.songName,
              subtitle: music.singerName,
              onTap: () {
                songOperator(-1);
                assetsAudioPlayer.playlistPlayAtIndex(index);
                setState(() {
                  isPlaying = true;
                });
              },
            );
          },
        ),
      ),
      bottomNavigationBar: Container(
        height: 80,
        decoration: BoxDecoration(
          color: siteSurface,
          border: Border(
            top: BorderSide(color: borderColor, width: 1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.skip_previous, size: 32),
              color: textPrimary,
              onPressed: () {
                songOperator(1);
                setState(() {
                  isPlaying = true;
                });
              },
            ),
            const SizedBox(width: 16),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: primaryColor,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 32,
                ),
                color: Colors.white,
                onPressed: () {
                  songOperator(0);
                  setState(() {
                    isPlaying = !isPlaying;
                  });
                },
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.skip_next, size: 32),
              color: textPrimary,
              onPressed: () {
                songOperator(2);
                setState(() {
                  isPlaying = true;
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
