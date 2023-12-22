// SPDX-License-Identifier: AGPLv3
pragma solidity 0.8.9;

import {SafeERC20Upgradeable as SafeERC20} from "./SafeERC20Upgradeable.sol";

import "./IFrabricERC20.sol";
import "./IAirdrop.sol";

contract Airdrop is IAirdrop {
    using SafeERC20 for IFrabricERC20;
    uint64 public expiryDate;
    address public token;

    mapping(address => uint256) private _claims;
    constructor(uint8 daysUntilExpiry, address erc20, address [] memory claimants, uint256 [] memory amounts){
        expiryDate = uint64(block.timestamp) + (daysUntilExpiry * 1 days);
        token = erc20;
        if (claimants.length != amounts.length) {
            revert DifferentLengths(claimants.length, amounts.length);
        }

        for (uint64 i = 0; i < claimants.length; i++) {
            _claims[claimants[i]] = amounts[i];
        }
    }


    /*
    * @dev Claim your tokens from the airdrop.
    * @notice This function will revert if the airdrop has expired, or if the claimant has already claimed.
    * @notice This function will send only the available tokens to the recipient if the airdrop contract does not have enough tokens to fulfill the claim.
    */

    function claim() external {
        if (block.timestamp > expiryDate) {
            revert Expired();
        }
        uint256 claim = _claims[msg.sender];
        if (claim == 0) {
            revert AlreadyClaimed(msg.sender);
        }
        _claims[msg.sender] = 0;
        uint256 finalAmount = _claims[msg.sender] > IFrabricERC20(token).balanceOf(address(this)) ? IFrabricERC20(token).balanceOf(address(this)) : claim;
        IFrabricERC20(token).safeTransfer(msg.sender, finalAmount);
        emit ClaimRedeemed(finalAmount, msg.sender);
    }

    /**
     * @dev Burns all remaining tokens in the contract.
     * This function can be called by anyone after the expiry date.
     */

    function expire() external {
        if (block.timestamp <= expiryDate) {
            revert StillActive();
        }
        uint256 balance = IFrabricERC20(token).balanceOf(address(this));
        IFrabricERC20(token).burn(balance);
        emit BurnedTokens(balance);
    }

    /**
    * @dev Returns the amount of tokens that a claimant can claim.
    * @param claimant The address of the claimant.
    * @return The amount of tokens that the claimant can claim.
    */

    function viewClaim(address claimant) external view returns (uint256) {
        if (block.timestamp > expiryDate) {
            return 0;
        } else {
            return (_claims[claimant]);
        }
    }

}

