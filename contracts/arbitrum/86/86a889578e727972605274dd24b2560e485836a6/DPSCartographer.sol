//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./Strings.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IERC1155.sol";
import "./IERC20MintableBurnable.sol";
import "./DPSInterfaces.sol";
import "./DPSStructs.sol";
import "./console.sol";

contract DPSCartographer is Ownable {
    using SafeERC20 for IERC20MintableBurnable;

    IERC20MintableBurnable public tmap;
    IERC20MintableBurnable public doubloon;
    DPSQRNGI public random;
    DPSGameSettingsI public gameSettings;

    /**
     * @notice we can have multiple voyages, we keep an array of voyages we want to use
     */
    mapping(DPSVoyageIV2 => bool) public voyages;

    uint256 private nonReentrant = 1;

    uint256 public randomRequestIndex;

    event Swap(address indexed _owner, bool indexed _tmapToDoubloon, uint256 _tmaps, uint256 _doubloons);
    event VoyageCreated(address indexed _owner, uint256 _id, uint256 _type);
    event SetContract(uint256 _target, address _contract);
    event TokenRecovered(address indexed _token, address _destination, uint256 _amount);

    constructor() {}

    /**
     * @notice swap tmaps for doubloons
     * @param _quantity of tmaps you want to swap
     */
    function swapTmapsForDoubloons(uint256 _quantity) external {
        if (gameSettings.isPaused(0) == 1) revert Paused();
        if (tmap.balanceOf(msg.sender) < _quantity) revert NotEnoughTokens();

        uint256 amountOfDoubloons = _quantity * gameSettings.tmapPerDoubloon();
        uint256 amountOfTmaps = _quantity;

        tmap.burn(msg.sender, amountOfTmaps);
        doubloon.mint(msg.sender, amountOfDoubloons);

        emit Swap(msg.sender, true, amountOfTmaps, amountOfDoubloons);
    }

    /**
     * @notice swap doubloons for tmaps
     * @param _quantity of doubloons you want to swap
     */
    function swapDoubloonsForTmaps(uint256 _quantity) external {
        if (gameSettings.isPaused(1) == 1) revert Paused();
        if (doubloon.balanceOf(msg.sender) < _quantity) revert NotEnoughTokens();

        uint256 amountOfDoubloons = _quantity;
        uint256 amountOfTmaps = (_quantity) / gameSettings.tmapPerDoubloon();

        doubloon.burn(msg.sender, amountOfDoubloons);
        tmap.mint(msg.sender, amountOfTmaps);

        emit Swap(msg.sender, false, amountOfTmaps, amountOfDoubloons);
    }

    /**
     * @notice buy a voyage using tmaps
     * @param _voyageType - type of the voyage 0 - EASY, 1 - MEDIUM, 2 - HARD, 3 - LEGENDARY
     * @param _amount - how many voyages you want to buy
     */
    function buyVoyages(
        uint16 _voyageType,
        uint256 _amount,
        DPSVoyageIV2 _voyage
    ) external {
        if (nonReentrant == 2 || !voyages[_voyage]) revert Unauthorized();
        nonReentrant = 2;

        if (gameSettings.isPaused(2) == 1) revert Paused();
        uint256 amountOfTmap = gameSettings.tmapPerVoyage(_voyageType);
        // this will return 0 if not a valid voyage
        if (amountOfTmap == 0) revert WrongParams(1);

        if (tmap.balanceOf(msg.sender) < amountOfTmap * _amount) revert NotEnoughTokens();

        bytes memory uniqueId = abi.encode(msg.sender, "BUY_VOYAGE", randomRequestIndex, block.timestamp);
        randomRequestIndex++;

        for (uint256 i; i < _amount; ++i) {
            CartographerConfig memory currentVoyageConfigPerType = gameSettings.voyageConfigPerType(_voyageType);
            uint8[] memory sequence = new uint8[](currentVoyageConfigPerType.totalInteractions);
            VoyageConfigV2 memory voyageConfig = VoyageConfigV2(
                _voyageType,
                uint8(sequence.length),
                sequence,
                block.number,
                currentVoyageConfigPerType.gapBetweenInteractions,
                uniqueId
            );

            uint256 voyageId = _voyage.maxMintedId() + 1;

            tmap.burn(msg.sender, amountOfTmap);

            _voyage.mint(msg.sender, voyageId, voyageConfig);
            emit VoyageCreated(msg.sender, voyageId, _voyageType);
        }
        random.makeRequestUint256(uniqueId);
        nonReentrant = 1;
    }

    /**
     * @notice burns a voyage
     * @param _voyageId - voyage that needs to be burnt
     */
    function burnVoyage(uint256 _voyageId, DPSVoyageIV2 _voyage) external {
        if (!voyages[_voyage]) revert Unauthorized();
        if (gameSettings.isPaused(3) == 1) revert Paused();
        if (_voyage.ownerOf(_voyageId) != msg.sender) revert WrongParams(1);
        _voyage.burn(_voyageId);
    }

    /**
     * @notice view voyage configurations.
     * @dev because voyage configurations are based on causality generated from future blocks, we need to send
     *      causality parameters retrieved from the DAPP. The causality params will determine the outcome of the voyage
     *      no of interactions, the order of interactions
     * @param _voyageId - voyage id
     * @param _voyage the voyage we want to get the config for, this is because we have multiple types of voyages
     * @return voyageConfig - a config of the voyage, see DPSStructs->VoyageConfig
     */
    function viewVoyageConfiguration(uint256 _voyageId, DPSVoyageIV2 _voyage)
        external
        view
        returns (VoyageConfigV2 memory voyageConfig)
    {
        if (!voyages[_voyage]) revert Unauthorized();

        voyageConfig = _voyage.getVoyageConfig(_voyageId);

        if (voyageConfig.noOfInteractions == 0) revert WrongParams(1);

        CartographerConfig memory configForThisInteraction = gameSettings.voyageConfigPerType(voyageConfig.typeOfVoyage);
        uint256 randomNumber = random.getRandomResult(voyageConfig.uniqueId);
        if (randomNumber == 0) revert NotFulfilled();

        // generating first the number of enemies, then the number of storms
        // if signature on then we need to generated based on signature, meaning is a verified generation
        RandomInteractions memory randomInteractionsConfig = generateRandomNumbers(
            randomNumber,
            _voyageId,
            voyageConfig.boughtAt,
            configForThisInteraction
        );

        voyageConfig.sequence = new uint8[](configForThisInteraction.totalInteractions);
        randomInteractionsConfig.positionsForGeneratingInteractions = new uint256[](3);
        randomInteractionsConfig.positionsForGeneratingInteractions[0] = 1;
        randomInteractionsConfig.positionsForGeneratingInteractions[1] = 2;
        randomInteractionsConfig.positionsForGeneratingInteractions[2] = 3;
        // because each interaction has a maximum number of happenings we need to make sure that it's met
        for (uint256 i; i < configForThisInteraction.totalInteractions; ) {
            /**
             * if we met the max number of generated interaction generatedChests == randomNoOfChests (defined above)
             * we remove this interaction from the positionsForGeneratingInteractions
             * which is an array containing the possible interactions that can gen generated as next values in the sequencer.
             * At first the positionsForGeneratingInteractions will have all 3 interactions (1 - Chest, 2 - Storm, 3 - Enemy)
             * but then we remove them as the generatedChests == randomNoOfChests
             */
            if (randomInteractionsConfig.generatedChests == randomInteractionsConfig.randomNoOfChests) {
                randomInteractionsConfig.positionsForGeneratingInteractions = removeByValue(
                    randomInteractionsConfig.positionsForGeneratingInteractions,
                    1
                );
                randomInteractionsConfig.generatedChests = 0;
            }
            if (randomInteractionsConfig.generatedStorms == randomInteractionsConfig.randomNoOfStorms) {
                randomInteractionsConfig.positionsForGeneratingInteractions = removeByValue(
                    randomInteractionsConfig.positionsForGeneratingInteractions,
                    2
                );
                randomInteractionsConfig.generatedStorms = 0;
            }
            if (randomInteractionsConfig.generatedEnemies == randomInteractionsConfig.randomNoOfEnemies) {
                randomInteractionsConfig.positionsForGeneratingInteractions = removeByValue(
                    randomInteractionsConfig.positionsForGeneratingInteractions,
                    3
                );
                randomInteractionsConfig.generatedEnemies = 0;
            }

            if (randomInteractionsConfig.positionsForGeneratingInteractions.length == 1) {
                randomInteractionsConfig.randomPosition = 0;
            } else {
                randomInteractionsConfig.randomPosition = random.getRandomNumber(
                    randomNumber,
                    voyageConfig.boughtAt,
                    string(abi.encode("INTERACTION_ORDER_", i, "_", _voyageId)),
                    0,
                    uint8(randomInteractionsConfig.positionsForGeneratingInteractions.length) - 1
                );
            }
            randomInteractionsConfig = interpretResult(randomInteractionsConfig, i, voyageConfig);
            unchecked {
                i++;
            }
        }
    }

    function interpretResult(
        RandomInteractions memory _randomInteractionsConfig,
        uint256 _index,
        VoyageConfigV2 memory _voyageConfig
    ) private pure returns (RandomInteractions memory) {
        uint256 selectedInteraction = _randomInteractionsConfig.positionsForGeneratingInteractions[
            _randomInteractionsConfig.randomPosition
        ];
        _voyageConfig.sequence[_index] = uint8(selectedInteraction);

        if (selectedInteraction == 1) _randomInteractionsConfig.generatedChests++;
        else if (selectedInteraction == 2) _randomInteractionsConfig.generatedStorms++;
        else if (selectedInteraction == 3) _randomInteractionsConfig.generatedEnemies++;
        return _randomInteractionsConfig;
    }

    function generateRandomNumbers(
        uint256 _randomNumber,
        uint256 _voyageId,
        uint256 _boughtAt,
        CartographerConfig memory _configForThisInteraction
    ) private view returns (RandomInteractions memory) {
        RandomInteractions memory _randomInteractionsConfig;

        _randomInteractionsConfig.randomNoOfEnemies = random.getRandomNumber(
            _randomNumber,
            _boughtAt,
            string(abi.encode("NOOFENEMIES", _voyageId)),
            _configForThisInteraction.minNoOfEnemies,
            _configForThisInteraction.maxNoOfEnemies
        );
        _randomInteractionsConfig.randomNoOfStorms = random.getRandomNumber(
            _randomNumber,
            _boughtAt,
            string(abi.encode("NOOFSTORMS", _voyageId)),
            _configForThisInteraction.minNoOfStorms,
            _configForThisInteraction.maxNoOfStorms
        );

        // then the rest of the remaining interactions represents the number of chests
        _randomInteractionsConfig.randomNoOfChests =
            _configForThisInteraction.totalInteractions -
            _randomInteractionsConfig.randomNoOfEnemies -
            _randomInteractionsConfig.randomNoOfStorms;
        return _randomInteractionsConfig;
    }

    /**
     * @notice a utility function that removes by value from an array
     * @param target - targeted array
     * @param value - value that needs to be removed
     * @return new array without the value
     */
    function removeByValue(uint256[] memory target, uint256 value) internal pure returns (uint256[] memory) {
        uint256[] memory newTarget = new uint256[](target.length - 1);
        uint256 k = 0;
        unchecked {
            for (uint256 j; j < target.length; j++) {
                if (target[j] == value) continue;
                newTarget[k++] = target[j];
            }
        }
        return newTarget;
    }

    /**
     * @notice Recover NFT sent by mistake to the contract
     * @param _nft the NFT address
     * @param _destination where to send the NFT
     * @param _tokenId the token to want to recover
     */
    function recoverNFT(
        address _nft,
        address _destination,
        uint256 _tokenId
    ) external onlyOwner {
        if (_destination == address(0)) revert AddressZero();
        IERC721(_nft).safeTransferFrom(address(this), _destination, _tokenId);
        emit TokenRecovered(_nft, _destination, _tokenId);
    }

    /**
     * @notice Recover TOKENS sent by mistake to the contract
     * @param _token the TOKEN address
     * @param _destination where to send the NFT
     */
    function recoverERC20(address _token, address _destination) external onlyOwner {
        if (_destination == address(0)) revert AddressZero();
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20MintableBurnable(_token).safeTransfer(_destination, amount);
        emit TokenRecovered(_token, _destination, amount);
    }

    /**
     * SETTERS & GETTERS
     */
    function setContract(
        address _contract,
        uint256 _target,
        bool _enabled
    ) external onlyOwner {
        if (_target == 1) {
            voyages[DPSVoyageIV2(_contract)] = _enabled;
        } else if (_target == 2) random = DPSQRNGI(_contract);
        else if (_target == 3) doubloon = IERC20MintableBurnable(_contract);
        else if (_target == 4) tmap = IERC20MintableBurnable(_contract);
        else if (_target == 5) gameSettings = DPSGameSettingsI(_contract);
        emit SetContract(_target, _contract);
    }
}

