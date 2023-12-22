// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.15;

import "./IERC20.sol";

contract BossGame {

    enum GameState {
        IN_PROGRESS,
        FINISHED,
        WIN,
        LOSE
    }

    struct Deposit {
        uint256 amount;
        bool claimed;
    }

    IERC20 public dibToken;
    uint256 public bossHp;
    uint256 public gameDuration;
    uint256 public endTime;
    uint256 public totalDeposits;
    mapping(address => Deposit) public deposits;

    address public factory;
    GameState public gameState;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    uint256 public rewardPerShare;
    uint256 public storedReward;

    modifier onlyInGameState(GameState _state) {
        require(gameState == _state, "wrong game state");
        _;
    }

    modifier onlyFactory {
        require(msg.sender == factory, "not factory");
        _;
    }

    function init(
        IERC20 _dibToken,
        uint256 _gameDuration,
        uint256 _bossHp
    ) external {
        require(address(dibToken) == address(0), "already initialized");
        require(address(_dibToken) != address(0), "zero dib address");
        require(_gameDuration > 0, "zero game duration");
        require(_bossHp > 0, "zero boss hp");
        _dibToken.balanceOf(address(this)); //safety check
        gameDuration = _gameDuration;
        dibToken = _dibToken;
        bossHp = _bossHp;

        endTime = block.timestamp + _gameDuration;

        gameState = GameState.IN_PROGRESS;
        factory = msg.sender;
    }

    function reward() external view returns (uint256) {
        if(gameState == GameState.IN_PROGRESS) {
            return dibToken.balanceOf(address(this)) - totalDeposits;
        } else {
            return storedReward;
        }
    }

    function stake(uint256 _amount) external onlyInGameState(GameState.IN_PROGRESS) {
        require(block.timestamp <= endTime, "finished");
        dibToken.transferFrom(msg.sender, address(this), _amount);
        deposits[msg.sender].amount += _amount;
        totalDeposits += _amount;
    }

    function claimRewards() external onlyInGameState(GameState.WIN) {
        require(!deposits[msg.sender].claimed, "already claimed");
        uint256 claimableAmount = (rewardPerShare * deposits[msg.sender].amount) / 1e18;
        deposits[msg.sender].claimed = true;
        dibToken.transfer(msg.sender, claimableAmount);
    }

    function endGame() external onlyFactory {
        gameState = GameState.FINISHED;
        storedReward = dibToken.balanceOf(address(this)) - totalDeposits;
    }

    function finishGame(uint256 _randomNumber) external onlyInGameState(GameState.FINISHED) onlyFactory {
        require(block.timestamp > endTime, "not yet");

        if (_randomNumber <= calculateWinThreshold(totalDeposits, bossHp) && totalDeposits > 0) {
            gameState = GameState.WIN;
            rewardPerShare = (dibToken.balanceOf(address(this)) * 1e18) / totalDeposits;
        } else {
            gameState = GameState.LOSE;
            dibToken.transfer(DEAD, dibToken.balanceOf(address(this)));
        }
    }

    function calculateWinThreshold(
        uint256 _totalDeposits,
        uint256 _bossHp
    ) public pure returns (uint256) {
        return (type(uint256).max / (_totalDeposits + _bossHp)) * _totalDeposits;
    }

}

