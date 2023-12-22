//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./Ownable.sol";
import "./ERC721Holder.sol";
import "./ERC1155Holder.sol";
import "./DPSStructs.sol";
import "./DPSInterfaces.sol";
import "./console.sol";

contract DPSDocks is ERC721Holder, ERC1155Holder, Ownable {
    DPSQRNGI public random;
    DPSPirateFeaturesI public dpsFeatures;
    DPSSupportShipI public supportShips;
    IERC1155 public artifact;
    DPSCartographerI public cartographer;
    DPSGameSettingsI public gameSettings;
    DPSGameEngineI public gameEngine;
    DPSChestsIV2 public chest;

    /**
     * @notice list of voyages started by wallet
     */
    mapping(address => mapping(uint256 => LockedVoyageV2)) private lockedVoyages;

    /**
     * @notice list of voyages finished by wallet
     */
    mapping(address => mapping(uint256 => LockedVoyageV2)) private finishedVoyages;

    /**
     * @notice list of voyages ids started by wallet
     */
    mapping(address => uint256[]) private lockedVoyagesIds;

    /**
     * @notice list of voyages ids finished by wallet
     */
    mapping(address => uint256[]) private finishedVoyagesIds;

    /**
     * @notice finished voyages results voyageId=>results
     */
    mapping(uint256 => VoyageResult) public voyageResults;

    /**
     * @notice we can have multiple voyages, we keep an array of voyages we want to use and their type, if it's v1 or v2
     */
    mapping(DPSVoyageIV2 => bool) public voyages;

    /**
     * @notice we can have multiple collections acting as pirates
     */
    mapping(IERC721Metadata => bool) public pirates;

    /**
     * @notice we can have multiple collections acting as flagships
     */
    mapping(DPSFlagshipI => bool) public flagships;

    address[] public voyagesArray;
    address[] public piratesArray;
    address[] public flagshipsArray;

    uint256 public randomRequestIndex;

    uint256 private nonReentrant = 1;

    /**
     * @notice list of locked voyages and their owners id => wallet
     */
    mapping(uint256 => address) public ownerOfLockedVoyages;

    /**
     * @notice list of finished voyages and their owners id => wallet
     */
    mapping(uint256 => address) public ownerOfFinishedVoyages;

    event LockVoyage(
        uint256 indexed _voyageId,
        uint256 indexed _dpsId,
        uint256 indexed _flagshipId,
        uint8[9] _supportShipIds,
        uint16[13] _artifactIds,
        uint256 _lockedAt
    );

    event ClaimVoyageRewards(
        uint256 indexed _voyageId,
        uint16 _noOfChests,
        uint8[9] _destroyedSupportShips,
        uint16 _healthDamage,
        uint16[] _interactionRNGs,
        uint8[] _interactionResults,
        uint256 _claimedAt
    );

    event SetContract(uint256 _target, address _contract);

    event TokenRecovered(address indexed _token, bytes _data);

    constructor() {}

    /**
     * @notice Locking a voyage
     * @param _lockedVoyages array of objects that contains:
     * - voyageId
     * - dpsId (Pirate)
     * - flagshipId
     * - supportShips - list of support ships ids, an array of 9 corresponding with the support ship types, 
                        a value at a certain position means a support ship sent to sail
     * - totalSupportShips
     * - artifactId
     * the rest of the params are ignored
     * @param _voyage the voyage address we lock the items for
     * @param _pirate the pirate used to lock the voyages
     * @param _flagship the flagship used to lock the voyages
     */
    function lockVoyageItems(
        LockedVoyageV2[] memory _lockedVoyages,
        DPSVoyageIV2 _voyage,
        IERC721Metadata _pirate,
        DPSFlagshipI _flagship
    ) external {
        if (nonReentrant == 2 || !voyages[_voyage] || !pirates[_pirate] || !flagships[_flagship]) revert Unauthorized();
        nonReentrant = 2;
        gameSettings.isPausedNonReentrant(4);

        for (uint256 index; index < _lockedVoyages.length; ++index) {
            LockedVoyageV2 memory lockedVoyage = _lockedVoyages[index];

            VoyageConfigV2 memory voyageConfig = cartographer.viewVoyageConfiguration(lockedVoyage.voyageId, _voyage);

            uint256 totalSupportShips;
            for (uint256 i; i < lockedVoyage.supportShips.length; ++i) {
                totalSupportShips += lockedVoyage.supportShips[i];
            }

            gameEngine.sanityCheckLockVoyages(
                lockedVoyages[msg.sender][lockedVoyage.voyageId],
                finishedVoyages[msg.sender][lockedVoyage.voyageId],
                lockedVoyage,
                voyageConfig,
                totalSupportShips,
                _flagship
            );

            bytes memory uniqueId = abi.encode(msg.sender, "LOCK_VOYAGE_", randomRequestIndex, block.timestamp);
            randomRequestIndex++;
            random.makeRequestUint256(uniqueId);

            lockedVoyage.lockedBlock = block.number;
            lockedVoyage.lockedTimestamp = block.timestamp;
            lockedVoyage.claimedTime = 0;
            lockedVoyage.navigation = 0;
            lockedVoyage.luck = 0;
            lockedVoyage.strength = 0;
            lockedVoyage.sequence = voyageConfig.sequence;
            lockedVoyage.totalSupportShips = uint8(totalSupportShips);
            lockedVoyage.voyageType = voyageConfig.typeOfVoyage;
            lockedVoyage.uniqueId = uniqueId;
            lockedVoyage.voyage = _voyage;
            lockedVoyage.pirate = _pirate;
            lockedVoyage.flagship = _flagship;
            lockedVoyages[msg.sender][lockedVoyage.voyageId] = lockedVoyage;
            lockedVoyagesIds[msg.sender].push(lockedVoyage.voyageId);
            ownerOfLockedVoyages[lockedVoyage.voyageId] = msg.sender;

            _pirate.safeTransferFrom(msg.sender, address(this), lockedVoyage.dpsId);
            _flagship.safeTransferFrom(msg.sender, address(this), lockedVoyage.flagshipId);

            unchecked {
                for (uint256 i; i < 9; ++i) {
                    if (lockedVoyage.supportShips[i] > 0) {
                        supportShips.safeTransferFrom(msg.sender, address(this), i, lockedVoyage.supportShips[i], "");
                    }
                }
            }

            unchecked {
                for (uint256 i = 1; i < 13; ++i) {
                    if (lockedVoyage.artifactIds[i] > 0) {
                        artifact.safeTransferFrom(msg.sender, address(this), i, lockedVoyage.artifactIds[i], "");
                    }
                }
            }

            _voyage.safeTransferFrom(msg.sender, address(this), lockedVoyage.voyageId);

            emit LockVoyage(
                lockedVoyage.voyageId,
                lockedVoyage.dpsId,
                lockedVoyage.flagshipId,
                lockedVoyage.supportShips,
                lockedVoyage.artifactIds,
                block.timestamp
            );
        }
        nonReentrant = 1;
    }

    /**
     * @notice Claiming rewards with params retrieved from the random future blocks
     * @param _voyageIds - ids of the voyages
     */
    function claimRewards(uint256[] memory _voyageIds) external {
        if (nonReentrant == 2) revert Unauthorized();
        nonReentrant = 2;
        gameSettings.isPausedNonReentrant(5);

        // params not ok
        for (uint256 i; i < _voyageIds.length; ++i) {
            uint256 voyageId = _voyageIds[i];

            // we get the owner of the voyage it be different than buyer in case nft sold on marketplaces
            address owner = ownerOfLockedVoyages[voyageId];
            if (owner == address(0)) revert AddressZero();

            LockedVoyageV2 memory lockedVoyage = lockedVoyages[owner][voyageId];
            VoyageConfigV2 memory voyageConfig = lockedVoyage.voyage.getVoyageConfig(voyageId);
            voyageConfig.sequence = lockedVoyage.sequence;

            uint256 randomNumber = random.getRandomResult(lockedVoyage.uniqueId);
            if (randomNumber == 0) revert NotFulfilled();

            VoyageResult memory voyageResult = gameEngine.computeVoyageState(
                lockedVoyage,
                voyageConfig.sequence,
                randomNumber
            );
            lockedVoyage.claimedTime = block.timestamp;
            lockedVoyages[owner][voyageId] = lockedVoyage;
            finishedVoyages[owner][lockedVoyage.voyageId] = lockedVoyage;
            finishedVoyagesIds[owner].push(lockedVoyage.voyageId);
            ownerOfFinishedVoyages[lockedVoyage.voyageId] = owner;
            voyageResults[voyageId] = voyageResult;

            cleanLockedVoyage(lockedVoyage.voyageId, owner);

            awardRewards(voyageResult, voyageConfig.typeOfVoyage, lockedVoyage, owner);

            emit ClaimVoyageRewards(
                voyageId,
                voyageResult.awardedChests,
                voyageResult.destroyedSupportShips,
                voyageResult.healthDamage,
                voyageResult.interactionRNGs,
                voyageResult.interactionResults,
                block.timestamp
            );
        }
        nonReentrant = 1;
    }

    /**
     * @notice checking voyage state between start start and finish sail, it uses causality parameters to determine the outcome of interactions
     * @param _voyageId - id of the voyage
     */
    function checkVoyageState(uint256 _voyageId) external view returns (VoyageResult memory voyageResult) {
        LockedVoyageV2 storage lockedVoyage = lockedVoyages[ownerOfLockedVoyages[_voyageId]][_voyageId];

        if (lockedVoyage.voyageId == 0) {
            lockedVoyage = finishedVoyages[ownerOfFinishedVoyages[_voyageId]][_voyageId];
        }

        // not started
        if (lockedVoyage.voyageId == 0) revert WrongState(1);

        VoyageConfigV2 memory voyageConfig = lockedVoyage.voyage.getVoyageConfig(_voyageId);
        voyageConfig.sequence = lockedVoyage.sequence;

        uint256 randomNumber = random.getRandomResult(lockedVoyage.uniqueId);
        if (randomNumber == 0) revert NotFulfilled();

        return gameEngine.computeVoyageState(lockedVoyage, voyageConfig.sequence, randomNumber);
    }

    /**
     * @notice awards the voyage (if any) and transfers back the assets that were locked into the voyage
     *         to the owners, also if support ship destroyed, it burns them, if health damage taken then apply effect on flagship
     * @param _voyageResult - the result of the voyage that is used to award and apply effects
     * @param _typeOfVoyage - used to mint the chests types accordingly with the voyage type
     * @param _lockedVoyage - locked voyage object used to get the locked items that needs to be transferred back
     * @param _owner - the owner of the voyage that will receive rewards + items back
     *
     */
    function awardRewards(
        VoyageResult memory _voyageResult,
        uint16 _typeOfVoyage,
        LockedVoyageV2 memory _lockedVoyage,
        address _owner
    ) private {
        chest.mint(_owner, uint256(_typeOfVoyage), _voyageResult.awardedChests);
        _lockedVoyage.pirate.safeTransferFrom(address(this), _owner, _lockedVoyage.dpsId);

        if (_voyageResult.healthDamage > 0)
            _lockedVoyage.flagship.upgradePart(
                FLAGSHIP_PART.HEALTH,
                _lockedVoyage.flagshipId,
                100 - _voyageResult.healthDamage
            );
        _lockedVoyage.flagship.safeTransferFrom(address(this), _owner, _lockedVoyage.flagshipId);
        for (uint256 i; i < 9; ++i) {
            if (_voyageResult.destroyedSupportShips[i] > 0) {
                supportShips.burn(address(this), i, _voyageResult.destroyedSupportShips[i]);
            }
            if (_lockedVoyage.supportShips[i] > _voyageResult.destroyedSupportShips[i])
                supportShips.safeTransferFrom(
                    address(this),
                    _owner,
                    i,
                    _lockedVoyage.supportShips[i] - _voyageResult.destroyedSupportShips[i],
                    ""
                );
        }
        for (uint256 i = 1; i < 13; ++i) {
            if (_lockedVoyage.artifactIds[i] == 0) continue;
            artifact.safeTransferFrom(address(this), _owner, i, _lockedVoyage.artifactIds[i], "");
        }
        _lockedVoyage.voyage.burn(_lockedVoyage.voyageId);
    }

    /**
     * @notice cleans a locked voyage, usually once it's finished
     * @param _voyageId - voyage id
     * @param _owner  - owner of the voyage
     */
    function cleanLockedVoyage(uint256 _voyageId, address _owner) private {
        uint256[] storage voyagesForOwner = lockedVoyagesIds[_owner];
        for (uint256 i; i < voyagesForOwner.length; ++i) {
            if (voyagesForOwner[i] == _voyageId) {
                voyagesForOwner[i] = voyagesForOwner[voyagesForOwner.length - 1];
                voyagesForOwner.pop();
            }
        }
        delete ownerOfLockedVoyages[_voyageId];
        delete lockedVoyages[_owner][_voyageId];
    }

    function onERC721Received(
        address _operator,
        address,
        uint256,
        bytes memory
    ) public view override returns (bytes4) {
        if (_operator != address(this)) revert Unauthorized();
        return this.onERC721Received.selector;
    }

    function onERC1155Received(
        address _operator,
        address,
        uint256,
        uint256,
        bytes memory
    ) public view override returns (bytes4) {
        if (_operator != address(this)) revert Unauthorized();
        return this.onERC1155Received.selector;
    }

    /**
     * @notice used to recover tokens using call. This will be used so we can save some contract sizes
     * @param _token the token address
     * @param _data encoded with abi.encodeWithSignature(signatureString, arg); of transferFrom, transfer methods
     */
    function recoverToken(address _token, bytes memory _data) external onlyOwner {
        (bool success, ) = _token.call{value: 0}(_data);
        if (!success) revert NotEnoughTokens();
        emit TokenRecovered(_token, _data);
    }

    function cleanVoyageResults(uint256 _voyageId) external onlyOwner {
        delete voyageResults[_voyageId];
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
            if (!_enabled) {
                for (uint256 i; i < voyagesArray.length; ++i) {
                    if (voyagesArray[i] == _contract) {
                        voyagesArray[i] = voyagesArray[voyagesArray.length - 1];
                        voyagesArray.pop();
                    }
                }
            }
        } else if (_target == 2) {
            random = DPSQRNGI(_contract);
        } else if (_target == 3) {
            pirates[IERC721Metadata(_contract)] = _enabled;
            if (!_enabled) {
                for (uint256 i; i < piratesArray.length; ++i) {
                    if (piratesArray[i] == _contract) {
                        piratesArray[i] = piratesArray[piratesArray.length - 1];
                        piratesArray.pop();
                    }
                }
            }
        } else if (_target == 4) {
            flagships[DPSFlagshipI(_contract)] = _enabled;
            if (!_enabled) {
                for (uint256 i; i < flagshipsArray.length; ++i) {
                    if (flagshipsArray[i] == _contract) {
                        flagshipsArray[i] = flagshipsArray[flagshipsArray.length - 1];
                        flagshipsArray.pop();
                    }
                }
            }
        } else if (_target == 5) {
            supportShips = DPSSupportShipI(_contract);
        } else if (_target == 6) {
            artifact = IERC1155(_contract);
        } else if (_target == 7) {
            gameSettings = DPSGameSettingsI(_contract);
        } else if (_target == 8) {
            cartographer = DPSCartographerI(_contract);
        } else if (_target == 9) {
            chest = DPSChestsIV2(_contract);
        } else if (_target == 10) {
            gameEngine = DPSGameEngineI(_contract);
        }
        emit SetContract(_target, _contract);
    }

    function getLockedVoyagesForOwner(
        address _owner,
        uint256 _start,
        uint256 _stop
    ) external view returns (LockedVoyageV2[] memory locked) {
        unchecked {
            uint256 length = lockedVoyagesIds[_owner].length;
            if (_stop > length) _stop = length;
            locked = new LockedVoyageV2[](length);
            for (uint256 i = _start; i < _stop; ++i) {
                locked[i - _start] = lockedVoyages[_owner][lockedVoyagesIds[_owner][i]];
            }
        }
    }

    function getFinishedVoyagesForOwner(
        address _owner,
        uint256 _start,
        uint256 _stop
    ) external view returns (LockedVoyageV2[] memory finished) {
        unchecked {
            uint256 length = finishedVoyagesIds[_owner].length;
            if (_stop > length) _stop = length;
            finished = new LockedVoyageV2[](length);
            for (uint256 i = _start; i < _stop; ++i) {
                finished[i - _start] = finishedVoyages[_owner][finishedVoyagesIds[_owner][i]];
            }
        }
    }

    function voyagesLength(address _owner, bool _locked) external view returns (uint256) {
        if (_locked) return lockedVoyagesIds[_owner].length;
        return finishedVoyagesIds[_owner].length;
    }
}

