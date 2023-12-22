// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { UsingDiamondOwner } from "./UsingDiamondOwner.sol";
import { LibDiamond } from "./libraries_LibDiamond.sol";
import { LibParaswap } from "./LibParaswap.sol";

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC4626.sol";
import "./IStrategOperatingPaymentToken.sol";
import "./IWETH.sol";

import "./console.sol";

contract StrategPortalParaswapFacet is UsingDiamondOwner {
    using SafeERC20 for IERC20;

    constructor() {}

    event ParaswapSetAugustus(address augustus);
    event ParaswapExecutionResult(bool success, bytes returnData);

    function paraswapAugustus() external view returns (address) {
        return LibParaswap.getAugustus();
    }

    function setParaswapAugustus(address _augustus) external onlyOwner {
        LibParaswap.setAugustus(_augustus);
        emit ParaswapSetAugustus(_augustus);
    }
}

