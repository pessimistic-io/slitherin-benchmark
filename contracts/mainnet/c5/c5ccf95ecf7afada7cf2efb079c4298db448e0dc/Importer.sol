//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// Force solc/typechain to compile test only dependencies
import "./ERC1967Proxy.sol";
import "./TransparentUpgradeableProxy.sol";
import "./TimelockController.sol";
import "./interfaces_IERC20Metadata.sol";
import "./FixedFeeModel.sol";
import "./ContangoYield.sol";
import "./ContangoYieldQuoter.sol";
import {IPoolOracle} from "./IPoolOracle.sol";

import {CompositeMultiOracle} from "./CompositeMultiOracle.sol";
import {IFYToken} from "./IFYToken.sol";

import "./IWETH9.sol";
import {ChainlinkAggregatorV2V3Mock} from "./ChainlinkAggregatorV2V3Mock.sol";
import {UniswapPoolStub} from "./UniswapPoolStub.sol";
import {IPoolStub} from "./IPoolStub.sol";
import {IOraclePoolStub} from "./IOraclePoolStub.sol";
import "./CashSettler.sol";

