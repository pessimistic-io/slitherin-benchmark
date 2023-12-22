// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import "./IStrategyVault.sol";

/**
 * @dev These functions should not be called on chain.
 */
contract StrategyQuoter {
    IStrategyVault immutable strategy;

    constructor(IStrategyVault _strategy) {
        strategy = _strategy;
    }

    function quoteDeposit(
        uint256 _strategyId,
        uint256 _strategyTokenAmount,
        address _recepient,
        uint256 _maxMarginAmount,
        IStrategyVault.StrategyTradeParams memory _tradeParams
    ) external returns (uint256 finalDepositMargin) {
        try strategy.deposit(_strategyId, _strategyTokenAmount, _recepient, _maxMarginAmount, true, _tradeParams) {}
        catch (bytes memory reason) {
            return handleRevert(reason);
        }
    }

    function parseRevertReason(bytes memory reason) private pure returns (uint256, uint256, uint256) {
        if (reason.length != 96) {
            if (reason.length < 68) revert("Unexpected error");
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (uint256, uint256, uint256));
    }

    function handleRevert(bytes memory reason) private pure returns (uint256 finalDepositMargin) {
        (finalDepositMargin,,) = parseRevertReason(reason);
    }
}

