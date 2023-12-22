//SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./IFees.sol";

interface IParallax is IFees {
    struct DepositLPs {
        uint256[] compoundAmountsOutMin;
        uint256 strategyId;
        uint256 positionId;
        uint256 amount;
    }

    struct DepositTokens {
        uint256[] compoundAmountsOutMin;
        uint256[] amountsOutMin;
        uint256 strategyId;
        uint256 positionId;
        uint256 amount;
    }

    struct DepositNativeTokens {
        uint256[] compoundAmountsOutMin;
        uint256[] amountsOutMin;
        address[][] paths;
        uint256 strategyId;
        uint256 positionId;
    }

    struct DepositERC20Token {
        uint256[] compoundAmountsOutMin;
        uint256[] amountsOutMin;
        address[][] paths;
        uint256 strategyId;
        uint256 positionId;
        uint256 amount;
        address token;
    }

    struct EmergencyWithdraw {
        uint256 strategyId;
        uint256 positionId;
        uint256 shares;
    }

    struct WithdrawLPs {
        uint256[] compoundAmountsOutMin;
        uint256 strategyId;
        uint256 positionId;
        uint256 shares;
    }

    struct WithdrawTokens {
        uint256[] compoundAmountsOutMin;
        uint256[] amountsOutMin;
        uint256 strategyId;
        uint256 positionId;
        uint256 shares;
    }

    struct WithdrawNativeToken {
        uint256[] compoundAmountsOutMin;
        uint256[] amountsOutMin;
        address[][] paths;
        uint256 strategyId;
        uint256 positionId;
        uint256 shares;
    }

    struct WithdrawERC20Token {
        uint256[] compoundAmountsOutMin;
        uint256[] amountsOutMin;
        address[][] paths;
        uint256 strategyId;
        uint256 positionId;
        uint256 shares;
        address token;
    }

    /// @notice The view method for getting current feesReceiver.
    function feesReceiver() external view returns (address);

    /**
     * @notice The view method for getting current withdrawal fee by strategy.
     * @param strategy An aaddress of a strategy.
     * @return Withdrawal fee.
     **/
    function getWithdrawalFee(address strategy) external view returns (uint256);

    /**
     * @notice The view method to check if the token is in the whitelist.
     * @param strategy An address of a strategy.
     * @param token An address of a token to check.
     * @return Boolean flag.
     **/
    function tokensWhitelist(
        address strategy,
        address token
    ) external view returns (bool);
}

