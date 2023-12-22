// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ProxyOFTV2.sol";
import "./IERC20BurnMint.sol";

contract Intermediary is ProxyOFTV2 {
    using SafeERC20 for IERC20;

    constructor(
        address _grain,
        address _layerZeroEndpoint,
        uint8 _sharedDecimals
    ) ProxyOFTV2(
        _grain,
        _sharedDecimals,
        _layerZeroEndpoint
    ) {}

    function _transferFrom(
        address _from,
        address _to,
        uint _amount
    ) internal virtual override returns (uint) {
        uint before = innerToken.balanceOf(_to);
        if (_from == address(this)) {
            IERC20BurnMint(address(innerToken)).mint(_to, _amount);
        } else {
            IERC20BurnMint(address(innerToken)).burn(_from, _amount);
        }

        return innerToken.balanceOf(_to) - before;
    }

    function _debitFrom(
        address _from,
        uint16,
        bytes32,
        uint _amount
    ) internal virtual override returns (uint) {
        require(_from == _msgSender(), "ProxyOFT: owner is not send caller");

        _amount = _transferFrom(_from, address(this), _amount);

        // check total outbound amount
        outboundAmount += _amount;
        uint cap = _sd2ld(type(uint64).max);
        require(cap >= outboundAmount, "ProxyOFT: outboundAmount overflow");

        return _amount;
    }

    function _creditTo(
        uint16,
        address _toAddress,
        uint _amount
    ) internal virtual override returns (uint) {
        outboundAmount -= _amount;

        // tokens are already in this contract, so no need to transfer
        if (_toAddress == address(this)) {
            return _amount;
        }

        return _transferFrom(address(this), _toAddress, _amount);
    }
}
