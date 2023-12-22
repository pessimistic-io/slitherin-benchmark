// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {ERC721} from "./ERC721.sol";


contract Claimer {

    function claim(ERC721 _token, uint _tokenID, address _receiver) external {
        _token.safeTransferFrom(address(this), _receiver, _tokenID);
    }

}

