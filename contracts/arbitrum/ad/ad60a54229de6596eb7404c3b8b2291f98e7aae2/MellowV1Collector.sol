// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20RootVault} from "./IERC20RootVault.sol";

import "./DefaultAccessControl.sol";
import "./IBaseCollector.sol";
import "./IBaseFeesCollector.sol";

contract MellowV1Collector is IBaseCollector, DefaultAccessControl {
    constructor(address owner) DefaultAccessControl(owner) {}

    mapping(address => address) public collectorForGovernance;

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
            (response.subvaultsTvl[i], ) = IERC20RootVault(subvault).tvl();
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

