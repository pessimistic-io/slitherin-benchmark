// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC4626.sol";
import "./IStrategOperatingPaymentToken.sol";
import "./IWETH.sol";
import { UsingDiamondOwner } from "./UsingDiamondOwner.sol";


import { LibDiamond } from "./libraries_LibDiamond.sol";
import { LibLiFi } from "./LibLiFi.sol";
import { LibParaswap } from "./LibParaswap.sol";
import { LibOneInch } from "./LibOneInch.sol";
import { LibPermit } from "./LibPermit.sol";
import { LibRelayer } from "./LibRelayer.sol";

error NoAmountOut();

contract StrategPortalSwapRouterFacet is UsingDiamondOwner {
    using SafeERC20 for IERC20;

    enum SwapIntegration {
        LIFI,
        PARASWAP,
        ONEINCH
    }
    
    constructor() {}

    function SOPT() external view returns (address) {
        return LibDiamond.diamondStorage().sopt;
    }

    function setSOPT(address _sopt) external onlyOwner {
        LibDiamond.setSOPT(_sopt);
    }

    function swap(
        bool sourceIsVault,
        bool targetIsVault,
        SwapIntegration _route,
        address _approvalAddress,
        address _sourceAsset,
        address _targetAsset,
        uint256 _amount,
        bytes memory _permitParams,
        bytes calldata _data
    ) external payable {
        address sender = LibRelayer.msgSender();
        if(_permitParams.length != 0) {
            LibPermit.executePermit(sender, _sourceAsset, _amount, _permitParams);
        }

        address sourceAsset = _sourceAsset;
        uint256 sourceAssetInAmount = _amount;
        if(sourceIsVault) {
            sourceAsset = IERC4626(_sourceAsset).asset();
            sourceAssetInAmount = IERC4626(_sourceAsset).redeem(_amount, address(this), sender);
        } else {
            IERC20(_sourceAsset).safeTransferFrom(sender, address(this), sourceAssetInAmount);
        }

        if(_route == SwapIntegration.LIFI) {
            LibLiFi.execute(sourceAsset, _approvalAddress, sourceAssetInAmount, _data);
        }

        if(_route == SwapIntegration.PARASWAP) {
            LibParaswap.execute(sourceAsset, _approvalAddress, sourceAssetInAmount, _data);
        }

        if(_route == SwapIntegration.ONEINCH) {
            LibOneInch.execute(sourceAsset, _approvalAddress, sourceAssetInAmount, _data);
        }

        if(targetIsVault) {
            IERC20 underlying = IERC20(IERC4626(_targetAsset).asset());
            uint256 assetOutAmount = underlying.balanceOf(address(this));

            if(assetOutAmount == 0) revert NoAmountOut();
            underlying.safeIncreaseAllowance(_targetAsset, assetOutAmount);
            IERC4626(_targetAsset).deposit(assetOutAmount, sender);
        } else {
            uint256 assetOutAmount = IERC20(_targetAsset).balanceOf(address(this));
            if(assetOutAmount == 0) revert NoAmountOut();
            IERC20(_targetAsset).safeTransfer(sender, assetOutAmount);
        }
    }

    function swapForSOPT(
        bool sourceIsVault,
        bool _nativeDeposit,
        SwapIntegration _route,
        address _receiver,
        address _approvalAddress,
        address _sourceAsset,
        uint256 _amount,
        bytes memory _permitParams,
        bytes calldata _data
    ) external payable {
        address sender = LibRelayer.msgSender();
        if(_permitParams.length != 0) {
            LibPermit.executePermit(sender, _sourceAsset, _amount, _permitParams);
        }

        address sourceAsset = _sourceAsset;
        uint256 sourceAssetInAmount = _amount;
        if(sourceIsVault) {
            sourceAsset = IERC4626(_sourceAsset).asset();
            sourceAssetInAmount = IERC4626(_sourceAsset).redeem(_amount, address(this), sender);
        } else {
            IERC20(_sourceAsset).safeTransferFrom(sender, address(this), _amount);
        }

        if(_route == SwapIntegration.LIFI) {
            LibLiFi.execute(sourceAsset, _approvalAddress, sourceAssetInAmount, _data);
        }

        if(_route == SwapIntegration.PARASWAP) {
            LibParaswap.execute(sourceAsset, _approvalAddress, sourceAssetInAmount, _data);
        }

        if(_route == SwapIntegration.ONEINCH) {
            LibOneInch.execute(sourceAsset, _approvalAddress, sourceAssetInAmount, _data);
        }

        IStrategOperatingPaymentToken sopt = IStrategOperatingPaymentToken(LibDiamond.diamondStorage().sopt);
        if(_nativeDeposit) {
            uint256 bal = address(this).balance;
            sopt.mint{ value: bal }(_receiver);
        } else {
            IWETH weth = IWETH(sopt.weth());
            uint256 bal = weth.balanceOf(address(this));
            weth.withdraw(bal);
            sopt.mint{ value: bal }(_receiver);
        }
    }
}

