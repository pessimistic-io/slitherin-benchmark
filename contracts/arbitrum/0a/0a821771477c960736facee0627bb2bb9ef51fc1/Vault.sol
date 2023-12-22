// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

// libraries
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";
import "./IERC20.sol";
import "./MozBridge.sol";
import "./MozaicLP.sol";
import "./IPlugin.sol";

/// @title  Vault
/// @notice Vault Contract
/// @dev    Vault Contract is responsible for accept deposit and withdraw requests and interact with the plugins and controller.
contract Vault is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Used to define the config of the plugins.
    struct pluginConfig {
        address pluginAddr;
        address pluginReward;
    }

    /// @notice Used to define the request model.
    struct Request {
        address user;
        address token;
    }

    /// @notice Used to store the deposit and withdraw requests.
    struct RequestBuffer {
        Request[] depositRequestList;
        mapping (address => mapping (address => uint256)) depositRequestLookup;
        mapping (address => uint256) depositAmountPerToken; // token => amountLD
        mapping (address => uint256) depositAmountPerUser;
        uint256 totalDepositAmount;
        Request[] withdrawRequestList;
        mapping (address => mapping (address => uint256)) withdrawRequestLookup;
        mapping (address => uint256) withdrawAmountPerToken; // token => amountMLP
        mapping (address => uint256) withdrawAmountPerUser;
        uint256 totalWithdrawAmount;
    }
    uint16 internal constant TYPE_REQUEST_SNAPSHOT = 1;
    uint16 internal constant TYPE_REPORT_SNAPSHOT  = 2;
    uint16 internal constant TYPE_REQUEST_SETTLE   = 3;
    uint16 internal constant TYPE_REPORT_SETTLE    = 4;
    uint16 internal constant TYPE_STAKE_ASSETS     = 5;
    uint16 internal constant TYPE_UNSTAKE_ASSETS   = 6;

    uint16 internal constant TYPE_ACTION_RETRY          = 7;
    uint16 internal constant TYPE_SNAPSHOT_RETRY        = 8;
    uint16 internal constant TYPE_SETTLE_RETRY          = 9;
    uint16 internal constant TYPE_REPORT_SNAPSHOT_RETRY = 10;
    uint16 internal constant TYPE_REPORT_SETTLE_RETRY   = 11;



    /* ========== STATE VARIABLES ========== */

    /// @notice The mozaic bridge contract address that is used to implement cross chain operations.
    address public mozBridge;

    /// @notice The mozaic LP token contract that is used to mint LP tokens to liquidity providers.
    address public mozLP;
    
    /// @notice The chain identifier of this vault.
    uint16 public immutable chainId;

    /// @notice The total amount of satablecoin with mozaic decimal.
    uint256 public totalCoinMD;

    /// @notice The total amount of mozaic LP token.
    uint256 public totalMLP;

    /// @notice Array of requset buffer to store the deposit and withdraw requests.
    RequestBuffer[2] public Buffer;
    
    /// @notice Array of tokens accepted in this vault.
    address[] public acceptingTokens;

    /// @notice Return whether a token is accepted. If token is accepted, return true.
    mapping (address => bool) public tokenMap;

    /// @notice Return the plugin config for a plugin id 
    mapping (uint8 => pluginConfig) public supportedPlugins;

    /// @notice Supported plugin ids.
    uint8[] public pluginIds;
    
    /// @notice The flag used to convert pending request buffer to staged request buffer.
    bool public bufferFlag = false;
    
    /// @notice Mozaic token decimal.
    uint8 public constant MOZAIC_DECIMALS = 6;
    
    /// @notice Address of admin
    address public admin;

    /// @notice Return the revertLookup payload for chainid, srcAddress and nonce
    mapping(uint16 => mapping(bytes => mapping(uint256 => bytes))) public revertLookup; //[chainId][srcAddress][nonce]

    /// @notice The snapshot of the localvault
    MozBridge.Snapshot public localSnapshot;

    /// @notice Current updated Number
    uint256 public updateNum;

    /// @notice The Address of lifi contract
    address public constant lifiContract = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE;
    
    /* ========== EVENTS =========== */
    event DepositRequestAdded (
        address indexed depositor,
        address indexed token,
        uint16 indexed chainId,
        uint256 amountLD
    );

    event WithdrawRequestAdded (
        address indexed withdrawer,
        address indexed token,
        uint16 indexed chainId,
        uint256 amountMLP
    );

    event DepositRequsetSettled();

    event WithdrawRequestSettled();

    event TakeSnapshot(
        uint256 totalStablecoin,
        uint256 totalMozaicLp,
        uint256 depositRequestAmount,
        uint256 withdrawRequestAmountMLP
    );

    event SetBridge(address mozBridge);

    event SetMozaicLP(address mozLP);

    event SetAdmin(address admin);

    event SetLifi(address lifi);

    event AddPlugin(
        uint8 indexed pluginId,
        address indexed pluginAddr,
        address indexed pluginReward
    );

    event RemovePlugin(
        uint8 indexed pluginId
    );

    event AddToken(address token);

    event RemoveToken(address token);

    event ActionExecuted(uint16 srcChainId, bytes indexed srcAddress, uint64 nonce, uint8 pluginId, IPlugin.ActionType actionType);

    event SnapshotReported(uint16 srcChainId, bytes indexed srcAddress, uint64 nonce, MozBridge.Snapshot snapshot, uint256 updateNum);
    
    event SettleReported(uint16 srcChainId, bytes indexed srcAddress, uint64 nonce, uint256 updateNum);

    event Revert(uint16 bridgeFunctionType, uint16 chainId, bytes srcAddress, uint256 nonce);

    event RetryRevert(uint16 bridgeFunctionType, uint16 chainId, bytes srcAddress, uint256 nonce);

    /* ========== MODIFIERS ========== */

    /// @notice Modifier to check if caller is the bridge.
    modifier onlyBridge() {
        require(msg.sender == mozBridge, "Vault: Invalid bridge");
        _;
    }
    /// @notice Modifier to check if caller is the admin.
    modifier onlyAdmin() {
        require(msg.sender == admin, "Vault: Invalid address");
        _;
    }

    /* ========== CONFIGURATION ========== */
    constructor(uint16 _chainId)  {
        require(_chainId > 0, "Vault: Invalid chainid");
        chainId = _chainId;
    }

    /// @notice Set the mozaic bridge of the vault.
    /// @param  _mozBridge - The address of the bridge being setted.
    function setBridge(address _mozBridge) public onlyOwner {
        require(_mozBridge != address(0), "Vault: Invalid address");
        mozBridge = _mozBridge;
        emit SetBridge(_mozBridge);
    }

    /// @notice Set the mozaic LP token contract of the vault.
    /// @param  _mozLP - The address of the mozaic LP token contract being setted.
    function setMozaicLP(address _mozLP) public onlyOwner {
        require(_mozLP != address(0), "Vault: Invalid address");
        mozLP = _mozLP;
        emit SetMozaicLP(_mozLP);
    }

    /// @notice Add the plugin with it's config to the vault.
    /// @param  _pluginId - The id of the plugin being setted.
    /// @param  _pluginAddr - The address of plugin being setted.
    /// @param  _pluginReward - The address of plugin reward token.
    function addPlugin(uint8 _pluginId, address _pluginAddr, address _pluginReward) public onlyOwner {
        require(_pluginId > 0, "Vault: Invalid id");
        require(_pluginAddr != address(0x0), "Vault: Invalid address");
        require(_pluginReward != address(0x0), "Vault: Invalid address");
        for(uint256 i = 0; i < pluginIds.length; ++i) {
            if(pluginIds[i] == _pluginId) revert("Vault: Plugin id already exist");
            if(supportedPlugins[pluginIds[i]].pluginAddr == _pluginAddr) revert("Vault: Plugin already exist");
        }
        pluginIds.push(_pluginId);
        supportedPlugins[_pluginId].pluginAddr = _pluginAddr;
        supportedPlugins[_pluginId].pluginReward = _pluginReward;

        emit AddPlugin(_pluginId, _pluginAddr, _pluginReward);
    }

    /// @notice Remove the plugin with it's id.
    /// @param  _pluginId - The id of the plugin being removed.
    function removePlugin(uint8 _pluginId) public onlyOwner {
        require(_pluginId > 0, "Vault: Invalid id");
        for(uint256 i = 0; i < pluginIds.length; ++i) {
            if(pluginIds[i] == _pluginId) {
                pluginIds[i] = pluginIds[pluginIds.length - 1]; 
                pluginIds.pop();
                delete supportedPlugins[_pluginId];
                emit RemovePlugin(_pluginId);
                return;
            }
        }
        revert("Vault: Plugin id doesn't exist.");
    }

    /// @notice Add the token address to the list of accepted token addresses.
    function addToken(address _token) external onlyOwner {
        if(tokenMap[_token] == false) {
            tokenMap[_token] = true;
            acceptingTokens.push(_token);
            emit AddToken(_token);
        }
    }
    /// @notice Remove the token address from the list of accepted token addresses.
    function removeToken(address _token) external onlyOwner {
        if(tokenMap[_token] == true) {
            tokenMap[_token] = false;
            for(uint256 i = 0; i < acceptingTokens.length; ++i) {
                if(acceptingTokens[i] == _token) {
                    acceptingTokens[i] = acceptingTokens[acceptingTokens.length - 1];
                    acceptingTokens.pop();
                    emit RemoveToken(_token);
                    return;
                }
            }
        }
        revert("Vault: Non accepted token.");
    }

    /// @notice Set the admin of the vault which can withdraw and deposit token.
    function setAdmin(address _admin) external onlyOwner {
        require(_admin != address(0x0), "Vault: Invaild address");
        admin = _admin;
        emit SetAdmin(_admin);
    }

    ///@notice Deposit token with specified amount.
    function depositToken(address _token, uint256 _amount) external onlyAdmin {
        require(isAcceptingToken(_token), "Vault: Invalid token");
        require(_amount != 0, "Vault: Invalid amount");
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    }

    function bridgeViaLifi(
        address _srcToken,
        uint256 _amount,
        uint256 _value,
        bytes calldata _data
    ) external onlyAdmin {
        require(
            address(lifiContract) != address(0),
            "Lifi: zero address"
        );
        bool isNative = (_srcToken == address(0));
        if (!isNative) {
            IERC20(_srcToken).safeApprove(address(lifiContract), 0);
            IERC20(_srcToken).safeApprove(address(lifiContract), _amount);
        }
        (bool success,) = lifiContract.call{value: _value}(_data);
        require(success, "Lifi: call failed");
    }

    /* ========== BRIDGE FUNCTIONS ========== */

    /// @notice Execute actions of the certain plugin.
    /// @param _pluginId - the destination plugin identifier
    /// @param _actionType -  the action identifier of plugin action
    /// @param _payload - a custom bytes payload to send to the destination contract
    function execute(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, uint8 _pluginId, IPlugin.ActionType _actionType, bytes memory _payload) public onlyBridge {
        require(_pluginId > 0 && supportedPlugins[_pluginId].pluginAddr != address(0x0) && supportedPlugins[_pluginId].pluginReward != address(0x0), "Vault: Invalid id");
        if(_actionType == IPlugin.ActionType.Stake) {
            (uint256 _amountLD, address _token) = abi.decode(_payload, (uint256, address));
            IERC20(_token).safeApprove(supportedPlugins[_pluginId].pluginAddr, 0);
            IERC20(_token).approve(supportedPlugins[_pluginId].pluginAddr, _amountLD);
        }
        if(MozBridge(mozBridge).mainChainId() == _srcChainId) {
            IPlugin(supportedPlugins[_pluginId].pluginAddr).execute(_actionType, _payload);
            emit ActionExecuted(_srcChainId, _srcAddress, _nonce, _pluginId, _actionType);
        } else {
            try IPlugin(supportedPlugins[_pluginId].pluginAddr).execute(_actionType, _payload) {
                emit ActionExecuted(_srcChainId, _srcAddress, _nonce, _pluginId, _actionType);
            } catch {
                revertLookup[_srcChainId][_srcAddress][_nonce] = abi.encode(
                    TYPE_ACTION_RETRY,
                    _pluginId, 
                    _actionType,
                    _payload
                );
                emit Revert(TYPE_ACTION_RETRY, _srcChainId, _srcAddress, _nonce);
            }
        }
    }

    /// @notice Report snapshot of the vault to the controller.
    function reportSnapshot(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        uint256 _updateNum
    ) public onlyBridge {
        MozBridge.Snapshot memory _snapshot;
        if(updateNum == _updateNum) {
            _snapshot = localSnapshot;
        }
        else {
            _snapshot = _takeSnapshot();
            localSnapshot = _snapshot;
            updateNum = _updateNum;
        }
        bytes memory payload = abi.encode(_snapshot, _updateNum);
        (uint256 _nativeFee, ) = MozBridge(mozBridge).quoteLayerZeroFee(MozBridge(mozBridge).mainChainId(), TYPE_REPORT_SNAPSHOT, MozBridge.LzTxObj(0, 0, "0x"), payload);
        try MozBridge(mozBridge).reportSnapshot{value: _nativeFee}(_snapshot, _updateNum, payable(address(this))) {
            emit SnapshotReported(_srcChainId, _srcAddress, _nonce, _snapshot, _updateNum);
        } catch {
            revertLookup[_srcChainId][_srcAddress][_nonce] = abi.encode(TYPE_REPORT_SNAPSHOT_RETRY, _snapshot, _updateNum);
            emit Revert(TYPE_REPORT_SNAPSHOT_RETRY, _srcChainId, _srcAddress, _nonce);
        }
    }

    /// @notice Report that the vault is settled.
    function reportSettled(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        uint256 _totalCoinMD,
        uint256 _totalMLP,
        uint256 _updateNum
    ) public onlyBridge {
        _preSettle(_totalCoinMD, _totalMLP);
        _settleRequests();
        bytes memory payload = abi.encode(_updateNum);
        (uint256 _nativeFee, ) = MozBridge(mozBridge).quoteLayerZeroFee(MozBridge(mozBridge).mainChainId(), TYPE_REPORT_SETTLE, MozBridge.LzTxObj(0, 0, "0x"), payload);
        try MozBridge(mozBridge).reportSettled{value: _nativeFee}(_updateNum, payable(address(this))) {
            emit SettleReported(_srcChainId, _srcAddress, _nonce, _updateNum);
        } catch {
            revertLookup[_srcChainId][_srcAddress][_nonce] = abi.encode(TYPE_REPORT_SETTLE_RETRY, _updateNum);
            emit Revert(TYPE_REPORT_SETTLE_RETRY, _srcChainId, _srcAddress, _nonce);
        }
    }

    /// @notice Retry reverted actions.
    function retryRevert(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce
    ) external payable {
        bytes memory payload = revertLookup[_srcChainId][_srcAddress][_nonce];
        require(payload.length > 0, "Vault: no retry revert");

        // empty it
        revertLookup[_srcChainId][_srcAddress][_nonce] = "";

        uint16 functionType;
        assembly {
            functionType := mload(add(payload, 32))
        }

        if (functionType == TYPE_ACTION_RETRY) {
            (, uint8 _pluginId, IPlugin.ActionType _actionType, bytes memory _payload) = abi.decode(
                payload,
                (uint16, uint8, IPlugin.ActionType, bytes)
            );
            IPlugin(supportedPlugins[_pluginId].pluginAddr).execute(_actionType, _payload);
        } else if (functionType == TYPE_REPORT_SNAPSHOT_RETRY) {
            (, MozBridge.Snapshot memory _snapshot, uint256 _updateNum) = abi.decode(
                payload,
                (uint16, MozBridge.Snapshot, uint256)
            );
            MozBridge(mozBridge).reportSnapshot{value: msg.value}(_snapshot, _updateNum, payable(address(msg.sender)));
        } else if (functionType == TYPE_REPORT_SETTLE_RETRY){
            (, uint256 _updateNum) = abi.decode(
                payload,
                (uint16, uint256)
            );
            MozBridge(mozBridge).reportSettled{value: msg.value}(_updateNum, payable(address(msg.sender)));
        } else if (functionType == TYPE_SNAPSHOT_RETRY){
            (, uint256 _updateNum) = abi.decode(
                payload,
                (uint16, uint256)
            );
            MozBridge.Snapshot memory _snapshot = _takeSnapshot();
            MozBridge(mozBridge).reportSnapshot{value: msg.value}(_snapshot, _updateNum, payable(address(msg.sender)));
        } else if (functionType == TYPE_SETTLE_RETRY){
            (, uint256 _totalCoinMD, uint256 _totalMLP, uint256 _updateNum) = abi.decode(
                payload,
                (uint16, uint256, uint256, uint256)
            );
            _preSettle(_totalCoinMD, _totalMLP);
            _settleRequests();
            MozBridge(mozBridge).reportSettled{value: msg.value}(_updateNum, payable(address(msg.sender)));
        } else {
            revert("Vault: invalid function type");
        }
        emit RetryRevert(functionType, _srcChainId, _srcAddress, _nonce);
    }

    /// @notice set the Revert Lookup
    function setRevertLookup(        
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint256 _nonce,
        bytes memory _payload
    ) public onlyBridge {
        revertLookup[_srcChainId][_srcAddress][_nonce] = _payload;
    }

    /// @notice Get the snapshot of current vault and return the snapshot.
    /// @dev Only used in main chain Vault
    function takeSnapshot() public onlyBridge returns (MozBridge.Snapshot memory snapshot) {
        return _takeSnapshot();
    }

    /// @notice Settle the requests with the total amount of the stablecoin and total amount of mozaic LP token.
    /// @dev Only used in main chain Vault
    function settleRequests(uint256 _totalCoinMD, uint256 _totalMLP) public onlyBridge {
        _preSettle(_totalCoinMD, _totalMLP);
        _settleRequests();
    }
    /* ========== USER FUNCTIONS ========== */
    
    /// @notice Add deposit request to the vault.
    /// @param _amountLD - The amount of the token to be deposited.
    /// @param _token - The address of the token  to be deposited.
    function addDepositRequest(uint256 _amountLD, address _token, address depositor) external {
        require(isAcceptingToken(_token), "Vault: Invalid token");
        require(_amountLD != 0, "Vault: Invalid amount");
        address _depositor = depositor;

        // Transfer token from depositer to vault.
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amountLD);

        // Get the pending buffer
        RequestBuffer storage _pendingBuffer = _requests(false);
        
        // Check if the user has already deposited with this token.
        bool exists = false;
        for(uint i = 0; i < _pendingBuffer.depositRequestList.length; ++i) {    
            Request memory req = _pendingBuffer.depositRequestList[i];
            if(req.user == _depositor && req.token == _token) {
                exists = true;
                break;
            }
        }
        if(!exists) {
            Request memory req;
            req.user = _depositor;
            req.token = _token;
            _pendingBuffer.depositRequestList.push(req);
        }

        // Convert local decimal to mozaic decimal.
        uint256 _amountMD = convertLDtoMD(_token, _amountLD);

        _pendingBuffer.depositRequestLookup[_depositor][_token] = _pendingBuffer.depositRequestLookup[_depositor][_token] + _amountMD;
        _pendingBuffer.depositAmountPerToken[_token] = _pendingBuffer.depositAmountPerToken[_token] + _amountMD;
        _pendingBuffer.depositAmountPerUser[_depositor] = _pendingBuffer.depositAmountPerUser[_depositor] + _amountMD;
        _pendingBuffer.totalDepositAmount = _pendingBuffer.totalDepositAmount + _amountMD;
        emit DepositRequestAdded(_depositor, _token, chainId, _amountMD);
    }

    /// @notice Add withdraw request to the vault.
    /// @param _amountMLP - The amount of the mozaic LP token used to withdraw token.
    /// @param _token - The address of the token to be withdrawn.
    function addWithdrawRequest(uint256 _amountMLP, address _token) external {
        require(isAcceptingToken(_token), "Vault: Invalid token");
        require(_amountMLP != 0, "Vault: Invalid amount");
        
        address _withdrawer = msg.sender;

        require(MozaicLP(mozLP).balanceOf(_withdrawer) >= _amountMLP, "Vault: Low LP token balance");

        // Get the pending buffer and staged buffer.
        RequestBuffer storage _pendingBuffer = _requests(false);

        IERC20(mozLP).safeTransferFrom(_withdrawer, address(this), _amountMLP);

        // Check if the user has already withdrawed with this token.
        bool exists = false;
        for(uint i = 0; i < _pendingBuffer.withdrawRequestList.length; ++i) {
            Request memory req = _pendingBuffer.withdrawRequestList[i];
            if(req.user == _withdrawer && req.token == _token) {
                exists = true;
                break;
            }
        }
        if(!exists) {
            Request memory req;
            req.user = _withdrawer;
            req.token = _token;
            _pendingBuffer.withdrawRequestList.push(req);
        }
        _pendingBuffer.withdrawRequestLookup[_withdrawer][_token] = _pendingBuffer.withdrawRequestLookup[_withdrawer][_token] + _amountMLP;
        _pendingBuffer.withdrawAmountPerUser[_withdrawer] = _pendingBuffer.withdrawAmountPerUser[_withdrawer] + _amountMLP;
        _pendingBuffer.withdrawAmountPerToken[_token] = _pendingBuffer.withdrawAmountPerToken[_token] + _amountMLP;
        _pendingBuffer.totalWithdrawAmount = _pendingBuffer.totalWithdrawAmount + _amountMLP;

        emit WithdrawRequestAdded(_withdrawer, _token, chainId, _amountMLP);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @notice Returns the pending request buffer or staged request buffer according to the param.
    /// @param _staged - false -> pending buffer, true -> staged buffer
    function _requests(bool _staged) internal view returns (RequestBuffer storage) {
        return _staged ? (bufferFlag ? Buffer[1] : Buffer[0]) : (bufferFlag ? Buffer[0] : Buffer[1]);
    }
    
    /// @notice Take snapshot from the vault and return the snapshot.
    function _takeSnapshot() internal returns (MozBridge.Snapshot memory snapshot) {
        require(_requests(true).totalDepositAmount == 0, "Still processing requests");
        require(_requests(true).totalWithdrawAmount == 0, "Still processing requests");

        // Switch pending request buffer to staged request buffer.
        bufferFlag = !bufferFlag;

        // Get the total amount of stablecoin in vault with mozaic decimal.
        uint256 _totalAssetMD;
        for(uint256 i = 0; i < acceptingTokens.length; ++i) {
            uint256 amountLD = IERC20(acceptingTokens[i]).balanceOf(address(this));
            uint256 amountMD = convertLDtoMD(acceptingTokens[i], amountLD);
            _totalAssetMD = _totalAssetMD + amountMD; 
        }

        // Get total amount of stablecoin of plugin.
        uint256 _totalStablecoinMD;
        snapshot.amounts = new uint256[](pluginIds.length);

        for(uint256 i = 0; i < pluginIds.length; ++i) {
            address plugin = supportedPlugins[pluginIds[i]].pluginAddr;
            bytes memory _payload = abi.encode(acceptingTokens);
            bytes memory response = IPlugin(plugin).execute(IPlugin.ActionType.GetTotalAssetsMD, _payload); 
            _totalStablecoinMD = _totalStablecoinMD + abi.decode(response, (uint256));
            
            address rewardToken = supportedPlugins[pluginIds[i]].pluginReward;
            uint256 rewardAmount = IERC20(rewardToken).balanceOf(address(this));
            // Add the plugin data to snapshot.
            snapshot.amounts[i] = convertLDtoMD(rewardToken, rewardAmount);
        }
        // // Configure and return snapshot.
        snapshot.totalStablecoin = _totalAssetMD + _totalStablecoinMD - _requests(true).totalDepositAmount;
        snapshot.totalMozaicLp = IERC20(mozLP).totalSupply();
        snapshot.depositRequestAmount = _requests(true).totalDepositAmount;
        snapshot.withdrawRequestAmountMLP = _requests(true).totalWithdrawAmount;
        emit TakeSnapshot(
            snapshot.totalStablecoin,
            snapshot.totalMozaicLp,
            snapshot.depositRequestAmount,
            snapshot.withdrawRequestAmountMLP
        );
    }

    /// @notice Set the total amount of stablecoin and total amount of mozaic LP token.
    function _preSettle(uint256 _totalCoinMD, uint256 _totalMLP) internal {
        totalCoinMD = _totalCoinMD;
        totalMLP = _totalMLP;
    }

    /// @notice Switch the pending requests to the staged requests and settle the staged requests.  
    function _settleRequests() internal  {
        // for all deposit requests, mint MozaicLp
        RequestBuffer storage _reqs = _requests(true);
        for (uint i; i < _reqs.depositRequestList.length; ++i) {
            Request storage request = _reqs.depositRequestList[i];
            uint256 _depositAmountMD = _reqs.depositRequestLookup[request.user][request.token];
            if (_depositAmountMD == 0) {
                continue;
            }

            // Calculate the amount of mozaic LP token to be minted.
            uint256 _amountMLPToMint = amountMDtoMLP(_depositAmountMD);

            // Mint moazic LP token.
            MozaicLP(mozLP).mint(request.user, _amountMLPToMint);

            // Reduce Handled Amount from Buffer
            _reqs.totalDepositAmount = _reqs.totalDepositAmount - _depositAmountMD;
            _reqs.depositAmountPerUser[request.user] = _reqs.depositAmountPerUser[request.user] - _depositAmountMD;
            _reqs.depositAmountPerToken[request.token] = _reqs.depositAmountPerToken[request.token] - _depositAmountMD;
            _reqs.depositRequestLookup[request.user][request.token] = _reqs.depositRequestLookup[request.user][request.token] - _depositAmountMD;
        }
        require(_reqs.totalDepositAmount == 0, "Has unsettled deposit amount.");
        delete _reqs.depositRequestList;

        emit DepositRequsetSettled();
        // for all withdraw requests, give tokens
        for (uint i; i < _reqs.withdrawRequestList.length; ++i) {
            Request storage request = _reqs.withdrawRequestList[i];
            uint256 _withdrawAmountMLP = _reqs.withdrawRequestLookup[request.user][request.token];
            if (_withdrawAmountMLP == 0) {
                continue;
            }
            // Calculate the amount of mozaic LP token to be burned and the amount of token to be redeem.
            uint256 _coinAmountMDtoGive = amountMLPtoMD(_withdrawAmountMLP);
            uint256 _coinAmountLDtoGive = convertMDtoLD(request.token, _coinAmountMDtoGive);
            uint256 _vaultBalanceLD = IERC20(request.token).balanceOf(address(this));
            uint256 _mlpToBurn = _withdrawAmountMLP;
            if (_vaultBalanceLD < _coinAmountLDtoGive) {
                // The vault does not have enough balance. Only give as much as it has.
                _mlpToBurn = _withdrawAmountMLP * _vaultBalanceLD / _coinAmountLDtoGive;
                _coinAmountLDtoGive = _vaultBalanceLD;
                IERC20(mozLP).safeTransfer(request.user, _withdrawAmountMLP - _mlpToBurn);
            }

            // Burn moazic LP token.
            MozaicLP(mozLP).burn(address(this), _mlpToBurn);

            // Transfer token to the user.
            IERC20(request.token).safeTransfer(request.user, _coinAmountLDtoGive);
            // Reduce Handled Amount from Buffer
            _reqs.totalWithdrawAmount = _reqs.totalWithdrawAmount - _withdrawAmountMLP;
            _reqs.withdrawAmountPerUser[request.user] = _reqs.withdrawAmountPerUser[request.user] - _withdrawAmountMLP;
            _reqs.withdrawAmountPerToken[request.token] = _reqs.withdrawAmountPerToken[request.token] - _withdrawAmountMLP;
            _reqs.withdrawRequestLookup[request.user][request.token] = _reqs.withdrawRequestLookup[request.user][request.token] - _withdrawAmountMLP;
        }
        require(_reqs.totalWithdrawAmount == 0, "Has unsettled withdrawal amount.");
        delete _reqs.withdrawRequestList;
        emit WithdrawRequestSettled();
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Whether the token is accepted token or not.
    /// @param _token - The address of token.
    function isAcceptingToken(address _token) public view returns (bool) {
        return tokenMap[_token];
    }

    /// @notice Get the deposit amount with specified user and token
    function getDepositAmount(bool _staged, address _user, address _token) public view returns (uint256) {
        return _requests(_staged).depositRequestLookup[_user][_token];
    }

    /// @notice Get the withdraw amount with specified user and token
    function getWithdrawAmount(bool _staged, address _user, address _token) public view returns (uint256) {
        return _requests(_staged).withdrawRequestLookup[_user][_token];
    }

    /// @notice Get the deposit request with the index
    function getDepositRequest(bool _staged, uint256 _index) public view returns (Request memory) {
        return _requests(_staged).depositRequestList[_index];
    }

    /// @notice Get the withdraw request with the index
    function getWithdrawRequest(bool _staged, uint256 _index) public view returns (Request memory) {
        return _requests(_staged).withdrawRequestList[_index];
    }

    /// @notice Get the total deposit amount
    function getTotalDepositAmount(bool _staged) public view returns (uint256) {
        return _requests(_staged).totalDepositAmount;
    }

    /// @notice Get the total withdraw amount
    function getTotalWithdrawAmount(bool _staged) public view returns (uint256) {
        return _requests(_staged).totalWithdrawAmount;
    }

    /// @notice Get the length of deposit requests
    function getDepositRequestListLength(bool _staged) public view returns (uint256) {
        return _requests(_staged).depositRequestList.length;
    }
    /// @notice Get the length of withdraw requests
    function getWithdrawRequestListLength(bool _staged) public view returns (uint256) {
        return _requests(_staged).withdrawRequestList.length;
    }

    /// @notice Get the address of plugin with it's id
    function getPluginAddress(uint8 id) public view returns (address) {
        return supportedPlugins[id].pluginAddr;
    }

    /// @notice Get the address of plugin reward with it's id
    function getPluginReward(uint8 id) public view returns (address) {
        return supportedPlugins[id].pluginReward;
    }
    
    /// @notice Get the depoist amount per token
    function getDepositAmountPerToken(bool _staged, address _token) public view returns (uint256) {
        return _requests(_staged).depositAmountPerToken[_token];
    }

    /// @notice Get the withdraw amount per token
    function getWithdrawAmountPerToken(bool _staged, address _token) public view returns (uint256) {
        return _requests(_staged).withdrawAmountPerToken[_token];
    }

    /// @notice Get the depoist amount per user
    function getDepositAmountPerUser(bool _staged, address _user) public view returns (uint256) {
        return _requests(_staged).depositAmountPerUser[_user];
    }

    /// @notice Get the withdraw amount per user
    function getWithdrawAmountPerUser(bool _staged, address _user) public view returns (uint256) {
        return _requests(_staged).withdrawAmountPerUser[_user];
    }

    /// @notice Get the number of plugins.
    function getNumberOfPlugins() public view returns (uint256) {
        return pluginIds.length;
    }

    /// Convert functions

    /// @notice Convert local decimal to mozaic decimal.
    /// @param _token - The address of the token to be converted.
    /// @param _amountLD - the token amount represented with local decimal.
    function convertLDtoMD(address _token, uint256 _amountLD) public view returns (uint256) {
        uint8 _localDecimals = IERC20Metadata(_token).decimals();
        if (MOZAIC_DECIMALS >= _localDecimals) {
            return _amountLD * (10**(MOZAIC_DECIMALS - _localDecimals));
        } else {
            return _amountLD / (10**(_localDecimals - MOZAIC_DECIMALS));
        }
    }

    /// @notice Convert mozaic decimal to local decimal.
    /// @param _token - The address of the token to be converted.
    /// @param _amountMD - the token amount represented with mozaic decimal.
    function convertMDtoLD(address _token, uint256 _amountMD) public view returns (uint256) {
        uint8 _localDecimals = IERC20Metadata(_token).decimals();
        if (MOZAIC_DECIMALS >= _localDecimals) {
            return _amountMD / (10**(MOZAIC_DECIMALS - _localDecimals));
        } else {
            return _amountMD * (10**(_localDecimals - MOZAIC_DECIMALS));
        }
    }

    /// @notice Convert Mozaic decimal amount to mozaic LP decimal amount.
    /// @param _amountMD - the token amount represented with mozaic decimal.
    function amountMDtoMLP(uint256 _amountMD) public view returns (uint256) {
        if (totalCoinMD == 0) {
            return _amountMD;
        } else {
            return _amountMD * totalMLP / totalCoinMD;
        }
    }
    
    /// @notice Convert mozaic LP decimal amount to Mozaic decimal amount.
    /// @param _amountMLP - the mozaic LP token amount.
    function amountMLPtoMD(uint256 _amountMLP) public view returns (uint256) {
        if (totalMLP == 0) {
            return _amountMLP;
        } else {
            return _amountMLP * totalCoinMD / totalMLP;
        }
    }
    
    receive() external payable {}
    // Fallback function is called when msg.data is not empty
    fallback() external payable {}
    function getBalance() public view returns (uint) {
        return address(this).balance;
    }
}
