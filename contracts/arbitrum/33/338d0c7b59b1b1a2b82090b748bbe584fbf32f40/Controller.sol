// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

// imports
import "./MozBridge.sol";
import "./Vault.sol";
import "./IPlugin.sol";

// libraries
import "./SafeERC20.sol";
import "./Ownable.sol";

/// @title  Mozaic Controller
/// @notice Mozaic Controller Contract
/// @dev    The Mozaic Controller performs Mozaic operations to enforce the Archimedes's guidance
///         against the APY(Annual Percentage Yield) of the pools.
contract Controller is Ownable {
    
    /// @notice The main status of the protocol 
    enum ProtocolStatus {
        IDLE,
        SNAPSHOTTING,
        OPTIMIZING,
        SETTLING
    }

    uint16 internal constant TYPE_REQUEST_SNAPSHOT = 1;
    uint16 internal constant TYPE_REPORT_SNAPSHOT  = 2;
    uint16 internal constant TYPE_REQUEST_SETTLE   = 3;
    uint16 internal constant TYPE_REPORT_SETTLE    = 4;

    /// @notice Address that is responsible for executing main actions.
    address public master;
    
    /// @notice Address that is used to implement the cross chain operations.
    MozBridge public mozBridge;
    
    /* ========== STATE VARIABLES ========== */

    /// @notice Array of the all supported chain ids.
    uint16[] public supportedChainIds;

    /// @notice Main chain identifier of this protocol.
    uint16 public immutable mainChainId;
    
    /// @notice The total amount of satable coin with mozaic decimal.
    uint256 public totalCoinMD;

    /// @notice The total amount of mozaic LP token.
    uint256 public totalMLP;

    /// @notice Return a snapshot data from given chain id.
    mapping (uint16 => MozBridge.Snapshot) public snapshotReported;

    /// @notice The current activated status.
    ProtocolStatus public protocolStatus;

    /// @notice Returns the flag if snapshot reported. (updateNum -> chainId -> flag)
    mapping(uint256 => mapping(uint16 => bool)) public snapshotFlag;

    /// @notice Returns the flag if settle reported. (updateNum -> chainId -> flag)
    mapping(uint256 => mapping(uint16 => bool)) public settleFlag;

    /// @notice Returns the flag if all snapshot reported. (updateNum -> flag)
    mapping(uint256 => bool) checkedSnapshot;

    /// @notice Returns the flag if all settle reported. (updateNum -> flag)
    mapping(uint256 => bool) checkedSettle;

    /// @notice Current updated state number.
    uint256 public updateNum;

    /// @notice The address of the treasury
    address payable public treasury;

    /* ========== MODIFIERS ========== */

    /// @notice Modifier to check if caller is the master.
    modifier onlyMaster() {
        require(msg.sender == master, "Controller: Invalid caller");
        _;
    }

    /// @notice Modifier to check if caller is the bridge.
    modifier onlyBridge() {
        require(msg.sender == address(mozBridge), "Controller: Invalid caller");
        _;
    }

    /* ========== EVENTS ========== */

    event SetChainId(uint16 chainId);
    event RemoveChainId(uint16 chainId);
    event SetBridge(address mozBridge);
    event SetMaster(address master);
    event SetTreasury(address payable treasury);
    event RequestSnapshot(uint16 chainId, uint256 updateNum);
    event RequestSettle(uint16 chainId, uint256 updateNum);
    event SnapshotReported(uint16 chainId, uint256 updateNum);
    event SettleReported(uint16 chainId, uint256 updateNum);
    event UpdateAssetState(uint256 updateNum);
    event SettleAllVaults(uint256 updateNum);
    event UpdatedTotalAsset(uint256 totalCoinMD, uint256 totalMLP);
    event ProtolcolStatusUpdated(ProtocolStatus status);
    event Withdraw(uint256 amount);
    /* ========== CONSTRUCTOR ========== */
    
    constructor(
        uint16 _mainChainId
    ) {
        require(_mainChainId > 0, "Controller: Invalid chainid");
        mainChainId = _mainChainId;
        supportedChainIds.push(mainChainId);
    }

    /* ========== CONFIGURATION ========== */

    /// @notice Set the bridge of the controller
    /// @param _mozBridge - The address of the bridge being setted.
    function setBridge(address _mozBridge) public onlyOwner {
        require(_mozBridge != address(0), "Controller: Invalid address");
        require(address(mozBridge) == address(0), "Controller: The bridge has been already set.");
        mozBridge = MozBridge(_mozBridge);
        emit SetBridge(_mozBridge);
    }

    /// @notice Set the master of the controller.
    /// @param _master - The address of the master being setted.
    function setMaster(address _master) public onlyOwner {
        require(_master != address(0), "Controller: Invalid address");
        master = _master;
        emit SetMaster(_master);
    }

    /// @notice Set the treasury of the controller.
    /// @param _treasury - The address of the treasury being setted.
    function setTreasury(address payable _treasury) public onlyOwner {
        require(_treasury != address(0), "Controller: Invalid address");
        treasury = _treasury;
        emit SetTreasury(_treasury);
    }

    /// @notice Add chain identifier to list of supported chain identifer.
    /// @param  _chainId - The identifier of the chain being added.
    function setChainId(uint16 _chainId) public onlyOwner {
        require(_chainId > 0, "Controller: Invalid chainID");
        require(protocolStatus == ProtocolStatus.IDLE, "Controller: Protocol status must be IDLE");
        if(isAcceptingChainId(_chainId)) revert("Controller: chainId already exist");
        supportedChainIds.push(_chainId);
        emit SetChainId(_chainId);
    }

    /// @notice Romove chain identifier from the list of chain identifier.
    /// @param  _chainId - The identifier of the chain being removed.
    function removeChainId(uint16 _chainId) public onlyOwner {
        require(_chainId > 0, "Controller: Invalid chainID");
        require(isAcceptingChainId(_chainId), "Contoller: chainId doesn't exist.");
        for(uint256 i = 0; i < supportedChainIds.length; ++i) { 
            if(_chainId == supportedChainIds[i]) {
                supportedChainIds[i] = supportedChainIds[supportedChainIds.length - 1];
                supportedChainIds.pop();
                emit RemoveChainId(_chainId);
                return;
            }
        }
    }

    /* ========== BRIDGE FUNCTIONS ========== */

    /// @notice Update the snapshot of the certain chain.
    /// @param  _srcChainId - The source chain identifier of snapshot being updated.
    /// @param  _snapshot - The snapshot from the local chain.
    function updateSnapshot(uint16 _srcChainId, MozBridge.Snapshot memory _snapshot, uint256 _updateNum) external onlyBridge {
        if(!isAcceptingChainId(_srcChainId)) return;
        _updateSnapshot(_srcChainId, _snapshot, _updateNum);
    }

    /// @notice Accept report from the vaults.
    function settleReport(uint16 _srcChainId, uint256 _updateNum) external onlyBridge {
        if(!isAcceptingChainId(_srcChainId)) return;
        _settleReport(_srcChainId, _updateNum);
    }

    /* ========== MASTER FUNCTIONS ========== */

    /// @notice Send the requsets to the local vaults to get the snapshot.
    function updateAssetState() external onlyMaster {
        require(protocolStatus == ProtocolStatus.IDLE, "Controller: Protocal must be IDLE");
        require(supportedChainIds.length != 0, "Controller: No supported chain");
        // update protocol status to `SNAPSHOTTING`
        protocolStatus = ProtocolStatus.SNAPSHOTTING;
        emit ProtolcolStatusUpdated(ProtocolStatus.SNAPSHOTTING);
        for(uint16 i = 0; i < supportedChainIds.length; ++i) {
            if(mainChainId == supportedChainIds[i]) {
                MozBridge.Snapshot memory _snapshot = mozBridge.takeSnapshot();
                _updateSnapshot(mainChainId, _snapshot, updateNum);
            } else {
                bytes memory payload = abi.encode(updateNum);
                (uint256 _nativeFee, ) = mozBridge.quoteLayerZeroFee(supportedChainIds[i], TYPE_REQUEST_SNAPSHOT, MozBridge.LzTxObj(0, 0, "0x"), payload);
                mozBridge.requestSnapshot{value: _nativeFee}(supportedChainIds[i], updateNum, payable(address(this)));
            }
        }
        emit UpdateAssetState(updateNum);
    }

    /// @notice Settle the deposit and withdraw request in local vaults with total coin amount and total mozaic LP token amount.
    function settleAllVaults() external onlyMaster {
        require(protocolStatus == ProtocolStatus.OPTIMIZING, "Controller: Protocal must be OPTIMIZING");
        require(supportedChainIds.length != 0, "Controller: No supported chain");
        // update the protocol status to `SETTING`
        protocolStatus = ProtocolStatus.SETTLING;
        emit ProtolcolStatusUpdated(ProtocolStatus.SETTLING);
        for(uint i = 0; i < supportedChainIds.length; ++i) { 
            // settle the vaults
            if(supportedChainIds[i] == mainChainId) {
                mozBridge.setSettle(totalCoinMD, totalMLP);
                _settleReport(mainChainId, updateNum);
            } else {
                bytes memory payload = abi.encode(totalCoinMD, totalMLP, updateNum);
                (uint256 _nativeFee, ) = mozBridge.quoteLayerZeroFee(supportedChainIds[i], TYPE_REQUEST_SETTLE, MozBridge.LzTxObj(0, 0, "0x"), payload);
                mozBridge.requestSettle{value: _nativeFee}(supportedChainIds[i], totalCoinMD, totalMLP, updateNum, payable(address(this)));
            }
        }
        emit SettleAllVaults(updateNum);
    }

    /// @notice Send the requsets to a certain local vault to get the snapshot.
    function requestSnapshot(uint16 _chainId) external onlyMaster {
        require(protocolStatus == ProtocolStatus.SNAPSHOTTING, "Controller: Protocal must be SNAPSHOTTING");
        require(isAcceptingChainId(_chainId),"Controller: Invalid chainId");
        if(_chainId == mainChainId) {
            MozBridge.Snapshot memory _snapshot = mozBridge.takeSnapshot();
            _updateSnapshot(mainChainId, _snapshot, updateNum);
        } else {
            bytes memory payload = abi.encode(updateNum);
            (uint256 _nativeFee, ) = mozBridge.quoteLayerZeroFee(_chainId, TYPE_REQUEST_SNAPSHOT, MozBridge.LzTxObj(0, 0, "0x"), payload);
            mozBridge.requestSnapshot{value: _nativeFee}(_chainId, updateNum, payable(address(this)));
        }
        emit RequestSnapshot(_chainId, updateNum);
    }

    /// @notice Settle the deposit and withdraw request in a certain local vault with total coin amount and total mozaic LP token amount.
    function requestSettle(uint16 _chainId) external onlyMaster {
        require(protocolStatus == ProtocolStatus.SETTLING, "Controller: Protocal must be SETTLING");
        require(isAcceptingChainId(_chainId),"Controller: Invalid chainId");
        if(_chainId == mainChainId) {
            mozBridge.setSettle(totalCoinMD, totalMLP);
            _settleReport(mainChainId, updateNum);
        } else {
            bytes memory payload = abi.encode(totalCoinMD, totalMLP, updateNum);
            (uint256 _nativeFee, ) = mozBridge.quoteLayerZeroFee(_chainId, TYPE_REQUEST_SETTLE, MozBridge.LzTxObj(0, 0, "0x"), payload);
            mozBridge.requestSettle{value: _nativeFee}(_chainId, totalCoinMD, totalMLP, updateNum, payable(address(this)));
        }
        emit RequestSettle(_chainId, updateNum);
    }

    ///  @notice Check the protocol status and the change the protocol status if it is necessary.
    function checkProtocolStatus() external onlyMaster {
        if(protocolStatus == ProtocolStatus.SNAPSHOTTING) {
            if(_checkSnapshot()) {
                _updateStats();
                checkedSnapshot[updateNum] = true;
                // update protocol status to `OPTIMIZING`
                protocolStatus = ProtocolStatus.OPTIMIZING;
                emit ProtolcolStatusUpdated(ProtocolStatus.OPTIMIZING);
            }
        }

        if(protocolStatus == ProtocolStatus.SETTLING) {
            if(_checkSettle()) {
                checkedSettle[updateNum] = true;
                // update protocol status to `IDLE`
                protocolStatus = ProtocolStatus.IDLE;
                emit ProtolcolStatusUpdated(ProtocolStatus.IDLE);
            }
        }
    }
    
    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Return the snapshot for a chain identifier.
    /// @dev    Used to return & access the certain snapshot struct in solidity
    function getSnapshotData(uint16 _chainId) public view returns (MozBridge.Snapshot memory ){
        return snapshotReported[_chainId];
    }

    /// @notice Whether chain identifer is supported.
    function isAcceptingChainId(uint16 _chainId) public view returns (bool) {
        for(uint256 i = 0; i < supportedChainIds.length; ++i) {
            if(_chainId == supportedChainIds[i]) return true;
        }
        return false;
    }

    /// @notice Check if snapshop of a certain chainId is reported .
    function isSnapshotReported(uint16 _chainId) public view returns (bool) {
        require(isAcceptingChainId(_chainId), "Controller: Invalid chainId");
        return snapshotFlag[updateNum][_chainId];
    }

    /// @notice Check if certain chainId is settled.
    function isSettleReported(uint16 _chainId) public view returns (bool) {
        require(isAcceptingChainId(_chainId), "Controller: Invalid chainId");
        return settleFlag[updateNum][_chainId];
    }

    /// @notice Get the length of supported chains.
    function getNumberOfChains() public view returns (uint256) {
        return supportedChainIds.length;
    }

    /// @notice Get the array of supported chain ids.
    function getSupportedChainIds() public view returns (uint16[] memory) {
        return supportedChainIds;
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    
    /// @notice Update the snapshot of the certain chain.
    /// @param  _srcChainId - The source chain identifier of snapshot being updated.
    /// @param  _snapshot - The snapshot to be setted.
    /// @param  _updateNum - The updated number.
    function _updateSnapshot(uint16 _srcChainId, MozBridge.Snapshot memory _snapshot, uint256 _updateNum) internal {
        if(updateNum != _updateNum) return;
        if(snapshotFlag[_updateNum][_srcChainId] == true) return;
        if(checkedSnapshot[_updateNum] == true) return;

        snapshotFlag[_updateNum][_srcChainId] = true;
        snapshotReported[_srcChainId] = _snapshot;
        emit SnapshotReported(_srcChainId, _updateNum);
        // check if all vaults reported their snapshot
        if(_checkSnapshot()) {
            checkedSnapshot[_updateNum] = true;
            _updateStats();
            // update protocol status to `OPTIMIZING`
            protocolStatus = ProtocolStatus.OPTIMIZING;
            emit ProtolcolStatusUpdated(ProtocolStatus.OPTIMIZING);
        }
    }

    /// @notice Accept settle reports from the local vaults.
    function _settleReport(uint16 _srcchainId, uint256 _updateNum) internal {
        if(updateNum != _updateNum) return;
        if(settleFlag[updateNum][_srcchainId] == true) return;
        if(checkedSettle[_updateNum] == true) return;
        
        settleFlag[updateNum][_srcchainId] = true;
        emit SettleReported(_srcchainId, _updateNum);
        // check if all vaults are settled
        if(_checkSettle()) {
            checkedSettle[_updateNum] = true;
            updateNum++;
            // update protocol status to `IDLE`
            protocolStatus = ProtocolStatus.IDLE;
            emit ProtolcolStatusUpdated(ProtocolStatus.IDLE);
        }
    }
    
    /// @notice Update stats with the snapshots from all local vaults.
    function _updateStats() internal {
        uint256 _totalCoinMD = 0;
        uint256 _totalMLP = 0;
        // Calculate the total amount of stablecoin and mozaic LP token.
        for (uint i; i < supportedChainIds.length; ++i) {
            MozBridge.Snapshot memory report = snapshotReported[supportedChainIds[i]];
            _totalCoinMD = _totalCoinMD + report.totalStablecoin;
            _totalMLP = _totalMLP + report.totalMozaicLp;
        }
        totalCoinMD = _totalCoinMD;
        totalMLP = _totalMLP;
        emit UpdatedTotalAsset(_totalCoinMD, _totalMLP);
    }

    /// @notice Check if get shapshots from all supported chains.
    function _checkSnapshot() internal view returns (bool) {
      for(uint256 i = 0; i < supportedChainIds.length; ++i) {
        if(snapshotFlag[updateNum][supportedChainIds[i]] == false) return false;
      }
      return true;
    }

    /// @notice Check if get settle reports from all supported chains.
    function _checkSettle() internal view returns (bool) {
      for(uint256 i = 0; i < supportedChainIds.length; ++i) {
        if(settleFlag[updateNum][supportedChainIds[i]] == false) return false;
      }
      return true;
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
        require(amount >= _amount, "Controller: Invalid withdraw amount.");
        // send Ether to treasury
        // Treasury can receive Ether since the address of treasury is payable
        require(treasury != address(0), "Controller: Invalid treasury");
        (bool success, ) = treasury.call{value: _amount}("");
        require(success, "Controller: Failed to send Ether");
        emit Withdraw(_amount);
    }
}

