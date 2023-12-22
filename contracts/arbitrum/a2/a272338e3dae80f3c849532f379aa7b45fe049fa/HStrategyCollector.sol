// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20RootVault} from "./IERC20RootVault.sol";
import {IUniV3Vault} from "./IUniV3Vault.sol";

import "./DefaultAccessControl.sol";
import "./IBaseCollector.sol";
import "./IBaseFeesCollector.sol";

import "./univ3_INonfungiblePositionManager.sol";
import "./univ3_IUniswapV3Pool.sol";
import "./IUniswapV3Factory.sol";
import "./PositionValue.sol";

contract HStrategyCollector is IBaseCollector, DefaultAccessControl {
    mapping(address => address) public collectorForGovernance;

    INonfungiblePositionManager public immutable positionManager;
    IUniswapV3Factory public immutable factory;

    constructor(address owner, INonfungiblePositionManager positionManager_) DefaultAccessControl(owner) {
        positionManager = positionManager_;
        factory = IUniswapV3Factory(positionManager.factory());
    }

    function setCollectors(address[] memory governances, address[] memory collectors) external {
        _requireAdmin();
        for (uint256 i = 0; i < governances.length; i++) {
            collectorForGovernance[governances[i]] = collectors[i];
        }
    }

    function collectFeesData(address vault) public view returns (address[] memory tokens, uint256[] memory amounts) {
        address feesCollector = collectorForGovernance[address(IERC20RootVault(vault).vaultGovernance())];
        if (feesCollector == address(0)) {
            return (tokens, amounts);
        }
        (tokens, amounts) = IBaseFeesCollector(feesCollector).collectFeesData(vault);
    }

    function calculateTvl(address vault) public view returns (uint256[] memory amounts) {
        if (IUniV3Vault(vault).supportsInterface(type(IUniV3Vault).interfaceId)) {
            IUniswapV3Pool pool = IUniswapV3Pool(address(IUniV3Vault(vault).pool()));
            (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
            amounts = new uint256[](2);
            (amounts[0], amounts[1]) = PositionValue.principal(
                positionManager,
                IUniV3Vault(vault).uniV3Nft(),
                sqrtRatioX96
            );
        } else {
            (amounts, ) = IERC20RootVault(vault).tvl();
        }
    }

    function collect(
        address vault,
        address user
    ) external view returns (Response memory response, address[] memory underlyingTokens) {
        (response.tvl, ) = IERC20RootVault(vault).tvl();

        uint256 numberOfSubvaults;
        {
            uint256[] memory subvaultNfts = IERC20RootVault(vault).subvaultNfts();
            numberOfSubvaults = subvaultNfts.length;
        }

        address[] memory tokens = IERC20RootVault(vault).vaultTokens();
        response.unclaimedFees = new uint256[](tokens.length);

        response.subvaultsTvl = new uint256[][](numberOfSubvaults);
        for (uint256 i = 0; i < numberOfSubvaults; i++) {
            address subvault = IERC20RootVault(vault).subvaultAt(i);
            response.subvaultsTvl[i] = calculateTvl(subvault);
            (address[] memory feesTokens, uint256[] memory amounts) = collectFeesData(subvault);
            for (uint256 j = 0; j < feesTokens.length; j++) {
                for (uint256 k = 0; k < tokens.length; k++) {
                    if (feesTokens[j] == tokens[k]) {
                        response.unclaimedFees[k] += amounts[j];
                        break;
                    }
                }
            }
        }
        underlyingTokens = IERC20RootVault(vault).vaultTokens();
        response.totalSupply = IERC20RootVault(vault).totalSupply();
        response.userBalance = IERC20RootVault(vault).balanceOf(user);
    }
}

