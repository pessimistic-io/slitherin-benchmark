// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC20PausableUpgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./IEzVault.sol";

contract EzTokenV1 is Initializable, ERC20PausableUpgradeable, AccessControlEnumerableUpgradeable {
  //Role Permission Definition
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
  bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
  //Whether the main contract has been linked
  bool private contacted;
  //vault contract
  IEzVault public vault;
  //Error Message Constant
  string internal constant ALREADY_CONTACTED = "EzToken:Contract Already Contacted";

  function __EzToken_init(string memory name_,string memory symbol_) internal onlyInitializing {
    __ERC20_init(name_, symbol_);
    __Pausable_init();
    __EzToken_init_unchained();
  }

  function __EzToken_init_unchained() internal onlyInitializing {
    //Granting the contract deployer administrative privileges
    _grantRole(GOVERNOR_ROLE, msg.sender);
  }

  /**
  * @notice           Linking the main contract
  * @param vault_      ezio main contract
  */
  function contact(IEzVault vault_) external onlyRole(GOVERNOR_ROLE){
    require(!contacted, ALREADY_CONTACTED);
    vault = vault_;
    _grantRole(MINTER_ROLE, address(vault_));
    _grantRole(BURNER_ROLE, address(vault_));
    contacted = true;
  }

  /**
  * @notice          Mining token, the onlyRole(MINTER_ROLE) modifier ensures that only the minter account set at contract initialization can execute the mint function
  * @param to        Account to obtain the token
  * @param amount    Mining quantity
  */
  function mint(address to, uint256 amount) public virtual onlyRole(MINTER_ROLE){
    _mint(to,amount);
  }

  /**
  * @notice          Burning token, the onlyRole(BURNER_ROLE) modifier ensures that only the burner account set at contract initialization can execute the burn function
  * @param from      Account to burn the token
  * @param amount    Burning quantity
  */
  function burn(address from, uint256 amount) public virtual onlyRole(BURNER_ROLE) {
    _burn(from,amount);
  }

  /**
  * @notice          Pausing the transfer function
  */
  function pause() external onlyRole(GOVERNOR_ROLE){
    _pause();
  }

  /**
  * @notice          Resuming the transfer function
  */
  function unpause() external onlyRole(GOVERNOR_ROLE){
    _unpause();
  }

  uint256[49] private __gap;
}

