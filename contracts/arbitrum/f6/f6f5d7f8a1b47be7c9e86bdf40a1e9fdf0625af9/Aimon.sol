// SPDX-License-Identifier: MIT
pragma solidity 0.8.18; // highest hardhat-supported version of solidity at time of writen | https://hardhat.org/hardhat-runner/docs/reference/solidity-support

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
        uint64 _subscriptionId
    ) public initializerERC721A initializer {
        __ERC721A_init("AI-Mons", "AIMON");
        __ERC721ABurnable_init();
        __Ownable_init();

        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        s_keyHash = _keyHash;
        s_subscriptionId = _subscriptionId;
        // CALLBACK_GAS_LIMIT = 1_000_000;
        // REQUEST_CONFIRMATIONS = 10;

        aiFee = 0.01 ether;
        pmonFee = 5 ether;
        maxMint = 10;
        pmon = IERC20Upgradeable(_pmon);
    }

    /****************************
     * PUBLIC WRITE FUNCTIONS *
     ***************************/

    // quantity is the number of packs; one pack has 3 mons
    function mintTo(uint8 quantity, address receiver) external payable {
        require(msg.value >= quantity * aiFee, "Not enough ETH sent");
        require(quantity * 3 <= maxMint, "Cannot mint more than maxMint");
        require(quantity > 0, "Cannot mint 0");

        uint256 startId = _totalMinted();

        // we request the random numbers from chainlink
        uint256 requestId = _requestRandomWords(quantity * 3);
        requestIdToStartId[requestId] = startId;

        _mint(receiver, quantity * 3);

        pmon.transferFrom(msg.sender, address(this), quantity * pmonFee);
    }

    function reverseSwap(uint256 tokenId) external {
        // sender has to be owner of the token
        require(msg.sender == ownerOf(tokenId), "Only owner can reverse swap");

        _burn(tokenId);
        pmon.transfer(msg.sender, pmonFee);
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

        if (random == 0) {
            return
                string(
                    abi.encodePacked(
                        'data:application/json;utf8,{"status" : "random number pending or monster does not exist"}'
                    )
                );
        } else {
            // get the creature data
            Creature memory creature = _createCreature(random);

            return
                string(
                    abi.encodePacked(
                        "data:application/json;utf8,",
                        "{",
                        '"id" : "',
                        tokenId.toString(),
                        '",',
                        '"image" : ',
                        '"https://ai-assets.polychainmonsters.com/?tokenId=',
                        tokenId.toString(),
                        '",',
                        '"randomNumber" : "',
                        random.toString(),
                        '",',
                        '"attributes":[',
                        '{"trait_type":"Species",',
                        '"value":"',
                        creature.species,
                        '"},',
                        '{"trait_type":"Creature Type",',
                        '"value":"',
                        creature.creatureType,
                        '"},',
                        '{"trait_type":"Guidance",',
                        '"value":',
                        uint256(creature.guidance).toString(),
                        "},",
                        '{"trait_type":"Denoising",',
                        '"value":',
                        uint256(creature.denoising).toString(),
                        "},",
                        '{"trait_type":"Steps",',
                        '"value":',
                        uint256(creature.steps).toString(),
                        "}",
                        "]}"
                    )
                );
        }
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
            newCreature.species = "Toon Unidragon";
        } else if (speciesRandomNumber % 1000 < 50) {
            newCreature.species = "Toon Uniaqua";
        } else if (speciesRandomNumber % 1000 < 100) {
            newCreature.species = "Toon Unibranch";
        } else if (speciesRandomNumber % 1000 < 200) {
            newCreature.species = "Toon Unikles";
        } else if (speciesRandomNumber % 1000 < 310) {
            newCreature.species = "Toon Unidonkey";
        } else if (speciesRandomNumber % 1000 < 420) {
            newCreature.species = "Toon Unifairy";
        } else if (speciesRandomNumber % 1000 < 530) {
            newCreature.species = "Toon Unicursed";
        } else if (speciesRandomNumber % 1000 < 650) {
            newCreature.species = "Toon Uniair";
        } else if (speciesRandomNumber % 1000 < 760) {
            newCreature.species = "Toon Uniturtle";
        } else if (speciesRandomNumber % 1000 < 870) {
            newCreature.species = "Toon Unichick";
        } else {
            newCreature.species = "Toon Unisheep";
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
        newCreature.steps = uint32((stepsRandomNumber % 70_001) + 30_000); // [30_000, 100_000]

        return newCreature;
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

    // function setRequestConfirmations(
    //     uint16 _requestConfirmations
    // ) external onlyOwner {
    //     REQUEST_CONFIRMATIONS = _requestConfirmations;
    // }

    // function setCallbackGasLimit(uint32 _callbackGasLimit) external onlyOwner {
    //     CALLBACK_GAS_LIMIT = _callbackGasLimit;
    // }

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
}

