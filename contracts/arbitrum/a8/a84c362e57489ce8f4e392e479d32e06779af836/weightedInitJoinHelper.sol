// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;
import "./IVault.sol";
import "./IWeightedPoolFactoryV4.sol";
import "./IWeightedPool.sol";




/**
 * @title The WeightedPool v4 create and join helper
 * @author tritium.eth
 * @notice This contract attempts to make creating and initjoining a pool easier from etherscan
 */
contract WeightedPoolInitHelper {
    IVault public immutable vault;
    IWeightedPoolFactoryV4 public immutable factory;
    address public constant DAO = 0xBA1BA1ba1BA1bA1bA1Ba1BA1ba1BA1bA1ba1ba1B;

    constructor(IVault _vault, IWeightedPoolFactoryV4 _factory) {
        vault = _vault;
        factory = _factory;
    }


    /**
     * @notice Easy Creation of a V4 weighted pool - using the factory directly saves a little gas
     * @param name The Long Name of the pool token - Normally like Balancer B-33WETH-33WBTC-34USDC Token
     * @param symbol The symbol - Normally like B-33WETH-33WBTC-34USDC
     * @param tokens An list of token addresses in the pool in ascending order (from 0 to f) - check the read functions
     * @param weightsFrom100 A list of token weights in percentage points ordered by the token addresses above (adds up to 100)
     * @param rateProviders An ordered list of rateProviders using zero addresses where there is none, or an empty array [] to autofill zeros for all rate providers.
     * @param amountsPerToken An ordered list of amounts (wei denominated) of tokens for the initial deposit.  This will define opening prices. You  must have open approvals for each token to the vault.
     * @param swapFeeBPS The swap fee expressed in basis ponts from 1 to 1000 (0.01 - 10%)
     * @return The address of the created pool
    */
    function createAndJoinWeightedPool(
        string memory name,
        string memory symbol,
        address[] memory tokens,
        address[] memory rateProviders,
        uint256[] memory amountsPerToken,
        uint256[] memory  weightsFrom100,
        uint256 swapFeeBPS
    ) public returns (address) {
        address poolAddress = createWeightedPool(name, symbol, tokens, rateProviders,  weightsFrom100, swapFeeBPS);
        IWeightedPool pool = IWeightedPool(poolAddress);
        bytes32 poolId = pool.getPoolId();
        initJoinWeightedPool(poolId, tokens, amountsPerToken);
        return poolAddress;
    }

    /**
      * @notice Init Joins an empty pool to set the starting price
     * @param poolId the pool id of the pool to init join
     * @param tokenAddresses a list of all the tokens in the pool, sorted from lowest to highest (0 to F)
     * @param amountsPerToken a list of amounts such that a matching index returns a token/amount pair
     */
    function initJoinWeightedPool(
        bytes32 poolId,
        address[] memory tokenAddresses,
        uint256[] memory amountsPerToken
    ) public {
        require(tokenAddresses.length == amountsPerToken.length, "Arrays of different length");
        IAsset[] memory tokens = toIAssetArray(tokenAddresses);

        // The 0 as the first argument represents an init join
        bytes memory userData = abi.encode(0, amountsPerToken);

        // Construct the JoinPoolRequest struct
        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: tokens,
            maxAmountsIn: amountsPerToken,
            userData: userData,
            fromInternalBalance: false
        });

        // Call the joinPool function
        for (uint8 i=0; i < tokenAddresses.length; i++) {
            IERC20 t = IERC20(tokenAddresses[i]);
            t.transferFrom(msg.sender, address(this), amountsPerToken[i]);
            t.approve(address(vault), amountsPerToken[i]);
        }
        vault.joinPool(poolId, address(this), msg.sender, request);
    }


    /**
      * @notice Easy Creation of a V4 weighted pool - using the factory directly saves a little gas
     * @param name The Long Name of the pool token - Normally like Balancer B-33WETH-33WBTC-34USDC Token
     * @param symbol The symbol - Normally like B-33WETH-33WBTC-34USDC
     * @param tokens An list of token addresses in the pool in ascending order (from 0 to f) - check the read functions
     * @param weightsFrom100 A list of token weights in percentage points ordered by the token addresses above (adds up to 100)
     * @param rateProviders A list of rateProviders using zero addresses where there is none, or an empty array [] to autofill zeros for all rate providers.
     * @param swapFeeBPS The swap fee expressed in basis ponts from 1 to 1000 (0.01 - 10%)
     * @return The address of the created pool
    */
    function createWeightedPool(
        string memory  name,
        string memory  symbol,
        address[] memory tokens,
        address[] memory rateProviders,
        uint256[] memory weightsFrom100,
        uint256 swapFeeBPS
    ) public returns (address) {
        // Check Stuff
        uint len = tokens.length;
        require(len < 8, "Weighted pools can support max 8 tokens");
        require(len == weightsFrom100.length, "weightsFrom 100 not same len as tokens");
        require(len == rateProviders.length || rateProviders.length == 0, "rateProviders  not same len as tokens");

        // Transform Weights
        uint256 totalWeight;
        uint256[] memory normalizedWeights = new uint256[](len);
        for (uint i=0; i < len; i++) {
            totalWeight += weightsFrom100[i];
            normalizedWeights[i] = weightsFrom100[i] * 10 **16;
        }
        require(totalWeight == 100, "Total Pool Weight does not add up to 100");

        // Replace empty array with zeroed out rate providers
        bool emptyRateProviders = rateProviders.length == 0;
        address[] memory RateProviders = new address[](len);
        if(!emptyRateProviders){
            RateProviders = rateProviders;
        }
        require(RateProviders.length == len);
        // Transform Fees
        require(swapFeeBPS >=1  && swapFeeBPS <= 1000, "Fees must be between 0.01%(1 BPS) and 10%(1000 BPS)");
        uint256 swapFeePercentage = swapFeeBPS * 10 ** 14;
        address poolAddress = factory.create(name, symbol, tokens, normalizedWeights, RateProviders, swapFeePercentage, DAO, 0);
        return poolAddress;
    }


    /**
     * @notice Converts an array of token addresses to an array of IAsset objects
     * @param tokenAddresses the array of token addresses to convert
     * @return the array of IAsset objects
     */
    function toIAssetArray(address[] memory tokenAddresses) private pure returns (IAsset[] memory) {
        IAsset[] memory assets = new IAsset[](tokenAddresses.length);
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            assets[i] = IAsset(tokenAddresses[i]);
        }
        return assets;
    }


    function sortAmountsByAddresses(address[] memory addresses, uint256[] memory amounts) public pure returns (address[] memory, uint256[] memory) {
    uint256 n = addresses.length;
    for (uint256 i = 0; i < n - 1; i++) {
        for (uint256 j = 0; j < n - i - 1; j++) {
            if (addresses[j] > addresses[j + 1]) {
                address tempAddress = addresses[j];
                addresses[j] = addresses[j + 1];
                addresses[j + 1] = tempAddress;
                uint256 tempAmount = amounts[j];
                amounts[j] = amounts[j + 1];
                amounts[j + 1] = tempAmount;
            }
        }
    }
    return (addresses, amounts);
    }

    function sortEverythingByAddresses(address[] memory addresses, address[] memory rateProviders, uint256[] memory amounts, uint256[] memory weights) public pure returns (address[] memory, uint256[] memory, uint256[] memory) {
    uint256 n = addresses.length;
    for (uint256 i = 0; i < n - 1; i++) {
        for (uint256 j = 0; j < n - i - 1; j++) {
            if (addresses[j] > addresses[j + 1]) {
                address tempAddress = addresses[j];
                addresses[j] = addresses[j + 1];
                addresses[j + 1] = tempAddress;
                uint256 tempAmount = amounts[j];
                amounts[j] = amounts[j + 1];
                amounts[j + 1] = tempAmount;
                uint256 tempWeight = weights[j];
                weights[j] = weights[j + 1];
                weights[j + 1] = tempWeight;
                address tempRateProvider = rateProviders[j];
                rateProviders[j] = rateProviders[j + 1];
                rateProviders[j + 1] = tempRateProvider;
            }
        }
    }
    return (addresses, amounts, weights);
    }
}





