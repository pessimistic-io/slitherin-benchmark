// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

// GMX All-in-one ACL
contract GMXACLSimpleVerForUUPS is OwnableUpgradeable, UUPSUpgradeable {
    address public safeAddress;
    address public safeModule;

    bytes32 private _checkedRole = hex"01";
    uint256 private _checkedValue = 1;
    string public constant NAME = "GMXACL";
    uint public constant VERSION = 1;

    function initialize(address _safeAddress, address _safeModule) initializer public {
        __gmx_acl_init(_safeAddress, _safeModule);
    }

    function __gmx_acl_init(address _safeAddress, address _safeModule) internal onlyInitializing {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __gmx_acl_init_unchained(_safeAddress, _safeModule);
    }

    function __gmx_acl_init_unchained(address _safeAddress, address _safeModule) internal onlyInitializing {
        require(_safeAddress != address(0), "Invalid safe address");
        require(_safeModule!= address(0), "Invalid module address");
        safeAddress = _safeAddress;
        safeModule = _safeModule;

        // make the given safe the owner of the current acl.
        _transferOwnership(_safeAddress);
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

    // GMX_ROUTER = "0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064"
    function approvePlugin(address _plugin) external onlySelf{}

    function swap(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOut,
        address _receiver
    ) external view onlySelf {
        require(_receiver == safeAddress, "Receiver Not Safe Address");
    }

    function swapTokensToETH(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOut,
        address payable _receiver
    ) external view onlySelf {
        require(_receiver == safeAddress, "Receiver Not Safe Address");
    }

    function swapETHToTokens(
        address[] memory _path,
        uint256 _minOut,
        address _receiver
    ) external view onlySelf {
        require(_receiver == safeAddress, "Receiver Not Safe Address");
    }

    // GMX_POSITION_ROUTER = "0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868"
    function createIncreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 _referralCode,
        address _callbackTarget
    ) external view onlySelf {
        require(_callbackTarget == address(0), "Not allow callback");
        require(_path.length == 1, "Not allow swap when createPosition");
    }

    function createIncreasePositionETH(
        address[] memory _path,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 _referralCode,
        address _callbackTarget
    ) external view onlySelf {
        require(_callbackTarget == address(0), "Not allow callback");
    }

    //TODO A callback function must be call to determine how much token is back to gnosis safe
    function createDecreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _acceptablePrice,
        uint256 _minOut,
        uint256 _executionFee,
        bool _withdrawETH,
        address _callbackTarget
    ) external view onlySelf {
        require(_receiver == safeAddress, "Receiver Not Safe Address");
        require(_callbackTarget == address(0), "Not allow callback");
    }

    // GMX_REWARD_ROUTER = "0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1"
    function stakeGmx(uint256 _amount) external view onlySelf {}

    function stakeEsGmx(uint256 _amount) external view onlySelf {}

    function unstakeGmx(uint256 _amount) external view onlySelf {}

    function unstakeEsGmx(uint256 _amount) external view onlySelf {}

    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external view onlySelf {}

    function mintAndStakeGlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external view onlySelf {}

    function mintAndStakeGlpETH(uint256 _minUsdg, uint256 _minGlp)
        external
        view
        onlySelf
    {}

    function unstakeAndRedeemGlp(
        address _tokenOut,
        uint256 _glpAmount,
        uint256 _minOut,
        address _receiver
    ) external view onlySelf {
        require(_receiver == safeAddress, "Receiver not safeAddress");
    }

    function unstakeAndRedeemGlpETH(
        uint256 _glpAmount,
        uint256 _minOut,
        address _receiver
    ) external view onlySelf {
        require(_receiver == safeAddress, "Receiver not safeAddress");
    }

    // GMX ORDER BOOK
    function createSwapOrder(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _triggerRatio, // tokenB / tokenA
        bool _triggerAboveThreshold,
        uint256 _executionFee,
        bool _shouldWrap,
        bool _shouldUnwrap
    ) external view onlySelf {}

    function updateSwapOrder(
        uint256 _orderIndex,
        uint256 _minOut,
        uint256 _triggerRatio,
        bool _triggerAboveThreshold
    ) external view onlySelf {}

    function cancelSwapOrder(uint256 _orderIndex) external view onlySelf {}

    function createIncreaseOrder(
        address[] memory _path,
        uint256 _amountIn,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        address _collateralToken,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold,
        uint256 _executionFee,
        bool _shouldWrap
    ) external view onlySelf {}

    function updateIncreaseOrder(
        uint256 _orderIndex,
        uint256 _sizeDelta,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external view onlySelf {}

    function cancelIncreaseOrder(uint256 _orderIndex) external view onlySelf {}

    function createDecreaseOrder(
        address _indexToken,
        uint256 _sizeDelta,
        address _collateralToken,
        uint256 _collateralDelta,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external view onlySelf {}

    function updateDecreaseOrder(
        uint256 _orderIndex,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) external onlySelf {}

    function cancelDecreaseOrder(uint256 _orderIndex) external onlySelf {}

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;

}

