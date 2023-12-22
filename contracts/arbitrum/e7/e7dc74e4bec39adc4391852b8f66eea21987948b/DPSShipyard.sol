//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./ReentrancyGuard.sol";
import "./Strings.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IERC1155.sol";
import "./IERC20MintableBurnable.sol";
import "./DPSInterfaces.sol";
import "./DPSStructs.sol";
import "./console.sol";

contract DPSShipyard is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC721 public dps;
    DPSFlagshipI public flagship;
    DPSSupportShipI public supportShip;
    IERC20MintableBurnable public doubloon;
    DPSGameSettingsI public gameSettings;

    mapping(DPSFlagshipI => bool) flagshipsAllowed;

    /**
     * @notice collections that are whitelisted to claim flagships for
     */
    mapping(IERC721 => bool) public whitelistedClaimers;

    event FlagshipMinted(address indexed _owner, uint16 _tokenId);
    event BoughSupportShip(address indexed _owner, SUPPORT_SHIP_TYPE _type, uint256 _quantity);
    event SetContract(uint256 _target, address _contract);
    event FlagshipRepaired(address indexed _owner, uint256 indexed _flagshipId);
    event FlagshipUpgraded(address indexed _owner, uint256 indexed _flagshipId, uint8[6] _levels, uint256 doubloonsSpent);
    event TokenRecovered(address indexed _token, address _destination, uint256 _amount);
    event ClaimerWhitelisted(IERC721 indexed _claimer, bool _approved);

    constructor() {}

    /**
     * @notice claiming a flagship by owning a Pirate. the flagship token id = dps id
     * @param _dpsId - pirate id
     */
    function claimFlagshipDPS(uint16 _dpsId) external nonReentrant {
        if (gameSettings.isPaused(10) == 1) revert Paused();
        if (dps.ownerOf(_dpsId) != msg.sender) revert WrongParams(1);

        flagship.mint(msg.sender, _dpsId);
        emit FlagshipMinted(msg.sender, _dpsId);
    }

    /**
     * @notice claiming a flagship by owning a claimer collection. flagship id sent as param
     * @dev this is v2 claiming, it mimics the DPS claiming from above but it is a bit more general
     * @param _claimerId - the token id of the claimer contract.
     * @param _claimer - claimer, the contract that is checked against as a whitelisted claimer
     */
    function claimFlagshipV2(uint16 _claimerId, IERC721 _claimer) external nonReentrant {
        if (gameSettings.isPaused(10) == 1) revert Paused();
        if (_claimer.ownerOf(_claimerId) != msg.sender) revert WrongParams(1);
        if (_claimerId < 3001) revert WrongParams(2);
        if (!whitelistedClaimers[_claimer]) revert WrongParams(3);

        flagship.mint(msg.sender, _claimerId);
        emit FlagshipMinted(msg.sender, _claimerId);
    }

    /**
     * @notice repairing a damaged ship, costs doubloons see `repairFlagshipCost` on GameSettings
     * @param _flagshipId - id of the flagship
     */
    function repairFlagship(DPSFlagshipI _flagship, uint256 _flagshipId) public {
        if (gameSettings.isPaused(11) == 1) revert Paused();
        if (!flagshipsAllowed[_flagship]) revert Unauthorized();
        // needs to be the owner of the flagship
        if (flagship.ownerOf(_flagshipId) != msg.sender) revert WrongParams(2);

        doubloon.burn(msg.sender, gameSettings.repairFlagshipCost());
        flagship.upgradePart(FLAGSHIP_PART.HEALTH, _flagshipId, 100);
        emit FlagshipRepaired(msg.sender, _flagshipId);
    }

    /**
     * @notice repairing a multiple flagships
     * @param _flagshipIds - ids of the flagships
     */
    function repairFlagships(DPSFlagshipI _flagship, uint256[] memory _flagshipIds) external nonReentrant {
        for (uint256 i; i < _flagshipIds.length; ++i) {
            repairFlagship(_flagship, _flagshipIds[i]);
        }
    }

    /**
     * @notice upgrade parts of flagship for doubloons
     * @dev we start the parts computation from 1 as 0 is health and we can not upgrade the health using this method
     * @param _flagshipId the flagship we want to upgrade
     * @param _levels an array of length 6 that represents every part and how many levels to upgrade it
     *                needs to correspond with the index of the part from flagship's _parts[]
     */
    function upgradeFlagship(
        DPSFlagshipI _flagship,
        uint256 _flagshipId,
        uint8[6] memory _levels
    ) external nonReentrant {
        if (gameSettings.isPaused(12) == 1) revert Paused();
        if (!flagshipsAllowed[_flagship]) revert Unauthorized();

        // needs to be the owner of the flagship
        if (flagship.ownerOf(_flagshipId) != msg.sender) revert WrongParams(3);

        uint8[7] memory currentLevels = flagship.getPartsLevel(_flagshipId);

        uint256 amountOfDoubloons;
        for (uint256 i = 1; i < 7; ++i) {
            uint8 upgradingLevel = _levels[i - 1];
            //we do i-1 because our levels array considers all the parts except health which is index 0 in the parts on the flagship
            if (upgradingLevel == 0) continue;
            FLAGSHIP_PART part = FLAGSHIP_PART(i);
            uint8 currentLevel = currentLevels[uint256(part)];

            if (part == FLAGSHIP_PART.HEALTH || currentLevel >= 10) continue;

            // we assume that all the levels that can be upgraded are filled with values meaning that over the max level it will add 0 doubloons
            amountOfDoubloons += computeDoubloonsForUpgrade(currentLevel, currentLevel + upgradingLevel);
            currentLevel += upgradingLevel;

            if (currentLevel > 10) {
                currentLevel = 10;
            }
            currentLevels[i] = currentLevel;
            flagship.upgradePart(part, _flagshipId, currentLevel);
        }

        if (amountOfDoubloons == 0 || doubloon.balanceOf(msg.sender) < amountOfDoubloons) revert NotEnoughTokens();
        doubloon.burn(msg.sender, amountOfDoubloons);

        emit FlagshipUpgraded(msg.sender, _flagshipId, _levels, amountOfDoubloons);
    }

    /**
     * @notice buy support ships, just 1 type per tx, requires doubloons
     * @param _type type of support ship you want to buy
     * @param _quantity the quantity you want to buy
     */
    function buySupportShips(SUPPORT_SHIP_TYPE _type, uint256 _quantity) external nonReentrant {
        if (gameSettings.isPaused(13) == 1) revert Paused();

        uint256 doubloonsPerShip = gameSettings.doubloonsPerSupportShipType(_type);
        doubloon.burn(msg.sender, doubloonsPerShip * _quantity);
        supportShip.mint(msg.sender, uint256(_type), _quantity);
        emit BoughSupportShip(msg.sender, _type, _quantity);
    }

    function computeDoubloonsForUpgrade(uint256 _startLevel, uint256 _endLevel) private view returns (uint256) {
        if (_startLevel >= _endLevel) return 0;
        uint256 doubloons;
        for (uint i = _startLevel; i <= _endLevel; ++i) {
            doubloons += gameSettings.doubloonPerFlagshipUpgradePerLevel(i);
        }
        return doubloons;
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
            dps = IERC721(_contract);
        } else if (_target == 2) flagship = DPSFlagshipI(_contract);
        else if (_target == 3) gameSettings = DPSGameSettingsI(_contract);
        else if (_target == 4) doubloon = IERC20MintableBurnable(_contract);
        else if (_target == 5) supportShip = DPSSupportShipI(_contract);
        else if (_target == 6) flagshipsAllowed[DPSFlagshipI(_contract)] = _enabled;
        emit SetContract(_target, _contract);
    }

    function setWhitelistedClaimer(IERC721 _claimer, bool _approved) external onlyOwner {
        if (address(_claimer) == address(0)) revert AddressZero();
        whitelistedClaimers[_claimer] = _approved;
        emit ClaimerWhitelisted(_claimer, _approved);
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
        IERC20(_token).safeTransfer(_destination, amount);
        emit TokenRecovered(_token, _destination, amount);
    }
}

