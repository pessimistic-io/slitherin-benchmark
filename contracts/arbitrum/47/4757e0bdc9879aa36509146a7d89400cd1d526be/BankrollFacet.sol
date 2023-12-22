// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {WithStorage} from "./LibStorage.sol";
import {LibDiamond} from "./LibDiamond.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";

contract BankrollFacet is WithStorage {
    using SafeERC20 for IERC20;

    event GameWhitelistStateChanged(address gameAddress, bool isValid);
    event TokenWhitelistStateChanged(address tokenAddress, bool isValid);

    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    function getOwner() external view returns (address) {
        return LibDiamond.contractOwner();
    }

    function withdrawFunds(address tokenAddress, address to, uint256 amount) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(to, amount);
    }

    function withdrawNativeFunds(address to, uint256 amount) external onlyOwner {
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "Transfer failed");
    }

    function whitelistGame(address game, bool isValid) external onlyOwner {
        bs().isGame[game] = isValid;
        emit GameWhitelistStateChanged(game, isValid);
    }

    function whitelistToken(address tokenAddress, bool isValid) external onlyOwner {
        bs().isTokenAllowed[tokenAddress] = isValid;
        emit TokenWhitelistStateChanged(tokenAddress, isValid);
    }

    function getIsGame(address game) external view returns (bool) {
        return (bs().isGame[game]);
    }

    function getIsValidWager(address game, address tokenAddress) external view returns (bool) {
        return (bs().isGame[game] && bs().isTokenAllowed[tokenAddress]);
    }

    function transferPayout(address player, uint256 payout, address tokenAddress) external {
        require(bs().isGame[msg.sender], "Not authorized");
        if (tokenAddress != address(0)) {
            IERC20(tokenAddress).safeTransfer(player, payout);
        } else {
            (bool success, ) = payable(player).call{value: payout}("");
            require(success, "Failed to send Ether");
        }
    }
}

