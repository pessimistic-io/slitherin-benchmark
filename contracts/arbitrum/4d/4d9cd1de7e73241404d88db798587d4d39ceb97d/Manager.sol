// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "./Ownable2StepUpgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./SafeERC20.sol";
import "./ClonesUpgradeable.sol";
import { State, KeeperRegistryInterface } from "./KeeperRegistryInterface.sol";
import "./IERC677.sol";
import "./AggregatorV3Interface.sol";
import "./IPersonalVault.sol";
import "./IKeeper.sol";
import "./IStrategy.sol";

/**
 * @notice
 *  This is a manager contract that manages all users, vaults and strategies.
 *  When a user create a vault, mint a NFT that has vault information to user.
 */
contract Manager is ERC721EnumerableUpgradeable, Ownable2StepUpgradeable {
  bytes4 private constant FUNC_SELECTOR = bytes4(
    keccak256("register(string,bytes,address,uint32,address,bytes,uint96,uint8,address)")
  );
  address public constant REGISTRAR_ADDRESS = 0x4F3AF332A30973106Fe146Af0B4220bBBeA748eC;       // address on arbitrum chain
  IERC677 public constant ERC677LINK = IERC677(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4);              // address on arbitrum chain
  
  KeeperRegistryInterface public constant keeperRegistry = KeeperRegistryInterface(0x75c0530885F385721fddA23C539AF3701d6183D4);    // address on arbitrum chain

  uint32 public gasLimit;
  uint256 public minLinkAmount;
  uint256 public minEthAmount;
  address public vaultImplementation;
  address public keeperImplementation;
  uint256 public vaultCounter;      // be used for tokenId calculation
  uint256 public maxVaultsPerUser;
  mapping (uint256 => address) public vaultMap;       // mapping(vaultId => vaultAddress)
  mapping (address => address) public upkeepMap;      // mapping(userAddress => keeperAddress)
  mapping (address => uint256) public upkeepTrash;    // mapping(accountAddress => upkeepId)
  mapping (bytes32 => address) public strategies;     // mapping(strategyIdentifier => strategyAddress)
  mapping (address => address) public perpVaults;     // perpetual vaults list
  mapping (address => AggregatorV3Interface) public cPriceFeed;    // chainlink price data feed

  event UpkeepCreated(address upkeep, uint256 upkeepId, address owner);
  event UpkeepFunded(address upkeep, uint256 amount);
  event UpkeepDestroyed(address upkeep);
  event StrategyAdded(address strategy);
  event VaultCreated(address owner, uint256 vaultId, address vault, address strategy);
  event VaultBurnt(uint256 vaultId);

  function initialize(
    address _keeperImp,
    address _vaultImp
  ) public initializer {
    require(_keeperImp != address(0), "zero address");
    require(_vaultImp != address(0), "zero address");
    __ERC721_init("Gamma Vault Manager", "GVM0D1");
    __Ownable2Step_init();
    vaultImplementation = _vaultImp;
    keeperImplementation = _keeperImp;
    ERC677LINK.approve(address(keeperRegistry), type(uint256).max);
    gasLimit = 5_000_000;
    minLinkAmount = 20 ether;
    minEthAmount = 0.02 ether;
    maxVaultsPerUser = 10;
  }

  /**
   * @notice
   *  create a vault that belongs only to a vault creator
   */
  function createVault(string memory _strategyId, address _hypervisor, address _hedgeToken, bytes memory _config) external {
    // only keeper owning account can create a vault
    require(upkeepMap[msg.sender] != address(0), "no keeper");
    bytes32 hash = keccak256(abi.encodePacked(_strategyId));
    address _strategy = strategies[hash];
    require(_strategy != address(0), "invalid strategy name");
    require(perpVaults[_hypervisor] != address(0), "no vault for hedge token");
    require(balanceOf(msg.sender) < 10, "exceed maximum vault count");
    
    address vault = ClonesUpgradeable.clone(vaultImplementation);
    vaultCounter = vaultCounter + 1;
    uint256 vaultId = vaultCounter;
    vaultMap[vaultId] = vault;
    _mint(msg.sender, vaultId);
    IPersonalVault(vault).initialize(vaultId, upkeepMap[msg.sender], _strategy, _hypervisor, _hedgeToken, _config);

    emit VaultCreated(msg.sender, vaultId, vault, _strategy);
  }

  function burnVault(uint256 _vaultId) external {
    require(ownerOf(_vaultId) == msg.sender, "invalid vault owner");
    IPersonalVault(vaultMap[_vaultId]).prepareBurn();
    _burn(_vaultId);

    emit VaultBurnt(_vaultId);
  }

  function createUpkeep(uint256 amount) external {
    require(amount >= minLinkAmount, "less than minimum");
    require(upkeepMap[msg.sender] == address(0), "already have a keeper");
    SafeERC20.safeTransferFrom(
      ERC677LINK,
      msg.sender,
      address(this),
      amount
    );

    address upkeep  = ClonesUpgradeable.clone(keeperImplementation);
    IKeeper(upkeep).initialize(msg.sender);
    (State memory state, ,) = keeperRegistry.getState();
    uint256 oldNonce = state.nonce;
    bytes memory data = abi.encodeWithSelector(
      FUNC_SELECTOR,
      "keeper",
      hex"",            // encrypted email, useless
      upkeep,
      gasLimit,        // The maximum amount of gas that will be used to execute your function on-chain
      address(this),    // admin address of upkeep
      hex"",            // registration data
      amount,           // The amount of LINK (in Wei) to fund a Upkeep
      0,
      address(this)
    );
    ERC677LINK.transferAndCall(REGISTRAR_ADDRESS, amount, data);
    (state, ,) = keeperRegistry.getState();
    uint256 newNonce = state.nonce;
    uint256 upkeepId;
    if (newNonce == oldNonce + 1) {
      upkeepId = uint256(
        keccak256(abi.encodePacked(
          blockhash(block.number - 1),
          address(keeperRegistry),
          uint32(oldNonce)
        ))
      );
      IKeeper(upkeep).setUpkeepId(upkeepId);
    } else {
      revert("auto-approve disabled");
    }

    upkeepMap[msg.sender] = upkeep;

    emit UpkeepCreated(upkeep, upkeepId, msg.sender);
  }

  function fundUpkeep(address _account, uint256 _amount) external {
    address _upkeep = upkeepMap[_account];
    require(_upkeep != address(0), "no upkeep for the account");
    uint256 upkeepId = IKeeper(_upkeep).upkeepId();
    SafeERC20.safeTransferFrom(
      ERC677LINK,
      msg.sender,
      address(this),
      _amount
    );
    keeperRegistry.addFunds(upkeepId, uint96(_amount));

    emit UpkeepFunded(_upkeep, _amount);
  }

  function destroyUpkeep() external {
    address _upkeep = upkeepMap[msg.sender];
    require(_upkeep != address(0), "no upkeep for the account");
    uint256 upkeepId = IKeeper(_upkeep).upkeepId();
    keeperRegistry.cancelUpkeep(upkeepId);
    require(balanceOf(msg.sender) == 0, "upkeep is not empty");
    upkeepMap[msg.sender] = address(0);
    upkeepTrash[msg.sender] = upkeepId;

    emit UpkeepDestroyed(_upkeep);
  }

  /**
   * @notice
   *  LINK token can be withdrawed only after 50 blocks from when upkeep destroyed
   * @param _recipient address to receive withdrawed LINK token
   */
  function withdrawFundsFromUpkeep(address _recipient) external {
    uint256 upkeepId = upkeepTrash[msg.sender];
    require(upkeepId != 0, "no upkeep for the account");
    keeperRegistry.withdrawFunds(upkeepId, _recipient);
    delete upkeepTrash[msg.sender];
  }

  function addStrategy(address _strategy) external onlyOwner {
    require(_strategy != address(0), "zero address");
    bytes32 strategyIdentifier = keccak256(abi.encodePacked(IStrategy(_strategy).name()));
    require(strategies[strategyIdentifier] == address(0), "name already used");
    strategies[strategyIdentifier] = _strategy;

    emit StrategyAdded(_strategy);
  }

  function setKeeperImplementation(address _keeperImp) external onlyOwner {
    keeperImplementation = _keeperImp;
  }

  function setVaultImplementation(address _vaultImp) external onlyOwner {
    vaultImplementation = _vaultImp;
  }

  function setMinLinkAmount(uint256 _amount) external onlyOwner {
    require(_amount != 0, "zero amount");
    minLinkAmount = _amount;
  }

  function setMinEthAmount(uint256 _amount) external onlyOwner {
    minEthAmount = _amount;
  }

  function setGasLimit(uint32 _gasLimit) external onlyOwner {
    require(_gasLimit != 0, "zero value");
    gasLimit = _gasLimit;
  }

  function setUpkeepGasLimit(uint32 _gasLimit) external {
    address _upkeep = upkeepMap[msg.sender];
    require(_upkeep != address(0), "zero address");
    uint256 upkeepId = IKeeper(_upkeep).upkeepId();
    keeperRegistry.setUpkeepGasLimit(upkeepId, _gasLimit);
  }

  // function setVaultLock(uint256 vaultId, bool lock) external onlyOwner {
  //   address vault = vaultMap[vaultId];
  //   require(vault != address(0), "zero address");
  //   IPersonalVault(vault).setLock(lock);
  // }

  function setPerpVaults(address hypervisor, address _vault) external onlyOwner {
    require(hypervisor != address(0), "zero address");
    perpVaults[hypervisor] = _vault;
  }

  function setPriceFeed(address token, address priceFeed) external onlyOwner {
    require(token != address(0), "zero address");
    require(priceFeed != address(0), "zero address");
    cPriceFeed[token] = AggregatorV3Interface(priceFeed);
  }

  //////////////////////////////
  ////    View Functions    ////
  //////////////////////////////

  function getTokenPrice(address token) external view returns (uint256) {
    (, int256 answer, , , ) = cPriceFeed[token].latestRoundData();
    return uint256(answer);
  }

  //////////////////////////////////
  ////    Internal Functions    ////
  //////////////////////////////////

  function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override {
    super._beforeTokenTransfer(from, to, tokenId, batchSize);
    if (from != address(0)) {
      IKeeper(upkeepMap[from]).removeVault(vaultMap[tokenId]);
    }
    if (to != address(0)) {
      IKeeper(upkeepMap[to]).addVault(vaultMap[tokenId]);
    }
  }
}

