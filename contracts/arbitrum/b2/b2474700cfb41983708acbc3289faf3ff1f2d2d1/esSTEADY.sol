// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ERC20.sol";
import "./Ownable.sol";
import "./EnumerableSet.sol";


contract esSTEADY is ERC20("Escrowed Steadefi", "esSTEADY"), Ownable {
  using EnumerableSet for EnumerableSet.AddressSet;

  /* ========== STATE VARIABLES ========== */

  // Address of token manager
  address public tokenManager;
  // Addresses allowed to send/receive esSteady
  EnumerableSet.AddressSet private _transferWhitelist;


  /* ========== EVENTS ========== */

  event SetTransferWhitelist(address account, bool add);
  event SetTokenManager(address tokenManager);

  /* ========== MODIFIERS ========== */

  /**
   * Only Token Manager allowed
   */
  modifier onlyTokenManager() {
    require(msg.sender == tokenManager, "Only TokenManager");
    _;
  }

  /* ========== CONSTRUCTOR ========== */

  constructor() {
    _transferWhitelist.add(address(this));
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
   * Returns length of transferWhitelist array
   * @return transferWhitelist length in uint256
   */
  function transferWhitelistLength() external view returns (uint256) {
    return _transferWhitelist.length();
  }

  /**
   * Returns transferWhitelist array item's address for "index"
   * @param _index index of whitelist to return
   * @return transferWhitelistItem address at index
   */
  function transferWhitelist(uint256 _index) external view returns (address) {
    return _transferWhitelist.at(_index);
  }

  /**
   * Returns if "account" is allowed to send/receive esSteady
   * @param _account address of account to check
   * @return isTransferWhitelisted boolean
   */
  function isTransferWhitelisted(address _account) external view returns (bool) {
    return _transferWhitelist.contains(_account);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
   * Mints esSTEADY tokens
   * @param _to address to mint tokens to
   * @param _amount amount of tokens to mint in uint256
   */
  function mint(address _to, uint256 _amount) external onlyTokenManager {
    _mint(_to, _amount);
  }

  /**
   * Burn caller's esSTEADY tokens
   * @param _amount amount of tokens to burn in uint256
   */
  function burn(uint256 _amount) external {
    _burn(msg.sender, _amount);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
   * Hook override to forbid transfers except from whitelisted addresses and minting
   * @param _from sender address
   * @param _to receiver address
   */
  function _beforeTokenTransfer(address _from, address _to, uint256 /* _amount */) internal view override {
    require(_from == address(0) || _transferWhitelist.contains(_from) || _transferWhitelist.contains(_to), "transfer: not allowed");
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  /**
   * Adds or removes addresses from the transferWhitelist
   * @param _account address to be added or removed from transfer whitelist
   * @param _add boolean to determine adding or removal of address to whitelist
   */
  function updateTransferWhitelist(address _account, bool _add) external onlyOwner {
    require(_account != address(this), "updateTransferWhitelist: Cannot remove esSteady from whitelist");

    if (_add) _transferWhitelist.add(_account);
    else _transferWhitelist.remove(_account);

    emit SetTransferWhitelist(_account, _add);
  }

  /**
   * Updates the tokenManager address
   * @param _tokenManager address of tokenManager
   */
  function updateTokenManager(address _tokenManager) external onlyOwner {
    tokenManager = _tokenManager;

    emit SetTokenManager(_tokenManager);
  }
}

