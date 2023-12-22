// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

// libraries
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./IERC20Metadata.sol";
import "./IERC20.sol";

import "./MozBridge.sol";
import "./MozaicLP.sol";
import "./IPlugin.sol";

/// @title  Vault
/// @notice Vault Contract
/// @dev    Vault Contract is responsible for accept deposit and withdraw requests and interact with the plugins and controller.
contract Vault is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Used to define the config of the plugins.
    struct PluginConfig {
        address pluginAddr;
        address pluginReward;
    }

    uint16 internal constant TYPE_REQUEST_SNAPSHOT = 1;
    uint16 internal constant TYPE_REPORT_SNAPSHOT  = 2;
    uint16 internal constant TYPE_REQUEST_SETTLE   = 3;
    uint16 internal constant TYPE_REPORT_SETTLE    = 4;

    uint16 internal constant TYPE_SNAPSHOT_RETRY        = 5;
    uint16 internal constant TYPE_SETTLE_RETRY          = 6;
    uint16 internal constant TYPE_REPORT_SNAPSHOT_RETRY = 7;
    uint16 internal constant TYPE_REPORT_SETTLE_RETRY   = 8;



    /* ========== STATE VARIABLES ========== */

    /// @notice The mozaic bridge contract address that is used to implement cross chain operations.
    address public mozBridge;

    /// @notice The mozaic LP token contract that is used to mint LP tokens to liquidity providers.
    address public mozLP;

    /// @notice Address of master
    address public master;

    /// @notice The address of the treasury
    address payable public treasury;
    
    /// @notice The chain identifier of this vault.
    uint16 public immutable chainId;

    /// @notice The total amount of satablecoin with mozaic decimal.
    uint256 public totalCoinMD;

    /// @notice The total amount of mozaic LP token.
    uint256 public totalMLP;

    /// @notice Array of tokens accepted in this vault.
    address[] public acceptingTokens;

    /// @notice Return whether a token is accepted. If token is accepted, return true.
    mapping (address => bool) public tokenMap;

    /// @notice Return the plugin config for a plugin id 
    mapping (uint8 => PluginConfig) public supportedPlugins;

    /// @notice Supported plugin ids.
    uint8[] public pluginIds;

    /// @notice Return the revertLookup payload for chainid, srcAddress and nonce
    mapping(uint16 => mapping(bytes => mapping(uint256 => bytes))) public revertLookup; //[chainId][srcAddress][nonce]

    /// @notice The snapshot of the localvault
    MozBridge.Snapshot public localSnapshot;

    /// @notice Current updated Number
    uint256 public updateNum;

    /// @notice Mozaic token decimal.
    uint8 public constant MOZAIC_DECIMALS = 6;

    uint256 public constant SLIPPAGE = 1;

    uint256 public constant BP_DENOMINATOR = 10000;

    /// @notice The Address of lifi contract
    address public constant LIFI_CONTRACT = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE;

    /// @notice The flag to lock the vault
    bool public lockVault;

    /* ========== EVENTS =========== */
    event Deposit (
        address indexed depositor,
        address indexed token,
        uint256 amountLD
    );

    event Withdraw (
        address indexed withdrawer,
        address indexed token,
        uint256 amountMLP,
        uint256 amountLD
    );

    event TakeSnapshot(
        uint256 totalStablecoin,
        uint256 totalMozaicLp
    );

    event SetBridge(address mozBridge);

    event SetMozaicLP(address mozLP);

    event SetMaster(address master);

    event SetTreasury(address payable treasury);
    
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

    event ActionExecuted(uint8 pluginId, IPlugin.ActionType actionType);

    event SnapshotReported(uint16 srcChainId, bytes indexed srcAddress, uint64 nonce, MozBridge.Snapshot snapshot, uint256 updateNum);
    
    event SettleReported(uint16 srcChainId, bytes indexed srcAddress, uint64 nonce, uint256 updateNum);

    event Revert(uint16 bridgeFunctionType, uint16 chainId, bytes srcAddress, uint256 nonce);

    event RetryRevert(uint16 bridgeFunctionType, uint16 chainId, bytes srcAddress, uint256 nonce);

    event ClaimReward();

    /* ========== MODIFIERS ========== */

    /// @notice Modifier to check if caller is the bridge.
    modifier onlyBridge() {
        require(msg.sender == mozBridge, "Vault: Invalid bridge");
        _;
    }

    /// @notice Modifier to check if caller is the master.
    modifier onlyMaster() {
        require(msg.sender == master, "Vault: Invalid caller");
        _;
    }

    /* ========== CONFIGURATION ========== */
    constructor(uint16 _chainId)  {
        require(_chainId > 0, "Vault: Invalid chainid");
        chainId = _chainId;
    }

    /// @notice Set the master of the vault
    function setMaster(address _master) public onlyOwner {
        require(_master != address(0), "Vault: Invalid address");
        master = _master;
        emit SetMaster(_master);
    }

    /// @notice Set the mozaic bridge of the vault.
    /// @param  _mozBridge - The address of the bridge being setted.
    function setBridge(address _mozBridge) public onlyOwner {
        require(_mozBridge != address(0), "Vault: Invalid address");
        // require(_mozBridge != address(0) && mozBridge == address(0), "Vault: Invalid address");

        mozBridge = _mozBridge;
        emit SetBridge(_mozBridge);
    }

    /// @notice Set the mozaic LP token contract of the vault.
    /// @param  _mozLP - The address of the mozaic LP token contract being setted.
    function setMozaicLP(address _mozLP) public onlyOwner {
        require(_mozLP != address(0) && mozLP == address(0), "Vault: Invalid address");
        mozLP = _mozLP;
        emit SetMozaicLP(_mozLP);
    }
    
    /// @notice Set the treasury of the controller.
    /// @param _treasury - The address of the treasury being setted.
    function setTreasury(address payable _treasury) public onlyOwner {
        require(_treasury != address(0), "Controller: Invalid address");
        // require(treasury == address(0), "Controller: The treasury has already been set");
        treasury = _treasury;
        emit SetTreasury(_treasury);
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
        } else {
            revert("Vault: Token already exist.");
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
        revert("Vault: Non-accepted token.");
    }

    function bridgeViaLifi(
        address _srcToken,
        uint256 _amount,
        uint256 _value,
        bytes calldata _data
    ) external onlyMaster {
        require(
            address(LIFI_CONTRACT) != address(0),
            "Lifi: zero address"
        );
        bool isNative = (_srcToken == address(0));
        if (!isNative) {
            IERC20(_srcToken).safeApprove(address(LIFI_CONTRACT), 0);
            IERC20(_srcToken).safeApprove(address(LIFI_CONTRACT), _amount);
        }
        (bool success,) = LIFI_CONTRACT.call{value: _value}(_data);
        require(success, "Lifi: call failed");
    }

    /// @notice Execute actions of the certain plugin.
    /// @param _pluginId - the destination plugin identifier
    /// @param _actionType -  the action identifier of plugin action
    /// @param _payload - a custom bytes payload to send to the destination contract
    function execute(uint8 _pluginId, IPlugin.ActionType _actionType, bytes memory _payload) public onlyMaster {
        require(_pluginId > 0 && supportedPlugins[_pluginId].pluginAddr != address(0x0) && supportedPlugins[_pluginId].pluginReward != address(0x0), "Vault: Invalid id");
        if(_actionType == IPlugin.ActionType.Stake) {
            (uint256 _amountLD, address _token) = abi.decode(_payload, (uint256, address));
            uint256 balance = IERC20(_token).balanceOf(address(this));
            require(balance >= _amountLD, "Vault: Invalid amount");
            IERC20(_token).safeApprove(supportedPlugins[_pluginId].pluginAddr, 0);
            IERC20(_token).approve(supportedPlugins[_pluginId].pluginAddr, _amountLD);
        } else if (_actionType == IPlugin.ActionType.SwapRemote) {
            (uint256 _amountLD, address _token, uint16 _dstChainId, ) = abi.decode(_payload, (uint256, address, uint16, uint256));
            IERC20(_token).safeApprove(supportedPlugins[_pluginId].pluginAddr, 0);
            IERC20(_token).approve(supportedPlugins[_pluginId].pluginAddr, _amountLD);
            uint256 _nativeFee =  IPlugin(supportedPlugins[_pluginId].pluginAddr).quoteSwapFee(_dstChainId);
            IPlugin(supportedPlugins[_pluginId].pluginAddr).execute{value: _nativeFee}(_actionType, _payload);
            emit ActionExecuted(_pluginId, _actionType);
            return;
        }
        IPlugin(supportedPlugins[_pluginId].pluginAddr).execute(_actionType, _payload);
        emit ActionExecuted(_pluginId, _actionType);
    }

    /// @notice Claim rewards from the plugins.
    function claimReward() public onlyMaster {
        bytes memory _payload = abi.encode(acceptingTokens);
        for(uint256 i = 0; i < pluginIds.length; ++i) {
            address plugin = supportedPlugins[pluginIds[i]].pluginAddr;
            IPlugin(plugin).execute(IPlugin.ActionType.ClaimReward, _payload);
        }
        emit ClaimReward();
    }

    /* ========== BRIDGE FUNCTIONS ========== */

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
        } else {
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
        _settle(_totalCoinMD, _totalMLP);
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

        if (functionType == TYPE_REPORT_SNAPSHOT_RETRY) {
            (, MozBridge.Snapshot memory _snapshot, uint256 _updateNum) = abi.decode(
                payload,
                (uint16, MozBridge.Snapshot, uint256)
            );
            require(_updateNum == updateNum, "Vault: Old request");
            MozBridge(mozBridge).reportSnapshot{value: msg.value}(_snapshot, _updateNum, payable(address(msg.sender)));
        } else if (functionType == TYPE_REPORT_SETTLE_RETRY){
            (, uint256 _updateNum) = abi.decode(
                payload,
                (uint16, uint256)
            );
            require(_updateNum == updateNum, "Vault: Old request");
            MozBridge(mozBridge).reportSettled{value: msg.value}(_updateNum, payable(address(msg.sender)));
        } else if (functionType == TYPE_SNAPSHOT_RETRY){
            (, uint256 _updateNum) = abi.decode(
                payload,
                (uint16, uint256)
            );
            require(_updateNum > updateNum, "Vault: Old request");
            MozBridge.Snapshot memory _snapshot = _takeSnapshot();
            localSnapshot = _snapshot;
            updateNum = _updateNum;
            MozBridge(mozBridge).reportSnapshot{value: msg.value}(_snapshot, _updateNum, payable(address(msg.sender)));
        } else if (functionType == TYPE_SETTLE_RETRY) {
            (, uint256 _totalCoinMD, uint256 _totalMLP, uint256 _updateNum) = abi.decode(
                payload,
                (uint16, uint256, uint256, uint256)
            );
            require(_updateNum == updateNum, "Vault: Old request");
            _settle(_totalCoinMD, _totalMLP);
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
        _settle(_totalCoinMD, _totalMLP);
    }
    /* ========== USER FUNCTIONS ========== */
    
    /// @notice Add deposit request to the vault.
    /// @param _amountLD - The amount of the token to be deposited.
    /// @param _token - The address of the token  to be deposited.
    function addDepositRequest(uint256 _amountLD, address _token, address _depositor) external {
        require(lockVault == false, "Vault: vault locked");
        require(isAcceptingToken(_token), "Vault: Invalid token");
        require(_amountLD != 0, "Vault: Invalid amount");
        // Transfer token from msg.sender to vault.
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amountLD);
        uint256 _amountMLPToMint =  amountMDtoMLP(convertLDtoMD(_token, _amountLD));
        require(_amountMLPToMint > 0, "Vault: Invalid fund");
        // Mint moazic LP token.
        MozaicLP(mozLP).mint(_depositor, _amountMLPToMint);
        emit Deposit(_depositor, _token, _amountLD);
    }

    /// @notice Add withdraw request to the vault.
    /// @param _amountMLP - The amount of the mozaic LP token.
    /// @param _token - The address of the token.
    function addWithdrawRequest(uint256 _amountMLP, address _token) external {
        require(lockVault == false, "Vault: vault locked");
        require(isAcceptingToken(_token), "Vault: Invalid token");
        require(_amountMLP != 0, "Vault: Invalid amount");

        address _withdrawer = msg.sender;
        require(MozaicLP(mozLP).balanceOf(_withdrawer) >= _amountMLP, "Vault: Low LP token balance");
        IERC20(mozLP).safeTransferFrom(_withdrawer, address(this), _amountMLP);

        uint256 _amountMDtoGive = amountMLPtoMD(_amountMLP);
        uint256 _amountLDtoGive = convertMDtoLD(_token, _amountMDtoGive);
        uint256 _vaultBalanceLD = IERC20(_token).balanceOf(address(this));
        uint256 _totalStakedAmount = getStakedAmountPerToken(_token);
        require(_totalStakedAmount + _vaultBalanceLD >= _amountLDtoGive, "Vault: Not Enough Token.");
        uint256 delta = _amountLDtoGive > _vaultBalanceLD ? _amountLDtoGive -  _vaultBalanceLD: 0;
        for(uint256 i = 0; i < pluginIds.length; ++i) {
            if(delta == 0) break;
            address plugin = supportedPlugins[pluginIds[i]].pluginAddr;
            (uint256 _stakedAmountLD, uint256 _stakedAmountLP) = IPlugin(plugin).getStakedAmount(_token);
            if(_stakedAmountLD == 0 || _stakedAmountLP == 0) continue;
            if(_stakedAmountLD > delta) {
                uint256 unstakeAmount = delta * _stakedAmountLP / _stakedAmountLD;
                bytes memory _payload = abi.encode(unstakeAmount, _token);
                IPlugin(plugin).execute(IPlugin.ActionType.Unstake, _payload);
                delta = 0;
            } else {
                delta -= _stakedAmountLD;
                bytes memory _payload = abi.encode(_stakedAmountLP, _token);
                IPlugin(plugin).execute(IPlugin.ActionType.Unstake, _payload);
            }
        }
        _vaultBalanceLD = IERC20(_token).balanceOf(address(this));
        require(_vaultBalanceLD >= _amountLDtoGive.mul(BP_DENOMINATOR - SLIPPAGE).div(BP_DENOMINATOR), "Vault: Not Enough Token.");
        _amountLDtoGive = _vaultBalanceLD >= _amountLDtoGive ? _amountLDtoGive : _vaultBalanceLD; 
        // Burn moazic LP token.
        MozaicLP(mozLP).burn(address(this), _amountMLP);

        // Transfer token to the user.
        if(_amountLDtoGive > 0) IERC20(_token).safeTransfer(_withdrawer, _amountLDtoGive);
        emit Withdraw(_withdrawer, _token, _amountMLP, _amountLDtoGive);
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    
    /// @notice Take snapshot from the vault and return the snapshot.
    function _takeSnapshot() internal returns (MozBridge.Snapshot memory snapshot) {
        lockVault = true;
        // Get the total amount of stablecoin in vault with mozaic decimal.
        uint256 _totalAssetMD;
        for(uint256 i = 0; i < acceptingTokens.length; ++i) { 
            uint256 amountLD = IERC20(acceptingTokens[i]).balanceOf(address(this));
            uint256 amountMD = convertLDtoMD(acceptingTokens[i], amountLD);
            _totalAssetMD = _totalAssetMD + amountMD; 
        }

        // Get total amount of stablecoin of plugin.
        uint256 _totalStakedMD;
        for(uint256 i = 0; i < pluginIds.length; ++i) {
            address plugin = supportedPlugins[pluginIds[i]].pluginAddr;
            bytes memory _payload = abi.encode(acceptingTokens);
            bytes memory response = IPlugin(plugin).execute(IPlugin.ActionType.GetTotalAssetsMD, _payload);
            _totalStakedMD = _totalStakedMD + abi.decode(response, (uint256));
        }
        // Configure and return snapshot.
        snapshot.totalStablecoin = _totalAssetMD + _totalStakedMD;
        snapshot.totalMozaicLp = IERC20(mozLP).totalSupply();
        emit TakeSnapshot(
            snapshot.totalStablecoin,
            snapshot.totalMozaicLp
        );
    }

    /// @notice Set the total amount of stablecoin and total amount of mozaic LP token.
    function _settle(uint256 _totalCoinMD, uint256 _totalMLP) internal {
        lockVault = false;
        totalCoinMD = _totalCoinMD;
        totalMLP = _totalMLP;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Get the available LD and LP amount per token.
    function getAvailbleAmountPerToken(address _token) public view returns (uint256, uint256) {
        uint256 _stakedAmount = getStakedAmountPerToken(_token);
        uint256 _tokenBalance = IERC20(_token).balanceOf(address(this));
        uint256 _totalAmount = _stakedAmount + _tokenBalance;
        uint256 _amountMD = convertLDtoMD(_token, _totalAmount);
        uint256 _amountMLP = amountMDtoMLP(_amountMD);
        return (_totalAmount, _amountMLP);
    }

    /// @notice Get the staked amount per token.
    function getStakedAmountPerToken(address _token) public view returns(uint256 _totalAmount) {
        for(uint256 i = 0; i < pluginIds.length; ++i) {
            address plugin = supportedPlugins[pluginIds[i]].pluginAddr;
            (uint256 stakedAmount, ) = IPlugin(plugin).getStakedAmount(_token);
            _totalAmount = _totalAmount + stakedAmount;
        }
    }

    /// @notice Whether the token is accepted token or not.
    /// @param _token - The address of token.
    function isAcceptingToken(address _token) public view returns (bool) {
        return tokenMap[_token];
    }

    /// @notice Get the address of plugin with it's id
    function getPluginAddress(uint8 id) public view returns (address) {
        return supportedPlugins[id].pluginAddr;
    }

    /// @notice Get the address of plugin reward with it's id
    function getPluginReward(uint8 id) public view returns (address) {
        return supportedPlugins[id].pluginReward;
    }

    /// @notice Get the number of plugins.
    function getNumberOfPlugins() public view returns (uint256) {
        return pluginIds.length;
    }

    /// @notice Get the number of tokens.
    function getNumberOfTokens() public view returns (uint256) {
        return acceptingTokens.length;
    }

    function getAcceptingTokens() public view returns(address[] memory) {
        return acceptingTokens;
    }

    function getPluginIds() public view returns (uint8[] memory) {
        return pluginIds;
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

    function withdraw(uint256 _amount) public onlyOwner {
        // get the amount of Ether stored in this contract
        uint amount = address(this).balance;
        require(amount >= _amount, "Vault: Invalid withdraw amount.");
        // send Ether to owner
        // Owner can receive Ether since the address of owner is payable
        require(treasury != address(0), "Vault: Invalid treasury");
        (bool success, ) = treasury.call{value: _amount}("");
        require(success, "Vault: Failed to send Ether");
    }
}
