// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { UsingDiamondOwner } from "./UsingDiamondOwner.sol";
import { LibDiamond } from "./libraries_LibDiamond.sol";
import { LibRelayer } from "./LibRelayer.sol";

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC4626.sol";
import "./IStrategOperatingPaymentToken.sol";
import "./IWETH.sol";

import "./console.sol";

contract StrategPortalRelayerFacet is UsingDiamondOwner {

    constructor() {}

    event SetRelayer(address relayer);

    function relayer() external view returns (address) {
        return LibRelayer.getRelayer();
    }

    function setRelayer(address _relayer) external onlyOwner {
        LibRelayer.setRelayer(_relayer);
        emit SetRelayer(_relayer);
    }
}

