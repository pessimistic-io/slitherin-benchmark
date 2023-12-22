// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { UsingDiamondOwner } from "./UsingDiamondOwner.sol";
import { LibDiamond } from "./libraries_LibDiamond.sol";
import { LibOneInch } from "./LibOneInch.sol";

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC4626.sol";
import "./IStrategOperatingPaymentToken.sol";
import "./IWETH.sol";

import "./console.sol";

contract StrategPortalOneInchFacet is UsingDiamondOwner {
    using SafeERC20 for IERC20;

    constructor() {}

    event OneInchSetRouter(address router);
    event OneInchExecutionResult(bool success, bytes returnData);

    function oneInchRouter() external view returns (address) {
        return LibOneInch.getRouter();
    }

    function setOneInchRouter(address _router) external onlyOwner {
        LibOneInch.setRouter(_router);
        emit OneInchSetRouter(_router);
    }
}

