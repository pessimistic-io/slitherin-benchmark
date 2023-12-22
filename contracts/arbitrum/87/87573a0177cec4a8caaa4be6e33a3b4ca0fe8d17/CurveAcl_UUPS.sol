// 61f5a666f1e2638ad41e1350907deced9dabdb64
// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.17;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";

interface IOracle {
    function getUSDPrice(address _token) external returns (uint256, uint256);
    function getUSDValue(address _token, uint256 _amount) external returns (uint256);
}

interface IERC20 {
    function decimals() external view returns (uint8);
}

contract CurveAcl is OwnableUpgradeable, UUPSUpgradeable {
    address public safeAddress;
    address public safeModule;

    bytes32 private _checkedRole = hex"01";
    uint256 private _checkedValue = 1;
    string public constant NAME = "CurveAcl";
    uint public constant VERSION = 1;
    

    uint256 public constant SLIPPAGE_BASE = 10000;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant ZERO_ADDRESS = address(0);
    mapping(bytes32 => uint256) public roleSlippage;
    mapping(bytes32 => mapping (address => bool)) public swapPairWhitelist;  // role => token => bool
    mapping(bytes32 => mapping (address => bool)) public swapInTokenWhitelist;
    mapping(bytes32 => mapping (address => bool)) public swapOutTokenWhitelist;
                              
    address public oracle;                                                    

    bool public isCheckSwapPair = true;    //
    bool public isCheckSwapToken = true;
    bool public isCheckRoleSlippage = true;
    
    struct SwapPair {
        bytes32 role;
        address pair; 
        bool pairStatus;
    }

    struct SwapInToken {
        bytes32 role;
        address token; 
        bool tokenStatus;
    }

    struct SwapOutToken {
        bytes32 role;
        address token; 
        bool tokenStatus;
    }

    enum FLAG {
        STABLE_SWAP,
        V2_EXACT_IN
    }

    /// @notice Constructor function for Acl
    /// @param _safeAddress the Gnosis Safe (GnosisSafeProxy) instance's address
    /// @param _safeModule the CoboSafe module instance's address
    function initialize(
        address _safeAddress,
        address _safeModule
    ) public initializer {
        __CurveAcl_init(_safeAddress, _safeModule);
    }

    function __CurveAcl_init(
        address _safeAddress,
        address _safeModule
    ) internal onlyInitializing {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __CurveAcl_init_unchained(_safeAddress, _safeModule);
    }

    function __CurveAcl_init_unchained(
        address _safeAddress,
        address _safeModule
    ) internal onlyInitializing {
        require(_safeAddress != address(0), "Invalid safe address");
        require(_safeModule != address(0), "Invalid module address");
        safeAddress = _safeAddress;
        safeModule = _safeModule;

        // make the given safe the owner of the current acl.
        _transferOwnership(_safeAddress);
    }

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

    function check(
        bytes32 _role,
        uint256 _value,
        bytes calldata data
    ) external onlyModule returns (bool) {
        _checkedRole = _role;
        _checkedValue = _value;
        (bool success, ) = address(this).staticcall(data);
        _checkedRole = hex"01";
        _checkedValue = 1;
        return success;
    }

    fallback() external {
        revert("Unauthorized access");
    }

    // ACL set methods

    function setSwapPair(bytes32 _role, address _pair, bool _pairStatus) external onlySafe returns (bool){    
        require(swapPairWhitelist[_role][_pair] != _pairStatus, "swappair pairStatus existed");
        swapPairWhitelist[_role][_pair] = _pairStatus;
        return true;
    }

    function setSwapPairs(SwapPair[] calldata _swapPair) external onlySafe returns (bool){    
        for (uint i=0; i < _swapPair.length; i++) { 
            swapPairWhitelist[_swapPair[i].role][_swapPair[i].pair] = _swapPair[i].pairStatus;
        }
        return true;
    }

    function setSwapInToken(bytes32 _role, address _token, bool _tokenStatus) external onlySafe returns (bool){   // sell
        require(swapInTokenWhitelist[_role][_token] != _tokenStatus, "swapIntoken tokenStatus existed");
        swapInTokenWhitelist[_role][_token] = _tokenStatus;
        return true;
    }

    function setSwapInTokens(SwapInToken[] calldata _swapInToken) external onlySafe returns (bool){    
        for (uint i=0; i < _swapInToken.length; i++) { 
            swapInTokenWhitelist[_swapInToken[i].role][_swapInToken[i].token] = _swapInToken[i].tokenStatus;
        }
        return true;
    }

    function setSwapOutToken(bytes32 _role, address _token, bool _tokenStatus) external onlySafe returns (bool){   // buy
        require(swapOutTokenWhitelist[_role][_token] != _tokenStatus, "swapIntoken tokenStatus existed");
        swapOutTokenWhitelist[_role][_token] = _tokenStatus;
        return true;
    }

    function setSwapOutTokens(SwapOutToken[] calldata _swapOutToken) external onlySafe returns (bool){    
        for (uint i=0; i < _swapOutToken.length; i++) { 
            swapOutTokenWhitelist[_swapOutToken[i].role][_swapOutToken[i].token] = _swapOutToken[i].tokenStatus;
        }
        return true;
    }

    function setRoleSlippage(bytes32 _role,uint256 _slippage) external onlySafe returns (bool){   
        require(roleSlippage[_role] != _slippage, "_role _slippage existed");
        roleSlippage[_role] = _slippage;
        return true;
    }
    

    function setOracle(address _oracle) external onlySafe returns (bool){
        require(_oracle != address(0), "_oracle not allowed");
        require(oracle != _oracle, "_oracle existed");
        oracle = _oracle;
        return true;
    }

    function setSwapCheckMethod(bool _isCheckSwapPair, bool _isCheckSwapToken,bool _isCheckRoleSlippage) external onlySafe returns (bool){
        isCheckSwapPair = _isCheckSwapPair;
        isCheckSwapToken = _isCheckSwapToken;
        isCheckRoleSlippage = _isCheckRoleSlippage;
        return true;
    }

    // ACL check methods

    function swapInOutTokenCheck(address _inToken, address _outToken) internal {  
        require(swapInTokenWhitelist[_checkedRole][_inToken],"token not allowed");
        require(swapOutTokenWhitelist[_checkedRole][_outToken],"token not allowed");
    }

    function poolsCheck(address[4] memory _pools) internal {  
        for (uint i=0; i < _pools.length - 1; i++) { 
            require(swapPairWhitelist[_checkedRole][_pools[i]], "Invalid _pools");
        }
    }

    function slippageCheckLiquidity(uint256 _tokenInAmount, uint256 _tokenOutAmount, address _tokenIn, address _tokenOut) internal {  
        uint256 _slippage = roleSlippage[_checkedRole];
        require(_slippage > 0 ,"_role _slippage not set");
        // check swap slippage
        uint256 valueInput = IOracle(oracle).getUSDValue(_tokenIn,_tokenInAmount);
        uint256 valueOutput = IOracle(oracle).getUSDValue(_tokenOut,_tokenOutAmount);
        require(valueOutput >= valueInput * (SLIPPAGE_BASE - _slippage) / SLIPPAGE_BASE, "Slippage is too high");
    }

    function getRoutePools(address[9] memory _route) internal pure returns (address,address,address[4] memory) {
        address _inToken = address(_route[0]);
        address[4] memory _routePools;
        address _outToken;
        uint j = 0;
        for (uint i=0; i < _route.length - 1;) {
            if (_route[i] != ZERO_ADDRESS) {
                if (_route[i + 1] != ZERO_ADDRESS) {
                    _routePools[j] = address(_route[i + 1]);
                    j++;
                } else {
                    _outToken = address(_route[i]);
                }
            }
            i = i + 2;
        }
        return (_inToken, _outToken, _routePools);
    }

    function routerCheckAcl(uint256 _tokenInAmount, uint256 _tokenOutAmount, address[9] memory _route, address[4] memory _pools) internal {
        (address _inToken, address _outToken, address[4] memory _routePools) = getRoutePools(_route);
        
        if(isCheckSwapToken){
            swapInOutTokenCheck(_inToken,_outToken);
        }

        if(isCheckSwapPair){
            poolsCheck(_routePools);
            poolsCheck(_pools);
        }

        if(isCheckRoleSlippage){
            slippageCheckLiquidity(_tokenInAmount,_tokenOutAmount,_inToken,_outToken);
        }
    }

    function exchange_multiple(address[9] memory _route, uint256[3][4] memory _swap_params, uint256 _amount, uint256 _expected)
        external
        payable
        onlySelf {
        address[4] memory _pools = [ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS];
        routerCheckAcl(_amount, _expected, _route, _pools);
    }

    function exchange_multiple(address[9] memory _route, uint256[3][4] memory _swap_params, uint256 _amount, uint256 _expected, address[4] memory _pools)    //default
        external
        payable
        onlySelf {
        routerCheckAcl(_amount, _expected, _route, _pools);
    }

    function exchange_multiple(address[9] memory _route, uint256[3][4] memory _swap_params, uint256 _amount, uint256 _expected, address[4] memory _pools, address _receiver)
        external
        payable
        onlySelf {
        require(_receiver == safeAddress,"_receiver not allowed");
        routerCheckAcl(_amount, _expected, _route, _pools);
    }

    /// @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
    /// {upgradeTo} and {upgradeToAndCall}.
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}

