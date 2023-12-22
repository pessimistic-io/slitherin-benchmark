//SPDX License Identifier: MIT
pragma solidity ^0.8.19;

/**
                             ,
                            /|      __
                           / |   ,-~ /
                          Y :|  //  /
                          | jj /( .^
                          >-"~"-v"
                         /       Y
                        jo  o    |
                       ( ~T~     j
                        >._-' _./
                       /   "~"  |
                      Y     _,  |
                     /| ;-"~ _  l
                    / l/ ,-"~    \
                    \//\/      .- \
                     Y        /    Y   
                     l       I     !
                     ]\      _\    /"\
                    (" ~----( ~   Y.  )
                ~~~~~~~~~~~~~~~~~~~~~~~~~~

 _______          _       ______   ______   _____  _________  
|_   __ \        / \     |_   _ \ |_   _ \ |_   _||  _   _  | 
  | |__) |      / _ \      | |_) |  | |_) |  | |  |_/ | | \_| 
  |  __ /      / ___ \     |  __'.  |  __'.  | |      | |     
 _| |  \ \_  _/ /   \ \_  _| |__) |_| |__) |_| |_    _| |_    
|____| |___||____| |____||_______/|_______/|_____|  |_____|   
                                                              
    https://twitter.com/Karrot_gg 

 */

import "./ReentrancyGuard.sol";
import "./ERC721.sol";
import "./Math.sol";
import "./Ownable.sol";
import "./Strings.sol";
import "./KarrotInterfaces.sol";
import "./IRandomizer.sol";
import "./IERC20.sol";

/**
Rabbit: destroyer of $KARROT
- Non-transferrable ERC721
- Mintable by burning $KARROT
- Minted as one of 3 tiers: white, gold, diamond, which have different reward rates per attack for karrots in the stolen pool
- Each rabbit has 5 HP (can fail 5 attacks, each failed attack is -1 HP), and has a 50/50 chance of attack success
- When a rabbit loses all HP, it is burned
- Rabbits cannot be burned by the owner, but can be rerolled for the same price in karrots paid to mint
- 
 */

contract Rabbit is ERC721, Ownable, ReentrancyGuard {
    //================================================================================================
    // SETUP
    //================================================================================================

    string public baseURI = "https://bafybeicblns3rjbuqytxlh6rj6vv6isevkowtyoa7h6fitazvz5js4uxwy.ipfs.nftstorage.link/";

    IConfig public config;

    bool private isInitialized;
    bool public rabbitMintIsOpen;
    bool public rabbitAttackIsOpen;

    uint16 public constant PERCENTAGE_DENOMINATOR = 10000;
    uint32 public amountMinted;
    uint32 public startTimestamp;
    uint16 public rabbitBatchSize = 50;
    uint32 public rabbitMintSecondsBetweenBatches = 2 days;
    uint8 public rabbitMaxPerWallet = 3;
    uint256 public rabbitMintPriceInKarrots = 1500000000 * 1e18;
    uint32 public rabbitAttackCooldownSeconds = 8 hours;
    uint8 public rabbitAttackHpDeductionAmount = 1;

    uint256 public rabbitRerollPriceInKarrots = 1500000000 * 1e18; //price to reroll existing rabbit
    uint16 public rabbitMintKarrotFeePercentageToBurn = 9000; //90%
    uint16 public rabbitMintKarrotFeePercentageToTreasury = 1000; //10%
    uint16 public rabbitMintTier1Threshold = 6000; //60%
    uint16 public rabbitMintTier2Threshold = 3000; //30%, used as chance > tier1, chance <= tier1+tier2
    uint8 public rabbitTier1HP = 5; //number of survivable attacks
    uint8 public rabbitTier2HP = 5; //number of survivable attacks
    uint8 public rabbitTier3HP = 5; //number of survivable attacks
    uint16 public rabbitTier1HitRate = 5000; //50%
    uint16 public rabbitTier2HitRate = 5000; //50%
    uint16 public rabbitTier3HitRate = 5000; //50%
    uint16 public rabbitAttackHpDeductionThreshold = 7500; //75%

    uint24 public attackCallbackGasLimit = 10000000;
    uint24 public mintCallbackGasLimit = 10000000;
    uint32 public constant claimRequestTimeout = 15 minutes; 

    struct RabbitEntry {
        uint16 healthPoints;
        uint8 tier;
        uint32 lastAttackTimestamp;
        string tokenURI;
    }
    mapping(uint256 => RabbitEntry) public rabbits;
    // mapping(uint256 => uint256) public rabbitIdToHealthPoints;
    // mapping(uint256 => string) public tokenUri;
    mapping(address => uint256[]) public ownerToRabbitIds;
    // mapping(uint256 => uint256) public rabbitIdToTier;
    mapping(uint256 => uint256) public batchNumberToAmountMinted;
    // mapping(uint256 => uint256) public rabbitIdToLastAttackTimestamp;
    mapping(address => uint256) public userLastRequestTimestamp;
    mapping(address => bool) public rabbitMintRequestIsPending;
    mapping(uint256 => uint256) public batchNumberToNumRerolls; // used to expand number minted per batch for rerolls since one is being burned, i.e. mintable0 = 50, reroll, mintable1 = 51, but there are still 50 since 1 was burned. just so that rerolls can't be used to drain the batch.
    
    struct Request {
        address sender;
        bool isMint;
        uint8 numberMinted;
        uint32 lastAttackTimestamp;
        uint32 rabbitId;
        uint184 feePaid;
    }

    mapping(uint256 => Request) public requests;
    
    event RabbitMint(uint256 rabbitId, uint256 tier, uint256 healthPoints, address owner);
    event RabbitReroll(address owner, uint256 rabbitId);
    event RabbitHealthPointsUpdated(uint256 rabbitId, uint256 healthPoints);
    event AttackResult(uint256 rabbitId, address attackSender, string attackResult);
    event RandomizerCallback(uint256 requestId, bool isMint);

    error InsuffientFundsForRngRequest();
    error ForwardFailed();
    error CallerIsNotRandomizer();
    error RabbitsPerWalletLimitReached();
    error TisSoulbound();
    error EOAsOnly(address sender);
    error InsufficientKarrotsForRabbitMint();
    error MaxRabbitsMinted();
    error NoRabbitsOwned();
    error InvalidAttackVerdict(uint256 verdict);
    error InvalidTier(uint256 tier);
    error CallerIsNotConfig();
    error AttackOnCooldown();
    error RequestAlreadyPending();
    error MintIsClosed();
    error AttacksAreClosed();
    error RequestNotTimedOut();
    error UnauthorizedCaller(address caller);
    error InvalidAmount();
    error InvalidAddress();
    error NotOwnerOfRabbit();

    constructor(address _configManagerAddress) ERC721("Rabbit", "RBT") {
        config = IConfig(_configManagerAddress);
        startTimestamp = uint32(block.timestamp);
    }


    //================================================================================================
    // RANDOMIZER / COMMIT - REVEAL LOGIC
    //================================================================================================

    function randomizerCallback(uint256 _id, bytes32 _value) external {
        if (msg.sender != config.randomizerAddress()) {
            revert CallerIsNotRandomizer();
        }

        uint256 randomNumber = uint256(_value);
        IRandomizer randomizer = IRandomizer(config.randomizerAddress());
        Request storage request = requests[_id];

        emit RandomizerCallback(_id, request.isMint);

        if (request.isMint) {
            //mint rabbit with karrots
            _mintNRabbits(_id, randomNumber, request.numberMinted);
        } else {
            //attack stolen pool
            _completeAttack(_id, randomNumber);
        }
    }

    function previewMintResult(bytes32 _value) public view returns (uint256, uint256) {
        uint256 thisTier;
        uint256 thisHp;
        
        uint256 randomNumber = uint256(_value);
        uint256 randValMod = randomNumber % PERCENTAGE_DENOMINATOR;

        if (randValMod <= rabbitMintTier1Threshold) {
            thisTier = 1;
            thisHp = rabbitTier1HP;
        } else if (randValMod > rabbitMintTier1Threshold && randValMod <= rabbitMintTier1Threshold + rabbitMintTier2Threshold) {
            thisTier = 2;
            thisHp = rabbitTier2HP;
        } else {
            thisTier = 3;
            thisHp = rabbitTier3HP;
        }

        return (thisTier, thisHp);
    }

    function previewAttackResult(uint256 _rabbitId, bytes32 _value) public view returns (bool) {
        bool thisResult;
        uint256 hitRate;
        uint256 randomNumber = uint256(_value);
        uint256 randValMod = randomNumber % PERCENTAGE_DENOMINATOR;
        RabbitEntry storage rabbit = rabbits[_rabbitId];
        uint256 thisRabbitTier = rabbit.tier;

        if(thisRabbitTier == 1){
            hitRate = rabbitTier1HitRate;
        } else if(thisRabbitTier == 2){
            hitRate = rabbitTier2HitRate;
        } else if(thisRabbitTier == 3){
            hitRate = rabbitTier3HitRate;
        }

        if (randValMod <= hitRate) {
            thisResult = true;
        } else {
            thisResult = false;
        }

        return thisResult;
    }

    //================================================================================================
    // MINT + REROLL LOGIC
    //================================================================================================

    /**
    requestToMintRabbits:
        requires prior approval of this contract to spend user's $KARROT!
        3 Args:
            _amount: number of rabbits to mint
            _isReroll: true if this is a reroll, false if it's a new mint
            _idToBurn: if _isReroll is true, this is the rabbitId to burn
    */

    function requestToMintRabbits(uint8 _amount, bool _isReroll, uint256 _idToBurn) public payable nonReentrant returns (uint256) {

        uint256 requestFee;
        uint256 requestId;
        IKarrotsToken karrots = IKarrotsToken(config.karrotsAddress());

        //check if mint is open
        if (!rabbitMintIsOpen) {
            revert MintIsClosed();
        }

        //if reroll, add 1 to mintable supply to offset the reroll and burn the rabbit and remove it from relevant mappings (in _burnRabbit())

        if(_isReroll){
            if(ownerOf(_idToBurn) != msg.sender){
                revert NotOwnerOfRabbit();
            }
            ++batchNumberToNumRerolls[getBatchNumber()];
            _burnRabbit(_idToBurn);
            emit RabbitReroll(msg.sender, _idToBurn);
        }

        uint256 thisBatchNumber = getBatchNumber();
        // rabbit supply resets after each batch time has passed
        if (
            batchNumberToAmountMinted[thisBatchNumber] + _amount >
            rabbitBatchSize + batchNumberToNumRerolls[thisBatchNumber]
        ) {
            revert MaxRabbitsMinted();
        }

        // if user has a pending (not fulfilled) request for minting a rabbit, revert
        if (rabbitMintRequestIsPending[msg.sender]) {
            revert RequestAlreadyPending();
        } else {
            rabbitMintRequestIsPending[msg.sender] = true;
            userLastRequestTimestamp[msg.sender] = block.timestamp;
        }

        //add to this batch's amount minted for supply calculations
        batchNumberToAmountMinted[thisBatchNumber] += _amount;

        if (msg.sender != tx.origin && msg.sender != address(this)) {
            revert EOAsOnly(msg.sender);
        }

        //enforce max per wallet if not a reroll
        if (
            balanceOf(msg.sender) + _amount > rabbitMaxPerWallet &&
            !_isReroll
        ) {
            revert RabbitsPerWalletLimitReached();
        }

        uint256 mintTransactionKarrotsTotal;
        if(_isReroll){
            mintTransactionKarrotsTotal = rabbitRerollPriceInKarrots * _amount;
        } else {
            mintTransactionKarrotsTotal = rabbitMintPriceInKarrots * _amount;
        }

        if (karrots.balanceOf(msg.sender) < mintTransactionKarrotsTotal) {
            revert InsufficientKarrotsForRabbitMint();
        }

        IRandomizer randomizer = IRandomizer(config.randomizerAddress());

        uint256 amountToBurn = Math.mulDiv(
            mintTransactionKarrotsTotal,
            rabbitMintKarrotFeePercentageToBurn,
            PERCENTAGE_DENOMINATOR
        );

        uint256 amountToTreasury = Math.mulDiv(
            mintTransactionKarrotsTotal,
            rabbitMintKarrotFeePercentageToTreasury,
            PERCENTAGE_DENOMINATOR
        );

        karrots.transferFrom(msg.sender, address(this), mintTransactionKarrotsTotal);
        karrots.transfer(config.treasuryAddress(), amountToTreasury);
        karrots.burn(amountToBurn);

        //randomizer.ai logic with option to control number of required confirmations...

        requestFee = randomizer.estimateFee(mintCallbackGasLimit);
        if (msg.value < requestFee) {
            revert InsuffientFundsForRngRequest();
        }
        //transfer request fee funds to our 'subscription' on the randomizer contract
        randomizer.clientDeposit{value: msg.value}(address(this));
        requestId = randomizer.request(mintCallbackGasLimit);

        requests[requestId] = Request({
            sender: msg.sender,
            isMint: true,
            numberMinted: _amount,
            lastAttackTimestamp: 0,
            rabbitId: 0,
            feePaid: uint184(msg.value)
        });

        return requestId;
    }

    //------------------------------------------------------------------------------------------------
    // MINT / REROLL - RELATED CALLBACKS
    //------------------------------------------------------------------------------------------------

    function _mintNRabbits(uint256 _requestId, uint256 _randomNumber, uint256 _amount) private {
        address requestSender = requests[_requestId].sender;
        rabbitMintRequestIsPending[requestSender] = false;

        for (uint256 i = 0; i < _amount; i++) {
            uint256 newRandom = uint256(keccak256(abi.encode(_randomNumber, i)));
            _mintRabbit(_requestId, newRandom);
        }
    }

    function _mintRabbit(uint256 _requestId, uint256 _randomNumber) private {
        address recipient = requests[_requestId].sender;

        uint256 randValMod = _randomNumber % PERCENTAGE_DENOMINATOR;

        //important this is set before all variables are set so everything matches...this is also the token ID!
        // ++amountMinted;
        RabbitEntry storage rabbit = rabbits[++amountMinted];

        if (randValMod <= rabbitMintTier1Threshold) {
            rabbit.tier = 1;
            rabbit.healthPoints = rabbitTier1HP;
        } else if (randValMod > rabbitMintTier1Threshold && randValMod <= rabbitMintTier1Threshold + rabbitMintTier2Threshold) {
            rabbit.tier = 2;
            rabbit.healthPoints = rabbitTier2HP;
        } else {
            rabbit.tier = 3;
            rabbit.healthPoints = rabbitTier3HP;
        }

        //set the URI for this token according to the tier
        string memory thisTokenURI = string(
            abi.encodePacked(baseURI, Strings.toString(rabbit.tier), ".json")
        );

        rabbit.tokenURI = thisTokenURI;
        ownerToRabbitIds[recipient].push(amountMinted);

        _safeMint(recipient, amountMinted);

        emit RabbitMint(amountMinted, rabbit.tier, rabbit.healthPoints, recipient);
    }

    /**
        @dev burns rabbit nft, and removes it's corresponding entries in all related mappings and from the owner's array of owned rabbit ids...
        ...finds index in owned rabbit ids array corresponding to desired rabbit id, and replaces it with the last element in the array, then pops the last element
    */
    function _burnRabbit(uint256 _id) private {
        //remove rabbit ownerToRabbitIds mapping

        address owner = ownerOf(_id);
        uint256[] storage rabbitIds = ownerToRabbitIds[owner];

        if(rabbitIds.length == 0){
            revert NoRabbitsOwned();
        }

        if (rabbitIds.length == 1) {
            delete ownerToRabbitIds[owner];
        } else {
            uint256 rabbitIdIndex;
            for (uint256 i = 0; i < rabbitIds.length; i++) {
                if (rabbitIds[i] == _id) {
                    rabbitIdIndex = i;
                    break;
                }
            }

            rabbitIds[rabbitIdIndex] = rabbitIds[rabbitIds.length - 1];
            rabbitIds.pop();
        }

        delete rabbits[_id];

        _burn(_id);
    }

    //================================================================================================
    // ATTACK LOGIC
    //================================================================================================

    function requestAttack(uint32 _rabbitId) external payable nonReentrant returns (uint256) {
        // cant call if request is already pending
        // needs to have one rabbit in wallet to attack
        uint256 requestFee;
        uint256 requestId;

        if(ownerOf(_rabbitId) != msg.sender){
            revert NotOwnerOfRabbit();
        }

        if (!rabbitAttackIsOpen) {
            revert AttacksAreClosed();
        }

        // [!] check if caller is an EOA (optional - review)
        if (msg.sender != tx.origin) {
            revert EOAsOnly(msg.sender);
        }

        //enforce cooldown, set last attack timestamp at end of function with other mappings...
        RabbitEntry storage rabbit = rabbits[_rabbitId];
        if (
            rabbit.lastAttackTimestamp != 0 &&
            (rabbit.lastAttackTimestamp + rabbitAttackCooldownSeconds) > block.timestamp
        ) {
            revert AttackOnCooldown();
        }

        //randomizer.ai logic
        //randomizer.ai logic with option to control number of required confirmations...
        IRandomizer randomizer = IRandomizer(config.randomizerAddress());
        
        requestFee = randomizer.estimateFee(attackCallbackGasLimit);
        if (msg.value < requestFee) {
            revert InsuffientFundsForRngRequest();
        }
        //transfer request fee funds to our 'subscription' on the randomizer contract
        randomizer.clientDeposit{value: msg.value}(address(this));
        requestId = randomizer.request(attackCallbackGasLimit);
        
        requests[requestId] = Request({
            sender: msg.sender,
            isMint: false,
            numberMinted: 0,
            lastAttackTimestamp: uint32(block.timestamp),
            rabbitId: _rabbitId,
            feePaid: uint184(msg.value)
        });
        rabbit.lastAttackTimestamp = uint32(block.timestamp);

        return requestId;
    }

    //------------------------------------------------------------------------------------------------
    // ATTACK-RELATED PRIVATE FUNCTIONS
    //------------------------------------------------------------------------------------------------

    function _completeAttack(uint256 _requestId, uint256 _randomNumber) private {
        //reveal random number and perform attack

        //perform attack
        Request storage request = requests[_requestId];
        uint256 rabbitId = request.rabbitId;
        RabbitEntry storage rabbit = rabbits[rabbitId];

        uint256 verdict = _getAttackVerdict(_randomNumber, rabbit.tier);
        address attackSender = request.sender;

        //carry out actions based on attackVerdict / values defined above
        if (verdict == 1) {
            IStolenPool(config.karrotStolenPoolAddress()).attack(attackSender, rabbit.tier, rabbitId); //input what stolen pool needs to calculate attack size
            emit AttackResult(rabbitId, attackSender, "Attack succeeded. No HP Lost.");
        } else if (verdict == 2) {
            //subtract health points
            _manageRabbitHealthPoints(_requestId);
            emit AttackResult(rabbitId, attackSender, "Attack failed. 1 HP Lost.");
        } else {
            revert InvalidAttackVerdict(verdict);
        }
    }

    function _manageRabbitHealthPoints(uint256 _requestId) private {
        //subtract health points
        //if rabbit loses and reaches 0 health points, burn the rabbit
        //considers the tier of the rabbit by virtue of the higher tier rabbits having more hp.
        uint256 thisRabbitId = requests[_requestId].rabbitId;
        RabbitEntry storage rabbit = rabbits[thisRabbitId];

        rabbit.healthPoints -= rabbitAttackHpDeductionAmount;

        emit RabbitHealthPointsUpdated(thisRabbitId, rabbit.healthPoints);

        if (rabbit.healthPoints == 0) {
            _burnRabbit(thisRabbitId);
        }
    }

    function _getAttackVerdict(uint256 _randomNumber, uint256 _rabbitTier) private view returns (uint256) {

        uint256 verdict;

        //get our random number between 0 and 10000
        uint256 randValModAttackSuccess = _randomNumber % PERCENTAGE_DENOMINATOR;

        uint256 thisAttackSuccessThreshold;

        //get the attack success threshold for the rabbit's tier
        if (_rabbitTier == 1) {
            thisAttackSuccessThreshold = rabbitTier1HitRate;
        } else if (_rabbitTier == 2) {
            thisAttackSuccessThreshold = rabbitTier2HitRate;
        } else if (_rabbitTier == 3) {
            thisAttackSuccessThreshold = rabbitTier3HitRate;
        } else {
            revert InvalidTier(_rabbitTier);
        }

        // calculate verdict as 1-4 based on the random values and thresholds

        if (randValModAttackSuccess <= thisAttackSuccessThreshold) {
            verdict = 1;
        } else {
            verdict = 2;
        }
        
        return verdict;
    }

    //================================================================================================
    // PUBLIC GET FUNCTIONS FOR FRONTEND, ETC.
    //================================================================================================

    function rabbitIdToTier(uint256 _rabbitId) public view returns (uint256) {
        return rabbits[_rabbitId].tier;
    }

    function rabbitIdToHealthPoints(uint256 _rabbitId) public view returns (uint256) {
        return rabbits[_rabbitId].healthPoints;
    }
    
    function rabbitIdToLastAttackTimestamp(uint256 _rabbitId) public view returns (uint256) {
        return rabbits[_rabbitId].lastAttackTimestamp;
    }

    function getRabbitIdsByOwner(address _owner) public view returns (uint256[] memory) {
        return ownerToRabbitIds[_owner];
    }

    function getRabbitHealthPoints(uint256 _rabbitId) public view returns (uint256) {
        return rabbits[_rabbitId].healthPoints;
    }

    function getRabbitCooldownSecondsRemaining(uint256 _rabbitId) public view returns (uint256) {
        RabbitEntry storage rabbit = rabbits[_rabbitId];
        if(rabbit.lastAttackTimestamp == 0){
            return 0;
        } else {
            //this should never revert. if it does, it means the rabbitIdToLastAttackTimestamp[_rabbitId] is somehow in the future, which should be impossible
            return rabbitAttackCooldownSeconds > (block.timestamp - rabbit.lastAttackTimestamp) ? 
            rabbitAttackCooldownSeconds - (block.timestamp - rabbit.lastAttackTimestamp) : 
            0;
        }
    }

    function getSecondsUntilNextBatchStarts() public view returns (uint256) {
        //number of batches since start time
        uint256 numBatchesSincestartTimestamp = Math.mulDiv(
            (block.timestamp - startTimestamp),
            1,
            rabbitMintSecondsBetweenBatches
        );

        // get the number of seconds that have passed since the start of the last batch, then seconds until next batch starts
        uint256 secondsSinceLastBatchEnded = (block.timestamp - startTimestamp) -
            Math.mulDiv(numBatchesSincestartTimestamp, rabbitMintSecondsBetweenBatches, 1);
        uint256 secondsUntilNextBatchStarts = rabbitMintSecondsBetweenBatches - secondsSinceLastBatchEnded;

        return secondsUntilNextBatchStarts;
    }

    function getNumberOfRemainingMintableRabbits() public view returns (uint256) {
        uint256 batchNumber = getBatchNumber();
        return batchNumberToNumRerolls[batchNumber] + rabbitBatchSize - batchNumberToAmountMinted[batchNumber];
    }

    function getBatchNumber() public view returns (uint256) {
        // get number of batches that have passed since the first batch
        uint256 numBatchesSincestartTimestamp = Math.mulDiv(
            (block.timestamp - startTimestamp),
            1,
            rabbitMintSecondsBetweenBatches
        );

        return numBatchesSincestartTimestamp;
    }

    //================================================================================================
    // SETTERS (those not handled by the config manager contract via structs)
    //================================================================================================

    /// @dev unstuck failed claim request after presumed timeout
    function setPendingRequestToFalse() external nonReentrant {
        if(block.timestamp < userLastRequestTimestamp[msg.sender] + claimRequestTimeout){
            revert RequestNotTimedOut();
        }
        rabbitMintRequestIsPending[msg.sender] = false;
    }

    function setBaseUri(string memory _baseUri) external onlyOwner {
        baseURI = _baseUri;
    }

    function setConfigManagerAddress(address _configManagerAddress) external onlyOwner {
        config = IConfig(_configManagerAddress);
    }


    modifier onlyConfig() {
        if (msg.sender != address(config)) {
            revert CallerIsNotConfig();
        }
        _;
    }

    function setRabbitMintIsOpen(bool _rabbitMintIsOpen) external onlyConfig {
        rabbitMintIsOpen = _rabbitMintIsOpen;
    }

    function setRabbitBatchSize(uint16 _rabbitBatchSize) external onlyConfig{
        rabbitBatchSize = _rabbitBatchSize;
    }

    function setRabbitMintSecondsBetweenBatches(uint32 _rabbitMintSecondsBetweenBatches) external onlyConfig{
        rabbitMintSecondsBetweenBatches = _rabbitMintSecondsBetweenBatches;
    }

    function setRabbitMaxPerWallet(uint8 _rabbitMaxPerWallet) external onlyConfig {
        rabbitMaxPerWallet = _rabbitMaxPerWallet;
    }

    function setRabbitMintPriceInKarrots(uint256 _rabbitMintPriceInKarrots) external onlyOwner {
        rabbitMintPriceInKarrots = _rabbitMintPriceInKarrots;
    }

    function setRabbitRerollPriceInKarrots(uint256 _rabbitRerollPriceInkarrots) external onlyOwner {
        rabbitRerollPriceInKarrots = _rabbitRerollPriceInkarrots;
    }

    function setRabbitMintKarrotFeePercentageToBurn(uint16 _rabbitMintKarrotFeePercentageToBurn) external onlyConfig {
        rabbitMintKarrotFeePercentageToBurn = _rabbitMintKarrotFeePercentageToBurn;
    }

    function setRabbitMintKarrotFeePercentageToTreasury(uint16 _rabbitMintKarrotFeePercentageToTreasury) external onlyConfig {
        rabbitMintKarrotFeePercentageToTreasury = _rabbitMintKarrotFeePercentageToTreasury;
    }

    function setRabbitMintTier1Threshold(uint16 _rabbitMintTier1Threshold) external onlyConfig {
        rabbitMintTier1Threshold = _rabbitMintTier1Threshold;
    }

    function setRabbitMintTier2Threshold(uint16 _rabbitMintTier2Threshold) external onlyConfig {
        rabbitMintTier2Threshold = _rabbitMintTier2Threshold;
    }

    function setRabbitTier1HP(uint8 _rabbitTier1HP) external onlyConfig {
        rabbitTier1HP = _rabbitTier1HP;
    }

    function setRabbitTier2HP(uint8 _rabbitTier2HP) external onlyConfig {
        rabbitTier2HP = _rabbitTier2HP;
    }

    function setRabbitTier3HP(uint8 _rabbitTier3HP) external onlyConfig {
        rabbitTier3HP = _rabbitTier3HP;
    }

    function setRabbitTier1HitRate(uint16 _rabbitTier1HitRate) external onlyConfig {
        rabbitTier1HitRate = _rabbitTier1HitRate;
    }

    function setRabbitTier2HitRate(uint16 _rabbitTier2HitRate) external onlyConfig {
        rabbitTier2HitRate = _rabbitTier2HitRate;
    }

    function setRabbitTier3HitRate(uint16 _rabbitTier3HitRate) external onlyConfig {
        rabbitTier3HitRate = _rabbitTier3HitRate;
    }

    function setRabbitAttackIsOpen(bool _rabbitAttackIsOpen) external onlyConfig {
        rabbitAttackIsOpen = _rabbitAttackIsOpen;
    }

    function setAttackCooldownSeconds(uint32 _attackCooldownSeconds) external onlyConfig {
        rabbitAttackCooldownSeconds = _attackCooldownSeconds;
    }

    function setAttackHPDeductionAmount(uint8 _attackHPDeductionAmount) external onlyConfig {
        rabbitAttackHpDeductionAmount = _attackHPDeductionAmount;
    }

    function setAttackHPDeductionThreshold(uint16 _attackHPDeductionThreshold) external onlyConfig {
        rabbitAttackHpDeductionThreshold = _attackHPDeductionThreshold;
    }

    function setRandomizerMintCallbackGasLimit(uint24 _callbackGasLimit) external onlyConfig {
        mintCallbackGasLimit = _callbackGasLimit;
    }

    function setRandomizerAttackCallbackGasLimit(uint24 _callbackGasLimit) external onlyConfig {
        attackCallbackGasLimit = _callbackGasLimit;
    }

    //================================================================================================
    // ERC721 OVERRIDES
    //================================================================================================

    //erc721 overrides
    function safeTransferFrom(address from, address to, uint256 tokenId) public override {
        revert TisSoulbound();
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public override {
        revert TisSoulbound();
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        revert TisSoulbound();
    }
    
    //"just in case lol"
    function _transfer(address from, address to, uint256 tokenId) internal override {
        revert TisSoulbound();
    }

    // overrides with uri assigned based on tier
    function tokenURI(uint256 _id) public view override returns (string memory) {
        return rabbits[_id].tokenURI;
    }

    //=========================================================================
    // WITHDRAWALS
    //=========================================================================

    function randomizerWithdrawRabbit(address _to, uint256 _amount) external {
        if(msg.sender != address(config) && msg.sender != owner()){
            revert UnauthorizedCaller(msg.sender);
        }
        if(_to == address(0)){
            revert InvalidAddress();
        }
        IRandomizer randomizer = IRandomizer(config.randomizerAddress());
        (uint256 depositedBalance, ) = randomizer.clientBalanceOf(address(this));
        if(_amount > depositedBalance){
            revert InvalidAmount();
        }
        randomizer.clientWithdrawTo(_to, _amount);
    }

    function withdrawERC20FromContract(address _to, address _token) external onlyOwner {
        bool os = IERC20(_token).transfer(_to, IERC20(_token).balanceOf(address(this)));
        if (!os) {
            revert ForwardFailed();
        }
    }

    function withdrawEthFromContract() external onlyOwner {
        address out = config.treasuryAddress();
        require(out != address(0));
        (bool os, ) = payable(out).call{value: address(this).balance}("");
        if (!os) {
            revert ForwardFailed();
        }
    }
}

