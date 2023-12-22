// SPDX-License-Identifier: MIT
pragma solidity ^0.4.26;

import "./IERC721.sol";
import "./Ownable.sol";
import "./SecurityBaseFor4.sol";

/**
 * @title TransferManagerERC721
 * @notice It allows the transfer of ERC721 tokens.
 */
contract TransferNFTManager is SecurityBaseFor4 {
    address public OK_EXCHANGE;

    /**
     * @notice Constructor
     * @param _exchange address of the LooksRare exchange
     */
    constructor(address _exchange) {
        OK_EXCHANGE = _exchange;
    }


    function setExchangeAddr(
        address _exchange
    ) public onlyOwner {
        OK_EXCHANGE = _exchange;
    }

    function proxy(
        address dest,
        uint256 howToCall,
        bytes calldataValue
    ) public returns (bool result) {
        require(msg.sender == OK_EXCHANGE, "Transfer: Only OK Exchange");
        if (howToCall == 0) {
            result = dest.call(calldataValue);
        }
        return result;
    }

}

