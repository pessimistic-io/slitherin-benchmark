// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";


contract FaircastleRedeemer is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public mimRedeemAmount = 12;

    // FCS token address
    address public FCS = 0xf754675Ca3d7D34290007065a4DE786FeA6bB9B5;
    // MIM token address
    address public MIM = 0xFEa7a6a0B346362BF88A9e4A88416B77a57D6c2A;

    constructor() {}

    /**
        @notice redeem FCS for MIM
        @param _amount uint256
     */
    function redeemFcs( uint256 _amount ) external nonReentrant() {
        require(_amount > 0, "Zero amount");

        IERC20( FCS ).safeTransferFrom( msg.sender, address(this), _amount );

        uint256 mimAmount = _amount.mul(10 ** 9).mul(mimRedeemAmount);
        IERC20( MIM ).safeTransfer( msg.sender, mimAmount );
    }

    /**
        @notice set MIM redeem amount
        @param _amount uint256
     */
    function setRedeemAmount( uint256 _amount ) external onlyOwner() {
        mimRedeemAmount = _amount;
    }

    /**
        @notice withdraw all FCS with owner
     */
    function withdrawFcs() external onlyOwner() {
        uint256 totalBalance = IERC20( FCS ).balanceOf( address(this) );
        IERC20( FCS ).safeTransfer( msg.sender, totalBalance );
    }

    /**
        @notice withdraw all MIM with owner
     */
    function withdrawMim() external onlyOwner() {
        uint256 totalBalance = IERC20( MIM ).balanceOf( address(this) );
        IERC20( MIM ).safeTransfer( msg.sender, totalBalance );
    }
}

