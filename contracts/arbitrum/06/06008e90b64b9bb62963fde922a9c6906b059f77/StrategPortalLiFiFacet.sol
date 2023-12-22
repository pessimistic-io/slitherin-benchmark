// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { UsingDiamondOwner } from "./UsingDiamondOwner.sol";
import { LibDiamond } from "./libraries_LibDiamond.sol";
import { LibLiFi } from "./LibLiFi.sol";

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC4626.sol";
import "./IStrategOperatingPaymentToken.sol";
import "./IWETH.sol";

import "./console.sol";

contract StrategPortalLiFiFacet is UsingDiamondOwner {
    using SafeERC20 for IERC20;

    constructor() {}

    event LiFiSetDiamond(address diamond);
    event LiFiExecutionResult(bool success, bytes returnData);

    function lifiDiamond() external view returns (address) {
        return LibLiFi.getDiamond();
    }

    function setLiFiDiamond(address _diamond) external onlyOwner {
        LibLiFi.setDiamond(_diamond);
        emit LiFiSetDiamond(_diamond);
    }

    function lifiBridgeReceiver(
        address _tokenReceived,
        address _sender,
        address _toVault
    ) external {
        IERC20 underlying = IERC20(_tokenReceived);
        
        uint256 msgSenderAllowance = underlying.allowance(msg.sender, address(this));
        if(msgSenderAllowance > 0) {
            underlying.safeTransferFrom(msg.sender, address(this), msgSenderAllowance);
        }

        uint256 assetOutAmount = underlying.balanceOf(address(this));
        underlying.safeIncreaseAllowance(_toVault, assetOutAmount);
        
        uint256 shares = IERC4626(_toVault).deposit(assetOutAmount, address(this));
        IERC4626(_toVault).transfer(_sender, shares);
    }

    function lifiBridgeReceiverForSOPT(
        address _tokenReceived,
        address _sender
    ) external payable {

        if(_tokenReceived != address(0)) {
            IERC20 underlying = IERC20(_tokenReceived);
            uint256 msgSenderAllowance = underlying.allowance(msg.sender, address(this));
            if(msgSenderAllowance > 0) {
                underlying.safeTransferFrom(msg.sender, address(this), msgSenderAllowance);
            }
        }
        
        IStrategOperatingPaymentToken sopt = IStrategOperatingPaymentToken(LibDiamond.diamondStorage().sopt);
        if(msg.value > 0) {
            uint256 balance = address(this).balance;
            sopt.mint{ value: balance }(_sender);
        }
        
        IWETH weth = IWETH(sopt.weth());
        uint256 bal = weth.balanceOf(address(this));

        if(bal > 0) {
            weth.withdraw(bal);
            sopt.mint{ value: bal }(_sender);
        }
    }
}

