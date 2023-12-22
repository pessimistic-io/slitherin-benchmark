pragma solidity ^0.8.0;

import "./Ownable.sol";
import {ERC20, SafeTransferLib} from "./SafeTransferLib.sol";

/// @notice contract to burn receipt token in exchange for underlying token 1:1
/// @dev this contract is useful
contract RedeemReceipt is Ownable {
    using SafeTransferLib for ERC20;

    event Redeem(address indexed who, uint256 amount);
    event Paused(bool paused);

    /// @notice pauses redeem functionality
    bool public paused;
    /// @notice receipt token to burn for underlying token 1:1
    ERC20 public immutable receiptToken;
    /// @notice underlying token to credit for burning receipt token 1:1
    ERC20 public immutable underlyingToken;

    constructor(address owner_, ERC20 receiptToken_, ERC20 underlyingToken_) Ownable() {
        _transferOwnership(owner_);
        receiptToken = receiptToken_;
        underlyingToken = underlyingToken_;

        paused = true;

        // sanity check to prevent improper setup
        if (
            receiptToken.totalSupply() > underlyingToken.totalSupply() ||
            receiptToken.decimals() != underlyingToken.decimals()
        ) revert("wrong token order");
    }

    /// @notice burns sender's balance of recipt token and transfers underlying token to sender
    function redeemReceipt() external {
        if (paused) revert("paused");

        uint256 redeemAmount = receiptToken.balanceOf(msg.sender);

        receiptToken.safeTransferFrom(msg.sender, address(0), redeemAmount);
        underlyingToken.safeTransfer(msg.sender, redeemAmount);

        emit Redeem(msg.sender, redeemAmount);
    }

    /// @notice Auth gated function to be able to withdraw an arbitrary ERC20 token
    function ownerWithdrawToken(
        ERC20 token,
        uint256 amount
    ) external onlyOwner {
        token.safeTransfer(msg.sender, amount);
    }

    /// @notice allows owner to pause redeems
    function ownerPause() external onlyOwner {
        paused = true;
        emit Paused(true);
    }

    /// @notice allows owner to unpause redeems
    function ownerUnpause() external onlyOwner {
        paused = false;
        emit Paused(false);
    }
}

