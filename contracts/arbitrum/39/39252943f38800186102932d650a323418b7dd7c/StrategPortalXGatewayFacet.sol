// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import "./IERC20.sol";
import "./SafeERC20.sol";


import { LibLiFi } from "./LibLiFi.sol";
import { LibPermit } from "./LibPermit.sol";
import { LibRelayer } from "./LibRelayer.sol";

import "./IERC4626.sol";

import "./console.sol";


contract StrategPortalXGatewayFacet {
    using SafeERC20 for IERC20;

    enum SwapIntegration {
        LIFI
    }
    
    constructor() {}

    function swapAndBridge(
        bool sourceIsVault,
        bool targetIsVault,
        SwapIntegration _route,
        address _sourceAsset,
        address _approvalAddress,
        address _targetAsset,
        uint256 _amount,
        uint256 _targetChain,
        bytes memory _permitParams, 
        bytes calldata _data
    ) external payable {

        address sender = LibRelayer.msgSender();
        if(_permitParams.length != 0) {
            LibPermit.executePermit(sender, _sourceAsset, _amount, _permitParams);
        }

        IERC20(_sourceAsset).safeTransferFrom(sender, address(this), _amount);

        address sourceAsset = _sourceAsset;
        uint256 sourceAssetInAmount = _amount;
        if(sourceIsVault) {
            sourceAsset = IERC4626(_sourceAsset).asset();
            IERC4626(_sourceAsset).redeem(_amount, address(this), address(this));
            sourceAssetInAmount = IERC20(sourceAsset).balanceOf(address(this));
        }

        if(_route == SwapIntegration.LIFI) {
            LibLiFi.execute(sourceAsset, _approvalAddress, sourceAssetInAmount, _data);
        }

        uint256 remainingBalance = IERC20(sourceAsset).balanceOf(address(this));
        if(remainingBalance > 0) {
            IERC20(sourceAsset).safeTransfer(sender, remainingBalance);
        }
    }
}

