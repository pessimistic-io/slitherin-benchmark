// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./OFTV2.sol";

contract VRC25 {
    event Fee(
        address indexed from,
        address indexed to,
        address indexed issuer,
        uint256 value
    );

    mapping(address => uint256) private _balances;
    uint256 private _minFee;
    address private _owner;

    constructor(address owner_, uint256 minFee_) {
        _owner = owner_;
        _minFee = minFee_;
    }

    function issuer() public view returns (address) {
        return _owner;
    }

    function minFee() public view returns (uint256) {
        return _minFee;
    }

    function estimateFee(uint256 value) external view returns (uint256) {
        return 0;
    }
}

contract TestTokenOFTxTRC25 is VRC25, OFTV2 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _sharedDecimals,
        address _layerZeroEndpoint
    )
        OFTV2(_name, _symbol, _sharedDecimals, _layerZeroEndpoint)
        VRC25(msg.sender, 0)
    {}

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        emit Fee(from, to, issuer(), 0);
    }
}

