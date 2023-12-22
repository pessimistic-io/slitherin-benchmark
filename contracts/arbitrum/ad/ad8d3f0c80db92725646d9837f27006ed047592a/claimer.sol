// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {ERC1155} from "./ERC1155.sol";

contract Claimer {
    function claim(
        ERC1155 _token,
        uint256 _tokenID,
        address _receiver,
        uint256 _amount
    ) external {
        _token.safeTransferFrom(
            address(this),
            _receiver,
            _tokenID,
            _amount,
            "0x"
        );
        // safeTransferFrom(address(this), _receiver, _tokenID);
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}

