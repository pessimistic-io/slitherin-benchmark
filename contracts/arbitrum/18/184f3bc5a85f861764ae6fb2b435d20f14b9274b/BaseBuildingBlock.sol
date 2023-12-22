// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./IActionPoolDcRouter.sol";
import "./NonBlockingBaseApp.sol";
import "./ILayerZeroEndpointUpgradeable.sol";
import "./UUPSUpgradeable.sol";

abstract contract BaseBuildingBlock is NonBlockingBaseApp, UUPSUpgradeable {
    address public nativeRouter;

    event TransferredToNativeRouter(address indexed token, uint256 amount);

    function approve(
        address _baseAsset,
        address _spender,
        uint256 _amount
    ) public onlySelf {
        IERC20(_baseAsset).approve(_spender, _amount);
    }

    function backTokensToNative(address _token, uint256 _amount)
        public
        onlySelf
    {
        require(
            IERC20(_token).transfer(nativeRouter, _amount),
            "BBB:Transfer failed"
        );
        emit TransferredToNativeRouter(_token, _amount);
    }

    function nativeBridge(
        address _nativeStableToken,
        uint256 _stableAmount,
        uint16 _receiverLZId,
        address _receiverAddress,
        address _destinationStableToken
    ) public payable onlySelf {
        _bridge(
            _nativeStableToken,
            _stableAmount,
            _receiverLZId,
            _receiverAddress,
            _destinationStableToken,
            msg.value,
            ""
        );
    }

    function setNativeRouter(address _newNativeRouter) public onlySelf {
        address oldNativeRouter = nativeRouter;
        nativeRouter = _newNativeRouter;
        emit RouterChanged(_msgSender(), oldNativeRouter, _newNativeRouter);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

