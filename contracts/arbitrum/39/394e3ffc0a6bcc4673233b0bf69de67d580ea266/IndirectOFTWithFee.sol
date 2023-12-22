// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./BaseOFTWithFee.sol";

interface IAnyswapBETS is IERC20 {
    function burn(address from, uint256 amount) external returns (bool);

    function mint(address to, uint256 amount) external returns (bool);
}

contract IndirectOFTWithFee is BaseOFTWithFee {
    using SafeERC20 for IAnyswapBETS;
    IAnyswapBETS public immutable anyswapBETS;
    uint public immutable ld2sdRate;

    constructor(
        address _token,
        uint8 _sharedDecimals,
        address _lzEndpoint
    ) BaseOFTWithFee(_sharedDecimals, _lzEndpoint) {
        anyswapBETS = IAnyswapBETS(_token);

        (bool success, bytes memory data) = _token.staticcall(
            abi.encodeWithSignature("decimals()")
        );
        require(success, "IndirectOFT: failed to get token decimals");
        uint8 decimals = abi.decode(data, (uint8));

        require(
            _sharedDecimals <= decimals,
            "IndirectOFT: sharedDecimals must be <= decimals"
        );
        ld2sdRate = 10 ** (decimals - _sharedDecimals);
    }

    /************************************************************************
     * public functions
     ************************************************************************/
    function circulatingSupply() public view virtual override returns (uint) {
        return anyswapBETS.totalSupply();
    }

    function token() public view virtual override returns (address) {
        return address(anyswapBETS);
    }

    /************************************************************************
     * internal functions
     ************************************************************************/
    function _debitFrom(
        address _from,
        uint16,
        bytes32,
        uint _amount
    ) internal virtual override returns (uint) {
        require(_from == _msgSender(), "IndirectOFT: owner is not send caller");

        anyswapBETS.burn(_from, _amount);

        return _amount;
    }

    function _creditTo(
        uint16,
        address _toAddress,
        uint _amount
    ) internal virtual override returns (uint) {
        anyswapBETS.mint(_toAddress, _amount);

        return _amount;
    }

    function _transferFrom(
        address _from,
        address _to,
        uint _amount
    ) internal virtual override returns (uint) {
        uint before = anyswapBETS.balanceOf(_to);
        if (_from == address(this)) {
            anyswapBETS.safeTransfer(_to, _amount);
        } else {
            anyswapBETS.safeTransferFrom(_from, _to, _amount);
        }
        return anyswapBETS.balanceOf(_to) - before;
    }

    function _ld2sdRate() internal view virtual override returns (uint) {
        return ld2sdRate;
    }
}

