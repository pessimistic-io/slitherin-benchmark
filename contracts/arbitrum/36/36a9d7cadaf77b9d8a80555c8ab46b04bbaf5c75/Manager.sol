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

  uint256 public GAS_LIMIT = 21000;
  uint256 public minLinkAmount = 0.1 ether;
  uint256 public MIN_ETH_AMOUNT = 0.02 ether;
  address public vaultImplementation;
  address public keeperImplementation;
  uint256 public vaultCounter;      // be used for tokenId calculation
  mapping (uint256 => address) public vaultMap;       // mapping(vaultId => vaultAddress)
  mapping (address => address) public upkeepMap;      // mapping(userAddress => keeperAddress)
  mapping (bytes => address) public strategies;     // mapping(strategyIdentifier => strategyAddress)
  uint256 public maxVaultsPerUser = 10;

  event UpkeepCreated(address upkeep, uint256 upkeepId, address owner);
  event UpkeepFunded(address upkeep, uint256 amount);
  event UpkeepDestroyed(address upkeep);
  event StrategyAdded(address strategy);

  constructor(
    address _keeperImp,
    address _vaultImp
  ) ERC721("Gamma Vault Manager", "GVM") {
    require(_keeperImp != address(0), "zero address");
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
    address _strategy = strategies[abi.encodePacked(_strategyId)];
    require(_strategy != address(0), "invalid strategy name");
    require(balanceOf(msg.sender) < 10, "exceed maximum vault count");
    if (_vaultType == VaultType.PERPETUAL) {
      require(msg.value > MIN_ETH_AMOUNT, "lower than minimum eth amount");
    }
    address vault = Clones.clone(vaultImplementation);
    uint256 vaultId = vaultCounter;
    _mint(msg.sender, vaultId);
    IPersonalVault(vault).initialize(vaultId, upkeepMap[msg.sender], _strategy, _inputs, _config);
    IKeeper(upkeepMap[msg.sender]).addVault(vaultMap[vaultId]);
    
    // update state variables
    vaultMap[vaultId] = vault;
    vaultCounter = vaultCounter + 1;
  }

  function burnVault(uint256 _vaultId) external {
    require(ownerOf(_vaultId) == msg.sender, "invalid vault owner");
    _burn(_vaultId);
    IKeeper(upkeepMap[msg.sender]).removeVault(vaultMap[_vaultId]);
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
      GAS_LIMIT,        // The maximum amount of gas that will be used to execute your function on-chain
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
          uint256(oldNonce)
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

  function destroyUpkeep(address _account) external {
    address _upkeep = upkeepMap[_account];
    require(_upkeep != address(0), "no upkeep for the account");
    /* code for withdrawing LINK fund and vault destroy confirm */
    upkeepMap[_account] = address(0);

    emit UpkeepDestroyed(_upkeep);
  }

  function addStrategy(address _strategy) external onlyOwner {
    require(_strategy != address(0), "zero address");
    bytes memory strategyIdentifier = abi.encodePacked(IStrategy(_strategy).name());
    strategies[strategyIdentifier] = _strategy;

    emit StrategyAdded(_strategy);
  }

  function setKeeperImplementation(address _keeperImp) external onlyOwner {
    keeperImplementation = _keeperImp;
  }

  function setMinLinkAmount(uint256 _amount) external onlyOwner {
    require(_amount != 0, "zero amount");
    minLinkAmount = _amount;
  }

  //////////////////////////////////
  ////    Internal Functions    ////
  //////////////////////////////////

  function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override {
    super._beforeTokenTransfer(from, to, tokenId);
    require(upkeepMap[to] != address(0), "cant transfer");
    IKeeper(upkeepMap[from]).removeVault(vaultMap[tokenId]);
    IKeeper(upkeepMap[to]).addVault(vaultMap[tokenId]);
  }
}

