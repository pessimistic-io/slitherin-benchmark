// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./IVault.sol";
import "./InputHelpers.sol";


library PoolRegistrationLib {
    function registerPool(
        IVault vault,
        IVault.PoolSpecialization specialization,
        IERC20[] memory tokens
    ) internal returns (bytes32) {
        return registerPoolWithAssetManagers(vault, specialization, tokens, new address[](tokens.length));
    }

    function registerPoolWithAssetManagers(
        IVault vault,
        IVault.PoolSpecialization specialization,
        IERC20[] memory tokens,
        address[] memory assetManagers
    ) internal returns (bytes32) {
        // The Vault only requires the token list to be ordered for the Two Token Pools specialization. However,
        // to make the developer experience consistent, we are requiring this condition for all the native pools.
        //
        // Note that for Pools which can register and deregister tokens after deployment, this property may not hold
        // as tokens which are added to the Pool after deployment are always added to the end of the array.
        InputHelpers.ensureArrayIsSorted(tokens);

        return _registerPool(vault, specialization, tokens, assetManagers);
    }

    function registerComposablePool(
        IVault vault,
        IVault.PoolSpecialization specialization,
        IERC20[] memory tokens,
        address[] memory assetManagers
    ) internal returns (bytes32) {
        // The Vault only requires the token list to be ordered for the Two Token Pools specialization. However,
        // to make the developer experience consistent, we are requiring this condition for all the native pools.
        //
        // Note that for Pools which can register and deregister tokens after deployment, this property may not hold
        // as tokens which are added to the Pool after deployment are always added to the end of the array.
        InputHelpers.ensureArrayIsSorted(tokens);

        IERC20[] memory composableTokens = new IERC20[](tokens.length + 1);
        // We insert the Pool's BPT address into the first position.
        // This allows us to know the position of the BPT token in the tokens array without explicitly tracking it.
        // When deregistering a token, the token at the end of the array is moved into the index of the deregistered
        // token, changing its index. By placing BPT at the beginning of the tokens array we can be sure that its index
        // will never change unless it is deregistered itself (something which composable pools must prevent anyway).
        composableTokens[0] = IERC20(address(this));
        for (uint256 i = 0; i < tokens.length; i++) {
            composableTokens[i + 1] = tokens[i];
        }

        address[] memory composableAssetManagers = new address[](assetManagers.length + 1);
        // We do not allow an asset manager for the Pool's BPT.
        composableAssetManagers[0] = address(0);
        for (uint256 i = 0; i < assetManagers.length; i++) {
            composableAssetManagers[i + 1] = assetManagers[i];
        }
        return _registerPool(vault, specialization, composableTokens, composableAssetManagers);
    }

    function _registerPool(
        IVault vault,
        IVault.PoolSpecialization specialization,
        IERC20[] memory tokens,
        address[] memory assetManagers
    ) private returns (bytes32) {
        bytes32 poolId = vault.registerPool(specialization);

        // We don't need to check that tokens and assetManagers have the same length, since the Vault already performs
        // that check.
        vault.registerTokens(poolId, tokens, assetManagers);

        return poolId;
    }

    function registerToken(
        IVault vault,
        bytes32 poolId,
        IERC20 token,
        address assetManager
    ) internal {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = token;

        address[] memory assetManagers = new address[](1);
        assetManagers[0] = assetManager;

        vault.registerTokens(poolId, tokens, assetManagers);
    }

    function deregisterToken(
        IVault vault,
        bytes32 poolId,
        IERC20 token
    ) internal {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = token;

        vault.deregisterTokens(poolId, tokens);
    }
}
