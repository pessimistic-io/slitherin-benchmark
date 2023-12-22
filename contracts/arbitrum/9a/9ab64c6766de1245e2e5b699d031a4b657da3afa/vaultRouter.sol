// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./ILpDepositor.sol";
import "./IVaultFactory.sol";
import "./IERC20.sol";
import "./INeadVault.sol";

import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";



contract vaultRouter is Initializable, AccessControlEnumerableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;


    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    address admin;
    address pauser;
    address setter; 
    address ram;
    address neadRam;
    address factory;
    address _vault;
    address lpDepositor;
    
    mapping(address => address) public vaultForPool;
    mapping(address => address) public tokenForPool;
    event Deposited(address indexed user, address indexed pool, uint amount);
    event Withdrawn(address indexed user, address indexed pool, uint amount);
 
 
    constructor() {
        _disableInitializers();
        }

    function initialize(address _admin, address _pauser, address _ram, address _neadRam, address _factory) external initializer {
        __Pausable_init();
        __AccessControlEnumerable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _pauser);
        ram = _ram;
        neadRam = _neadRam;
        factory = _factory;
    }
    function setAddress(address _lpDepositor) external onlyRole(PAUSER_ROLE) {
        lpDepositor = _lpDepositor;
    }
    //Deposit to any Ennead vault. If one does not exist, it makes a new one before sending funds to it.
    function deposit(address pool, uint256 amount) external {
              _vault = vaultForPool[pool];
        IVault vault = IVault(_vault);
        if(vaultForPool[pool] == address(0)) {
            string memory _symbol = IERC20(pool).symbol(); 
            string memory name = string(abi.encodePacked("nv-", _symbol, ""));
            string memory symbol = string(abi.encodePacked("nv-", _symbol));
           address _tokenForPool = ILpDepositor(lpDepositor).tokenForPool(pool);
            if(_tokenForPool == (address(0))) {
                _giveApproval(pool, lpDepositor);
                ILpDepositor(lpDepositor).deposit(pool, amount);
                ILpDepositor(lpDepositor).withdraw(pool, amount);
            }
            _tokenForPool = ILpDepositor(lpDepositor).tokenForPool(pool);
            tokenForPool[pool] = _tokenForPool;
            vaultForPool[pool] = IVaultFactory(factory).createVault(pool, name, symbol, ram, neadRam, _tokenForPool);
             _giveApproval(pool, _vault);
        } 
         
          IERC20Upgradeable(pool).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
      
        vault.deposit(amount, msg.sender); 
       
    }
    //Withdraw from any Ennead vault granted it exists. 
    function withdraw(address pool, uint amount) external whenNotPaused nonReentrant { 
         _vault = vaultForPool[pool];
 
        require(_vault != address(0), "Unknown pool");
        IVault vault = IVault(_vault);
        vault.withdraw(amount, msg.sender, msg.sender);
        IERC20Upgradeable(pool).safeTransfer(msg.sender, amount);
 
        emit Withdrawn(msg.sender, pool, amount);
    }
    //Check pending Rewards for a given user in a given vault without converting to neadRam or LP
    function pendingRewards(address pool, address user) external returns(uint256) {
         _vault = vaultForPool[pool];
         IVault vault = IVault(_vault);
        return vault.pendingRewards(user, ram); 
    }
    //Claim rewards on behalf of user without the need for permissions or multiple transfers. 
    // Tokens are deposited to user directly from vault, saving some gas.
    function claim(address pool, address user, bool LP ) external {
        _vault = vaultForPool[pool];
         IVault vault = IVault(_vault);
         vault.claim(user, LP);
    }
    
        function _giveApproval(address pool, address vault) internal  {
        IERC20Upgradeable _depositToken = IERC20Upgradeable(pool); 
        _depositToken.approve(vault, type(uint256).max);
    }
}


