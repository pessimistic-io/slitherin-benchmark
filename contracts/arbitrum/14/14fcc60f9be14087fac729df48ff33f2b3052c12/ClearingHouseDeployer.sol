// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity =0.8.14;

import { TransparentUpgradeableProxy } from "./TransparentUpgradeableProxy.sol";
import { IERC20 } from "./IERC20.sol";

import { ProxyAdminDeployer } from "./ProxyAdminDeployer.sol";

import { IClearingHouse } from "./IClearingHouse.sol";
import { IClearingHouseSystemActions } from "./IClearingHouseSystemActions.sol";
import { IInsuranceFund } from "./IInsuranceFund.sol";
import { IOracle } from "./IOracle.sol";
import { IVQuote } from "./IVQuote.sol";

/// @notice Manages deployment for ClearingHouseProxy
/// @dev ClearingHouse proxy is deployed only once
abstract contract ClearingHouseDeployer is ProxyAdminDeployer {
    struct DeployClearingHouseParams {
        address clearingHouseLogicAddress;
        IERC20 settlementToken;
        IOracle settlementTokenOracle;
        IInsuranceFund insuranceFund;
        IVQuote vQuote;
    }

    function _deployProxyForClearingHouseAndInitialize(DeployClearingHouseParams memory params)
        internal
        returns (IClearingHouse)
    {
        return
            IClearingHouse(
                address(
                    new TransparentUpgradeableProxy(
                        params.clearingHouseLogicAddress,
                        address(proxyAdmin),
                        abi.encodeCall(
                            IClearingHouseSystemActions.initialize,
                            (
                                address(this), // RageTradeFactory
                                msg.sender, // initialGovernance
                                msg.sender, // initialTeamMultisig
                                params.settlementToken,
                                params.settlementTokenOracle,
                                params.insuranceFund,
                                params.vQuote
                            )
                        )
                    )
                )
            );
    }
}

