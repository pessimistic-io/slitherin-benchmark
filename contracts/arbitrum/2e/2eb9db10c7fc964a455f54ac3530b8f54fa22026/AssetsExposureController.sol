// SPDX-License-Identifier: BUSL-1.1
// Last deployed from commit: ;
pragma solidity 0.8.17;

import "./IERC20Metadata.sol";
import "./ITokenManager.sol";
import "./IStakingPositions.sol";

//This path is updated during deployment
import "./DeploymentConstants.sol";

contract AssetsExposureController {

    function resetPrimeAccountAssetsExposure() external {
        bytes32[] memory ownedAssets = DeploymentConstants.getAllOwnedAssets();
        IStakingPositions.StakedPosition[] storage positions = DiamondStorageLib.stakedPositions();
        ITokenManager tokenManager = DeploymentConstants.getTokenManager();

        for(uint i=0; i<ownedAssets.length; i++){
            IERC20Metadata token = IERC20Metadata(tokenManager.getAssetAddress(ownedAssets[i], true));
            tokenManager.decreaseProtocolExposure(ownedAssets[i], token.balanceOf(address(this)) * 1e18 / 10**token.decimals());
        }
        for(uint i=0; i<positions.length; i++){
            (bool success, bytes memory result) = address(this).staticcall(abi.encodeWithSelector(positions[i].balanceSelector));
            if (success) {
                uint256 balance = abi.decode(result, (uint256));
                uint256 decimals = IERC20Metadata(tokenManager.getAssetAddress(positions[i].symbol, true)).decimals();
                tokenManager.decreaseProtocolExposure(positions[i].identifier, balance * 1e18 / 10**decimals);
            }
        }
    }

    function setPrimeAccountAssetsExposure() external {
        bytes32[] memory ownedAssets = DeploymentConstants.getAllOwnedAssets();
        IStakingPositions.StakedPosition[] storage positions = DiamondStorageLib.stakedPositions();
        ITokenManager tokenManager = DeploymentConstants.getTokenManager();

        for(uint i=0; i<ownedAssets.length; i++){
            IERC20Metadata token = IERC20Metadata(tokenManager.getAssetAddress(ownedAssets[i], true));
            tokenManager.increaseProtocolExposure(ownedAssets[i], token.balanceOf(address(this)) * 1e18 / 10**token.decimals());
        }
        for(uint i=0; i<positions.length; i++){
            (bool success, bytes memory result) = address(this).staticcall(abi.encodeWithSelector(positions[i].balanceSelector));
            if (success) {
                uint256 balance = abi.decode(result, (uint256));
                uint256 decimals = IERC20Metadata(tokenManager.getAssetAddress(positions[i].symbol, true)).decimals();
                tokenManager.increaseProtocolExposure(positions[i].identifier, balance * 1e18 / 10**decimals);
            }
        }
    }
}

