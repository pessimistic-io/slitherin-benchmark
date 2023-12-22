// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IUniswapV2Pair.sol";
import "./IWETH.sol";
import "./IPlennyERC20.sol";
import "./IPlennyCoordinator.sol";
import "./IPlennyTreasury.sol";
import "./IPlennyOcean.sol";
import "./IPlennyStaking.sol";
import "./IPlennyValidatorElection.sol";
import "./IPlennyOracleValidator.sol";
import "./IPlennyDappFactory.sol";
import "./IPlennyReward.sol";
import "./IPlennyLiqMining.sol";
import "./IPlennyLocking.sol";
import "./IUniswapV2Router02.sol";

interface IContractRegistry {

    function getAddress(bytes32 name) external view returns (address);

    function requireAndGetAddress(bytes32 name) external view returns (address);

    function plennyTokenContract() external view returns (IPlennyERC20);

    function factoryContract() external view returns (IPlennyDappFactory);

    function oceanContract() external view returns (IPlennyOcean);

    function lpContract() external view returns (IUniswapV2Pair);

    function uniswapRouterV2() external view returns (IUniswapV2Router02);

    function treasuryContract() external view returns (IPlennyTreasury);

    function stakingContract() external view returns (IPlennyStaking);

    function coordinatorContract() external view returns (IPlennyCoordinator);

    function validatorElectionContract() external view returns (IPlennyValidatorElection);

    function oracleValidatorContract() external view returns (IPlennyOracleValidator);

    function wrappedETHContract() external view returns (IWETH);

    function rewardContract() external view returns (IPlennyReward);

    function liquidityMiningContract() external view returns (IPlennyLiqMining);

    function lockingContract() external view returns (IPlennyLocking);
}

