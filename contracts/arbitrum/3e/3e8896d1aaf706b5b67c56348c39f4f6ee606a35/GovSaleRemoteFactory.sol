// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./UpgradeableBeacon.sol";
import "./BeaconProxy.sol";

import "./AdminProxyManager.sol";
import "./IGovFactory.sol";
import "./IGovSaleRemote.sol";

contract GovSaleRemoteFactory is
  Initializable,
  UUPSUpgradeable,
  OwnableUpgradeable,
  PausableUpgradeable,
  AdminProxyManager,
  IGovFactory
{
  // d2 = 2 decimal
  uint256 public override operationalPercentage_d2;
  uint256 public override marketingPercentage_d2;
  uint256 public override treasuryPercentage_d2;

  address[] public override allProjects; // all projects created
  address[] public override allPayments; // all payment Token accepted
  uint256[] public override allChainsStaked;

  address public override komV;
  address public override beacon;
  address public override savior; // KOM address to spend left tokens
  address public override saleGateway; // dst sale gateway

  address public override operational; // operational address
  address public override marketing; // marketing address
  address public override treasury; // treasury address

  mapping(address => uint256) public override getPaymentIndex;
  mapping(uint256 => uint256) public override getChainStakedIndex;
  mapping(address => bool) public override isKnown;

  function init(
    address _komV,
    address _beacon,
    address _savior,
    address _saleGateway, // sale gateway
    address _operational,
    address _marketing,
    address _treasury
  ) external initializer proxied {
    __UUPSUpgradeable_init();
    __Ownable_init();
    __Pausable_init();
    __AdminProxyManager_init(_msgSender());

    require(
      _beacon != address(0) &&
        _savior != address(0) &&
        _saleGateway != address(0) &&
        _operational != address(0) &&
        _marketing != address(0) &&
        _treasury != address(0),
      'bad'
    );

    komV = _komV;
    beacon = _beacon;
    savior = _savior;
    saleGateway = _saleGateway;
    operational = _operational;
    marketing = _marketing;
    treasury = _treasury;

    operationalPercentage_d2 = 4000;
    marketingPercentage_d2 = 3000;
    treasuryPercentage_d2 = 3000;
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override proxied {}

  /**
   * @dev Get total number of chain staked supported
   */
  function allChainsStakedLength() external view virtual override returns (uint256) {
    return allChainsStaked.length;
  }

  /**
   * @dev Get total number of projects created
   */
  function allProjectsLength() external view virtual override returns (uint256) {
    return allProjects.length;
  }

  /**
   * @dev Get total number of payment Toked accepted
   */
  function allPaymentsLength() external view virtual override returns (uint256) {
    return allPayments.length;
  }

  /**
   * @dev Create new project for raise fund
   * @param _start Epoch date to start round 1
   * @param _duration Duration per booster (in seconds)
   * @param _sale Amount token project to sell (based on token decimals of project)
   * @param _price Token project price in payment decimal
   * @param _fee_d2 Fee project percent in each rounds in 2 decimal
   * @param _payment Tokens to raise
   * @param _targetSale Target sale on destination chain
   */
  function createProject(
    uint128 _start,
    uint128 _duration,
    uint256 _sale,
    uint256 _price,
    uint256[4] memory _fee_d2,
    address _payment,
    string[3] calldata _nameVersionMsg,
    uint128[2] calldata _voteStartEnd,
    uint128 _dstPaymentDecimals,
    address _targetSale
  ) external virtual onlyOwner whenNotPaused returns (address project) {
    require(
      _payment != address(0) &&
        _payment == allPayments[getPaymentIndex[_payment]] &&
        block.timestamp < _start &&
        allPayments.length > 0,
      'bad'
    );

    bytes memory data = abi.encodeWithSelector(
      IGovSaleRemote.init.selector,
      _start,
      _duration,
      _sale,
      _price,
      _fee_d2,
      _payment,
      _nameVersionMsg,
      _voteStartEnd,
      _dstPaymentDecimals,
      _targetSale
    );

    project = address(new BeaconProxy(beacon, data));

    allProjects.push(project);
    isKnown[project] = true;

    emit ProjectCreated(project, allProjects.length - 1);
  }

  /**
   * @dev Set new token to be accepted
   * @param _token New token address
   */
  function setPayment(address _token) external virtual override onlyOwner {
    require(_token != address(0), 'bad');
    if (allPayments.length > 0) require(_token != allPayments[getPaymentIndex[_token]], 'existed');

    allPayments.push(_token);
    getPaymentIndex[_token] = allPayments.length - 1;
  }

  /**
   * @dev Remove token as payment
   * @param _token Token address
   */
  function removePayment(address _token) external virtual override onlyOwner {
    require(_token != address(0), 'bad');
    require(allPayments.length > 0 && _token == allPayments[getPaymentIndex[_token]], '!found');

    uint256 indexToDelete = getPaymentIndex[_token];
    address addressToMove = allPayments[allPayments.length - 1];

    allPayments[indexToDelete] = addressToMove;
    getPaymentIndex[addressToMove] = indexToDelete;

    allPayments.pop();
    delete getPaymentIndex[_token];
  }

  function setChainStaked(uint256[] calldata _chainID) external virtual override onlyOwner {
    for (uint256 i = 0; i < _chainID.length; ++i) {
      if (allChainsStaked.length > 0 && allChainsStaked[getChainStakedIndex[_chainID[i]]] == _chainID[i]) continue;

      getChainStakedIndex[_chainID[i]] = allChainsStaked.length;
      allChainsStaked.push(_chainID[i]);
    }
  }

  function removeChainStaked(uint256[] calldata _chainID) external virtual override onlyOwner {
    require(allChainsStaked.length > 0, 'bad');

    for (uint256 i = 0; i < _chainID.length; ++i) {
      if (allChainsStaked[getChainStakedIndex[_chainID[i]]] != _chainID[i]) continue;

      uint256 indexToDelete = getChainStakedIndex[_chainID[i]];
      uint256 chainToMove = allChainsStaked[allChainsStaked.length - 1];

      allChainsStaked[indexToDelete] = chainToMove;
      getChainStakedIndex[chainToMove] = indexToDelete;

      allChainsStaked.pop();
      delete getChainStakedIndex[_chainID[i]];
    }
  }

  function config(
    address _komV,
    address _beacon,
    address _saleGateway,
    address _savior,
    address _operational,
    address _marketing,
    address _treasury
  ) external virtual override onlyOwner {
    require(
      _beacon != address(0) &&
        _saleGateway != address(0) &&
        _savior != address(0) &&
        _operational != address(0) &&
        _marketing != address(0) &&
        _treasury != address(0),
      'bad'
    );

    komV = _komV;
    beacon = _beacon;
    saleGateway = _saleGateway;
    savior = _savior;
    operational = _operational;
    marketing = _marketing;
    treasury = _treasury;
  }

  /**
   * @dev Config Factory percentage
   * @param _operationalPercentage Operational percentage in 2 decimal
   * @param _marketingPercentage Marketing percentage in 2 decimal
   * @param _treasuryPercentage Treasury percentage in 2 decimal
   */
  function setPercentage_d2(
    uint256 _operationalPercentage,
    uint256 _marketingPercentage,
    uint256 _treasuryPercentage
  ) external virtual onlyOwner {
    require(_operationalPercentage + _marketingPercentage + _treasuryPercentage == 10000, 'bad');
    operationalPercentage_d2 = _operationalPercentage;
    marketingPercentage_d2 = _marketingPercentage;
    treasuryPercentage_d2 = _treasuryPercentage;
  }

  function togglePause() external virtual onlyOwner {
    if (paused()) {
      _unpause();
    } else {
      _pause();
    }
  }

  function owner() public view virtual override(IGovFactory, OwnableUpgradeable) returns (address) {
    return super.owner();
  }
}

