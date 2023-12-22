// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./MonopolyToken.sol";
import "./DuoToken.sol";

// @title MonoDuoConvert
// @author MonopolyChef
// @notice This contract is used to convert Mono to Duo for layer 2
contract MonoDuoConvert is ReentrancyGuard {
    using SafeERC20 for MonopolyToken;

    address public immutable deployer;

    MonopolyToken public mono; // 5.813953488372093
    DuoToken public duo; //  1

    uint256 public monoToDuoRate = 172 * 1e15; // 0.172,

    uint256 PRECISION = 1e18;

    bool public initialized = false;

    uint256 public startTime;

    constructor() {
        deployer = msg.sender;
    }

    function initialize(
        MonopolyToken _mono,
        DuoToken _duo,
        uint256 _monoToDuoRate,
        uint256 _startTime
    ) external {
        require(!initialized, "MonoDuoConvert: ALREADY_INITIALIZED");
        require(msg.sender == deployer, "MonoDuoConvert: FORBIDDEN");
        require(
            _startTime > block.timestamp,
            "MonoDuoConvert: INVALID_START_TIME"
        );
        require(
            address(mono) == address(0),
            "MonoDuoConvert: ALREADY_INITIALIZED"
        );
        require(
            address(duo) == address(0),
            "MonoDuoConvert: ALREADY_INITIALIZED"
        );

        mono = _mono;
        duo = _duo;
        monoToDuoRate = _monoToDuoRate; //
        startTime = _startTime;
        initialized = true;
    }

    function setMonoToDuoRate(uint256 _monoToDuoRate) external {
        require(msg.sender == deployer, "MonoDuoConvert: FORBIDDEN");
        monoToDuoRate = _monoToDuoRate;
    }

    function _monoToDuo(uint256 _monoAmount) internal view returns (uint256) {
        return (_monoAmount * monoToDuoRate) / PRECISION;
    }

    function monoToDuo(uint256 _monoAmount) external view returns (uint256) {
        return _monoToDuo(_monoAmount);
    }

    function convert() external nonReentrant {
        require(startTime < block.timestamp, "MonoDuoConvert: NOT_STARTED");

        uint256 _amount = mono.balanceOf(msg.sender);
        require(_amount > 0, "MonoDuoConvert: INSUFFICIENT_BALANCE");

        uint256 duoAmount = _monoToDuo(_amount);

        mono.safeTransferFrom(msg.sender, address(this), _amount);

        duo.mint(msg.sender, duoAmount);
    }
}

