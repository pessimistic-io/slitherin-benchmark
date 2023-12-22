// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IERC20.sol";
import "./IERC721.sol";

contract BatchTransfer {

    function tokenTransfer(
        address[] calldata _addresses,
        uint256[] calldata _amounts
    ) external payable {
        require(_addresses.length == _amounts.length, "Invalid input");
        for (uint256 i; i < _addresses.length; i++) {
            (bool success,) = payable(_addresses[i]).call{value: _amounts[i]}("");
            require(success, "Transfer failed");
        }
    }

    function ERC20Transfer(
        address _token,
        address[] calldata _addresses,
        uint256[] calldata _amount
    ) external {
        require(_addresses.length == _amount.length, "Invalid input");
        for (uint256 i; i < _addresses.length; i++) {
            IERC20(_token).transferFrom(
                msg.sender,
                payable(_addresses[i]),
                _amount[i]
            );
        }
    }

    function ERC721Transfer(
        address _token,
        address[] calldata _addresses,
        uint256[] calldata _tokenId
    ) external {
        require(_addresses.length == _tokenId.length, "Invalid input");
        for (uint256 i; i < _addresses.length; i++) {
            IERC721(_token).transferFrom(msg.sender, _addresses[i], _tokenId[i]);
        }
    }
}

