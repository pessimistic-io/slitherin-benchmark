// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./Pausable.sol";

import "./IRealm.sol";
import "./ICity.sol";
import "./IRealmLock.sol";
import "./ICollectible.sol";
import "./IBatchStaker.sol";
import "./ICityStorage.sol";

import "./ManagerModifier.sol";

contract CityMinter is ReentrancyGuard, Pausable, ManagerModifier {
  //=======================================
  // Immutables
  //=======================================
  IRealm public immutable REALM;
  ICity public immutable CITY;
  IRealmLock public immutable REALM_LOCK;
  ICollectible public immutable COLLECTIBLE;
  IBatchStaker public immutable BATCH_STAKER;
  ICityStorage public immutable CITY_STORAGE;
  address public immutable COLLECTIBLE_HOLDER;

  //=======================================
  // Ints
  //=======================================
  uint256 public collectibleCostPerCity = 10;
  uint256 public maxCities = 15;
  uint256 public hoursPerCity = 24;

  //=======================================
  // Arrays
  //=======================================
  uint256[] public cityRequirements;
  uint256[] public cityRequirementAmounts;

  //=======================================
  // Mappings
  //=======================================
  mapping(uint256 => uint256[]) public primeCollectibles;

  //=======================================
  // Events
  //=======================================
  event Minted(uint256 realmId, uint256 cityId, uint256 quantity);
  event CollectiblesUsed(
    uint256 realmId,
    uint256 collectibleId,
    uint256 amount
  );
  event StakedCities(
    uint256 realmId,
    address addr,
    uint256[] cityIds,
    uint256[] amounts
  );
  event UnstakedCities(
    uint256 realmId,
    address addr,
    uint256[] cityIds,
    uint256[] amounts
  );

  //=======================================
  // Constructor
  //=======================================
  constructor(
    address _realm,
    address _manager,
    address _collectible,
    address _batchStaker,
    address _cityStorage,
    address _city,
    address _realmLock,
    address _collectibleHolder,
    uint256[][] memory _primeCollectible,
    uint256[] memory _cityRequirements,
    uint256[] memory _cityRequirementAmounts
  ) ManagerModifier(_manager) {
    REALM = IRealm(_realm);
    COLLECTIBLE = ICollectible(_collectible);
    BATCH_STAKER = IBatchStaker(_batchStaker);
    CITY_STORAGE = ICityStorage(_cityStorage);
    CITY = ICity(_city);
    REALM_LOCK = IRealmLock(_realmLock);
    COLLECTIBLE_HOLDER = _collectibleHolder;

    primeCollectibles[0] = _primeCollectible[0];
    primeCollectibles[1] = _primeCollectible[1];
    primeCollectibles[2] = _primeCollectible[2];
    primeCollectibles[3] = _primeCollectible[3];
    primeCollectibles[4] = _primeCollectible[4];
    primeCollectibles[5] = _primeCollectible[5];
    primeCollectibles[6] = _primeCollectible[6];

    cityRequirements = _cityRequirements;
    cityRequirementAmounts = _cityRequirementAmounts;
  }

  //=======================================
  // External
  //=======================================
  function mint(
    uint256 _realmId,
    uint256[] calldata _collectibleIds,
    uint256[] calldata _cityIds,
    uint256[] calldata _quantities
  ) external nonReentrant whenNotPaused {
    // Check if Realm owner
    require(
      REALM.ownerOf(_realmId) == msg.sender,
      "CityMinter: Must be Realm owner"
    );

    uint256 totalQuantity;

    for (uint256 j = 0; j < _cityIds.length; j++) {
      uint256 collectibleId = _collectibleIds[j];
      uint256 cityId = _cityIds[j];
      uint256 desiredQuantity = _quantities[j];

      // Check collectibleId is prime collectible
      _checkPrimeCollectibles(cityId, collectibleId);

      // Check city requirements
      _checkCityRequirements(_realmId, cityId);

      // Mint
      _mint(_realmId, cityId, desiredQuantity);

      // Add to quantity
      totalQuantity = totalQuantity + desiredQuantity;

      uint256 collectibleAmount = collectibleCostPerCity * desiredQuantity;

      // Burn collectibles
      COLLECTIBLE.safeTransferFrom(
        msg.sender,
        COLLECTIBLE_HOLDER,
        collectibleId,
        collectibleAmount,
        ""
      );

      emit CollectiblesUsed(_realmId, collectibleId, collectibleAmount);
    }

    // Check if totalQuantity is below max cities
    require(
      totalQuantity <= maxCities,
      "CityMinter: Max cities per transaction reached"
    );

    // Build
    CITY_STORAGE.build(_realmId, totalQuantity * hoursPerCity);
  }

  function stakeBatch(
    uint256[] calldata _realmIds,
    uint256[][] calldata _cityIds,
    uint256[][] calldata _amounts
  ) external nonReentrant whenNotPaused {
    for (uint256 j = 0; j < _realmIds.length; j++) {
      uint256 realmId = _realmIds[j];
      uint256[] memory cityIds = _cityIds[j];
      uint256[] memory amounts = _amounts[j];

      BATCH_STAKER.stakeBatchFor(
        msg.sender,
        address(CITY),
        realmId,
        cityIds,
        amounts
      );

      emit StakedCities(realmId, address(CITY), cityIds, amounts);
    }
  }

  function unstakeBatch(
    uint256[] calldata _realmIds,
    uint256[][] calldata _cityIds,
    uint256[][] calldata _amounts
  ) external nonReentrant whenNotPaused {
    for (uint256 j = 0; j < _realmIds.length; j++) {
      uint256 realmId = _realmIds[j];

      // Check if Realm is locked
      require(REALM_LOCK.isUnlocked(realmId), "CityMinter: Realm is locked");

      uint256[] memory cityIds = _cityIds[j];
      uint256[] memory amounts = _amounts[j];

      BATCH_STAKER.unstakeBatchFor(
        msg.sender,
        address(CITY),
        realmId,
        cityIds,
        amounts
      );

      emit UnstakedCities(realmId, address(CITY), cityIds, amounts);
    }
  }

  //=======================================
  // Admin
  //=======================================
  function pause() external onlyAdmin {
    _pause();
  }

  function unpause() external onlyAdmin {
    _unpause();
  }

  function updateCollectibleCostPerCity(uint256 _collectibleCostPerCity)
    external
    onlyAdmin
  {
    collectibleCostPerCity = _collectibleCostPerCity;
  }

  function updateMaxCities(uint256 _maxCities) external onlyAdmin {
    maxCities = _maxCities;
  }

  function updateHoursPerCity(uint256 _hoursPerCity) external onlyAdmin {
    hoursPerCity = _hoursPerCity;
  }

  function updateCityRequirements(uint256[] calldata _cityRequirements)
    external
    onlyAdmin
  {
    cityRequirements = _cityRequirements;
  }

  function updateCityRequirementAmounts(
    uint256[] calldata _cityRequirementAmounts
  ) external onlyAdmin {
    cityRequirementAmounts = _cityRequirementAmounts;
  }

  //=======================================
  // Internal
  //=======================================
  function _checkCityRequirements(uint256 _realmId, uint256 _cityId)
    internal
    view
  {
    // Town does not require any staked cities
    if (_cityId == 0) return;

    // Check they have right amount of staked cities
    require(
      BATCH_STAKER.hasStaked(
        _realmId,
        address(CITY),
        cityRequirements[_cityId],
        cityRequirementAmounts[_cityId]
      ),
      "CityMinter: Don't have the required Cities staked"
    );
  }

  function _checkPrimeCollectibles(uint256 _cityId, uint256 _collectibleId)
    internal
    view
  {
    bool invalid;

    for (uint256 j = 0; j < primeCollectibles[_cityId].length; j++) {
      // Check collectibleId matches prime collectible IDs
      if (_collectibleId == primeCollectibles[_cityId][j]) {
        invalid = false;
        break;
      }

      invalid = true;
    }

    require(
      !invalid,
      "CityMinter: Collectible doesn't match City requirements"
    );
  }

  function _mint(
    uint256 _realmId,
    uint256 _cityId,
    uint256 _desiredQuantity
  ) internal {
    // Mint
    CITY.mintFor(msg.sender, _cityId, _desiredQuantity);

    // Add Nourishment credits
    CITY_STORAGE.addNourishmentCredit(_realmId, _desiredQuantity);

    emit Minted(_realmId, _cityId, _desiredQuantity);
  }
}

