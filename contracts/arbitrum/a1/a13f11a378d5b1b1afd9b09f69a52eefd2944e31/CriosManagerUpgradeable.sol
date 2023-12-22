// SPDX-License-Identifier: UNLICENSED


pragma solidity ^0.8.11;

import "./OwnableUpgradeable.sol";
import "./ERC721Upgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./ERC721URIStorageUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./StringsUpgradeable.sol";
import "./Base64Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";

import "./OwnerRecoveryUpgradeable.sol";
import "./ZeusImplementationPointerUpgradeable.sol";
import "./LiquidityPoolManagerImplementationPointerUpgradeable.sol";

contract CriosManagerUpgradeable is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    OwnerRecoveryUpgradeable,
    ReentrancyGuardUpgradeable,
    ZeusImplementationPointerUpgradeable,
    LiquidityPoolManagerImplementationPointerUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;

    struct artifactInfoEntity {
        ArtifactEntity artifact;
        uint256 id;
        uint256 pendingRewards;
        uint256 rewardPerDay;
        uint256 compoundDelay;
        uint256 pendingRewardsGross;
        uint256 rewardPerDayGross;
    }

    struct ArtifactEntity {
        uint256 id;
        string name;
        uint256 creationTime;
        uint256 lastProcessingTimestamp;
        uint256 rewardMult;
        uint256 artifactValue;
        uint256 totalClaimed;
        bool exists;
        bool isMerged;
    }
    

    struct TierStorage {
        uint256 rewardMult;
        uint256 amountLockedInTier;
        bool exists;
    }

  struct Tier {
    uint32 level;
    uint32 slope;
    uint32 dailyAPR;
    uint32 claimFee;
    uint32 claimBurnFee;
    uint32 compoundFee;
    string name;
    string imageURI;
  }



    CountersUpgradeable.Counter private _artifactCounter;
    mapping(uint256 => ArtifactEntity) private _artifacts;
    mapping(uint256 => TierStorage) private _tierTracking;
    uint256[] _tiersTracked;

    bool public feesLive;
    uint256 public rewardPerDay;

    address private devWallet;


    uint256 public creationMinPrice;
    uint256 public compoundDelay;
    uint256 public processingFee;
    

    Tier[6] public artifacts;

    string public ipfsBaseURI;
   
    uint256 private constant ONE_DAY = 86400;
    uint256 public totalValueLocked;

    uint256 public burnedFromRenaming;
    uint256 public burnedFromMerging;



    function _onlyArtifactOwner() public {
        address sender = _msgSender();
        require(
            sender != address(0),
            "Artifacts: Can not be the zero address"
        );
        require(
            isOwnerOfArtifact(sender),
            "Artifacts: No Artifact owned by this account"
        );
    }

    modifier onlyArtifactOwner() {
         _onlyArtifactOwner();
        _;
    }


    function _checkPermissions(uint256 _artifactId) public {
         address sender = _msgSender();
        require(artifactExists(_artifactId), "Artifact: This artifact doesn't exist");
        require(
            isApprovedOrOwnerOfArtifact(sender, _artifactId),
            "Artifact: You do not have control over this artifact"
        );
    }



    modifier checkPermissions(uint256 _artifactId) {
        _checkPermissions(_artifactId);
        _;
    }


    function _checkPermissionsMultiple(uint256[] memory _artifactId) public {
            address sender = _msgSender();
        for (uint256 i = 0; i < _artifactId.length; i++) {
            require(
                artifactExists(_artifactId[i]),
                "artifact: This artifact doesn't exist"
            );
            require(
                isApprovedOrOwnerOfArtifact(sender, _artifactId[i]),
                "artifact: You do not control this artifact"
            );
        }
    }


    modifier checkPermissionsMultiple(uint256[] memory _artifactId) {
       _checkPermissionsMultiple(_artifactId);
        _;
    }



    function _verifyName(string memory artifactName) public {
        require(
            bytes(artifactName).length > 1 && bytes(artifactName).length < 32,
            "artifact: Incorrect name length, must be between 2 to 31"
        );
    }



    modifier verifyName(string memory artifactName) {
        _verifyName(artifactName);
        _;
    }




    event Compound(
        address indexed account,
        uint256 indexed artifactId,
        uint256 amountToCompound
    );
    event Cashout(
        address indexed account,
        uint256 indexed artifactId,
        uint256 rewardAmount
    );

    event CompoundAll(
        address indexed account,
        uint256[] indexed affectedArtifacts,
        uint256 amountToCompound
    );
    event CashoutAll(
        address indexed account,
        uint256[] indexed affectedArtifacts,
        uint256 rewardAmount
    );

    event Create(
        address indexed account,
        uint256 indexed newArtifactId,
        uint256 amount
    );

    event Rename(
        address indexed account,
        string indexed previousName,
        string indexed newName
    );

    event Merge(
        uint256[] indexed artifactIds,
        string indexed name,
        uint256 indexed previousTotalValue
    );

    function initialize() external initializer {
        __ERC721_init("Crios Ecosystem", "CRIOS");
        __Ownable_init();
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        feesLive = true;
        devWallet = 0x17628628f634B57556DF4E1F991A6864D2928F00;

        ipfsBaseURI = "ipfs://QmaUZoxcNHpaXDxkNi5SkvTBKnvJ27vGeQ96F7qThVEHco/";
    

        // Initialize contract
        changeNodeMinPrice(42_000 * (10**18)); // 42,000 CRIOS
        changeCompoundDelay(60); 

    

         Tier[6] memory _artifs = [

      Tier({
        level: 1000,
        slope: 1000,
        dailyAPR: 15,
        claimFee: 80,
        claimBurnFee: 0,
        compoundFee: 40,
        name: "Thor's Hammer",
        imageURI: string(abi.encodePacked(ipfsBaseURI, "Tier1.png"))
      }),
      Tier({
        level: 5000,
        slope: 1000,
        dailyAPR: 25,
        claimFee: 40,
        claimBurnFee: 0,
        compoundFee: 20,
        name: "Hermes's Boots",
        imageURI: string(abi.encodePacked(ipfsBaseURI, "Tier2.png"))
      }),
      Tier({
        level: 11000,
        slope: 1000,
        dailyAPR: 35,
        claimFee: 20,
        claimBurnFee: 0,
        compoundFee: 10,
        name: "Eros's Bow",
        imageURI: string(abi.encodePacked(ipfsBaseURI, "Tier3.png"))
      }),
      Tier({
        level: 19000,
        slope: 1000,     
        dailyAPR: 45,
        claimFee: 10,
        claimBurnFee: 0,
        compoundFee: 0,
        name: "Hades's Helmet",
        imageURI: string(abi.encodePacked(ipfsBaseURI, "Tier4.png"))
      }),
      Tier({
        level: 32000,
        slope: 1000,
        dailyAPR: 60,
        claimFee: 10,
        claimBurnFee: 0,
        compoundFee: 0,
        name: "Achile's Shield",
        imageURI: string(abi.encodePacked(ipfsBaseURI, "Tier5.png"))
      }),
      Tier({
        level: 50000,
        slope: 1000,
        dailyAPR: 70,
        claimFee: 0,
        claimBurnFee: 0,
        compoundFee: 0,
        name: "Zeus's Thunderbolt",
        imageURI: string(abi.encodePacked(ipfsBaseURI, "Tier6.png"))
      })
    ];

    changeTiers(_artifs);
        
    }

    function changeFeesLive(bool _feesLive) onlyOwner external{
        feesLive = _feesLive;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721URIStorageUpgradeable, ERC721Upgradeable)
        returns (string memory)
    {
          ArtifactEntity memory _artifact = _artifacts[tokenId];
        (uint256 tier, string memory _type, string memory image) = getTierMetadata(
        _artifact.rewardMult
        );

       bytes memory dataURI = abi.encodePacked(
      '{"name": "',
      _artifact.name,
      '", "image": "',
      image,
      '", "attributes": [',
      '{"trait_type": "tier", "value": "',
      StringsUpgradeable.toString(tier),
      '"}, {"trait_type": "type", "value": "',
      _type,
      '"}, {"trait_type": "tokens", "value": "',
      StringsUpgradeable.toString(_artifact.artifactValue / (10**18)),
      '"}]}'
    );


   return
      string(
        abi.encodePacked(
          "data:application/json;base64,",
          Base64Upgradeable.encode(dataURI)
        )
      );

    }


    function changeBaseURI(string memory _newBaseURI) public onlyOwner {
        ipfsBaseURI = _newBaseURI;
    }



    function renameArtifact(uint256 _artifactId, string memory artifactName)
        external
        nonReentrant
        onlyArtifactOwner
        checkPermissions(_artifactId)
        whenNotPaused
        verifyName(artifactName)
    {
        address account = _msgSender();
        ArtifactEntity storage artifact = _artifacts[_artifactId];
        require(artifact.artifactValue > 0, "Error: artifact is empty");
        (uint256 newArtifactValue, uint256 feeAmount) = getPercentageOf(
            artifact.artifactValue,
            1
        );
        logTier(artifact.rewardMult, -int256(feeAmount));
        burnedFromRenaming += feeAmount;
        artifact.artifactValue = newArtifactValue;
        string memory previousName = artifact.name;
        artifact.name = artifactName;
        emit Rename(account, previousName, artifactName);
    }



      function getTierMetadata(uint256 prevMult)
    private
    view
    returns (
      uint256,
      string memory,
      string memory
    )
  {
    (Tier memory tier, uint256 tierIndex) = getTier(prevMult);
    return (tierIndex + 1, tier.name, tier.imageURI);
  }



  
   function getTier(uint256 mult) public view returns (Tier memory, uint256) {
    Tier memory _artifact;
    for (int256 i = int256(artifacts.length - 1); i >= 0; i--) {
      _artifact = artifacts[uint256(i)];
      if (mult >= _artifact.level) {
        return (_artifact, uint256(i));
      }
    }
    return (_artifact, 0);
  }


   
    function createArtifactWithTokens(
        string memory artifactName,
        uint256 artifactValue
    ) public whenNotPaused verifyName(artifactName) returns (uint256) {
        address sender = _msgSender();
        require(
            artifactValue >= creationMinPrice,
            "artifacts: artifact value set below minimum"
        );
        require(
            isNameAvailable(sender, artifactName),
            "artifacts: Name not available"
        );
        require(
            zeus.balanceOf(sender) >= creationMinPrice,
            "artifacts: Balance too low for creation"
        );

        // Burn the tokens used to mint the NFT
        zeus.accountBurn(sender, artifactValue);

        // Increment the total number of tokens
        _artifactCounter.increment();

        uint256 newArtifactId = _artifactCounter.current();
        uint256 currentTime = block.timestamp;

        // Add this to the TVL
        totalValueLocked += artifactValue;
        logTier(artifacts[0].level, int256(artifactValue));

        // Add artifact
            _artifacts[newArtifactId] = ArtifactEntity({
            id: newArtifactId,
            name: artifactName,
            creationTime: currentTime,
            lastProcessingTimestamp: currentTime,
            rewardMult: artifacts[0].level,
            artifactValue: artifactValue,
            totalClaimed: 0,
            exists: true,
            isMerged: false
        });

        // Assign the artifact to this account
        _mint(sender, newArtifactId);

        emit Create(sender, newArtifactId, artifactValue);

        return newArtifactId;
    }

    function cashoutReward(uint256 _artifactId)
        external
        nonReentrant
        onlyArtifactOwner
        checkPermissions(_artifactId)
        whenNotPaused
    {
        address account = _msgSender();
        uint256 amountToReward = _getartifactCashoutRewards(_artifactId);
        _cashoutReward(amountToReward);

        emit Cashout(account, _artifactId, amountToReward);
    }

    function cashoutAll() external nonReentrant onlyArtifactOwner whenNotPaused {
        address account = _msgSender();
        uint256 rewardsTotal = 0;
        uint256[] memory artifactsOwned = getArtifactIdsOf(account);
        for (uint256 i = 0; i < artifactsOwned.length; i++) {
            uint256 amountToReward = _getartifactCashoutRewards(artifactsOwned[i]);
            rewardsTotal += amountToReward;
        }
        _cashoutReward(rewardsTotal);

        emit CashoutAll(account, artifactsOwned, rewardsTotal);
    }

    
    function compoundReward(uint256 _artifactId)
        public
        onlyArtifactOwner
        checkPermissions(_artifactId)
        whenNotPaused
    {
        address account = _msgSender();

        uint256 amountToCompound = _getArtifactCompoundRewards(_artifactId);
        require(
            amountToCompound > 0,
            "artifacts: You must wait until you can compound again"
        );
      
        zeus.liquidityReward(amountToCompound);
        emit Compound(account, _artifactId, amountToCompound);
    }



    function compoundAll() external nonReentrant onlyArtifactOwner whenNotPaused {
        address account = _msgSender();
        uint256 amountsToCompound = 0;
        uint256[] memory artifactsOwned = getArtifactIdsOf(account);
        uint256[] memory artifactsAffected = new uint256[](artifactsOwned.length);

        for (uint256 i = 0; i < artifactsOwned.length; i++) {
            uint256 amountToCompound = _getArtifactCompoundRewards(
                artifactsOwned[i]
            );
            if (amountToCompound > 0) {
                artifactsAffected[i] = artifactsOwned[i];
                amountsToCompound += amountToCompound;
            } else {
                delete artifactsAffected[i];
            }
        }

        require(amountsToCompound > 0, "artifacts: No rewards to compound");

        liquidityReward(amountsToCompound);

        emit CompoundAll(account, artifactsAffected, amountsToCompound);
    }



    // Private reward functions

    function _getartifactCashoutRewards(uint256 _artifactId)
        private
        returns (uint256)
    {
        ArtifactEntity storage artifact = _artifacts[_artifactId];

        if (!isProcessable(artifact)) {
            return 0;
        }

        uint256 reward = calculateReward(artifact);
        artifact.totalClaimed += reward;

        if (artifact.rewardMult != artifacts[0].level) {
            logTier(artifact.rewardMult, -int256(artifact.artifactValue));
            logTier(artifacts[0].level, int256(artifact.artifactValue));
        }

                (
        uint256 takeAsFeePercentage,
        uint256 burnFromFeePercentage
        ) = getCashoutDynamicFee(artifact.rewardMult);
        (uint256 amountToReward, uint256 takeAsFee) = getPercentageOf(
        reward,
        takeAsFeePercentage + burnFromFeePercentage
        );

        artifact.rewardMult = artifacts[0].level;
        artifact.lastProcessingTimestamp = block.timestamp;

        return reward;
    }



    function _getArtifactCompoundRewards(uint256 _artifactId)
        private
        returns (uint256)
    {
        ArtifactEntity storage artifact = _artifacts[_artifactId];

        if (!isProcessable(artifact)) {
            return 0;
        }

        uint256 reward = calculateReward(artifact);
        if (reward > 0) {


             uint256 compoundFee = getCompoundDynamicFee(artifact.rewardMult);
              (uint256 amountToCompound, uint256 feeAmount) = getPercentageOf(
              reward,
             compoundFee
             );

            totalValueLocked += amountToCompound;

            logTier(artifact.rewardMult, -int256(artifact.artifactValue));

            artifact.lastProcessingTimestamp = block.timestamp;
            artifact.artifactValue += amountToCompound;
            artifact.rewardMult += increaseMultiplier(artifact.rewardMult);

            logTier(artifact.rewardMult, int256(artifact.artifactValue));
        }
        return reward;
    }

    function _cashoutReward(uint256 amountToReward) private {
        require(
            amountToReward > 0,
            "artifacts: You don't have enough reward to cash out"
        );
        address to = _msgSender();
        zeus.accountReward(to, amountToReward);

        // Send the minted fee to the contract where liquidity will be added later on
        liquidityReward(amountToReward);
    }
    

    function _cashoutRewardNoFees(uint256 amountToReward) private {
        require(feesLive == false, 'Fees are live use function with fees');
        require(
            amountToReward > 0,
            "artifacts: You don't have enough reward to cash out"
        );
        address to = _msgSender();

        zeus.accountReward(to, amountToReward);

        // Send the minted fee to the contract where liquidity will be added later on
    
    }

    function logTier(uint256 mult, int256 amount) private {
        TierStorage storage tierStorage = _tierTracking[mult];
        if (tierStorage.exists) {
            require(
                tierStorage.rewardMult == mult,
                "artifacts: rewardMult does not match in TierStorage"
            );
            uint256 amountLockedInTier = uint256(
                int256(tierStorage.amountLockedInTier) + amount
            );
            require(
                amountLockedInTier >= 0,
                "artifacts: amountLockedInTier cannot underflow"
            );
            tierStorage.amountLockedInTier = amountLockedInTier;
        } else {
            // Tier isn't registered exist, register it
            require(
                amount > 0,
                "artifacts: Fatal error while creating new TierStorage. Amount cannot be below zero."
            );
            _tierTracking[mult] = TierStorage({
                rewardMult: mult,
                amountLockedInTier: uint256(amount),
                exists: true
            });
            _tiersTracked.push(mult);
        }
    }

    // Private view functions
    function getPercentageOf(uint256 rewardAmount, uint256 _feeAmount)
        private
        pure
        returns (uint256, uint256)
    {
        uint256 feeAmount = 0;
        if (_feeAmount > 0) {
            feeAmount = (rewardAmount * _feeAmount) / 100;
        }
        return (rewardAmount - feeAmount, feeAmount);
    }


    // function increaseMultiplier(uint256 prevMult)
    //     private
    //     view
    //     returns (uint256)
    // {
    //     if (prevMult >= tierLevel[5]) {
    //         return tierSlope[5];
    //     } else if (prevMult >= tierLevel[4]) {
    //         return tierSlope[4];
    //     } else if (prevMult >= tierLevel[3]) {
    //         return tierSlope[3];
    //     } else if (prevMult >= tierLevel[2]) {
    //         return tierSlope[2];
    //     } else if (prevMult >= tierLevel[1]) {
    //         return tierSlope[1];
    //     } else {
    //         return tierSlope[0];
    //     }
    // }


      function increaseMultiplier(uint256 prevMult) private view returns (uint256) {
    (Tier memory tier, ) = getTier(prevMult);
    return tier.slope;
  }



    function getTieredRevenues(uint256 mult) private view returns (uint256) {
    (Tier memory tier, ) = getTier(mult);
    return tier.dailyAPR;
  }


  function getCompoundDynamicFee(uint256 mult) private view returns (uint256) {
    (Tier memory tier, ) = getTier(mult);
    return (tier.compoundFee);
  }


      function getCashoutDynamicFee(uint256 mult)
    private
    view
    returns (uint256, uint256)
  {
    (Tier memory tier, ) = getTier(mult);
    return (tier.claimFee, tier.claimBurnFee);
  }


    function isProcessable(ArtifactEntity memory artifact)
        private
        view
        returns (bool)
    {
        return
            block.timestamp >= artifact.lastProcessingTimestamp + compoundDelay;
    }

    function calculateReward(ArtifactEntity memory artifact)
        private
        view
        returns (uint256)
    {
        return
            _calculateRewardsFromValue(
                artifact.artifactValue,
                artifact.rewardMult,
                block.timestamp - artifact.lastProcessingTimestamp
            );
    }

    function rewardPerDayFor(ArtifactEntity memory artifact)
        private
        view
        returns (uint256)
    {
        return
            _calculateRewardsFromValue(
                artifact.artifactValue,
                artifact.rewardMult,
                ONE_DAY
            );
    }

    function _calculateRewardsFromValue(
        uint256 _artifactValue,
        uint256 _rewardMult,
        uint256 _timeRewards
    ) private view returns (uint256) {
        uint256 numOfDays = ((_timeRewards * 1e10) / 1 days);
        uint256 yieldPerDay = getTieredRevenues(_rewardMult);
        return (numOfDays * yieldPerDay * _artifactValue) / (1000 * 1e10);

    }



    function artifactExists(uint256 _artifactId) private view returns (bool) {
        require(_artifactId > 0, "artifacts: Id must be higher than zero");
        ArtifactEntity memory artifact = _artifacts[_artifactId];
        if (artifact.exists) {
            return true;
        }
        return false;
    }



    // Public view functions

    function calculateTotalDailyEmission() external view returns (uint256) {
        uint256 dailyEmission = 0;
        for (uint256 i = 0; i < _tiersTracked.length; i++) {
            TierStorage memory tierStorage = _tierTracking[_tiersTracked[i]];
            dailyEmission += _calculateRewardsFromValue(
                tierStorage.amountLockedInTier,
                tierStorage.rewardMult,
                ONE_DAY
            );
        }
        return dailyEmission;
    }




    function isNameAvailable(address account, string memory artifactName)
        public
        view
        returns (bool)
    {
        uint256[] memory artifactsOwned = getArtifactIdsOf(account);
        for (uint256 i = 0; i < artifactsOwned.length; i++) {
            ArtifactEntity memory artifact = _artifacts[artifactsOwned[i]];
            if (keccak256(bytes(artifact.name)) == keccak256(bytes(artifactName))) {
                return false;
            }
        }
        return true;
    }



    function isOwnerOfArtifact(address account) public view returns (bool) {
        return balanceOf(account) > 0;
    }

    function isApprovedOrOwnerOfArtifact(address account, uint256 _artifactId)
        public
        view
        returns (bool)
    {
        return _isApprovedOrOwner(account, _artifactId);
    }

    function getArtifactIdsOf(address account)
        public
        view
        returns (uint256[] memory)
    {
        uint256 numberOfartifacts = balanceOf(account);
        uint256[] memory artifactIds = new uint256[](numberOfartifacts);
        for (uint256 i = 0; i < numberOfartifacts; i++) {
            uint256 artifactId = tokenOfOwnerByIndex(account, i);
            require(
                artifactExists(artifactId),
                "artifacts: This artifact doesn't exist"
            );
            artifactIds[i] = artifactId;
        }
        return artifactIds;
    }



    function getartifactsByIds(uint256[] memory _artifactIds)
        external
        view
        returns (artifactInfoEntity[] memory)
    {
        artifactInfoEntity[] memory artifactsInfo = new artifactInfoEntity[](
            _artifactIds.length
        );

        for (uint256 i = 0; i < _artifactIds.length; i++) {
            uint256 artifactId = _artifactIds[i];
            ArtifactEntity memory artifact = _artifacts[artifactId];

            // need to create function if dynamics fees 
            (
            uint256 takeAsFeePercentage,
            uint256 burnFromFeePercentage
            ) = getCashoutDynamicFee(artifact.rewardMult);

            uint256 pendingRewardsGross = calculateReward(artifact);
            uint256 rewardsPerDayGross = rewardPerDayFor(artifact);


                (uint256 amountToReward, ) = getPercentageOf(
            pendingRewardsGross,
            takeAsFeePercentage + burnFromFeePercentage
             );


            (uint256 amountToRewardDaily, ) = getPercentageOf(
            rewardsPerDayGross,
            takeAsFeePercentage + burnFromFeePercentage
             );
        

            artifactsInfo[i] = artifactInfoEntity(
                artifact,
                artifactId,
                amountToReward,
                amountToRewardDaily,
                compoundDelay,
                pendingRewardsGross,
                rewardsPerDayGross
            );

        }

        return artifactsInfo;
    }

    // Owner functions

    function changeNodeMinPrice(uint256 _creationMinPrice) public onlyOwner {
        require(
            _creationMinPrice > 0,
            "artifacts: Minimum price to create a artifact must be above 0"
        );
        creationMinPrice = _creationMinPrice;
    }

    function changeCompoundDelay(uint256 _compoundDelay) public onlyOwner {
        require(
            _compoundDelay > 0,
            "artifacts: compoundDelay must be greater than 0"
        );
        compoundDelay = _compoundDelay;
    }


  function changeTiers(Tier[6] memory _newArtifs) public onlyOwner {
    require(_newArtifs.length == 6, "Pyramids: new Tiers length has to be 6");
    for (uint256 i = 0; i < _newArtifs.length; i++) {
      artifacts[i] = _newArtifs[i];
    }
  }



    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function burn(uint256 _artifactId)
        external
        virtual
        nonReentrant
        onlyArtifactOwner
        whenNotPaused
        checkPermissions(_artifactId)
    {
        _burn(_artifactId);
    }


    function getBurnedFromServiceFees() external view returns (uint256) {
        return burnedFromRenaming + burnedFromMerging;
    }

    function liquidityReward(uint256 amountToReward) private {
        (, uint256 liquidityFee) = getPercentageOf(
            amountToReward,
            5 // Mint the 5% Treasury fee
        );
        zeus.liquidityReward(liquidityFee);
    }

    // Mandatory overrides
    function _burn(uint256 tokenId)
        internal
        override(ERC721URIStorageUpgradeable, ERC721Upgradeable)
    {
        ArtifactEntity storage artifact = _artifacts[tokenId];
        artifact.exists = false;
        logTier(artifact.rewardMult, -int256(artifact.artifactValue));
        ERC721Upgradeable._burn(tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount,
        uint256 batchSize
    )
        internal
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        whenNotPaused
    {
        super._beforeTokenTransfer(from, to, amount, batchSize);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
