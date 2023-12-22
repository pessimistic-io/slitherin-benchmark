// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Clones.sol";
import "./DVault.sol";
import "./IERC20.sol";
import "./TransferHelper.sol";
import "./SupportedTokens.sol";
import "./DVaultConfig.sol";

enum VaultStatus {
        LOCKED,
        UNLOCKED
}

struct VaultDetails {
        string name;
        address owner1;
        address owner2;
        string uri;
        VaultStatus owner1Status;
        VaultStatus owner2Status;
        VaultStatus status;
        uint256 lockTime;
        uint256 lockInitiatedTime;
        address lockInitiatedAddress;
        uint256 unlockInitiatedTime;
        bool owner1BlockStatus;
        bool owner2BlockStatus;
}

interface IDVault {
    function isAuthorizedOwner(address addr) external view returns (bool);
    function getVaultDetails() external view returns (VaultDetails memory);
    function updateOwner(address oldOwner, address newOwner) external;
}

contract DVaultFactory is Ownable {

    using TransferHelper for IERC20;

    uint256 _counter;
    bool _counterUpdated;
    address _implementation;
    mapping(uint256 => address) _allVaults;
    mapping(address => uint256[]) _userVaults;
    SupportedTokens _globalList;
    address[] _whitelistedTokens;
    address _createVaultFeeTokenAddress;
    uint256 _createVaultFeeAmount;
    bool _isCollectCreateFee;
    address _feeAddress = 0x89A674E8ef54554a0519885295d4FC5d972De140;
    address _riseBurnAddress = address(0xdead);
    address public _riseAddress = 0xC17c30e98541188614dF99239cABD40280810cA3;
    uint256 public _riseBurnAmount = 20_000 * 10 ** 18;
    bool _isBurnRise;
    uint256 public _owner1Limit = 2;
    uint256 public _owner2Limit = 2;
    bool _createVault = true;
    bool _enableMultipleVaults;
    address _superOwner;
    bool _ownerAuthorized;

    DVaultConfig _vaultConfig;

    error TokenNotSupported(); //0x3dd1b305
    error InsufficientAmount(); //0x5945ea56
    error FailedETHSend(); //0xaf3f2195
    error NotZeroAddress(); //0x66385fa3
    error NotAuthorized(); //0xea8e4eb5
    error MultipleVaultsNotAllowed(); //0x76fe3111
    error CurrentlyLocked();


    constructor() Ownable(msg.sender) {
        _implementation = address(new DVault());
        _globalList = new SupportedTokens();
        _vaultConfig = new DVaultConfig();
        _superOwner = msg.sender;
    }

    modifier authorized() {
        if (!_ownerAuthorized) revert NotAuthorized();
        _;
    } 

    receive() external payable  {}

    fallback() external payable {}

    function setSuperOwner(address addr) external {
        if (msg.sender != _superOwner) revert NotAuthorized();
        require(!isContract(addr), "Super Owner can not be a contract");
        _superOwner = addr;
    }

    function setOwnerAuthorized(bool flag) external {
        if (msg.sender != _superOwner) revert NotAuthorized();
        _ownerAuthorized = flag;
    }

    function getOwnerAuthorized() external view returns (bool) {
        return _ownerAuthorized;
    }

    function getSuperOwner() external view returns (address) {
        return _superOwner;
    }

    function setEnableMultipleVaults(bool flag) external onlyOwner {
        _enableMultipleVaults = flag;
    }

    function setOwner1Limit(uint256 value) external onlyOwner {
        _owner1Limit = value;
    }

    function setOwner2Limit(uint256 value) external onlyOwner {
        _owner2Limit = value;
    }

    function setIsRiseBurn(bool flag) external onlyOwner {
        _isBurnRise = flag;
    }

    function setCreateVault(bool flag) external onlyOwner {
        _createVault = flag;
    }

    function setRiseAddress(address newAddress) external onlyOwner {
        _riseAddress = newAddress;
    }

    function setRiseBurnAddress(address newAddress) external onlyOwner {
        _riseBurnAddress = newAddress;
    }

    function setRiseBurnAmount(uint256 amount, uint256 decimals) external onlyOwner {
        _riseBurnAmount = (amount * 10**18) / 10 ** decimals;
    }

    function getRiseBurnAmount() external view returns (uint256) {
        return _riseBurnAmount;
    }

    function setFeeAddress(address feeAddress) external onlyOwner {
        _feeAddress = feeAddress;
    }

    function setConfigFeeAddress(address feeAddress) external onlyOwner {
        _vaultConfig.setFeeAddress(feeAddress);
    }

    function getFeeAddress() external view returns (address) {
        return _feeAddress;
    }

    function setCreateVaultFee(address feeToken, uint256 amount, uint256 fractionalDecimals) external onlyOwner {
        _createVaultFeeTokenAddress = feeToken;
        uint8 decimals = 18;
        if (feeToken != address(0)) {
            decimals = Metadata(feeToken).decimals();
        }
        _createVaultFeeAmount = (amount * 10**decimals) / 10 ** fractionalDecimals;
    }

    function setIsCollectCreateFee(bool create) external onlyOwner {
        _isCollectCreateFee = create;
    }

    function getCreateVaultFeeTokenAddress() external view returns (address) {
        return _createVaultFeeTokenAddress;
    }

    function getCreateVaultFeeAmount() external view returns (uint256) {
        return _createVaultFeeAmount;
    }

    function getIsCollectCreateFee() external view returns (bool) {
        return _isCollectCreateFee;
    }

    function createVaultClone(string calldata name, address owner2, string calldata uri) external payable returns (address) {
        require(_createVault, "Create Vault is not allowed");
        require(msg.sender != owner2, "Same Address is not allowed");
        require(!isContract(owner2), "Owner2 can not be a contract");
        
        if (_userVaults[msg.sender].length > _owner1Limit - 1 || _userVaults[owner2].length > _owner2Limit - 1) {
            if (!_enableMultipleVaults) revert MultipleVaultsNotAllowed();
            if (_isCollectCreateFee) collectCreateFee();
        }

        if (_isBurnRise) {
            IERC20(_riseAddress).safeTransferFrom(msg.sender, address(this), _riseBurnAmount);
            IERC20(_riseAddress).safeTransfer(_riseBurnAddress, _riseBurnAmount);
        }

        address payable clonedVault = payable(Clones.clone(_implementation));
        DVault(clonedVault).initialize(name, msg.sender, owner2, address(this), uri, _vaultConfig,  _globalList);

        _counter++;
        _allVaults[_counter] = address(clonedVault);
        _userVaults[msg.sender].push(_counter);
        _userVaults[owner2].push(_counter);
        return clonedVault;
    }

    function collectCreateFee() internal {
        if (_createVaultFeeTokenAddress == address(0)) {
            if (msg.value < _createVaultFeeAmount) revert InsufficientAmount();
            _transfer(_feeAddress, _createVaultFeeAmount);
        } else {
            IERC20(_createVaultFeeTokenAddress).safeTransferFrom(msg.sender, _feeAddress, _createVaultFeeAmount);
        }
    }

    function _transfer(address to, uint256 amount) internal {
        if (to == address(0)) revert NotZeroAddress();
        (bool success, ) = payable(to).call{value: amount}("");
        
        if (!success) revert FailedETHSend();
    }

    function transferToVault(uint256 id, address token, uint256 amount) external {
        address vaultAddress = _allVaults[id];
        if (vaultAddress == address(0)) revert NotZeroAddress();
        if (!_globalList.isSupportedToken(token)) revert TokenNotSupported();
        require(amount > 0, "Amount should be greater than 0");
        uint256 initial = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 newAmount = IERC20(token).balanceOf(address(this)) - initial;
        require(amount == newAmount, "Amounts Mismatch");
        IERC20(token).safeTransfer(vaultAddress, amount);
    }

    function transferFromVault(uint256 id, address token, uint256 amount) external {
        address vaultAddress = _allVaults[id];
        if (vaultAddress == address(0)) revert NotZeroAddress();
        if (!_globalList.isSupportedToken(token)) revert TokenNotSupported();
        if (!IDVault(vaultAddress).isAuthorizedOwner(msg.sender)) revert NotAuthorized();
        VaultDetails memory details = IDVault(vaultAddress).getVaultDetails();
        if (details.status == VaultStatus.LOCKED) revert CurrentlyLocked();
        require(amount > 0, "Amount should be greater than 0");
        uint256 initial = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(vaultAddress, address(this), amount);
        uint256 newAmount = IERC20(token).balanceOf(address(this)) - initial;
        require(amount == newAmount, "Amounts Mismatch");
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    // Introduced in V3
    function updateOwner(uint256 vault_id, address oldOwner, address newOwner) external {
        address vaultAddress = _allVaults[vault_id];
        if (vaultAddress == address(0)) revert NotZeroAddress();
        if (!IDVault(vaultAddress).isAuthorizedOwner(msg.sender)) revert NotAuthorized();
        require(!isContract(newOwner), "New Owner can not be a contract");
        
        if (_userVaults[newOwner].length > _owner2Limit - 1) {
            if (!_enableMultipleVaults) revert MultipleVaultsNotAllowed();
            if (_isCollectCreateFee) collectCreateFee();
        }
        IDVault(vaultAddress).updateOwner(oldOwner, newOwner);
        _userVaults[newOwner].push(vault_id);

        uint length = _userVaults[oldOwner].length;
        for (uint i = 0; i < length; i++) {
            if (_userVaults[oldOwner][i] == vault_id) {
                _userVaults[oldOwner][i] = _userVaults[oldOwner][length - 1];
                break;
            }
        }
        _userVaults[oldOwner].pop();
    }



    function isContract(address addr) public view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }

    function getVault(uint256 id) public view returns (address) {
        return _allVaults[id];
    }

    function addSupportedToken(address token, bool whitelisted) external onlyOwner {
        _globalList.addSupportedToken(token);
        if (whitelisted) _whitelistedTokens.push(token);
    }

    function setUnlockVaultFee(address feeToken, uint256 amount, uint256 fractionalDecimals) external onlyOwner authorized {
        _vaultConfig.setUnlockVaultFeeDetails(feeToken, amount, fractionalDecimals);
    }

    function setTimelockFee(address feeToken, uint256 amount, uint256 fractionalDecimals) external onlyOwner authorized {
        _vaultConfig.setTimelockFeeDetails(feeToken, amount, fractionalDecimals);
    }

    function setNFTAddress(address addr) external onlyOwner authorized {
        _vaultConfig.setNFTAddress(addr);
    }

    function setUnlockFeeFlag(bool unlock) external onlyOwner authorized {
        _vaultConfig.setCollectUnlockFee(unlock);
    }

    function setTimelockFeeFlag(bool timelock) external onlyOwner authorized {
        _vaultConfig.setCollectTimelockFee(timelock);
    }

    function setCheckForNFFlag(bool flag) external onlyOwner authorized {
        _vaultConfig.setCheckForNFT(flag);
    }

    function updateEverRiseInfo(address erAddress, address erStakeAddress) external onlyOwner authorized {
        _vaultConfig.updateEverRiseInfo(erAddress, erStakeAddress);
    }

    function getWhiteListedTokens() external view returns (address[] memory) {
        return _whitelistedTokens;
    }

    function setCounter(uint256 value) external onlyOwner {
        require(!_counterUpdated, "Already Updated");
        _counter = value;
        _counterUpdated = true;
    }

    function getCounter() public view returns (uint256) {
        return _counter;
    }

    function getVaults(address user) external view returns (uint256[] memory) {
        return _userVaults[user];
    }

    function getTimeLockFeeTokenAddress() external view returns (address) {
        return _vaultConfig.getTimeLockFeeTokenAddress();
    }

    function getTimeLockFeeAmount() external view returns (uint256) {
        return _vaultConfig.getTimeLockFeeAmount();
    }

    function getCollectTimeLockFee() external view returns (bool) {
        return _vaultConfig.getCollectTimelockFee();
    }

    function getUnlockVaultFeeTokenAddress() external view returns (address) {
        return _vaultConfig.getUnlockVaultFeeTokenAddress();
    }

    function getUnlockVaultFeeAmount() external view returns (uint256) {
        return _vaultConfig.getUnlockVaultFeeAmount();
    }

    function getCollectUnlockFee() external view returns (bool) {
        return _vaultConfig.getCollectUnlockFee();
    }

    function getConfigFeeAddress() external view returns (address) {
        return _vaultConfig.getFeeAddress();
    }
}
