// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./OFT.sol";

contract Cocks is OFT {
    bool public setOnce;
    address public cockadoods;

    modifier onlyCockadoods() {
        require(msg.sender == cockadoods, "Not authorized");
        _;
    }

    constructor(address _layerZeroEndpoint) OFT("CockadoodsOFT", "CKC", _layerZeroEndpoint) {}

    function mintTokens(address _to, uint256 _amount) public onlyCockadoods {
        _mint(_to, _amount);
    }

    function setCockadoods(address _cocksnft) public onlyOwner {
        require(setOnce == false, "Already set");
        cockadoods = _cocksnft;
        setOnce = true;
    }
}

