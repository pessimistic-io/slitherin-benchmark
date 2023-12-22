// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.7.0;
pragma experimental ABIEncoderV2;

import "./IERC777Recipient.sol";
import "./IERC777Sender.sol";
import "./IERC1820Registry.sol";
import "./ERC165.sol";
import "./SafeMath.sol";
import "./Math.sol";
import "./Context.sol";
import "./Address.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./ERC721Holder.sol";
import "./IERC721Receiver.sol";
import "./IFarmlandCollectible.sol";
import "./Manageable.sol";

/**
 * @dev Farmland - CropV2 Smart Contract
 */
contract L2Corn is Manageable, IERC777Recipient, IERC721Receiver, ERC165, ERC721Holder, ReentrancyGuard
 {

    /**
     * @dev Protect against overflows by using safe math operations (these are .add,.sub functions)
     */
    using SafeMath for uint256;

// MODIFIERS

    /**
     * @dev To limit one action per block per address when dealing with Land or Harvesting Crops
     */
    modifier preventSameBlock(address farmAddress) {
        require(
            ownerOfFarm[farmAddress].blockNumber != block.number &&
                ownerOfFarm[farmAddress].lastHarvestedBlockNumber != block.number,
            "You can not allocate/release or harvest in the same block"
        );
        _; // Call the actual code
    }

    /**
     * @dev To limit one action per block per address when dealing with Collectibles
     */
    modifier preventSameBlockCollectible(address farmAddress) {
        (,uint256 lastAddedBlockNumber) = getFarmCollectibleTotals(farmAddress);
        require(
            lastAddedBlockNumber != block.number,
            "You can not equip or release a collectible in the same block"
        );
        _; // Call the actual code
    }

    /**
     * @dev There must be a farm on this LAND to execute this function
     */
    modifier requireFarm(address farmAddress, bool requiredState) {
        if (requiredState) {
            require(
                ownerOfFarm[farmAddress].amount != 0,
                "You need to allocate land to grow crops on your farm"
            );
        } else {
            require(
                ownerOfFarm[farmAddress].amount == 0,
                "Ensure you release your land first"
            );
        }
        _; // Call the actual code
    }

    /**
      * @dev Decline some incoming transactions (Only allow crop smart contract to send/receive LAND)
      */
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata,
        bytes calldata
    ) external override {
        require(amount > 0,                             "You must receive a positive number of tokens");
        require(_msgSender() == address(landContract),  "You can only build farms on LAND");
        require(operator == address(this),              "Only CORN contract can send itself LAND tokens"); // Ensure someone doesn't send in some LAND to this contract by mistake (Only the contract itself can send itself LAND)
        require(to == address(this),                    "Funds must be coming into a CORN token");
        require(from != to,                             "Why would CORN contract send tokens to itself?");
    }

// STATE VARIABLES

    /**
     * @dev To register the contract with ERC1820 Registry
     */
    IERC1820Registry private constant ERC1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 private constant TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");
   
    /**
     * @dev 0.00000001 crops grown per block for each LAND allocated to a farm ... 10^18 / 10^8 = 10^10
     */
    uint256 private constant HARVEST_PER_BLOCK_DIVISOR = 10**8;

    /**
     * @dev To avoid small burn ratios we multiply the ratios by this number.
     */
    uint256 private constant RATIO_MULTIPLIER = 10**10;

    /**
     * @dev To get 4 decimals on our multipliers, we multiply all ratios & divide ratios by this number.
     * @dev This is done because we're using integers without any decimals.
     */
    uint256 private constant PERCENT_MULTIPLIER = 10000;

    /**
     * @dev PUBLIC: Create a mapping to the Farm Struct .. by making farms public we can access elements through the contract view (vs having to create methods)
     */
    mapping(address => Farm) public ownerOfFarm;

    /**
     * @dev PUBLIC: Create a mapping to the Collectible Struct.
     */
    mapping(address => Collectible[]) public ownerOfCollectibles;

// CONSTRUCTOR

    constructor(
        address[3] memory farmlandAddresses_,                                                                    // Load key contract addresses
        address[] memory farmAddresses_,                                                                        // Load Addresses that composted Corn on L1
        uint256[] memory composted_                                                                             // Load Amounts of Corn composted on L1
    ) 
        public
        nonReentrant
        ERC777 ("Corn", "CORN", new address[](0))                                                               // Define contract details
        {
            require(farmlandAddresses_.length == 3,                                                             "Invalid number of contract addresses");
            require(farmlandAddresses_[0] != address(0),                                                        "Invalid Land Contract address");
            require(farmlandAddresses_[1] != address(0),                                                        "Invalid Gateway Contract address");
            require(farmlandAddresses_[2] != address(0),                                                        "Invalid L1Corn Contract address");
            landContract = IERC777(farmlandAddresses_[0]);                                                      // Define the ERC777 Land Contract
            L2_GATEWAY = farmlandAddresses_[1];                                                                 // Set L2 Gateway address
            l1Address = farmlandAddresses_[2];                                                                  // Set the L1 Corn Address
            uint256 _length = farmAddresses_.length;                                                            // Set the amount of addresses to migrate from L1
            for(uint i = 0; i < _length; i++){                                                                  // Loop through all the addresses
                ownerOfFarm[farmAddresses_[i]].lastHarvestedBlockNumber = block.number;                         // Set the last harvest height to the current block
                ownerOfFarm[farmAddresses_[i]].compostedAmount = composted_[i];}                                // Set amount composted from L1
            _registerInterface(IERC721Receiver.onERC721Received.selector);                                      // Register the ERC721 receiver so we can utilise safeTransferFrom for NFTs
            ERC1820.setInterfaceImplementer(address(this),TOKENS_RECIPIENT_INTERFACE_HASH,address(this));       // Register the contract with ERC1820
            _mint(_msgSender(), 150000 * (10**18), "", "");                                                     // Add premine to provide initial liquidity
        }

// EVENTS

    event Allocated(address sender, uint256 blockNumber, address farmAddress, uint256 amount, uint256 burnedAmountIncrease);
    event Released(address sender, uint256 amount, uint256 burnedAmountDecrease);
    event Composted(address sender, address farmAddress, uint256 amount, uint256 bonus);
    event Harvested(address sender, uint256 blockNumber, address farmAddress, address targetAddress, uint256 targetBlock, uint256 amount);
    event CollectibleEquipped(address sender, uint256 blockNumber, uint256 TokenID, CollectibleType collectibleType);
    event CollectibleReleased(address sender, uint256 blockNumber, uint256 TokenID, CollectibleType collectibleType);

// SETTERS

    /**
     * @dev PUBLIC: Allocate LAND to farm for growing crops with the specified address as the harvester.
     */
    function allocate(address farmAddress, uint256 amount)
        external
        whenNotPaused
        nonReentrant
        preventSameBlock(_msgSender())
    {
        Farm storage farm = ownerOfFarm[_msgSender()];                                          // Shortcut accessor for the farm
        if ( farm.amount.add(amount) > maxFarmSizeWithoutFarmer &&                              // Check that with the additional Land farm size is within limits
             getFarmCollectibleTotalOfType(farmAddress,CollectibleType.Farmer)<1 ) {            // Check to see if theres a farmer on this farm
             revert(                                                                            "You need a farmer to build a farm this size");
        }
        if ( farm.amount.add(amount) > maxFarmSizeWithoutTractor &&                             // Check that with the additional Land farm size is within limits
             getFarmCollectibleTotalOfType(farmAddress,CollectibleType.Tractor)<1 ) {           // Check to see if theres a tractor on this farm
             revert(                                                                            "You need a farmer and a tractor to build a farm this size");
        }
       
        if (farm.amount == 0) {                                                                 // Check to see if there is LAND in the farm
            farm.amount = amount;                                                               // Stores the amount of LAND
            farm.blockNumber = block.number;                                                    // Block when farm first setup
            farm.harvesterAddress = farmAddress;                                                // Stores the farmers address
            globalCompostedAmount = globalCompostedAmount.add(farm.compostedAmount);            // retains any composted crops for returning farmers
            globalTotalFarms = globalTotalFarms.add(1);                                         // Increment the total farms counter
        } else {
            if ( getFarmCollectibleTotalOfType(farmAddress,CollectibleType.Farmer)>0 ) {        // Ensures that there is a farmer to increase the size of a farm
                farm.amount = farm.amount.add(amount);                                          // Adds additional LAND
            } else {
                revert(                                                                         "You need a farmer to increase the size of a farm");
            }
        }
        globalAllocatedAmount = globalAllocatedAmount.add(amount);                              // Adds the amount of Land to the global variable
        farm.lastHarvestedBlockNumber = block.number;                                           // Reset the last harvest height to the new LAND allocation height
        emit Allocated(_msgSender(), block.number, farmAddress, amount, farm.compostedAmount);  // Write an event to the chain
        IERC777(landContract).operatorSend(_msgSender(), address(this), amount, "", "" );       // Send [amount] of LAND token from the address that is calling this function to crop smart contract. [RE-ENTRANCY WARNING] external call, must be at the end
    }

    /**
     * @dev PUBLIC: Releasing a farm returns LAND to the owners
     */
    function release()
        external
        nonReentrant
        preventSameBlock(_msgSender())
        requireFarm(_msgSender(), true)                                                 // Ensure the address you are releasing has a farm on the LAND
    {
        Farm storage farm = ownerOfFarm[_msgSender()];                                  // Shortcut accessor
        uint256 amount = farm.amount;                                                   // Pull the farm size into a local variable to save gas
        farm.amount = 0;                                                                // Set the farm size to zero
        globalAllocatedAmount = globalAllocatedAmount.sub(amount);                      // Reduce the global Land variable
        globalCompostedAmount = globalCompostedAmount.sub(farm.compostedAmount);        // Reduce the global Crop composted
        globalTotalFarms = globalTotalFarms.sub(1);                                     // Reduce the global number of farms
        emit Released(_msgSender(), amount, farm.compostedAmount);                      // Write an event to the chain
        IERC777(landContract).send(_msgSender(), amount, "");                           // Send back the Land to person calling the function. [RE-ENTRANCY WARNING] external call, must be at the end
    }

    /**
     * @dev PUBLIC: Composting a crop fertilizes a farm at specific address
     */
    function compost(address farmAddress, uint256 amount)
        external
        whenNotPaused
        nonReentrant
        requireFarm(farmAddress, true)                                                  // Ensure the address you are composting to has a farm on the LAND
    {
        Farm storage farm = ownerOfFarm[farmAddress];                                   // Shortcut accessor
        uint256 bonusAmount = getCompostBonus(farmAddress, amount);                     // Get a composting bonus if you own a farmer or tractor
        farm.compostedAmount += amount.add(bonusAmount);                                // Update global Land variable
        globalCompostedAmount += amount.add(bonusAmount);                               // Update global composted amount variable
        emit Composted(_msgSender(), farmAddress, amount, bonusAmount);                 // Write an event to the chain
        _burn(_msgSender(), amount, "", "");                                            // Call the normal ERC-777 burn (this will destroy a crop token). We don't need to check address balance for amount because the internal burn does this check for us. [RE-ENTRANCY WARNING] external call, must be at the end
    }

    /**
     * @dev PUBLIC: Harvests crops from the Farm to a target address UP TO the target block (target address can be used to harvest to an alternative address)
     */
    function harvest(
        address farmAddress,
        address targetAddress,
        uint256 targetBlock
    )
        external
        whenNotPaused
        nonReentrant
        preventSameBlock(farmAddress)
        requireFarm(farmAddress, true)                                                              // Ensure the adress that is being harvested has a farm on the LAND
    {
        require(targetBlock <= block.number,                                                        "You can only harvest up to current block");
        Farm storage farm = ownerOfFarm[farmAddress];                                               // Shortcut accessor, pay attention to farmAddress here
        require(farm.lastHarvestedBlockNumber < targetBlock,                                        "You can only harvest ahead of last harvested block");
        require(farm.harvesterAddress == _msgSender(),                                              "You must be the owner of the farm to harvest");
        uint256 mintAmount = getHarvestAmount(farmAddress, targetBlock);                            // Get the amount to harvest and store in a local variable saves a little gas
        farm.lastHarvestedBlockNumber = targetBlock;                                                // Reset the last harvested height
        emit Harvested(_msgSender(),block.number,farmAddress,targetAddress,targetBlock,mintAmount); // Write an event to the chain
        _mint(targetAddress, mintAmount, "", "");                                                   // Call the normal ERC-777 mint (this will harvest crop tokens to targetAddress). [RE-ENTRANCY WARNING] external call, must be at the end
    }

    /**
     * @dev PUBLIC: Harvest & Compost in a single call for a farms with a farmer & tractor.
     */
    function directCompost(
        address farmAddress,
        uint256 targetBlock
    )   
        external
        whenNotPaused
        nonReentrant
        requireFarm(farmAddress, true)                                                  // Ensure the adress that is being harvested has a farm on the LAND
    {
        require(targetBlock <= block.number,                                            "You can only harvest & compost up to current block");
        require(getFarmCollectibleTotalOfType(farmAddress,CollectibleType.Tractor)>0 && 
                getFarmCollectibleTotalOfType(farmAddress,CollectibleType.Farmer)>0,    "You need a farmer & a tractor on this farm");
        Farm storage farm = ownerOfFarm[farmAddress];                                   // Shortcut accessor
        require(farm.lastHarvestedBlockNumber < targetBlock,                            "You can only harvest and compost ahead of last harvested block");
        require(farm.harvesterAddress == _msgSender(),                                  "You must be the owner of the farm to harvest and compost");
        uint256 amount = getHarvestAmount(farmAddress, targetBlock);                    // Pull the harvest amount into a local variable to save gas
        farm.lastHarvestedBlockNumber = targetBlock;                                    // Reset the last harvested height
        uint256 bonusAmount = getCompostBonus(farmAddress, amount);                     // Get a composting bonus if you own a farmer or tractor
        farm.compostedAmount += amount.add(bonusAmount);                                // Update global Land variable
        globalCompostedAmount += amount.add(bonusAmount);                               // Update global composted amount variable
        emit Composted(_msgSender(), farmAddress, amount, bonusAmount);                 // Write an event to the chain
    }

    /**
     * @dev PUBLIC: Add an NFT to the farm
     */
    function equipCollectible(uint256 tokenID, CollectibleType collectibleType)
        external
        whenNotPaused
        nonReentrant
        preventSameBlockCollectible(_msgSender())
        requireFarm(_msgSender(), true)                                                                                              // You can't add a collectible if you don't have a farm
        {
        Farm storage farm = ownerOfFarm[_msgSender()];                                                                               // Shortcut accessors for farm
        IFarmlandCollectible farmlandCollectible = IFarmlandCollectible(getNFTAddress(collectibleType));                               // Set the collectible contract based on collectible type
        farm.numberOfCollectibles = farm.numberOfCollectibles.add(1);                                                                // Increment number of collectibles owned by that address
        uint256 _maxBoostLevel;                                                                                                      // Initialise the max boost level variable
        (uint256 _expiry, uint256 _boostTrait,,,,) = farmlandCollectible.collectibleTraits(tokenID);                                 // Retrieve Collectible expiry & boost trait
        (string memory _uri) = farmlandCollectible.tokenURI(tokenID);                                                                // Retrieve Collectible URI
        if (collectibleType == CollectibleType.Farmer) {                                                                             // Check for farmer
            _maxBoostLevel = _boostTrait.mul(100).add(10000);                                                                        // Farmers stamina gives a boost of between 100% to 200%
        } else {
            _maxBoostLevel = _boostTrait.mul(100).div(4).add(5000);}                                                                 // Tractors power gives a boost of between 75% to 150%
        ownerOfCollectibles[_msgSender()].push(Collectible(tokenID, collectibleType, _maxBoostLevel, block.number, _expiry, _uri));  // Add details to Collectibles
        emit CollectibleEquipped(_msgSender(),block.number,tokenID,collectibleType);                                                 // Write an event to the chain
        IERC721(farmlandCollectible).safeTransferFrom(_msgSender(),address(this),tokenID);                                           // Receive the Collectibles from the address that is calling this function to crop smart contract. [RE-ENTRANCY WARNING] external call, must be at the end    
    }

    /**
     * @dev PUBLIC: Release an NFT from the farm
     */
    function releaseCollectible(uint256 index)
        external
        nonReentrant
        preventSameBlockCollectible(_msgSender())
        {
        Farm storage farm = ownerOfFarm[_msgSender()];                                                                                  // Shortcut accessors for farm
        require(farm.numberOfCollectibles != 0,                                                                                         "You need a collectible on your farm");
        Collectible memory collectible = ownerOfCollectibles[_msgSender()][index];                                                      // Shortcut accessors for collectibles
        CollectibleType collectibleType = collectible.collectibleType;                                                                  // Pull the collectible type into a local variable to save gas
        IFarmlandCollectible farmlandCollectible = IFarmlandCollectible(getNFTAddress(collectibleType));                                  // Set the collectible contract based on collectible type being released
        uint256 collectibleID = collectible.id;                                                                                         // Store the collectible id before its removed
        if ( farm.amount > maxFarmSizeWithoutFarmer &&                                                                                  // REVERT if the size of the farm is too large to release a farmer
             getFarmCollectibleTotalOfType(_msgSender(),CollectibleType.Farmer) < 2 &&                                                  // AND farm has only one farmer left
             collectibleType == CollectibleType.Farmer) {                                                                               // AND trying to release a farmer
             revert(                                                                                                                    "You need at least one farmer to run a farm this size");
        }
        if ( farm.amount > maxFarmSizeWithoutTractor &&                                                                                 // REVERT if the size of the farm is too large to release a tractor
             getFarmCollectibleTotalOfType(_msgSender(),CollectibleType.Tractor) < 2 &&                                                 // AND farm has only one tractor left
             collectibleType == CollectibleType.Tractor) {                                                                              // AND trying to release a tractor
             revert(                                                                                                                    "You need a farmer and a tractor to run a farm this size");
        }
        ownerOfCollectibles[_msgSender()][index] = ownerOfCollectibles[_msgSender()][ownerOfCollectibles[_msgSender()].length.sub(1)];  // In the farms collectible array swap the last item for the item being released
        ownerOfCollectibles[_msgSender()].pop();                                                                                        // Delete the final item in the farms collectible array
        farm.numberOfCollectibles = farm.numberOfCollectibles.sub(1);                                                                   // Update number of collectibles
        emit CollectibleReleased(_msgSender(),block.number,collectibleID,collectibleType);                                              // Write an event to the chain
        IERC721(farmlandCollectible).safeTransferFrom(address(this),_msgSender(),collectibleID);                                        // Return Collectible to the address that is calling this function. [RE-ENTRANCY WARNING] external call, must be at the end
    }

// GETTERS

    /**
     * @dev Return the amount available to harvest at a specific block by farm
     */
    function getHarvestAmount(address farmAddress, uint256 targetBlock)
        private
        view
        returns (uint256 availableToHarvest)
    {
        Farm memory farm = ownerOfFarm[farmAddress];                                                                                                 // Shortcut accessor for the farm
        uint256 amount = farm.amount;                                                                                                                // Grab the amount of LAND to save gas
        if (amount == 0) {return 0;}                                                                                                                 // Ensure this address has a farm on the LAND 
        require(targetBlock <= block.number,                                                                                                         "You can only calculate up to current block");
        require(farm.lastHarvestedBlockNumber <= targetBlock,                                                                                        "You can only specify blocks at or ahead of last harvested block");

        // Owning a farmer increase the length of the growth cycle
        uint256 _lastBlockInGrowthCycle;                                                                                                             // Initialise _lastBlockInGrowthCycle
        uint256 _blocksMinted;                                                                                                                       // Initiialise _blocksMinted
        if ( getFarmCollectibleTotalOfType(farmAddress, CollectibleType.Farmer) < 1 ) {                                                              // Check if the farm has a farmer
            _lastBlockInGrowthCycle = farm.lastHarvestedBlockNumber.add(maxGrowthCycle);                                                             // Calculate last block without a farmer
            _blocksMinted = maxGrowthCycle;                                                                                                          // Set the number of blocks that will be harvested if growing cycle completed
        } else {
            _lastBlockInGrowthCycle = farm.lastHarvestedBlockNumber.add(maxGrowthCycleWithFarmer);                                                   // Calculate last block with a farmer
            _blocksMinted = maxGrowthCycleWithFarmer;                                                                                                // Set the number of blocks that will be harvested if growing cycle completed .. longer with a farmer
        }
        if (targetBlock < _lastBlockInGrowthCycle) {                                                                                                 // Check if the growing cycle has completed
            _blocksMinted = targetBlock.sub(farm.lastHarvestedBlockNumber);                                                                          // Set the number of blocks that will be harvested if growing cycle not completed
        }

        uint256 _availableToHarvestBeforeBoosts = amount.mul(_blocksMinted);                                                                         // Calculate amount to harvest before boosts
        availableToHarvest = getTotalBoost(farmAddress).mul(_availableToHarvestBeforeBoosts).div(PERCENT_MULTIPLIER).div(HARVEST_PER_BLOCK_DIVISOR); // Adjust for boosts

    }

    /**
     * @dev Return a farms compost productivity boost for a specific address. This will be returned as PERCENT (10000x)
     */
    function getFarmCompostBoost(address farmAddress)
        private
        view
        returns (uint256 compostBoost)
    {
        uint256 myRatio = getAddressRatio(farmAddress);                                                                         // Sets the LAND/CROP burn ratio for a specific farm
        uint256 globalRatio = getGlobalRatio();                                                                                 // Sets the LAND/CROP global compost ratio
        if (globalRatio == 0 || myRatio == 0) {return PERCENT_MULTIPLIER;}                                                      // Avoid division by 0 & ensure 1x boost if nothing is locked
        compostBoost = Math.min(maxCompostBoost,myRatio.mul(PERCENT_MULTIPLIER).div(globalRatio).add(PERCENT_MULTIPLIER));      // The final multiplier is returned with PERCENT (10000x) multiplication and needs to be divided by 10000 for final number. Min 1x, Max depends on the global maxCompostBoost attribute
    }

    /**
     * @dev Return a farms maturity boost for the farm at the address
     */
    function getFarmMaturityBoost(address farmAddress)
        private
        view
        returns (uint256 maturityBoost)
    {
        Farm memory farm = ownerOfFarm[farmAddress];                                            // Shortcut accessor
        uint256 _totalMaxBoost;                                                                 // Initialize local variable for max boost
        uint256 _targetBlockNumber;                                                             // Initialize local variable for target block number
        if ( farm.amount == 0 ) {return PERCENT_MULTIPLIER;}                                    // Ensure this address has a farm on the LAND
        if (farm.numberOfCollectibles > 0) {                                                    // Ensure there are collectibles and then pull the totals into local variables
            (_totalMaxBoost, _targetBlockNumber) = getFarmCollectibleTotals(farmAddress);       // Sets the collectible boost & the starting block to when the last collectible was added. So adding a collectible restarts the maturity boost counter.
        } else {
            _targetBlockNumber = farm.blockNumber;                                              // If there are no collectibles it sets the starting block to when the farm is built
        }
        _totalMaxBoost = _totalMaxBoost.add(maxMaturityBoost);                                  // Calculate the combined collectible & maturity boost
        if ( _totalMaxBoost > maxMaturityCollectibleBoost ) {                                   // Checks the Maturity Collectible boost doesn't exceed the maximum   
            _totalMaxBoost = maxMaturityCollectibleBoost;                                       // if it does set it to the maximum boost
        }
        uint256 _boostExtension = _totalMaxBoost.sub(PERCENT_MULTIPLIER);                       // Calculates the boost extension by removing 10000 from the totalmaxboost; i.e., the extension over and above 1x e.g., the 2x to get to a 3x boost
        uint256 _blockDiff = block.number.sub(_targetBlockNumber)
                            .mul(_boostExtension).div(endMaturityBoost).add(PERCENT_MULTIPLIER);// Calculate the Min before farm maturity starts to increment, stops maturity boost at max ~ the function returns PERCENT (10000x) the multiplier for 4 decimal accuracy
        maturityBoost = Math.min(_totalMaxBoost, _blockDiff);                                   // returm the maturity boost .. Min 1x, Max depends on the boostExtension attribute 
    }

    /**
     * @dev Return a farms total boost
     */
    function getTotalBoost(address farmAddress)
        private
        view
        returns (
            uint256 totalBoost
        )
    {
        uint256 _maturityBoost = getFarmMaturityBoost(farmAddress);                             // Get the farms Maturity Boost
        uint256 _compostBoost = getFarmCompostBoost(farmAddress);                               // Get the farms Compost Boost        
        totalBoost = _compostBoost.mul(_maturityBoost).div(PERCENT_MULTIPLIER);                 // Maturity & Collectible boosts are combined & multiplied by the Compost boost to return the total boost. Ensuring that when both collectible and maturity are 10000, that the combined total 10000 and not 20000.
    }

    /**
     * @dev Return the compost bonus
     */
    function getCompostBonus(address farmAddress, uint256 amount)
        private
        view
        returns (
            uint256 compostBonus
        )
    {
        if ( getFarmCollectibleTotalOfType(farmAddress,CollectibleType.Farmer) >0 ){
            compostBonus = bonusCompostBoostWithFarmer.mul(amount).div(PERCENT_MULTIPLIER);  // If theres a farmer running this farm, add an additional 10%
        }
        if ( getFarmCollectibleTotalOfType(farmAddress,CollectibleType.Tractor) >0 ){
            compostBonus = bonusCompostBoostWithTractor.mul(amount).div(PERCENT_MULTIPLIER); // If theres a tractor on this farm, add an additional 20%
        }
    }

    /**
     * @dev PUBLIC: Get NFT contract address based on the collectible type
     */
    function getNFTAddress(CollectibleType collectibleType)
        internal
        view
        returns (address payable collectibleAddress)
    {
        if (collectibleType == CollectibleType.Farmer) {
            collectibleAddress = farmerNFTAddress;      // returns the Farmer NFT contract address
        } else {
            collectibleAddress = tractorNFTAddress;     // returns the Tractor NFT contract address
        }
    }

    /**
     * @dev PUBLIC: Return the combined totals associated with Collectibles on a farm
     */
    function getFarmCollectibleTotals(address farmAddress)
        public
        view
        returns (
            uint256 totalMaxBoost,
            uint256 lastAddedBlockNumber
            )
    {
        uint256 _total = ownerOfCollectibles[farmAddress].length;                                       // Store the total number of collectibles on a farm in a local variable
        bool _expired = false;                                                                          // Initialize the expired local variable as false
        uint256 _expiry;                                                                                // Initialize a local variable to hold the expiry
        uint256 _addedBlockNumber;                                                                      // Initialize a local variable to hold the block number each collectible was added
        for (uint i = 0; i < _total; i++) {                                                             // Loop through all the collectibles on this farm
            _expiry = ownerOfCollectibles[farmAddress][i].expiry;                                       // Store the collectibles expiry in a local variable
            _addedBlockNumber = ownerOfCollectibles[farmAddress][i].addedBlockNumber;                   // Store the block the collectibles was added in a local variable
            if (_expiry == 0 ) {                                                                        // If expiry is zero
                _expired = false;                                                                       // Then this collectible has not expired
            } else {
                if ( block.timestamp > _expiry ) {                                                      // If the current blocks timestamp is greater than the expiry
                    _expired = true;                                                                    // Then this collectible has expired
                }
            }
            if ( !_expired ) {                                                                          // Only count collectibles that have not already expired
                totalMaxBoost = totalMaxBoost.add(ownerOfCollectibles[farmAddress][i].maxBoostLevel);   // Add all the individual collectible boosts to get the total collectible boost
                if ( lastAddedBlockNumber < _addedBlockNumber) {                                      
                    lastAddedBlockNumber = _addedBlockNumber;                                           // Store the block number of latest collectible added to the farm
                }
            }
        }
    }

    /**
     * @dev PUBLIC: Returns total number of a collectible type found on a farm
     */
    function getFarmCollectibleTotalOfType(address farmAddress, CollectibleType collectibleType)
        public
        view
        returns (
            uint256 ownsCollectibleTotal
            )
    {
        uint256 _total = ownerOfCollectibles[farmAddress].length;                                       // Store the total number of collectibles on a farm in a local variable
        for (uint i = 0; i < _total; i++) {
            if ( ownerOfCollectibles[farmAddress][i].collectibleType == collectibleType ) {             // Check if collectible type is found on the farm
                ownsCollectibleTotal = ownsCollectibleTotal.add(1);                                     // If it is then add it to the return variable
            }
        }
    }

    /**
     * @dev PUBLIC: Return array of collectibles on a farm
     */
    function getCollectiblesByFarm(address farmAddress)
        external
        view
        returns (
            Collectible[] memory farmCollectibles                                                        // Define the array of collectibles to be returned. Requires ABIEncoderV2.
        )
    {
        uint256 _total = ownerOfCollectibles[farmAddress].length;                                        // Store the total number of collectibles on a farm in a local variable
        Collectible[] memory _collectibles = new Collectible[](_total);                                  // Initialize an array to store all the collectibles on the farm
        for (uint i = 0; i < _total; i++) {                                                              // Loop through the collectibles
            _collectibles[i].id = ownerOfCollectibles[farmAddress][i].id;                                // Add the id to the array
            _collectibles[i].collectibleType = ownerOfCollectibles[farmAddress][i].collectibleType;      // Add the colectible type to the array
            _collectibles[i].maxBoostLevel = ownerOfCollectibles[farmAddress][i].maxBoostLevel;          // Add the maxboostlevel to the array
            _collectibles[i].addedBlockNumber = ownerOfCollectibles[farmAddress][i].addedBlockNumber;    // Add the blocknumber the collectible was added to the array
            _collectibles[i].expiry = ownerOfCollectibles[farmAddress][i].expiry;                        // Add the expiry to the array
            _collectibles[i].uri = ownerOfCollectibles[farmAddress][i].uri;                              // Add the token URI
        }
        return _collectibles;                                                                            // Return the array of collectibles on the farm
    }

    /**
     * @dev Return LAND/CROP burn ratio for a specific farm
     */
    function getAddressRatio(address farmAddress)
        private
        view
        returns (uint256 myRatio)
    {
        Farm memory farm = ownerOfFarm[farmAddress];                                                    // Shortcut accessor of the farm
        uint256 _addressLockedAmount = farm.amount;                                                     // Intialize and store the amount of Land on this farm
        if (_addressLockedAmount == 0) { return 0; }                                                    // If you haven't harvested or composted anything then you get the default 1x boost
        myRatio = farm.compostedAmount.mul(RATIO_MULTIPLIER).div(_addressLockedAmount);                 // Compost/Maturity ratios for both address & network, multiplying both ratios by the ratio multiplier before dividing for tiny CROP/LAND burn ratios.
    }

    /**
     * @dev Return LAND/CROP compost ratio for global (entire network)
     */
    function getGlobalRatio() 
        private
        view
        returns (uint256 globalRatio) 
    {
        if (globalAllocatedAmount == 0) { return 0; }                                                     // If you haven't harvested or composted anything then you get the default 1x multiplier
        globalRatio = globalCompostedAmount.mul(RATIO_MULTIPLIER).div(globalAllocatedAmount);             // Compost/Maturity for both address & network, multiplying both ratios by the ratio multiplier before dividing for tiny CROP/LAND burn ratios.
    }

    /**
     * @dev PUBLIC: Return a collection of data associated with an farm
     */
    function getAddressDetails(address farmAddress)
        external
        view
        returns (
            uint256 blockNumber,
            uint256 cropBalance,
            uint256 cropAvailableToHarvest,
            uint256 farmMaturityBoost,
            uint256 farmCompostBoost,
            uint256 farmTotalBoost
        )
    {
        blockNumber = block.number;                                                         // return the current block number
        cropBalance = balanceOf(farmAddress);                                               // return the Crop balance
        cropAvailableToHarvest = getHarvestAmount(farmAddress, block.number);               // return the Crop available to harvest
        farmMaturityBoost = getFarmMaturityBoost(farmAddress);                              // return the Maturity boost
        farmCompostBoost = getFarmCompostBoost(farmAddress);                                // return the Compost boost
        farmTotalBoost = getTotalBoost(farmAddress);                                        // return the Total boost
    }
}
