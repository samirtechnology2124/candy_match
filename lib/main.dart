import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flame/events.dart';
import 'package:flame/effects.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flame/particles.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlameAudio.audioCache.loadAll(['pop.mp3', 'swap.mp3', 'match.mp3', 'bomb.mp3']);
  runApp(GameWidget(game: CandyMatchGame()));
}

enum GameState { splash, playing, levelComplete, gameOver, settings }
enum CandyType { red, blue, green, yellow, purple, orange }
enum SpecialType { none, horizontal, vertical }

class CandyMatchGame extends FlameGame with TapCallbacks, DragCallbacks, HasGameRef {
  GameState state = GameState.splash;
  final Random _random = Random();
  bool soundEnabled = true;
  GameState previousState = GameState.splash;

  static const int gridSize = 8;
  static const double candySize = 45;
  static const double gridOffsetY = 200;

  late List<List<CandyComponent?>> grid;
  int score = 0;
  int movesLeft = 30;
  int level = 1;
  int targetScore = 2000;
  int highScore = 0;

  CandyComponent? selectedCandy;
  TextComponent? scoreText;
  TextComponent? movesText;
  TextComponent? levelText;
  TextComponent? highScoreText;
  bool isProcessing = false;
  RectangleComponent? background;
  ClickableText? settingsButtonInGame;
  ui.Image? logoImage;

  @override
  Future<void> onLoad() async {
    await loadSettings();
    try { logoImage = await images.load('logo.png'); } catch(e) { logoImage = null; }

    background = RectangleComponent(
      size: size,
      paint: Paint()
      ..shader = const LinearGradient(
          colors: [Color(0xFFFF6B9D), Color(0xFFFFC3A0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromLTWH(0, 0, 1, 1)),
    );
    add(background!);
    showSplash();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    highScore = prefs.getInt('highScore')?? 0;
    soundEnabled = prefs.getBool('soundEnabled')?? true;
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('highScore', highScore);
    await prefs.setBool('soundEnabled', soundEnabled);
  }

  void playSound(String name) {
    if (soundEnabled) FlameAudio.play(name);
  }

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    background?.size = newSize;
  }

  double get gridOffsetX => (size.x - gridSize * candySize) / 2;

  void showSplash() {
    state = GameState.splash;
    removeAll(children);
    add(background!);

    if(logoImage!= null) {
      add(SpriteComponent(
        sprite: Sprite(logoImage!),
        size: Vector2(160, 160),
        position: size / 2 + Vector2(0, -140),
        anchor: Anchor.center,
      ));
    }

    add(TextComponent(
      text: 'CANDY MATCH', position: size / 2 + Vector2(0, -20), anchor: Anchor.center,
      textRenderer: TextPaint(style: GoogleFonts.pacifico(fontSize: 50, color: Colors.white))
    ));

    highScoreText = TextComponent(
      text: 'Best: $highScore', position: size / 2 + Vector2(0, 30), anchor: Anchor.center,
      textRenderer: TextPaint(style: GoogleFonts.nunito(fontSize: 20, color: Colors.white))
    );
    add(highScoreText!);

    add(ClickableText(text: 'Tap to Start', position: size / 2 + Vector2(0, 90), onTap: startGame));
    add(ClickableText(text: '⚙️ Settings', position: Vector2(size.x - 20, size.y - 20), anchor: Anchor.bottomRight, onTap: () => showSettings(GameState.splash), fontSize: 18));
  }

  void showSettings(GameState fromState) {
    previousState = fromState;
    state = GameState.settings;
    removeAll(children);
    add(background!);

    add(TextComponent(text: 'SETTINGS', position: size/2 + Vector2(0,-100), anchor: Anchor.center,
      textRenderer: TextPaint(style: GoogleFonts.nunito(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white))));

    add(ClickableText(text: 'Sound: ${soundEnabled? "ON" : "OFF"}', position: size/2, anchor: Anchor.center, onTap: toggleSound, fontSize: 28));
    add(TextComponent(text: 'Tap Sound to Toggle', position: size/2 + Vector2(0,40), anchor: Anchor.center,
      textRenderer: TextPaint(style: GoogleFonts.nunito(fontSize: 16, color: Colors.white70))));
    add(ClickableText(text: '← Back', position: Vector2(30, size.y - 30), anchor: Anchor.bottomLeft, onTap: () {
      if(previousState == GameState.playing) startGame(); else showSplash();
    }, fontSize: 20));
  }

  void toggleSound() async {
    soundEnabled =!soundEnabled;
    await saveSettings();
    showSettings(previousState);
    if(soundEnabled) playSound('match.mp3');
  }

  void startGame() {
    state = GameState.playing;
    score = 0; movesLeft = 30; selectedCandy = null;
    removeAll(children);
    add(background!);

    levelText = TextComponent(text: 'Level: $level', position: Vector2(size.x/2, 30), anchor: Anchor.center,
      textRenderer: TextPaint(style: GoogleFonts.nunito(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)));
    scoreText = TextComponent(text: 'Score: 0', position: Vector2(30, 70), anchor: Anchor.centerLeft,
      textRenderer: TextPaint(style: GoogleFonts.nunito(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)));
    movesText = TextComponent(text: 'Moves: 30', position: Vector2(size.x - 30, 70), anchor: Anchor.centerRight,
      textRenderer: TextPaint(style: GoogleFonts.nunito(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)));

    settingsButtonInGame = ClickableText(text: '⚙️', position: Vector2(size.x - 20, 30), anchor: Anchor.topRight, onTap: () => showSettings(GameState.playing), fontSize: 28);

    addAll([levelText!, scoreText!, movesText!, settingsButtonInGame!]);
    Future.delayed(const Duration(milliseconds: 50), () => initGrid());
  }

  void initGrid() {
    grid = List.generate(gridSize, (_) => List.filled(gridSize, null));
    for (int row = 0; row < gridSize; row++) {
      for (int col = 0; col < gridSize; col++) {
        CandyType type;
        do { type = CandyType.values[_random.nextInt(CandyType.values.length)]; }
        while (wouldCreateMatch(col, row, type));
        final candy = CandyComponent(type: type, gridPos: Vector2(col.toDouble(), row.toDouble()));
        grid[row][col] = candy;
        add(candy);
      }
    }
  }

  bool wouldCreateMatch(int col, int row, CandyType type) {
    if (col >= 2 && grid[row][col-1]?.type == type && grid[row][col-2]?.type == type) return true;
    if (row >= 2 && grid[row-1][col]?.type == type && grid[row-2][col]?.type == type) return true;
    return false;
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (state!= GameState.playing || isProcessing) return;
    final worldPos = event.localPosition;
    final col = ((worldPos.x - gridOffsetX) / candySize).floor();
    final row = ((worldPos.y - gridOffsetY) / candySize).floor();
    if (row >= 0 && row < gridSize && col >= 0 && col < gridSize && grid[row][col]!= null) {
      handleCandySelection(grid[row][col]!);
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    if (isProcessing || selectedCandy == null || state!= GameState.playing) return;
    final dragVector = event.velocity;
    if (dragVector.length < 100) { selectedCandy!.deselect(); selectedCandy = null; return; }
    int dx = dragVector.x.abs() > dragVector.y.abs()? (dragVector.x > 0? 1 : -1) : 0;
    int dy = dragVector.x.abs() <= dragVector.y.abs()? (dragVector.y > 0? 1 : -1) : 0;
    final newRow = selectedCandy!.gridPos.y.toInt() + dy;
    final newCol = selectedCandy!.gridPos.x.toInt() + dx;
    if (newRow >= 0 && newRow < gridSize && newCol >= 0 && newCol < gridSize && grid[newRow][newCol]!= null) {
      trySwap(selectedCandy!, grid[newRow][newCol]!);
    } else { selectedCandy!.deselect(); }
    selectedCandy = null;
  }

  void handleCandySelection(CandyComponent candy) {
    if (selectedCandy == null) {
      selectCandy(candy);
    } else if (selectedCandy == candy) {
      candy.deselect();
      selectedCandy = null;
    } else if (_isAdjacent(selectedCandy!, candy)) {
      trySwap(selectedCandy!, candy);
      selectedCandy = null;
    } else {
      selectCandy(candy);
    }
  }

  bool _isAdjacent(CandyComponent c1, CandyComponent c2) {
    return (c1.gridPos.x - c2.gridPos.x).abs() + (c1.gridPos.y - c2.gridPos.y).abs() == 1;
  }

  void trySwap(CandyComponent c1, CandyComponent c2) async {
    isProcessing = true;
    playSound('swap.mp3');
    await swapCandies(c1, c2);
    final matches = findMatches();
    if (matches.isEmpty) { await swapCandies(c1, c2); isProcessing = false; }
    else {
      movesLeft--; movesText!.text = 'Moves: $movesLeft';
      await processMatches(matches, c1, c2);
    }
  }

  Future<void> swapCandies(CandyComponent c1, CandyComponent c2) async {
    final tempPos = c1.gridPos.clone();
    c1.gridPos = c2.gridPos.clone();
    c2.gridPos = tempPos;
    grid[c1.gridPos.y.toInt()][c1.gridPos.x.toInt()] = c1;
    grid[c2.gridPos.y.toInt()][c2.gridPos.x.toInt()] = c2;
    await Future.wait([c1.moveToGrid(), c2.moveToGrid()]);
  }

  List<List<CandyComponent>> findMatches() {
    List<List<CandyComponent>> allMatches = [];
    for (int row = 0; row < gridSize; row++) {
      for (int col = 0; col < gridSize; col++) {
        List<CandyComponent> match = [];
        CandyType? type = grid[row][col]?.type;
        int c = col;
        while (c < gridSize && grid[row][c]?.type == type) { match.add(grid[row][c]!); c++; }
        if (match.length >= 3) { allMatches.add(match); col = c - 1; }
      }
    }
    for (int col = 0; col < gridSize; col++) {
      for (int row = 0; row < gridSize; row++) {
        List<CandyComponent> match = [];
        CandyType? type = grid[row][col]?.type;
        int r = row;
        while (r < gridSize && grid[r][col]?.type == type) { match.add(grid[r][col]!); r++; }
        if (match.length >= 3) { allMatches.add(match); row = r - 1; }
      }
    }
    return allMatches;
  }

  Future<void> processMatches(List<List<CandyComponent>> matches, CandyComponent c1, CandyComponent c2) async {
    Set<CandyComponent> toRemove = {};
    List<CandyComponent> specialsToCreate = [];

    for (var match in matches) {
      if (match.length == 4) {
        CandyComponent special = match.contains(c1)? c1 : c2;
        special.special = match.first.gridPos.x == match.last.gridPos.x? SpecialType.vertical : SpecialType.horizontal;
        specialsToCreate.add(special);
        toRemove.addAll(match.where((c) => c!= special));
      } else {
        toRemove.addAll(match);
      }
    }

    for (var special in specialsToCreate) {
      playSound('bomb.mp3');
      score += 100;
      if (special.special == SpecialType.horizontal) {
        int row = special.gridPos.y.toInt();
        for (int col = 0; col < gridSize; col++) if (grid[row][col]!= null) toRemove.add(grid[row][col]!);
      } else {
        int col = special.gridPos.x.toInt();
        for (int row = 0; row < gridSize; row++) if (grid[row][col]!= null) toRemove.add(grid[row][col]!);
      }
    }

    playSound('match.mp3');
    score += toRemove.length * 10 * level;
    scoreText!.text = 'Score: $score';

    for (var candy in toRemove) {
      addParticleExplosion(candy.position);
      playSound('pop.mp3');
      grid[candy.gridPos.y.toInt()][candy.gridPos.x.toInt()] = null;
      candy.add(ScaleEffect.to(Vector2(0, 0), EffectController(duration: 0.2)));
      candy.add(RemoveEffect());
    }
    await Future.delayed(const Duration(milliseconds: 300));
    await applyGravity();
    await refillGrid();

    var newMatches = findMatches();
    if (newMatches.isNotEmpty) await processMatches(newMatches, c1, c2);
    else { isProcessing = false; checkLevel(); }
  }

  void addParticleExplosion(Vector2 pos) {
    add(ParticleSystemComponent(
      particle: Particle.generate(
        count: 15,
        generator: (i) => AcceleratedParticle(
          acceleration: Vector2(0, 200),
          speed: Vector2.random(_random) * 120,
          position: pos.clone(),
          child: CircleParticle(paint: Paint()..color = Colors.white, radius: 2),
          lifespan: 0.5,
        ),
      ),
    ));
  }

  Future<void> applyGravity() async {
    List<Future> futures = [];
    for (int col = 0; col < gridSize; col++) {
      int emptyRow = gridSize - 1;
      for (int row = gridSize - 1; row >= 0; row--) {
        if (grid[row][col] == null) { emptyRow = min(emptyRow, row); }
        else if (emptyRow!= row) {
          grid[emptyRow][col] = grid[row][col];
          grid[row][col] = null;
          grid[emptyRow][col]!.gridPos.y = emptyRow.toDouble();
          futures.add(grid[emptyRow][col]!.moveToGrid());
        }
      }
    }
    await Future.wait(futures);
  }

  Future<void> refillGrid() async {
    List<Future> futures = [];
    for (int col = 0; col < gridSize; col++) {
      for (int row = 0; row < gridSize; row++) {
        if (grid[row][col] == null) {
          final type = CandyType.values[_random.nextInt(CandyType.values.length)];
          final candy = CandyComponent(type: type, gridPos: Vector2(col.toDouble(), row.toDouble()));
          candy.position.y -= 200;
          grid[row][col] = candy;
          add(candy);
          futures.add(candy.moveToGrid());
        }
      }
    }
    await Future.wait(futures);
  }

  void checkLevel() async {
    if (score >= targetScore) {
      state = GameState.levelComplete;
      if (score > highScore) { highScore = score; await saveSettings(); }
      add(ClickableText(
        text: 'LEVEL COMPLETE!\nScore: $score\nTap to Continue',
        position: size / 2,
        anchor: Anchor.center,
        onTap: () { level++; startGame(); },
        fontSize: 36
      ));
    } else if (movesLeft <= 0) {
      state = GameState.gameOver;
      if (score > highScore) { highScore = score; await saveSettings(); }
      add(ClickableText(
        text: 'GAME OVER\nScore: $score\nBest: $highScore\nTap to Restart',
        position: size / 2,
        anchor: Anchor.center,
        onTap: () { level = 1; startGame(); },
        fontSize: 36
      ));
    }
  }

  void selectCandy(CandyComponent candy) {
    selectedCandy?.deselect();
    selectedCandy = candy;
    candy.select();
  }
}

// FIXED CLICKABLE TEXT
class ClickableText extends PositionComponent with TapCallbacks {
  final String text;
  final Function() onTap;
  final double fontSize;
  late TextComponent _textComp;

  ClickableText({required this.text, required Vector2 position, required this.onTap, this.fontSize = 24, Anchor anchor = Anchor.center}) {
    this.position = position;
    this.anchor = anchor;
  }

  @override
  Future<void> onLoad() async {
    _textComp = TextComponent(text: text, textRenderer: TextPaint(style: GoogleFonts.nunito(fontSize: fontSize, color: Colors.white)));
    await add(_textComp);
    size = _textComp.size;
  }

  @override
  void onTapDown(TapDownEvent event) { onTap(); }
}

class CandyComponent extends PositionComponent with TapCallbacks {
  final CandyType type;
  Vector2 gridPos;
  bool isSelected = false;
  SpecialType special = SpecialType.none;

  CandyComponent({required this.type, required this.gridPos}) {
    size = Vector2.all(CandyMatchGame.candySize - 5);
    anchor = Anchor.center;
  }

  @override
  void onMount() {
    super.onMount();
    position = getWorldPosition();
  }

  Vector2 getWorldPosition() {
    final game = findParent<CandyMatchGame>()!;
    return Vector2(
      gridPos.x * CandyMatchGame.candySize + game.gridOffsetX + size.x/2,
      gridPos.y * CandyMatchGame.candySize + CandyMatchGame.gridOffsetY + size.y/2,
    );
  }

  Future<void> moveToGrid() async {
    add(MoveEffect.to(getWorldPosition(), EffectController(duration: 0.3, curve: Curves.easeOut)));
    await Future.delayed(const Duration(milliseconds: 300));
  }
  void select() { isSelected = true; add(ScaleEffect.to(Vector2(1.15, 1.15), EffectController(duration: 0.1))); }
  void deselect() { isSelected = false; add(ScaleEffect.to(Vector2(1.0, 1.0), EffectController(duration: 0.1))); }
  @override
  void onTapDown(TapDownEvent event) {
    final game = findParent<CandyMatchGame>()!;
    if (game.isProcessing || game.state!= GameState.playing) return;
    game.handleCandySelection(this);
  }
  Color get color {
    switch(type) {
      case CandyType.red: return const Color(0xFFFF5252);
      case CandyType.blue: return const Color(0xFF448AFF);
      case CandyType.green: return const Color(0xFF66BB6A);
      case CandyType.yellow: return const Color(0xFFFFEB3B);
      case CandyType.purple: return const Color(0xFFAB47BC);
      case CandyType.orange: return const Color(0xFFFFA726);
    }
  }
  @override
  void render(Canvas canvas) {
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.x, size.y), const Radius.circular(15)), Paint()..color = color);
    canvas.drawCircle(Offset(size.x * 0.3, size.y * 0.3), 5, Paint()..color = Colors.white.withOpacity(0.6));
    if (special == SpecialType.horizontal) canvas.drawRect(Rect.fromLTWH(5, size.y/2 - 3, size.x - 10, 6), Paint()..color = Colors.white);
    else if (special == SpecialType.vertical) canvas.drawRect(Rect.fromLTWH(size.x/2 - 3, 5, 6, size.y - 10), Paint()..color = Colors.white);
    if(isSelected) canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-3, -3, size.x+6, size.y+6), const Radius.circular(18)), Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3);
  }
}