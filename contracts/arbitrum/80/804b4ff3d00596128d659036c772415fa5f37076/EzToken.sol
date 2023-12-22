// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC20PausableUpgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./IEzTreasury.sol";

contract EzTokenV1 is Initializable, ERC20PausableUpgradeable, AccessControlEnumerableUpgradeable {
  //角色权限定义
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
  bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
  //是否已关联主合约
  bool private contacted;
  //ezio主合约
  IEzTreasury public treasury;
  //报错信息常量
  string internal constant ALREADY_CONTACTED = "EzToken:Contract Already Contacted";

  function __EzToken_init(string memory name_,string memory symbol_) internal onlyInitializing {
    __ERC20_init(name_, symbol_);
    __Pausable_init();
    __EzToken_init_unchained();
  }

  function __EzToken_init_unchained() internal onlyInitializing {
    //赋予合约发布者管理员的权限
    _grantRole(GOVERNOR_ROLE, msg.sender);
  }

  /**
  * @notice           关联主合约
  * @param treasury_      ezio主合约
  */
  function contact(IEzTreasury treasury_) external onlyRole(GOVERNOR_ROLE){
    require(!contacted, ALREADY_CONTACTED);
    treasury = treasury_;
    _grantRole(MINTER_ROLE, address(treasury_));
    _grantRole(BURNER_ROLE, address(treasury_));
    contacted = true;
  }

  /**
  * @notice          开采token,onlyRole(MINTER_ROLE)修饰符确保只有合约初始化时设定的minter账户才能执行mint方法
  * @param to        获得token的账户
  * @param amount    挖矿的数量
  */
  function mint(address to, uint256 amount) public virtual onlyRole(MINTER_ROLE){
    _mint(to,amount);
  }

  /**
  * @notice          销毁token,onlyRole(BURNER_ROLE)修饰符确保只有合约初始化时设定的burner账户才能执行burn方法
  * @param from      销毁token的账户
  * @param amount    销毁的数量
  */
  function burn(address from, uint256 amount) public virtual onlyRole(BURNER_ROLE) {
    _burn(from,amount);
  }

  /**
  * @notice          暂停转账功能
  */
  function pause() external onlyRole(GOVERNOR_ROLE){
    _pause();
  }

  /**
  * @notice          恢复转账功能
  */
  function unpause() external onlyRole(GOVERNOR_ROLE){
    _unpause();
  }

  uint256[49] private __gap;
}

