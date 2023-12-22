// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.5.0;

/// @notice Manages the recording and creation of Numoen CFMM pairs and lending markets
/// @author Kyle Scott (https://github.com/numoen/core/blob/master/src/Factory.sol)
/// @author Modified from Uniswap (https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Factory.sol)
/// and Primitive (https://github.com/primitivefinance/rmm-core/blob/main/contracts/PrimitiveFactory.sol)
interface IFactory {
    /// @notice Returns the lendgine address for a given pair of tokens and upper bound
    /// @dev returns address 0 if it doesn't exist
    function getLendgine(
        address base,
        address speculative,
        uint256 baseScaleFactor,
        uint256 speculativeScaleFactor,
        uint256 upperBound
    ) external view returns (address lendgine);

    /// @notice Get the parameters to be used in constructing the lendgine and pair, set
    /// transiently during pool creation
    /// @dev Called by the pair constructor to fetch the parameters of the pair
    function pairParameters()
        external
        view
        returns (
            address lendgine,
            address base,
            address speculative,
            uint256 baseScaleFactor,
            uint256 speculativeScaleFactor,
            uint256 upperBound
        );

    /// @notice Pair address used to pass to the lendgine, set transiently during pool creation
    /// @dev Called by the lendgine constructor
    function pair() external view returns (address);

    /// @notice Deploys a lendgine contract by transiently setting the parameters storage slots
    /// and clearing it after the pool has been deployed
    function createLendgine(
        address base,
        address speculative,
        uint256 baseScaleFactor,
        uint256 speculativeScaleFactor,
        uint256 upperBound
    ) external returns (address, address);
}

