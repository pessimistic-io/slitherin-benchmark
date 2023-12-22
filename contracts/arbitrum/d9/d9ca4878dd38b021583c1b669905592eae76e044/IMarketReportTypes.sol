// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMarketReportTypes {
  struct MarketReport {
    address poolAddressesProviderRegistry;
    address poolAddressesProvider;
    address poolProxy;
    address poolImplementation;
    address poolConfiguratorProxy;
    address poolConfiguratorImplementation;
    address protocolDataProvider;
    address aaveOracle;
    address aclManager;
    address treasuryFactory;
    address treasury;
    address treasuryProxyAdmin;
    address treasuryImplementation;
    address treasuryController;
    address wrappedTokenGateway;
    address walletBalanceProvider;
    address uiIncentiveDataProvider;
    address uiPoolDataProvider;
    address paraSwapLiquiditySwapAdapter;
    address paraSwapRepayAdapter;
  }

  struct LibrariesReport {
    address borrowLogic;
    address bridgeLogic;
    address configuratorLogic;
    address eModeLogic;
    address flashLoanLogic;
    address liquidationLogic;
    address poolLogic;
    address supplyLogic;
  }

  struct Roles {
    address registryOwner;
    address marketOwner;
    address poolAdmin;
    address emergencyAdmin;
  }

  struct MarketConfig {
    address ethUsdChainlinkOracle;
    string marketId;
    uint8 oracleDecimals;
    address paraswapAugustusRegistry;
    uint256 providerId;
    address wrappedNativeToken;
  }

  struct DeployFlags {
    bool linkMarketToRegistry;
    bool l2;
  }
}

