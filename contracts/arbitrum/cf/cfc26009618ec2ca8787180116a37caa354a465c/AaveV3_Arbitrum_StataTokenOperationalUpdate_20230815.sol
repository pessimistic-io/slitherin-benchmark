// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IProposalGenericExecutor} from "./IProposalGenericExecutor.sol";
import {AaveV3Arbitrum} from "./AaveV3Arbitrum.sol";
import {AaveMisc} from "./AaveMisc.sol";
import {ProxyAdmin} from "./ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "./TransparentUpgradeableProxy.sol";
import {IStaticATokenFactory} from "./IStaticATokenFactory.sol";

/**
 * @title stataToken operational update
 * @author BGD labs
 * - Discussion: https://governance.aave.com/t/bgd-statatoken-operational-update/14497
 */
contract AaveV3_Arbitrum_StataTokenOperationalUpdate_20230815 is IProposalGenericExecutor {
  address public constant NEW_ADMIN = 0xaF23DC5983230E9eEAf93280e312e57539D098D0;

  function execute() external {
    address[] memory tokens = IStaticATokenFactory(AaveV3Arbitrum.STATIC_A_TOKEN_FACTORY)
      .getStaticATokens();
    for (uint256 i; i < tokens.length; i++) {
      ProxyAdmin(AaveMisc.PROXY_ADMIN_ARBITRUM).changeProxyAdmin(
        TransparentUpgradeableProxy(payable(tokens[i])),
        NEW_ADMIN
      );
    }
  }
}

