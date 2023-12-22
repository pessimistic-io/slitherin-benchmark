// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./VibeBase.sol";

// ⢠⣶⣿⣿⣶⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⣿⣿⠁⠀⠙⢿⣦⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠸⣿⣆⠀⠀⠈⢻⣷⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣾⡿⠿⠛⠻⠿⣿⣦⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⣤⣤⣤⣀⡀⠀
// ⠀⢻⣿⡆⠀⠀⠀⢻⣷⡀⠀⠀⠀⠀⠀⠀⢀⣴⣾⠿⠿⠿⣿⣿⠀⠀⠀⠀⠀⠈⢻⣷⡀⠀⠀⠀⠀⠀⢀⣠⣶⣿⠿⠛⠋⠉⠉⠻⣿⣦
// ⠀⠀⠻⣿⡄⠀⠀⠀⢿⣧⣠⣶⣾⠿⠿⠿⣿⡏⠀⠀⠀⠀⢹⣿⡀⠀⠀⠀⢸⣿⠈⢿⣷⠀⠀⠀⢀⣴⣿⠟⠉⠀⠀⠀⠀⠀⠀⠀⢸⣿
// ⠀⠀⠀⠹⣿⡄⠀⠀⠈⢿⣿⡏⠀⠀⠀⠀⢻⣷⠀⠀⠀⠀⠸⣿⡇⠀⠀⠀⠈⣿⠀⠘⢿⣧⣠⣶⡿⠋⠁⠀⠀⠀⠀⠀⠀⣀⣠⣤⣾⠟
// ⠀⠀⠀⠀⢻⣿⡄⠀⠀⠘⣿⣷⠀⠀⠀⠀⢸⣿⡀⠀⠀⠀⠀⣿⣷⠀⠀⠀⠀⣿⠀⢶⠿⠟⠛⠉⠀⠀⠀⠀⠀⢀⣤⣶⠿⠛⠋⠉⠁⠀
// ⠀⠀⠀⠀⠀⢿⣷⠀⠀⠀⠘⣿⡆⠀⠀⠀⠀⣿⡇⠀⠀⠀⠀⢹⣿⠀⠀⠀⠀⣿⡆⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⡿⠋⠁⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠘⣿⡇⠀⠀⠀⢸⣷⠀⠀⠀⠀⢿⣷⠀⠀⠀⠀⠈⣿⡇⠀⠀⠀⣿⡇⠀⠀⠀⠀⠀⠀⠀⣴⣿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⢻⣿⠀⠀⠀⠀⢿⣇⠀⠀⠀⠸⣿⡄⠀⠀⠀⠀⣿⣷⠀⠀⠀⣿⡇⠀⠀⠀⠀⠀⠀⣼⡿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠘⣿⡇⠀⠀⠀⠸⣿⡀⠀⠀⠀⢿⣇⠀⠀⠀⠀⢸⣿⡀⠀⢠⣿⠇⠀⠀⠀⠀⠀⣼⡿⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⢹⣿⠀⠀⠀⠀⢻⣧⠀⠀⠀⠸⣿⡄⠀⠀⠀⢘⣿⡿⠿⠟⠋⠀⠀⠀⠀⠀⣼⣿⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠈⣿⣇⠀⠀⠀⠈⣿⣄⠀⢀⣠⣿⣿⣶⣶⣶⡾⠋⠀⠀⠀⠀⠀⠀⠀⠀⣰⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⢹⣿⡀⠀⠀⠀⠈⠻⠿⠟⠛⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⢻⣷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢿⣧⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⣿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⢻⣧⡀⠀⠀⠀⣀⠀⠀⠀⣴⣤⣄⣀⣀⣀⣠⣤⣾⣿⡿⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠹⣿⣶⣶⣿⡿⠃⠀⠀⠉⠛⠻⠿⠿⠿⠿⢿⣿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣿⡏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢿⣇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣿⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀

abstract contract MintSaleBase is VibeBase {
    using BoringERC20 for IERC20;
    event SaleExtended(uint32 newEndTime);
    event SaleEnded();
    event SaleEndedEarly();

    uint32 public beginTime;
    uint32 public endTime;

    IERC20 public paymentToken;

    constructor(SimpleFactory vibeFactory_, IWETH WETH_) VibeBase(vibeFactory_, WETH_){

    }

    function getPayment(uint256 amount, uint256 mintingFee) internal virtual override {
        if (address(paymentToken) == address(WETH)) {
            if (mintingFee > 0) {
                require(msg.value == amount + mintingFee, "Not enough value");

                (bool success, ) = fees.vibeTreasury.call{value: mintingFee}(
                    ""
                );
                require(success, "Revert treasury call");
            } else {
                require(msg.value == amount, "Incorrect value");
            }
            WETH.deposit{value: amount}();
        } else {
            if (mintingFee > 0) {
                require(msg.value == mintingFee, "Not enough value");
                (bool success, ) = fees.vibeTreasury.call{value: mintingFee}(
                    ""
                );
                require(success, "Revert treasury call");
            } else {
                require(msg.value == 0, "Cannot send value");
            }

            paymentToken.safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    /// @notice Removes tokens and reclaims ownership of the NFT contract after the sale has ended.
    /// @dev The sale must have ended before calling this function.
    /// @param proceedRecipient The address that will receive the proceeds from the sale.
    function removeTokensAndReclaimOwnership(
        address proceedRecipient
    ) external onlyOwner {
        if (block.timestamp < endTime) {
            endTime = uint32(block.timestamp);
            emit SaleEndedEarly();
        } else {
            emit SaleEnded();
        }
        claimEarnings(proceedRecipient);
        nft.renounceMinter();
    }

    function claimEarnings(address proceedRecipient) public onlyOwner {
        claimEarnings(paymentToken, proceedRecipient);
    } 

    /// @notice Extends the sale end time to a new timestamp.
    /// @dev The new end time must be in the future.
    /// @param newEndTime The new end time for the sale.
    function extendEndTime(uint32 newEndTime) external onlyOwner {
        require(
            newEndTime > block.timestamp && newEndTime > beginTime,
            "New end time must > beginTime"
        );
        endTime = newEndTime;

        emit SaleExtended(endTime);
    }

}

