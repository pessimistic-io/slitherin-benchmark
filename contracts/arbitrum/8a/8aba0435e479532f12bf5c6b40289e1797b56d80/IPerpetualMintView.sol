// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import { PerpetualMintInternal } from "./PerpetualMintInternal.sol";
import { TiersData, VRFConfig } from "./Storage.sol";

/// @title PerpetualMint facet contract
/// @dev contains all externally called functions
interface IPerpetualMintView {
    /// @notice Returns the current accrued consolation fees
    /// @return accruedFees the current amount of accrued consolation fees
    function accruedConsolationFees()
        external
        view
        returns (uint256 accruedFees);

    /// @notice returns the current accrued mint earnings across all collections
    /// @return accruedEarnings the current amount of accrued mint earnings across all collections
    function accruedMintEarnings()
        external
        view
        returns (uint256 accruedEarnings);

    /// @notice returns the current accrued protocol fees
    /// @return accruedFees the current amount of accrued protocol fees
    function accruedProtocolFees() external view returns (uint256 accruedFees);

    /// @notice returns the value of BASIS
    /// @return value BASIS value
    function BASIS() external pure returns (uint32 value);

    /// @notice Returns the current mint price for a collection
    /// @param collection address of collection
    /// @return mintPrice current collection mint price
    function collectionMintPrice(
        address collection
    ) external view returns (uint256 mintPrice);

    /// @notice Returns the current collection-wide risk of a collection
    /// @param collection address of collection
    /// @return risk value of collection-wide risk
    function collectionRisk(
        address collection
    ) external view returns (uint32 risk);

    /// @notice Returns the consolation fee in basis points
    /// @return consolationFeeBasisPoints consolation fee in basis points
    function consolationFeeBP()
        external
        view
        returns (uint32 consolationFeeBasisPoints);

    /// @notice Returns the default mint price for a collection
    /// @return mintPrice default collection mint price
    function defaultCollectionMintPrice()
        external
        pure
        returns (uint256 mintPrice);

    /// @notice Returns the default risk for a collection
    /// @return risk default collection risk
    function defaultCollectionRisk() external pure returns (uint32 risk);

    /// @notice Returns the default ETH to $MINT ratio
    /// @return ratio default ETH to $MINT ratio
    function defaultEthToMintRatio() external pure returns (uint32 ratio);

    /// @notice Returns the current ETH to $MINT ratio
    /// @return ratio current ETH to $MINT ratio
    function ethToMintRatio() external view returns (uint256 ratio);

    /// @notice Returns the mint fee in basis points
    /// @return mintFeeBasisPoints mint fee in basis points
    function mintFeeBP() external view returns (uint32 mintFeeBasisPoints);

    /// @notice Returns the address of the current $MINT token
    /// @return token address of the current $MINT token
    function mintToken() external view returns (address token);

    /// @notice returns the current redemption fee in basis points
    /// @return feeBP redemptionFee in basis points
    function redemptionFeeBP() external view returns (uint32 feeBP);

    /// @notice returns value of redeemPaused
    /// @return status boolean indicating whether redeeming is paused
    function redeemPaused() external view returns (bool status);

    /// @notice Returns the current $MINT consolation tiers
    function tiers() external view returns (TiersData memory tiersData);

    /// @notice returns the current VRF config
    /// @return config VRFConfig struct
    function vrfConfig() external view returns (VRFConfig memory config);

    /// @notice returns the current VRF subscription LINK balance threshold
    /// @return threshold VRF subscription balance threshold
    function vrfSubscriptionBalanceThreshold()
        external
        view
        returns (uint96 threshold);
}

