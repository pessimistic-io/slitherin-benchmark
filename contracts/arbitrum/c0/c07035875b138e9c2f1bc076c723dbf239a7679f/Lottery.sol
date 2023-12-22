// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./Counters.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./Ownable.sol";

import "./IArbSys.sol";

contract Lottery is Ownable {
    using Counters for Counters.Counter;

    IERC20 public FARB = IERC20(0x8907855758bDEE82782599F86B04052C71137D79);
    address public deadAddress = 0x000000000000000000000000000000000000dEaD;
    address public devAddress = 0xA09B62ddD79d3bc2E4787d6116571C3d0A232641;

    Counters.Counter private nonceCounter; // 随机数 counter
    Counters.Counter public gameIDCounter; // 游戏ID counter

    uint256 public Lv1GameParticipants = 6; // 初级场参与人数
    uint256 public Lv2GameParticipants = 6; // 中级场参与人数
    uint256 public Lv3GameParticipants = 6; // 高级场参与人数

    uint256 public onePiece = 1_000_000 * 1e18; // 每份金额

    uint256 public Lv1GamePiece = 1; // 初级场投注份数
    uint256 public Lv2GamePiece = 3; // 中级场投注份数
    uint256 public Lv3GamePiece = 10; // 高级场投注份数

    uint256 public winnerRate = 9000; // 中奖占比
    uint256 public burnRate = 700;
    uint256 public devRate = 300;

    bool public paused = false;

    uint256 private seed;

    struct GameStruct {
        uint256 levelID; // 等级id
        uint256 gameID; // 游戏id
        uint256 unitAmount; // 每份金额
        uint256 gamerCount; // 参与人数
        address[] participants; // 参与用户
        address winner; // 中奖者
        uint256 startTime; // 开始时间
        uint256 endTime; // 结束时间
    }

    mapping(uint256 => GameStruct) public _games;

    uint256 public constant Lv1ID = 1;
    uint256 public constant Lv2ID = 2;
    uint256 public constant Lv3ID = 3;

    mapping(uint256 => GameStruct) public currentGames;
    mapping(address => bool)  public _blacklist;

    event gameStart(
        uint256 indexed levelID,
        uint256 indexed gameID,
        uint256 indexed unitAmount,
        uint256 participantNeed
    );
    event gameEnd(
        uint256 indexed levelID,
        uint256 indexed gameID,
        address indexed winner,
        uint256 winnerAmount,
        uint256 gameUsedTime
    );
    event gameJoin(
        uint256 indexed levelID,
        uint256 indexed gameID,
        address indexed participant,
        uint256 participantCount,
        uint256 participantNeed,
        uint256 participantAmount
    );

    constructor (){
        seed = uint256(keccak256(abi.encodePacked(block.timestamp)));
    }

    function setWinnerRate(uint256 rate) external onlyOwner {
        require(rate >= 9000, "invalid rate");
        winnerRate = rate;
    }

    function setGamePiece(uint256 Lv1, uint256 Lv2, uint256 Lv3) external onlyOwner {
        Lv1GamePiece = Lv1;
        Lv2GamePiece = Lv2;
        Lv3GamePiece = Lv3;
    }

    function setGameParticipants(uint256 Lv1, uint256 Lv2, uint256 Lv3) external onlyOwner {
        Lv1GameParticipants = Lv1;
        Lv2GameParticipants = Lv2;
        Lv3GameParticipants = Lv3;
    }

    function createLv1Game() internal {
        if (currentGames[Lv1ID].gameID > 0) {
            return;
        }
        _createNewGame(Lv1ID, Lv1GameParticipants, Lv1GamePiece);
    }

    function createLv2Game() internal {
        if (currentGames[Lv2ID].gameID > 0) {
            return;
        }
        _createNewGame(Lv2ID, Lv2GameParticipants, Lv2GamePiece);
    }

    function createLv3Game() internal {
        if (currentGames[Lv3ID].gameID > 0) {
            return;
        }
        _createNewGame(Lv3ID, Lv3GameParticipants, Lv3GamePiece);
    }

    function checkGame() public {
        createLv1Game();
        createLv2Game();
        createLv3Game();
    }

    function _createNewGame(uint256 LvID, uint256 gamerCount, uint256 pieceCount) internal {
        if (paused) {
            return;
        }
        gameIDCounter.increment();
        GameStruct memory gameStruct = GameStruct({
            levelID: LvID,
            gameID: gameIDCounter.current(),
            unitAmount: pieceCount * onePiece,
            gamerCount: gamerCount,
            participants: new address[](0),
            winner: address(0),
            startTime: block.timestamp,
            endTime: 0
        });
        _games[gameStruct.gameID] = gameStruct;
        currentGames[LvID] = gameStruct;
        emit gameStart(
            LvID,
            gameStruct.gameID,
            gameStruct.unitAmount,
            gameStruct.gamerCount
        );
    }

    function joinGame(uint256 gameID) external {
        require(msg.sender == tx.origin, "only EOA");
        require(gameID <= gameIDCounter.current(), "invalid gameID");
        require(!_blacklist[msg.sender], "blacklist");
        GameStruct storage game = _games[gameID];
        require(game.gameID > 0, "game not exist");
        require(game.winner == address(0), "game is over");
        require(game.endTime == 0, "game is over");
        require(game.participants.length < game.gamerCount, "game is full");
        game.participants.push(msg.sender);
        currentGames[game.levelID] = game;
        require(FARB.transferFrom(msg.sender, address(this), game.unitAmount), "transferFrom failed");
        emit gameJoin(
            game.levelID,
            game.gameID,
            msg.sender,
            game.participants.length,
            game.gamerCount,
            game.unitAmount
        );
        if (game.participants.length == game.gamerCount) {
            delete currentGames[game.levelID];
            execGame(game);
        }
    }

    function execGame(GameStruct storage game) internal {
        require(game.participants.length == game.gamerCount, "game is not full");
        uint256 winnerIndex = calculateHashNumber() % game.gamerCount;
        game.winner = game.participants[winnerIndex];
        game.endTime = block.timestamp;
        uint256 prizePool = game.unitAmount * game.gamerCount;
        uint256 winnerAmount = prizePool * winnerRate / 10000;
        uint256 devAmount = prizePool * devRate / 10000;
        uint256 burnAmount = prizePool - winnerAmount - devAmount;

        require(FARB.transfer(game.winner, winnerAmount));
        require(FARB.transfer(devAddress, devAmount));
        require(FARB.transfer(deadAddress, burnAmount));
        emit gameEnd(
            game.levelID,
            game.gameID,
            game.winner,
            winnerAmount,
            game.endTime - game.startTime
        );

        checkGame();
    }

    function calculateHashNumber() internal returns (uint256) {
        nonceCounter.increment();
        bytes32 lastHash = IArbSys(address(100)).arbBlockHash(IArbSys(address(100)).arbBlockNumber() - 1);
        return uint256(keccak256(abi.encodePacked(
            msg.sender,
            nonceCounter.current(),
            seed,
            block.timestamp,
            lastHash
        )));
    }

    function withdrawToken(address _token) external onlyOwner {
        IERC20 token = IERC20(_token);
        require(token.transfer(msg.sender, token.balanceOf(address(this))));
    }

    function withdrawETH() external onlyOwner {
        (bool s,) = msg.sender.call{value: address(this).balance}("");
        require(s, "transfer failed");
    }

    function flipPaused() external onlyOwner {
        paused = !paused;
    }

    function flipBlacklist(address _address) external onlyOwner {
        _blacklist[_address] = !_blacklist[_address];
    }

    function setOneGamePiece(uint256 _oneGamePiece) external onlyOwner {
        onePiece = _oneGamePiece;
    }

    function setSeed(uint256 _seed) external onlyOwner {
        seed = _seed;
    }

    function getGameCount() external view returns (uint256) {
        return gameIDCounter.current();
    }

    function getGameByID(uint256 gameID) external view returns (GameStruct memory) {
        return _games[gameID];
    }

    function getGameByLevel(uint256 LvID) external view returns (GameStruct memory) {
        return currentGames[LvID];
    }

    function getCurrentGames() external view returns (GameStruct[] memory) {
        GameStruct[] memory _currentGames = new GameStruct[](3);
        _currentGames[0] = currentGames[Lv1ID];
        _currentGames[1] = currentGames[Lv2ID];
        _currentGames[2] = currentGames[Lv3ID];
        return _currentGames;
    }
}

