// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "./Ownable.sol";
import "./ERC721Enumerable.sol";
import "./SafeERC20.sol";
import "./Clones.sol";
import { State, KeeperRegistryInterface } from "./KeeperRegistryInterface.sol";
import "./IERC677.sol";
import "./IPersonalVault.sol";
import "./IKeeper.sol";
import "./IStrategy.sol";

/**
 * @notice
 *  This is a manager contract that manages all users, vaults and strategies.
 *  When a user create a vault, mint a NFT that has vault information to user.
 */
contract Manager is ERC721Enumerable, Ownable {
  enum VaultType {
    STANDARD,
    PERPETUAL
  }
  bytes4 private constant FUNC_SELECTOR = bytes4(
    keccak256("register(string,bytes,address,uint32,address,bytes,uint96,uint8,address)")
  );
  address public constant REGISTRAR_ADDRESS = 0x4F3AF332A30973106Fe146Af0B4220bBBeA748eC;       // address on arbitrum chain
  IERC677 public constant ERC677LINK = IERC677(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4);              // address on arbitrum chain
  
  KeeperRegistryInterface public keeperRegistry = KeeperRegistryInterface(0x75c0530885F385721fddA23C539AF3701d6183D4);    // address on arbitrum chain

  uint256 public gasLimit = 21000;
  uint256 public minLinkAmount = 10 ether;
  uint256 public minEthAmount = 0.02 ether;
  address public vaultImplementation;
  address public keeperImplementation;
  uint256 public vaultCounter;      // be used for tokenId calculation
  mapping (uint256 => address) public vaultMap;       // mapping(vaultId => vaultAddress)
  mapping (address => address) public upkeepMap;      // mapping(userAddress => keeperAddress)
  mapping (address => uint256) public upkeepTrash;    // mapping(accountAddress => upkeepId)
  mapping (bytes32 => address) public strategies;     // mapping(strategyIdentifier => strategyAddress)
  uint256 public maxVaultsPerUser = 10;

  event UpkeepCreated(address upkeep, uint256 upkeepId, address owner);
  event UpkeepFunded(address upkeep, uint256 amount);
  event UpkeepDestroyed(address upkeep);
  event StrategyAdded(address strategy);
  event VaultCreated(address owner, uint256 vaultId, address vault, VaultType vaultType, address strategy);
  event VaultBurnt(uint256 vaultId);

  constructor(
    address _keeperImp,
    address _vaultImp
  ) ERC721("Gamma Vault Manager", "GVM") {
    require(_keeperImp != address(0), "zero address");
    require(_vaultImp != address(0), "zero address");
    vaultImplementation = _vaultImp;
    keeperImplementation = _keeperImp;
    ERC677LINK.approve(address(keeperRegistry), type(uint256).max);
  }

  /**
   * @notice
   *  create a vault that belongs only to a vault creator
   */
  function createVault(VaultType _vaultType, string memory _strategyId, address[] memory _inputs, bytes memory _config) external payable {
    // only keeper owning account can create a vault
    require(upkeepMap[msg.sender] != address(0), "no keeper");
    bytes32 hash = keccak256(abi.encodePacked(_strategyId));
    address _strategy = strategies[hash];
    require(_strategy != address(0), "invalid strategy name");
    require(balanceOf(msg.sender) < 10, "exceed maximum vault count");
    if (_vaultType == VaultType.PERPETUAL) {
      require(msg.value >= minEthAmount, "lower than minimum eth amount");
    }
    address vault = Clones.clone(vaultImplementation);
    vaultCounter = vaultCounter + 1;
    uint256 vaultId = vaultCounter;
    vaultMap[vaultId] = vault;
    _mint(msg.sender, vaultId);
    IPersonalVault(vault).initialize{value: msg.value}(vaultId, upkeepMap[msg.sender], _strategy, _inputs, _config);
    
    // update state variables

    emit VaultCreated(msg.sender, vaultId, vault, _vaultType, _strategy);
  }

  function burnVault(uint256 _vaultId) external {
    require(ownerOf(_vaultId) == msg.sender, "invalid vault owner");
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

    address upkeep  = Clones.clone(keeperImplementation);
    IKeeper(upkeep).initialize();
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

  function setGasLimit(uint256 _gasLimit) external onlyOwner {
    require(_gasLimit != 0, "zero value");
    gasLimit = _gasLimit;
  }

  //////////////////////////////////
  ////    Internal Functions    ////
  //////////////////////////////////

  function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override {
    super._beforeTokenTransfer(from, to, tokenId);
    if (from != address(0)) {
      IKeeper(upkeepMap[from]).removeVault(vaultMap[tokenId]);
    }
    if (to != address(0)) {
      IKeeper(upkeepMap[to]).addVault(vaultMap[tokenId]);
    }
  }
}

