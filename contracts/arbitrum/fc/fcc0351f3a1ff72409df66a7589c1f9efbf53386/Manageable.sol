// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.7.0;

import "./IERC777.sol";
import "./ERC777.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./IArbToken.sol";
import "./ICropV2.sol";

/**
 * @dev Farmland - Manageable
 */
abstract contract Manageable is ERC777, Ownable, Pausable, IArbToken
 {

// STATE VARIABLES

    /**
     * @dev Used to define the address of the L2 Custom Gateway
     */
    address public L2_GATEWAY;
    
    /**
     * @dev Defines the L1 Corn contract
     */
    address public override l1Address;

    /**
     * @dev This is the LAND contract address
     */
    IERC777 internal landContract;

    /**
     * @dev This is the Farmland Farmer NFT contract address
     */
    address payable farmerNFTAddress;

    /**
     * @dev This is the Farmland Tractor NFT contract address
     */
    address payable tractorNFTAddress;

    /**
     * @dev How many blocks before the maximum 3x farm maturity boost is reached ( Set to 28 days)
     */
    uint256 internal endMaturityBoost = 179200;

    /**
     * @dev This is the maximum number of blocks in each growth cycle ( around 7 days) before a harvest is required. After this many blocks crop will stop growing.
     */
    uint256 internal maxGrowthCycle = 44800;

    /**
     * @dev If you have a Farmer, this is the maximum number of blocks in each growth cycle ( around 14 days) before a harvest is required. After this many blocks crop will stop growing.
     */
    uint256 internal maxGrowthCycleWithFarmer = 89600;

    /**
     * @dev This is the farm's maximum 10x compost productivity boost. It's multiplicative with the maturity boost.
     */
    uint256 internal maxCompostBoost = 100000;

    /**
     * @dev This is the farm's maximum 3x maturity productivity boost.
     */
    uint256 internal maxMaturityBoost = 30000;

    /**
     * @dev This is the farm's maximum 8x maturity productivity boost.
     */
    uint256 internal maxMaturityCollectibleBoost = 100000;

    /**
     * @dev internal: Largest farm you can build without a farmer
     */
    uint256 internal maxFarmSizeWithoutFarmer = 15000 * (10**18);

    /**
     * @dev internal: Largest farm you can build without a farmer & a tractor
     */
    uint256 internal maxFarmSizeWithoutTractor = 100000 * (10**18);

    /**
     * @dev internal: 10% Compost boost with farmer
     */
    uint256 internal bonusCompostBoostWithFarmer = 1000;

    /**
     * @dev internal: 25% Compost boost with tractor
     */
    uint256 internal bonusCompostBoostWithTractor = 2500;

    /**
     * @dev internal: Store how much LAND is allocated to growing crops in farms globally
     */
    uint256 internal globalAllocatedAmount;

    /**
     * @dev internal: Store how much is crop has been composted globally (only from active farms on LAND addresses)
     */
    uint256 internal globalCompostedAmount;

    /**
     * @dev internal: Store how many addresses currently have an active farm
     */
    uint256 internal globalTotalFarms;

// MODIFIERS
    /**
     * @dev Only the L2 Gateway is allowed to perform this function
     */
    modifier onlyGateway {
        require(msg.sender == L2_GATEWAY, "ONLY_GATEWAY");
        _;
    }

//EVENTS

    event FarmlandVariablesSet( uint256 endMaturityBoost_, uint256 maxGrowthCycle_, uint256 maxGrowthCycleWithFarmer_, uint256 maxCompostBoost_, uint256 maxMaturityBoost_, uint256 maxMaturityCollectibleBoost_, uint256 maxFarmSizeWithoutFarmer_, uint256 maxFarmSizeWithoutTractor_, uint256 bonusCompostBoostWithFarmer_, uint256 bonusCompostBoostWithTractor_);

// SETTERS

    /**
     * @notice Mint tokens on L2. Callable path is L1Gateway depositToken (which handles L1 escrow), which triggers L2_GATEWAY, which calls this
     * @param account recipient of tokens
     * @param amount amount of tokens minted
     */
    function bridgeMint(address account, uint256 amount) external virtual override onlyGateway {
        bytes calldata _data;
        _mint(account, amount, _data, "");
    }

    /**
     * @notice Burn tokens on L2.
     * @dev only the token bridge can call this
     * @param account owner of tokens
     * @param amount amount of tokens burnt
     */
    function bridgeBurn(address account, uint256 amount) external virtual override onlyGateway {
        bytes calldata _data;
        _burn(account, amount, _data, "");
    }

    // Start or pause the contract
    function isPaused(bool value) public onlyOwner {
        if ( !value ) {
            _unpause();
        } else {
            _pause();
        }
    }

    // Enable changes to key Farmland variables
    function setFarmlandVariables(
            uint256 endMaturityBoost_,
            uint256 maxGrowthCycle_,
            uint256 maxGrowthCycleWithFarmer_,
            uint256 maxCompostBoost_,
            uint256 maxMaturityBoost_,
            uint256 maxMaturityCollectibleBoost_,
            uint256 maxFarmSizeWithoutFarmer_,
            uint256 maxFarmSizeWithoutTractor_,
            uint256 bonusCompostBoostWithFarmer_,
            uint256 bonusCompostBoostWithTractor_
        ) 
        external 
        onlyOwner
    {
        if ( endMaturityBoost_ > 0 && endMaturityBoost_ != endMaturityBoost ) {endMaturityBoost = endMaturityBoost_;}
        if ( maxGrowthCycle_ > 0 && maxGrowthCycle_ != maxGrowthCycle ) {maxGrowthCycle = maxGrowthCycle_;}
        if ( maxGrowthCycleWithFarmer_ > 0 && maxGrowthCycleWithFarmer_ != maxGrowthCycleWithFarmer ) {maxGrowthCycleWithFarmer = maxGrowthCycleWithFarmer_;}
        if ( maxCompostBoost_ > 0 && maxCompostBoost_ != maxCompostBoost ) {maxCompostBoost = maxCompostBoost_;}
        if ( maxMaturityBoost_ > 0 && maxMaturityBoost_ != maxMaturityBoost ) {maxMaturityBoost = maxMaturityBoost_;}
        if ( maxMaturityCollectibleBoost_ > 0 && maxMaturityCollectibleBoost_ != maxMaturityCollectibleBoost ) {maxMaturityCollectibleBoost = maxMaturityCollectibleBoost_;}
        if ( maxFarmSizeWithoutFarmer_ > 0 && maxFarmSizeWithoutFarmer_ != maxFarmSizeWithoutFarmer ) {maxFarmSizeWithoutFarmer = maxFarmSizeWithoutFarmer_;}
        if ( maxFarmSizeWithoutTractor_ > 0 && maxFarmSizeWithoutTractor_ != maxFarmSizeWithoutTractor ) {maxFarmSizeWithoutTractor = maxFarmSizeWithoutTractor_;}
        if ( bonusCompostBoostWithFarmer_ > 0 && bonusCompostBoostWithFarmer_ != bonusCompostBoostWithFarmer ) {bonusCompostBoostWithFarmer = bonusCompostBoostWithFarmer_;}
        if ( bonusCompostBoostWithTractor_ > 0 && bonusCompostBoostWithTractor_ != bonusCompostBoostWithTractor ) {bonusCompostBoostWithTractor = bonusCompostBoostWithTractor_;}
        emit FarmlandVariablesSet(endMaturityBoost_, maxGrowthCycle_, maxGrowthCycleWithFarmer_, maxCompostBoost_, maxMaturityBoost_, maxMaturityCollectibleBoost_, maxFarmSizeWithoutFarmer_, maxFarmSizeWithoutTractor_, bonusCompostBoostWithFarmer_, bonusCompostBoostWithTractor_);

    }

    // Enable changes to key Farmland addresses
    function setFarmlandAddresses(
            address landAddress_,
            address payable farmerNFTAddress_,
            address payable tractorNFTAddress_
        ) 
        external 
        onlyOwner
    {
        if ( landAddress_ != address(0) && landAddress_ != address(IERC777(landContract)) ) { landContract = IERC777(landAddress_);}
        if ( farmerNFTAddress_ != address(0) && farmerNFTAddress_ != farmerNFTAddress ) {farmerNFTAddress = farmerNFTAddress_;}
        if ( tractorNFTAddress_ != address(0) && tractorNFTAddress_ != tractorNFTAddress ) {tractorNFTAddress = tractorNFTAddress_;}
    }

// GETTERS

    /**
     * @dev PUBLIC: Get the key Farmland Variables
     */
    function getFarmlandVariables()
        external
        view
        returns (
            uint256 totalFarms,
            uint256 totalAllocatedAmount,
            uint256 totalCompostedAmount,
            uint256 maximumCompostBoost,
            uint256 maximumMaturityBoost,
            uint256 maximumGrowthCycle,
            uint256 maximumGrowthCycleWithFarmer,
            uint256 maximumMaturityCollectibleBoost,
            uint256 endMaturityBoostBlocks,
            uint256 maximumFarmSizeWithoutFarmer,
            uint256 maximumFarmSizeWithoutTractor,
            uint256 bonusCompostBoostWithAFarmer,
            uint256 bonusCompostBoostWithATractor
        )
    {
        return (
            globalTotalFarms,
            globalAllocatedAmount,
            globalCompostedAmount,
            maxCompostBoost,
            maxMaturityBoost,
            maxGrowthCycle,
            maxGrowthCycleWithFarmer,
            maxMaturityCollectibleBoost,
            endMaturityBoost,
            maxFarmSizeWithoutFarmer,
            maxFarmSizeWithoutTractor,
            bonusCompostBoostWithFarmer,
            bonusCompostBoostWithTractor
        );
    }

    /**
     * @dev PUBLIC: Get key Farmland addresses
     */
    function getFarmlandAddresses()
        external
        view
        returns (
                address,
                address,
                address,
                address,
                address
        )
    {
        return (
                farmerNFTAddress,
                tractorNFTAddress,
                l1Address,
                L2_GATEWAY,
                address(IERC777(landContract))

        );
    }
}

