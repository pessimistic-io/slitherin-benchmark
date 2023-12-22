// SPDX-License-Identifier: Unlicensed
// Modified from https://github.com/LayerZero-Labs/solidity-examples/blob/main/contracts/token/oft/OFT.sol
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./IOFT.sol";
import "./OFTCore.sol";

abstract contract OFT is OFTCore {
    constructor(address _lzEndpoint) OFTCore(_lzEndpoint) {}

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IOFT).interfaceId || interfaceId == type(IERC20).interfaceId || super.supportsInterface(interfaceId);
    }

    function token() public view virtual override returns (address) {
        return address(this);
    }

}
