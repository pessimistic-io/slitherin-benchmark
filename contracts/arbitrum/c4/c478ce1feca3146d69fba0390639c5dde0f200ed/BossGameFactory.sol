// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.15;

import "./Clones.sol";
import "./BossGame.sol";
import "./IRandomizer.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract BossGameFactory is Ownable {

    using SafeERC20 for IERC20;

    IERC20 public immutable dibToken;
    address public immutable bossGameImplementation;
    address public immutable randomizer;
    mapping(uint256 => address) randomRequestIdToGameAddress;
    uint256 randomizerGasLimit = 1000000;

    address[] public games;

    event GameCreated(uint256 indexed gameId, address indexed gameAddress, uint256 reward, uint256 bossHp, uint256 duration);

    constructor(IERC20 _dibToken, address _randomizer) {
        require(address(_dibToken) != address(0), "zero dib token address");
        require(address(_randomizer) != address(0), "zero randomizer address");
        dibToken = _dibToken;
        randomizer = _randomizer;
        bossGameImplementation = address(new BossGame());
    }

    function addGame(
        uint256 _gameDuration,
        uint256 _bossHp,
        uint256 _reward
    ) external onlyOwner returns (address newGame) {
        newGame = Clones.clone(bossGameImplementation);
        games.push(newGame);

        BossGame(newGame).init(dibToken, _gameDuration, _bossHp);

        dibToken.safeTransferFrom(msg.sender, newGame, _reward);

        emit GameCreated(games.length - 1, newGame, _reward, _bossHp, _gameDuration);
    }

    function addReward(uint256 _gameId, uint256 _amount) external {
        require(_gameId < games.length, "wrong id");
        address gameAddress = games[_gameId];
        require(BossGame(gameAddress).gameState() == BossGame.GameState.IN_PROGRESS, "game finished");
        dibToken.safeTransferFrom(msg.sender, gameAddress, _amount);
    }

    function finishGame(uint256 _gameId) external {
        require(_gameId < games.length, "wrong id");

        BossGame game = BossGame(games[_gameId]);
        require(game.gameState() == BossGame.GameState.IN_PROGRESS, "game finished");
        require(block.timestamp > game.endTime(), "not finished");

        game.endGame();

        uint256 requestId = IRandomizer(randomizer).request(randomizerGasLimit);
        randomRequestIdToGameAddress[requestId] = address(game);
    }

    function randomizerCallback(uint256 _id, bytes32 _value) external {
        require(msg.sender == address(randomizer), "caller not Randomizer");
        BossGame game = BossGame(randomRequestIdToGameAddress[_id]);
        game.finishGame(uint256(_value));
    }

    function gamesLength() external view returns (uint256) {
        return games.length;
    }

    function setRandomizerGasLimit(uint256 _newLimit) external onlyOwner {
        randomizerGasLimit = _newLimit;
    }

    function randomizerWithdraw(uint256 amount) external onlyOwner {
        IRandomizer(randomizer).clientWithdrawTo(msg.sender, amount);
    }

}

