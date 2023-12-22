/**
 * https://arcadeum.io
 * https://arcadeum.gitbook.io/arcadeum
 * https://twitter.com/arcadeum_io
 * https://discord.gg/qBbJ2hNPf8
 */

// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.13;

import "./IesARCIncentiveManager.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20BackwardsCompatible.sol";

contract esARCIncentiveManager is IesARCIncentiveManager, Ownable, ReentrancyGuard {
    error OnlyALP(address _caller);

    address public immutable esARC;
    IERC20BackwardsCompatible public immutable esarc;
    address public immutable ALP;
    IERC20BackwardsCompatible public immutable alp;

    modifier onlyALP() {
        if (msg.sender != ALP) {
            revert OnlyALP(msg.sender);
        }
        _;
    }

    constructor (address _esARC, address _ALP) {
        esARC = _esARC;
        esarc = IERC20BackwardsCompatible(_esARC);
        ALP = _ALP;
        alp = IERC20BackwardsCompatible(_ALP);
    }

    function registerALPDeposit(address _provider, uint256 _amountUSDT, uint256 _timestamp, uint256 _amountALP) external nonReentrant onlyALP {}

    function registerALPWithdrawal(address _provider, uint256 _amountUSDT, uint256 _timestamp, uint256 _amountALP) external nonReentrant onlyALP {}
}

