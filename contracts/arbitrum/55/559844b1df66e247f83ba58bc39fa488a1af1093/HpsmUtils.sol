// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.7;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./hPSM.sol";

/*
 * @dev safeApprove is intentionally not used, as since this contract should not store
 * funds between transactions, the approval race vulnerability does not apply.
 */
abstract contract HpsmUtils is Ownable {
    using SafeERC20 for IERC20;

    address public hpsm;

    event ChangeHpsm(address newPsm);

    constructor(address _hpsm) {
        hpsm = _hpsm;
        emit ChangeHpsm(hpsm);
    }

    /** @notice Sets the peg stability module address*/
    function setHpsm(address _hpsm) external onlyOwner {
        require(hpsm != _hpsm, "Address already set");
        hpsm = _hpsm;
        emit ChangeHpsm(hpsm);
    }

    /**
     * @notice Deposits pegged token for fxToken in the hPSM
     * @param peggedToken the token to be deposited
     * @param fxToken the token to receive
     * @param amount the amount of {peggedToken} to deposit
     */
    function _hpsmDeposit(
        address peggedToken,
        address fxToken,
        uint256 amount
    ) internal {
        // approve hPSM for amount
        IERC20(peggedToken).approve(hpsm, amount);

        // deposit in hPSM
        hPSM(hpsm).deposit(fxToken, peggedToken, amount);
    }

    /**
     * @notice Withdraws peggedToken for fxToken in
     * @param fxToken the token to burn
     * @param peggedToken the token to receive
     * @param amount the amount of {fxToken} to burn
     */
    function _hpsmWithdraw(
        address fxToken,
        address peggedToken,
        uint256 amount
    ) internal {
        // No approval is needed as the hpsm can mint/burn fxtokens
        hPSM(hpsm).withdraw(fxToken, peggedToken, amount);
    }
}

