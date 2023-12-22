// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract StargateACLUUPS is OwnableUpgradeable, UUPSUpgradeable {
    struct lzTxObj {
        uint256 dstGasForCall;
        uint256 dstNativeAmount;
        bytes dstNativeAddr;
    }


    address public safeAddress;
    address public safeModule;
    mapping(uint256 => bool) public allowed_lp_pid;
    mapping(uint256 => bool) public allowed_pool_pid;
    bytes32 public claimer_role;

    bytes32 private _checkedRole = hex"01";
    uint256 private _checkedValue = 1;
    string public constant NAME = "StargateACL";
    uint public constant VERSION = 1;

    function initialize(address _safeAddress, address _safeModule) initializer public {
        __stargate_acl_init(_safeAddress, _safeModule);
    }

    function __stargate_acl_init(address _safeAddress, address _safeModule) internal onlyInitializing {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __stargate_acl_init_unchained(_safeAddress, _safeModule);
    }

    function __stargate_acl_init_unchained(address _safeAddress, address _safeModule) internal onlyInitializing {
        require(_safeAddress != address(0), "Invalid safe address");
        require(_safeModule!= address(0), "Invalid module address");
        safeAddress = _safeAddress;
        safeModule = _safeModule;


        // make the given safe the owner of the current acl.
        _transferOwnership(_safeAddress);
    }

    // set the pool Id for adding liquidity
    function setPoolidForLiquidity(uint256 _pid, bool _status) external onlySafe {
        allowed_pool_pid[_pid] = _status;
    }

    // set the pid for the staking pool
    function setPoolidForStaking(uint256 _pid, bool _status) external onlySafe {
        allowed_lp_pid[_pid] = _status;
    }

    function configClaimerRole(bytes32 _role_name) external onlySafe{
        claimer_role = _role_name;
    }



    // modifiers
    modifier onlySelf() {
        require(address(this) == msg.sender, "Caller is not inner");
        _;
    }

    modifier onlyModule() {
        require(safeModule == msg.sender, "Caller is not the module");
        _;
    }

    modifier onlySafe() {
        require(safeAddress == msg.sender, "Caller is not the safe");
        _;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function bytesToAddress(bytes memory _baddr) internal pure  returns (address _addr){
        assembly {
            _addr := mload(add(_baddr, 20))
        }
    }

    function _callSelf(
        bytes32 _role,
        uint256 _value,
        bytes calldata data
    ) private returns (bool) {
        _checkedRole = _role;
        _checkedValue = _value;
        (bool success, ) = address(this).staticcall(data);
        _checkedRole = hex"01"; // gas refund.
        _checkedValue = 1;
        return success;
    }

    function check(
        bytes32 _role,
        uint256 _value,
        bytes calldata data
    ) external onlyModule returns (bool) {
        bool success = _callSelf(_role, _value, data);
        return success;
    }

// ACL functions
    //ERC20 Router
    function addLiquidity(
            uint256 poolId,
            uint256, // _amountLD
            address _to
        ) external view {
        require(allowed_pool_pid[poolId] == true, "pid not allowed");
        require(_to == safeAddress, "To not safe address");
    }

    function instantRedeemLocal(
        uint16 _srcPoolId,
        uint256, //_amountLP,
        address _to
        ) external view onlySelf  {
        require(allowed_pool_pid[_srcPoolId] == true, "pid not allowed");
        require (_to == safeAddress, "To not safe address");
    }


    //LPStaking
    function deposit(
        uint256 _pid, 
        uint256 amount
        ) public view onlySelf  {
        if (_checkedRole == claimer_role) {
            require(amount == 0, "claimer_role not allowed to deposit");
        }
        require(allowed_lp_pid[_pid] == true, "pid not allowed");
    }

    function withdraw(
        uint256 _pid, 
        uint256 // amount
    ) external view onlySelf {
        require(allowed_lp_pid[_pid] == true, "pid not allowed");
    }
}




