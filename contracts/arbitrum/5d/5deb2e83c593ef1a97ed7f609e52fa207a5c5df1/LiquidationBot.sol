// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseVault } from "./BaseVault.sol";
import { Controllable } from "./Controllable.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { TauMath } from "./TauMath.sol";
import { Constants } from "./Constants.sol";

contract LiquidationBot is Controllable {
    using SafeERC20 for IERC20;

    // errors
    error wrongOffset(uint256);
    error oracleCorrupt();
    error insufficientFunds();

    // events
    event CollateralWithdrawn(address indexed userAddress, uint256 amount);

    struct LiqParams {
        address vaultAddress;
        address accountAddr;
        uint256 amount;
        uint256 minExchangeRate;
    }

    IERC20 public immutable tau;

    constructor(address _tau, address _controller) Controllable(_controller) {
        tau = IERC20(_tau);
    }

    /**
     * @dev approve any token.
     * @param _tokenIn The address of the token to be approved
     * @param _vault The address of the vault upon which this contract will run liquidations.
     * note calleable by multisig.
     */
    function approveTokens(address _tokenIn, address _vault) external onlyMultisig {
        IERC20(_tokenIn).approve(_vault, type(uint256).max);
    }

    function revokeTokens(address _tokenIn, address _vault) external onlyMultisig {
        IERC20(_tokenIn).approve(_vault, 0);
    }

    /**
     * @dev Run a liquidation on a vault.
     * note calleable only by registered keepers.
     */
    function liquidate(LiqParams memory _liqParams) external onlyKeeper {
        BaseVault vault = BaseVault(_liqParams.vaultAddress);

        if (_liqParams.amount > tau.balanceOf(address(this))) revert insufficientFunds();

        vault.liquidate(_liqParams.accountAddr, _liqParams.amount, _liqParams.minExchangeRate);
    }

    function withdrawLiqRewards(address _token, uint256 _amount) external onlyMultisig {
        IERC20 collToken = IERC20(_token);
        if (_amount > collToken.balanceOf(address(this))) revert insufficientFunds();
        collToken.safeTransfer(msg.sender, _amount);

        emit CollateralWithdrawn(msg.sender, _amount);
    }
}

