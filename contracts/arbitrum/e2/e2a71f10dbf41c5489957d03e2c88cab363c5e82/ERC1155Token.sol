// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {ERC1155} from "./ERC1155.sol";
import "./console.sol";
contract ERC1155Token is ERC1155 {
    function mint(address to, uint256 id, uint256 amount) external {
        _mint(to, id, amount, "0x");
    }

    function batchMint(address to, uint256[] memory id, uint256 amount) external {
        uint256 _len= id.length;
        for (uint256 index = 0; index < _len; index++) {
            _mint(to, id[index], amount, "0x");
        }
    }

    function uri(uint256) public pure override returns (string memory){
        return "https://ipfs.io/ipfs/bafkreihx7i5zkwgx5w3fy3t357vrtzqmcihkp6i3rjzzbqn267rm5wuxgy";
    }

}

