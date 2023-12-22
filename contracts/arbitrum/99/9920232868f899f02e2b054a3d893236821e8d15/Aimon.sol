// SPDX-License-Identifier: MIT
pragma solidity 0.8.18; // highest hardhat-supported version of solidity at time of writing | https://hardhat.org/hardhat-runner/docs/reference/solidity-support

import "./ERC721ABurnableUpgradeable.sol";
import "./VRFCoordinatorV2Interface.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./StringsUpgradeable.sol";

contract AiMon is ERC721ABurnableUpgradeable, OwnableUpgradeable {
    using StringsUpgradeable for uint256;

    /****************************
     * VARIABLES *
     ***************************/

    uint256 public aiFee;
    uint256 public maxMint;
    IERC20Upgradeable public pmon;
    mapping(uint256 => uint256) public tokenIdToRandom;

    struct Creature {
        string species;
        string creatureType;
        uint16 guidance;
        uint16 denoising;
        uint32 steps;
    }

    // chainlink vrf related
    mapping(uint256 => uint256) public requestIdToStartId;
    uint32 public constant CALLBACK_GAS_LIMIT = 1_000_000;
    uint16 public constant REQUEST_CONFIRMATIONS = 10;
    VRFCoordinatorV2Interface public COORDINATOR;
    uint64 public s_subscriptionId;
    bytes32 public s_keyHash;

    uint256 public pmonFee;
    string public imageBaseUri;
    string public imageUnrevealedUri;

    uint256 public withdrawalDelay; // in seconds

    uint256 public startTokenId;

    /****************************
     * EVENTS *
     ***************************/

    event AiFeeChanged(uint256 AiFee);
    event MaxMintChanged(uint256 maxMint);
    event RandomWordsFulfilled(uint256 tokenId, uint256 randomness);
    event PmonFeeChanged(uint256 pmonFee);

    /****************************
     * ERRORS *
     ***************************/

    error OnlyCoordinatorCanFulfill(address have, address want);

    /****************************
     * CONSTRUCTOR *
     ***************************/

    function initialize(
        address _pmon,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId,
        uint256 _startTokenIdValue,
        uint256 _aiFee
    ) public initializerERC721A initializer {
        startTokenId = _startTokenIdValue;

        __ERC721A_init("Polychain Monsters Experimental", "AI1");
        __ERC721ABurnable_init();
        __Ownable_init();

        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        s_keyHash = _keyHash;
        s_subscriptionId = _subscriptionId;

        aiFee = _aiFee;
        pmonFee = 6 ether;
        maxMint = 10;
        pmon = IERC20Upgradeable(_pmon);

        withdrawalDelay = 1 days;
    }

    /****************************
     * PUBLIC WRITE FUNCTIONS *
     ***************************/

    // quantity is the number of packs; one pack has 3 mons
    function mintTo(uint8 quantity, address receiver) external payable {
        require(msg.value >= quantity * aiFee, "Not enough ETH sent");
        require(quantity * 3 <= maxMint, "Cannot mint more than maxMint");
        require(quantity > 0, "Cannot mint 0");

        uint256 startId = _nextTokenId();

        // we request the random numbers from chainlink
        uint256 requestId = _requestRandomWords(quantity * 3);
        requestIdToStartId[requestId] = startId;

        _mint(receiver, quantity * 3);

        pmon.transferFrom(msg.sender, address(this), quantity * pmonFee);
    }

    function reverseSwap(uint256 tokenId) external {
        // sender has to be owner of the token
        require(msg.sender == ownerOf(tokenId), "Only owner can reverse swap");

        // get the tokenOwnership of the token and the startTimestamp
        TokenOwnership memory tokenOwnership = _ownershipOf(tokenId);
        uint64 startTimestamp = tokenOwnership.startTimestamp;

        // has to be at least owner since 1 day
        require(
            block.timestamp - startTimestamp >= withdrawalDelay,
            "Can only reverse swap after withdrawalDelay"
        );

        _burn(tokenId);
        pmon.transfer(msg.sender, pmonFee / 3);
    }

    /******************************
     * PUBLIC VIEW FUNCTIONS *
     ***************************/

    function tokenURI(
        uint256 tokenId
    )
        public
        view
        override(ERC721AUpgradeable, IERC721AUpgradeable)
        returns (string memory)
    {
        // get the random number for this tokenId
        uint256 random = tokenIdToRandom[tokenId];

        // get the creature data
        Creature memory creature = _createCreature(random);

        string memory imageUri = imageUnrevealedUri;
        if (random != 0) {
            imageUri = string(
                abi.encodePacked(imageBaseUri, tokenId.toString(), ".png")
            );
        }

        return
            string(
                abi.encodePacked(
                    "data:application/json;utf8,",
                    "{",
                    '"id" : "',
                    tokenId.toString(),
                    '",',
                    '"image" : "',
                    imageUri,
                    '",',
                    '"randomNumber" : "',
                    random.toString(),
                    '",',
                    '"attributes":[',
                    '{"trait_type":"Species",',
                    '"value":"',
                    creature.species,
                    '"},',
                    '{"trait_type":"Element",',
                    '"value":"',
                    creature.creatureType,
                    '"},',
                    '{"trait_type":"Guidance",',
                    '"value":',
                    division(2, creature.guidance, 1000),
                    "},",
                    '{"trait_type":"Denoising",',
                    '"value":',
                    division(2, creature.denoising, 1000),
                    "},",
                    '{"trait_type":"Steps",',
                    '"value":',
                    division(2, creature.steps, 1000),
                    "}",
                    "]}"
                )
            );
    }

    function createCreature(
        uint256 randomness
    ) public pure returns (Creature memory) {
        return _createCreature(randomness);
    }

    /****************************
     * INTERNAL VIEW FUNCTIONS *
     ***************************/

    function _createCreature(
        uint256 randomness
    ) private pure returns (Creature memory) {
        Creature memory newCreature;

        uint32 speciesRandomNumber = uint32(randomness);
        uint32 typeRandomNumber = uint32(randomness >> 32);
        uint64 stepsRandomNumber = uint64(randomness >> 64);
        uint64 guidanceRandomNumber = uint64(randomness >> 128);
        uint64 denoisingRandomNumber = uint64(randomness >> 192);

        // Species
        if (speciesRandomNumber % 1000 < 10) {
            newCreature.species = "Exp. Unidragon";
        } else if (speciesRandomNumber % 1000 < 50) {
            newCreature.species = "Exp. Uniaqua";
        } else if (speciesRandomNumber % 1000 < 100) {
            newCreature.species = "Exp. Unibranch";
        } else if (speciesRandomNumber % 1000 < 200) {
            newCreature.species = "Exp. Unikles";
        } else if (speciesRandomNumber % 1000 < 310) {
            newCreature.species = "Exp. Unidonkey";
        } else if (speciesRandomNumber % 1000 < 420) {
            newCreature.species = "Exp. Unifairy";
        } else if (speciesRandomNumber % 1000 < 530) {
            newCreature.species = "Exp. Unicursed";
        } else if (speciesRandomNumber % 1000 < 650) {
            newCreature.species = "Exp. Uniair";
        } else if (speciesRandomNumber % 1000 < 760) {
            newCreature.species = "Exp. Uniturtle";
        } else if (speciesRandomNumber % 1000 < 870) {
            newCreature.species = "Exp. Unichick";
        } else {
            newCreature.species = "Exp. Unisheep";
        }

        // Type
        if (typeRandomNumber % 1000 < 225) {
            newCreature.creatureType = "Fire";
        } else if (typeRandomNumber % 1000 < 450) {
            newCreature.creatureType = "Wind";
        } else if (typeRandomNumber % 1000 < 675) {
            newCreature.creatureType = "Earth";
        } else if (typeRandomNumber % 1000 < 900) {
            newCreature.creatureType = "Water";
        } else {
            newCreature.creatureType = "Mythic";
        }

        // Guidance
        newCreature.guidance = uint16((guidanceRandomNumber % 401) + 250); // [250, 650]

        // Denoising
        newCreature.denoising = uint16(
            (denoisingRandomNumber % 5_001) + 25_000
        ); // [30_000, 35_000]

        // Steps
        newCreature.steps = uint32((stepsRandomNumber % 50_001) + 100_000); // [100_000, 150_000]

        return newCreature;
    }

    /***************************
     * ERC721A Overrides *
     **************************/

    function _startTokenId() internal view override returns (uint256) {
        return startTokenId;
    }

    /****************************
     * ORACLE FUNCTIONS *
     ***************************/

    function _requestRandomWords(uint32 _numWords) internal returns (uint256) {
        return
            COORDINATOR.requestRandomWords(
                s_keyHash,
                s_subscriptionId,
                REQUEST_CONFIRMATIONS,
                CALLBACK_GAS_LIMIT,
                _numWords
            );
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal {
        // get the startId from the requestId
        uint256 startId = requestIdToStartId[requestId];

        for (uint256 i = 0; i < randomWords.length; i++) {
            tokenIdToRandom[startId + i] = randomWords[i];
            emit RandomWordsFulfilled(startId + i, randomWords[i]);
        }
    }

    /****************************
     * ADMIN FUNCTIONS *
     ***************************/

    function setAiFee(uint256 _aiFee) external onlyOwner {
        aiFee = _aiFee;
        emit AiFeeChanged(_aiFee);
    }

    function setPmonFee(uint256 _pmonFee) external onlyOwner {
        pmonFee = _pmonFee;
        emit PmonFeeChanged(_pmonFee);
    }

    function setMaxMint(uint256 _maxMint) external onlyOwner {
        maxMint = _maxMint;
        emit MaxMintChanged(_maxMint);
    }

    function withdraw() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function withdrawPmon() external onlyOwner {
        pmon.transfer(msg.sender, pmon.balanceOf(address(this)));
    }

    function setKeyHash(bytes32 _keyHash) external onlyOwner {
        s_keyHash = _keyHash;
    }

    function setSubscriptionId(uint64 _subscriptionId) external onlyOwner {
        s_subscriptionId = _subscriptionId;
    }

    function setCoordinator(address _coordinator) external onlyOwner {
        COORDINATOR = VRFCoordinatorV2Interface(_coordinator);
    }

    function setWithdrawalDelay(uint256 _withdrawalDelay) external onlyOwner {
        withdrawalDelay = _withdrawalDelay;
    }

    function setImageBaseUri(string memory _imageBaseUri) external onlyOwner {
        imageBaseUri = _imageBaseUri;
    }

    function setImageUnrevealedUri(
        string memory _imageUnrevealedUri
    ) external onlyOwner {
        imageUnrevealedUri = _imageUnrevealedUri;
    }

    /************************************************
     * FLATTENED VRF CONSUMER BASE FUNCTIONS *
     ***********************************************/

    // Flattened the VRFConsumerBaseV2 into this contract to have an easy option to make it upgradeable
    function rawFulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) external {
        if (msg.sender != address(COORDINATOR)) {
            revert OnlyCoordinatorCanFulfill(msg.sender, address(COORDINATOR));
        }
        fulfillRandomWords(requestId, randomWords);
    }

    function division(
        uint256 decimalPlaces,
        uint256 numerator,
        uint256 denominator
    ) internal pure returns (string memory result) {
        uint256 factor = 10 ** decimalPlaces;
        uint256 quotient = numerator / denominator;
        bool rounding = 2 * ((numerator * factor) % denominator) >= denominator;
        uint256 remainder = ((numerator * factor) / denominator) % factor;
        if (rounding) {
            remainder += 1;
        }
        result = string(
            abi.encodePacked(
                quotient.toString(),
                ".",
                numToFixedLengthStr(decimalPlaces, remainder)
            )
        );
    }

    function numToFixedLengthStr(
        uint256 decimalPlaces,
        uint256 num
    ) internal pure returns (string memory result) {
        bytes memory byteString;
        for (uint256 i = 0; i < decimalPlaces; i++) {
            uint256 remainder = num % 10;
            byteString = abi.encodePacked(remainder.toString(), byteString);
            num = num / 10;
        }
        result = string(byteString);
    }
}

