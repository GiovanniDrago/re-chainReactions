import 'dart:collection';
import 'dart:math' as math;

import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flame/text.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const ChainReactionsApp());
}

class ChainReactionsApp extends StatelessWidget {
  const ChainReactionsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final ChainReactionsGame _game;

  @override
  void initState() {
    super.initState();
    _game = ChainReactionsGame();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GameWidget<ChainReactionsGame>(
        game: _game,
        overlayBuilderMap: {
          'settings': (context, game) => SettingsOverlay(game: game),
        },
      ),
    );
  }
}

class ChainReactionsGame extends FlameGame with TapCallbacks {
  static const double boardPadding = 16;
  static const double hudHeight = 72;

  ChainReactionsGame({this.rows = 6, this.cols = 6}) {
    _createBoard();
  }

  int rows;
  int cols;
  late List<List<Cell>> board;

  int currentPlayer = 1;
  bool gameOver = false;
  int? winner;
  bool _pendingTurn = false;
  bool _animating = false;
  double _time = 0;
  String? _toastMessage;
  double _toastTimer = 0;

  final List<MovingBall> _movingBalls = [];

  Rect _boardRect = Rect.zero;
  Rect _restartRect = Rect.zero;
  Rect _settingsRect = Rect.zero;

  final TextPaint _hudPaint = TextPaint(
    style: const TextStyle(
      color: Color(0xFFF4F1E8),
      fontSize: 18,
      fontWeight: FontWeight.w600,
    ),
  );

  final Paint _bgPaint = Paint();

  final Paint _gridPaint = Paint()
    ..color = const Color(0xFF2A3A46)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;

  final Paint _cellFillPaint = Paint()
    ..color = const Color(0xFF15232D)
    ..style = PaintingStyle.fill;

  final Paint _bluePaint = Paint()..color = const Color(0xFF2D6CFF);
  final Paint _redPaint = Paint()..color = const Color(0xFFFF4D4D);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _bgPaint.shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0B1F2A), Color(0xFF111820)],
    ).createShader(Rect.fromLTWH(0, 0, size.x, size.y));
    final double usableHeight = size.y - hudHeight - (boardPadding * 2);
    final double usableWidth = size.x - (boardPadding * 2);
    final double cellSize = (usableWidth / cols).clamp(0, usableHeight / rows);
    final double boardWidth = cellSize * cols;
    final double boardHeight = cellSize * rows;
    final double left = (size.x - boardWidth) / 2;
    final double top = hudHeight + (size.y - hudHeight - boardHeight) / 2;
    _boardRect = Rect.fromLTWH(left, top, boardWidth, boardHeight);
    const double buttonWidth = 100;
    const double buttonHeight = 36;
    final double right = left + boardWidth;
    _restartRect = Rect.fromLTWH(
      right - buttonWidth,
      18,
      buttonWidth,
      buttonHeight,
    );
    _settingsRect = Rect.fromLTWH(
      right - (buttonWidth * 2) - 12,
      18,
      buttonWidth,
      buttonHeight,
    );
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.x, size.y), _bgPaint);
    _renderHud(canvas);
    _renderBoard(canvas);
    _renderMovingBalls(canvas);
  }

  void _renderHud(Canvas canvas) {
    final String turnText = gameOver
        ? 'Winner: ${winner == 1 ? 'Blue' : 'Red'}'
        : 'Turn: ${currentPlayer == 1 ? 'Blue' : 'Red'}';
    _hudPaint.render(canvas, turnText, Vector2(20, 28));
    if (_toastTimer > 0 && _toastMessage != null) {
      _hudPaint.render(canvas, _toastMessage!, Vector2(20, 50));
    }

    final TextPaint restartPaint = TextPaint(
      style: TextStyle(
        color: const Color(0xFFF4F1E8),
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );

    final Paint buttonBox = Paint()
      ..color = const Color(0xFF1C2C36)
      ..style = PaintingStyle.fill;
    _drawHudButton(canvas, _settingsRect, buttonBox, 'Settings', restartPaint);
    _drawHudButton(canvas, _restartRect, buttonBox, 'Restart', restartPaint);
  }

  void _drawHudButton(
    Canvas canvas,
    Rect rect,
    Paint fill,
    String label,
    TextPaint textPaint,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      _gridPaint,
    );
    textPaint.render(canvas, label, Vector2(rect.left + 12, 28));
  }

  void _renderBoard(Canvas canvas) {
    if (_boardRect == Rect.zero) {
      return;
    }

    final double cellSize = _boardRect.width / cols;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final Rect cellRect = Rect.fromLTWH(
          _boardRect.left + c * cellSize,
          _boardRect.top + r * cellSize,
          cellSize,
          cellSize,
        );
        canvas.drawRect(cellRect, _cellFillPaint);
        canvas.drawRect(cellRect, _gridPaint);
        _renderCellBalls(canvas, cellRect, board[r][c]);
      }
    }
  }

  void _renderCellBalls(Canvas canvas, Rect cellRect, Cell cell) {
    if (cell.count == 0) {
      return;
    }

    final Color color = cell.owner == 1 ? _bluePaint.color : _redPaint.color;
    final double radius = cellRect.shortestSide * 0.14;
    final Offset center = cellRect.center;
    final double spread = radius * 1.8;

    final List<Offset> positions = _orbitPositions(
      center,
      spread,
      cell.count,
      _time + (cellRect.left + cellRect.top) * 0.01,
    );

    for (int i = 0; i < positions.length; i++) {
      _draw3DBall(canvas, positions[i], radius, color, _time + i * 0.6);
    }
  }

  List<Offset> _orbitPositions(
    Offset center,
    double radius,
    int count,
    double phase,
  ) {
    if (count <= 1) {
      return [center];
    }
    final double angleStep = (math.pi * 2) / count;
    final double baseAngle = phase * 1.2;
    final List<Offset> positions = [];
    for (int i = 0; i < count; i++) {
      final double angle = baseAngle + angleStep * i;
      positions.add(
        center.translate(
          radius * math.cos(angle),
          radius * math.sin(angle) * 0.8,
        ),
      );
    }
    return positions;
  }

  void _renderMovingBalls(Canvas canvas) {
    for (int i = 0; i < _movingBalls.length; i++) {
      final MovingBall ball = _movingBalls[i];
      _draw3DBall(canvas, ball.position, ball.radius, ball.color, _time + i);
    }
  }

  void _draw3DBall(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double phase,
  ) {
    final Paint basePaint = Paint()..color = color;
    canvas.drawCircle(center, radius, basePaint);

    final double angle = phase * 1.8;
    final Offset highlightOffset = Offset(
      radius * 0.45 * math.cos(angle),
      radius * 0.45 * math.sin(angle),
    );
    final Offset highlightCenter = center + highlightOffset;
    final Paint highlightPaint = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.6);
    canvas.drawCircle(highlightCenter, radius * 0.38, highlightPaint);

    final Paint shadowPaint = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: 0.25);
    canvas.drawCircle(
      center.translate(radius * 0.2, radius * 0.28),
      radius * 0.75,
      shadowPaint,
    );
  }

  @override
  void onTapDown(TapDownEvent event) {
    final Offset tap = event.canvasPosition.toOffset();

    if (_settingsRect.contains(tap)) {
      _toggleSettings();
      return;
    }

    if (_restartRect.contains(tap)) {
      _resetGame();
      return;
    }

    if (gameOver) {
      _showToast('Game over — ${winner == 1 ? 'Blue' : 'Red'} wins');
      return;
    }

    if (_animating || overlays.isActive('settings')) {
      return;
    }

    if (!_boardRect.contains(tap)) {
      return;
    }

    final int col = ((tap.dx - _boardRect.left) / (_boardRect.width / cols))
        .clamp(0, cols - 1)
        .toInt();
    final int row = ((tap.dy - _boardRect.top) / (_boardRect.height / rows))
        .clamp(0, rows - 1)
        .toInt();

    if (!_isLegalMove(row, col, currentPlayer)) {
      return;
    }

    _applyMove(row, col, currentPlayer);
    _pendingTurn = true;
  }

  bool _isLegalMove(int row, int col, int player) {
    final Cell cell = board[row][col];
    return cell.owner == 0 || cell.owner == player;
  }

  void _applyMove(int row, int col, int player) {
    final Queue<Point> queue = ListQueue<Point>();
    _addBall(row, col, player, queue);

    while (queue.isNotEmpty) {
      final Point point = queue.removeFirst();
      final Cell cell = board[point.row][point.col];
      final int capacity = _capacity(point.row, point.col);
      if (cell.count < capacity) {
        continue;
      }
      cell.count -= capacity;
      if (cell.count == 0) {
        cell.owner = 0;
      }
      for (final Point neighbor in _neighbors(point.row, point.col)) {
        _enqueueMoveAnimation(
          point.row,
          point.col,
          neighbor.row,
          neighbor.col,
          player,
        );
        _addBall(neighbor.row, neighbor.col, player, queue);
      }
    }
    _animating = _movingBalls.isNotEmpty;
  }

  void _addBall(int row, int col, int player, Queue<Point> queue) {
    final Cell cell = board[row][col];
    cell.owner = player;
    cell.count += 1;
    if (cell.count >= _capacity(row, col)) {
      queue.add(Point(row, col));
    }
  }

  void _advanceTurn() {
    currentPlayer = currentPlayer == 1 ? 2 : 1;
    if (!_hasLegalMove(currentPlayer)) {
      gameOver = true;
      winner = currentPlayer == 1 ? 2 : 1;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    if (_toastTimer > 0) {
      _toastTimer -= dt;
      if (_toastTimer <= 0) {
        _toastTimer = 0;
        _toastMessage = null;
      }
    }
    for (int i = _movingBalls.length - 1; i >= 0; i--) {
      final MovingBall ball = _movingBalls[i];
      ball.t += dt / ball.duration;
      if (ball.t >= 1) {
        _movingBalls.removeAt(i);
      }
    }
    if (_animating && _movingBalls.isEmpty) {
      _animating = false;
    }
    if (_pendingTurn && !_animating) {
      _pendingTurn = false;
      _advanceTurn();
    }
  }

  bool _hasLegalMove(int player) {
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (_isLegalMove(r, c, player)) {
          return true;
        }
      }
    }
    return false;
  }

  int _capacity(int row, int col) {
    int edges = 4;
    if (row == 0 || row == rows - 1) {
      edges -= 1;
    }
    if (col == 0 || col == cols - 1) {
      edges -= 1;
    }
    return edges;
  }

  List<Point> _neighbors(int row, int col) {
    final List<Point> neighbors = [];
    if (row > 0) {
      neighbors.add(Point(row - 1, col));
    }
    if (row < rows - 1) {
      neighbors.add(Point(row + 1, col));
    }
    if (col > 0) {
      neighbors.add(Point(row, col - 1));
    }
    if (col < cols - 1) {
      neighbors.add(Point(row, col + 1));
    }
    return neighbors;
  }

  void _resetGame() {
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        board[r][c].owner = 0;
        board[r][c].count = 0;
      }
    }
    currentPlayer = 1;
    gameOver = false;
    winner = null;
    _pendingTurn = false;
    _animating = false;
    _movingBalls.clear();
    _toastMessage = null;
    _toastTimer = 0;
  }

  void _showToast(String message) {
    _toastMessage = message;
    _toastTimer = 2.2;
  }

  void setGridSize(int newRows, int newCols) {
    rows = newRows;
    cols = newCols;
    _createBoard();
    _resetGame();
    if (size.x > 0 && size.y > 0) {
      onGameResize(size);
    }
  }

  void _toggleSettings() {
    if (overlays.isActive('settings')) {
      overlays.remove('settings');
    } else {
      overlays.add('settings');
    }
  }

  void _createBoard() {
    board = List.generate(rows, (_) => List.generate(cols, (_) => Cell()));
  }

  void _enqueueMoveAnimation(
    int fromRow,
    int fromCol,
    int toRow,
    int toCol,
    int player,
  ) {
    if (_boardRect == Rect.zero) {
      return;
    }
    final Offset start = _cellCenter(fromRow, fromCol);
    final Offset end = _cellCenter(toRow, toCol);
    final Color color = player == 1 ? _bluePaint.color : _redPaint.color;
    _movingBalls.add(
      MovingBall(
        start: start,
        end: end,
        color: color,
        radius: (_boardRect.width / cols) * 0.14,
      ),
    );
  }

  Offset _cellCenter(int row, int col) {
    final double cellSize = _boardRect.width / cols;
    return Offset(
      _boardRect.left + col * cellSize + cellSize / 2,
      _boardRect.top + row * cellSize + cellSize / 2,
    );
  }
}

class Cell {
  int owner = 0;
  int count = 0;
}

class Point {
  Point(this.row, this.col);

  final int row;
  final int col;
}

class MovingBall {
  MovingBall({
    required this.start,
    required this.end,
    required this.color,
    required this.radius,
    this.duration = 0.28,
  });

  final Offset start;
  final Offset end;
  final Color color;
  final double radius;
  final double duration;
  double t = 0;

  Offset get position => Offset(
    start.dx + (end.dx - start.dx) * _easeOutCubic(t.clamp(0, 1)),
    start.dy + (end.dy - start.dy) * _easeOutCubic(t.clamp(0, 1)),
  );
}

double _easeOutCubic(double t) => 1 - (1 - t) * (1 - t) * (1 - t);

class SettingsOverlay extends StatefulWidget {
  const SettingsOverlay({super.key, required this.game});

  final ChainReactionsGame game;

  @override
  State<SettingsOverlay> createState() => _SettingsOverlayState();
}

class _SettingsOverlayState extends State<SettingsOverlay> {
  late int _rows;
  late int _cols;

  final List<int> _sizes = [4, 5, 6, 7, 8, 9, 10];

  @override
  void initState() {
    super.initState();
    _rows = widget.game.rows;
    _cols = widget.game.cols;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xAA0A1116),
      child: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF18232B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2A3A46)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Settings',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFF4F1E8),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              _buildSizeRow('Rows', _rows, (value) {
                if (value != null) {
                  setState(() => _rows = value);
                }
              }),
              const SizedBox(height: 12),
              _buildSizeRow('Cols', _cols, (value) {
                if (value != null) {
                  setState(() => _cols = value);
                }
              }),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  widget.game.setGridSize(_rows, _cols);
                  widget.game.overlays.remove('settings');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6CFF),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Start New Round'),
              ),
              TextButton(
                onPressed: () {
                  widget.game.overlays.remove('settings');
                },
                child: const Text(
                  'Close',
                  style: TextStyle(color: Color(0xFFF4F1E8)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSizeRow(String label, int value, ValueChanged<int?> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFFF4F1E8))),
        DropdownButton<int>(
          value: value,
          dropdownColor: const Color(0xFF18232B),
          iconEnabledColor: const Color(0xFFF4F1E8),
          items: _sizes
              .map(
                (size) => DropdownMenuItem<int>(
                  value: size,
                  child: Text(
                    size.toString(),
                    style: const TextStyle(color: Color(0xFFF4F1E8)),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
