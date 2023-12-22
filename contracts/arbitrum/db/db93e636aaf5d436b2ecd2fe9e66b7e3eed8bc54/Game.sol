// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ERC20.sol";
import "./IERC20BackwardsCompatible.sol";
import "./IGame.sol";
import "./IConsole.sol";
import "./IHouse.sol";
import "./IRNG.sol";
import "./IUSDTVault.sol";

abstract contract Game is IGame, Ownable {
    error InvalidRolls(uint256 max, uint256 rolls);
    error MinBet(uint256 minRate, uint256 stake);

    IERC20BackwardsCompatible public usdtToken;
    IUSDTVault public usdtVault;
    IConsole public consoleInst;
    IHouse public house;
    IRNG public rng;
    uint256 id;
    uint256 public maxRoll;
    uint256 public numbersPerRoll;
    uint256 public minBetRate;
    
    event GameStart(uint256 indexed betId, uint256 _bet, uint256[50] _data);
    event GameEnd(uint256 indexed betId, uint256[] _randomNumbers, uint256[] _rolls, uint256 _bet, uint256 _stake, uint256 wins, uint256 losses, uint256 _payout, address indexed _account, uint256 indexed _timestamp);

    constructor (address _usdt, address _vault, address _console, address _house, address _rng, uint256 _id, uint256 _numbersPerRoll) {
        usdtToken = IERC20BackwardsCompatible(_usdt);
        usdtVault = IUSDTVault(_vault);
        consoleInst = IConsole(_console);
        house = IHouse(_house);
        rng = IRNG(_rng);
        id = _id;
        numbersPerRoll = _numbersPerRoll;
        maxRoll = 1;
        minBetRate = 0; //(10 ** 16); // 0.01 USDT
    }

    function getMaxPayout(uint256 _bet, uint256[50] memory _data) public virtual view returns (uint256);
    function finalize(uint256 _betId, uint256[] memory _randomNumbers) internal virtual returns (uint256);

    function updateMaxRoll(uint256 _newValue) external onlyOwner {
        require(maxRoll != _newValue, "Already Set");
        maxRoll = _newValue;
    }

    function updateMinBetRate(uint256 _newValue) external onlyOwner {
        require(minBetRate != _newValue, "Already Set");
        minBetRate = _newValue;
    }

    function play(uint256 _rolls, uint256 _bet, uint256[50] memory _data, uint256 _stake) external override {// gas: 871654 for roulette
        uint256 betId;
        uint256 betAmountWithFee;

        if (maxRoll > 0 && _rolls > maxRoll) {
            revert InvalidRolls(maxRoll, _rolls);
        }

        require(_stake > 0, "Please bet some coins");

        if (_stake * (10 ** 18) / (10 ** ERC20(address(usdtToken)).decimals()) < minBetRate) {
            revert MinBet(minBetRate, _stake);
        }

        (betId, betAmountWithFee) = house.openWager(msg.sender, id, _rolls, _bet, _data, _stake, getMaxPayout(_bet, _data)); // gas: 525635

        uint256[] memory ra = rng.generateMultiple(_rolls * numbersPerRoll); // gas: 23646
        uint256 payout = finalize(betId, ra); // gas: 59437

        house.closeWager(betId, msg.sender, id, payout); // gas: 154535

        usdtVault.finalizeGame(msg.sender, payout, betAmountWithFee - _rolls * _stake); // gas: 66308
    }

    function getId() external view returns (uint256) {
        return id;
    }

    function getLive() external view returns (bool) {
        Types.Game memory _game = consoleInst.getGame(id);
        return _game.live;
    }

    function getEdge() public view returns (uint256) {
        Types.Game memory _game = consoleInst.getGame(id);
        return _game.edge;
    }

    function getName() external view returns (string memory) {
        Types.Game memory _game = consoleInst.getGame(id);
        return _game.name;
    }

    function getDate() external view returns (uint256) {
        Types.Game memory _game = consoleInst.getGame(id);
        return _game.date;
    }

    function setUSDTToken(address _newUSDT) external onlyOwner {
        require(address(usdtToken) != _newUSDT, "Already Set");
        usdtToken = IERC20BackwardsCompatible(_newUSDT);
    }

    function setUSDTVault(address _newVault) external onlyOwner {
        require(address(usdtVault) != _newVault, "Already Set");
        usdtVault = IUSDTVault(_newVault);
    }

    function setConsoleInst(address _newConsole) external onlyOwner {
        require(address(consoleInst) != _newConsole, "Already Set");
        consoleInst = IConsole(_newConsole);
    }

    function setHouse(address _newHouse) external onlyOwner {
        require(address(house) != _newHouse, "Already Set");
        house = IHouse(_newHouse);
    }

    function setRNG(address _newRNG) external onlyOwner {
        require(address(rng) != _newRNG, "Already Set");
        rng = IRNG(_newRNG);
    }
}

